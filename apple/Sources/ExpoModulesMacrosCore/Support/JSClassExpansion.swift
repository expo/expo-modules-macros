import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

/// The part of a JavaScript class macro that doesn't depend on the kind of class. It collects the `@JS`
/// members of the class body, reports their diagnostics, and emits the hooks that core calls when it
/// builds the JavaScript class. `@JSClass` and `@SharedObject` use it, and give it what is specific to
/// the kind of class: the macro name for the diagnostics, the statement that recovers the native
/// instance from the JavaScript `this`, whether the superclass may bind JavaScript members, whether
/// the class is the root of its JavaScript class chain, and whether JavaScript gets an instance only
/// from the constructor.
internal struct JSClassExpansion {
  /// The class that the macro is attached to.
  let classDecl: ClassDeclSyntax
  /// The attribute of the macro, which can override the JavaScript name of the class.
  let macroAttribute: AttributeSyntax
  /// The name of the macro with its `@`, for the diagnostics.
  let macroName: String
  /// The statement that binds `_self` to the native instance of the JavaScript `this` in an instance
  /// binding (see `Receiver.instance(unwrapStatement:)`).
  let instanceUnwrapStatement: String
  /// True when the superclass may be another class with the macro, whose JavaScript class is up the
  /// prototype chain of this class's prototype and constructor (see `_jsSuperclassType` in
  /// `members(in:)`). An assignment to a name that it binds as an accessor would call the accessor, so
  /// each function of this class then defines its name as a data property first.
  let mayInheritJSMembers: Bool
  /// True when no superclass conforms to `AnyJavaScriptClass`, so the class implements the hooks of
  /// the protocol instead of overriding them, and has no JavaScript superclass. The class properties of
  /// a root (`_jsName`, `_jsClassType` and `_jsSuperclassType`) are `nonisolated`, so that core can read
  /// them off the main actor also when the module builds with `-default-isolation MainActor`. The
  /// decorate phases and the constructor stay `@JavaScriptActor`.
  let isRoot: Bool
  /// True when JavaScript gets an instance of the class only from its constructor, as for `@JSClass`,
  /// which isn't `JavaScriptEncodable`. A `final` class with instance `@JS` members and no `@JS init`
  /// then gets a warning, since no JavaScript object can call those members. A non-`final` class can
  /// have a subclass with a `@JS init`, whose instances get the members through the prototype chain.
  let instancesComeFromConstructor: Bool

  /// The members that the macro adds to the class.
  func members(in context: some MacroExpansionContext) throws -> [DeclSyntax] {
    let typeName = classDecl.name.text
    let jsName = jsNameArgument(of: macroAttribute) ?? withoutBackticks(typeName)
    let isFinal = classDecl.modifiers.contains { $0.name.tokenKind == .keyword(.final) }
    // The hooks of an `open` class are `open`, so that a subclass in another module can override them.
    let access = classDecl.modifiers.contains { $0.name.tokenKind == .keyword(.open) } ? "open" : "public"

    // `@JS func`s/`var`s and the `@JS init` are bound directly into the class's JS object by
    // the synthesized `_decorateClass(prototype:)` / `_decorateClass(constructor:)` / `_constructInstance`.
    //
    // Members split by the `static`/`class` modifier onto two different JS objects: instance members
    // decorate the prototype (receiver recovered from JS `this`), static members decorate the
    // constructor (called on the metatype). A JS instance and static member may share a name without
    // colliding: they live on different objects.
    var instanceFunctions: [JSFunction] = []
    var instanceProperties: [JSProperty] = []
    var staticFunctions: [JSFunction] = []
    var staticProperties: [JSProperty] = []
    var constructor: JSConstructor?
    var assertions: [MemberConformanceAssertion] = []
    let aliases = TupleTypeAliases(in: classDecl.memberBlock)

    for member in classDecl.memberBlock.members {
      // The types of a `@JS` member are read with the class's tuple aliases resolved.
      let decl = aliases.resolving(member.decl)
      // A generic member or unsupported initializer (`init?`, `init!`, `async init`) is reported by `@JS`
      // and left out, so the build has no errors in its binding.
      if memberHasJSAttribute(decl) && jsGenericParameterClause(of: decl) != nil {
        continue
      }
      if let initDecl = decl.as(InitializerDeclSyntax.self),
        initDecl.attributes.firstAttribute(named: "JS") != nil,
        initDecl.optionalMark != nil || initDecl.signature.effectSpecifiers?.asyncSpecifier != nil
      {
        continue
      }
      if memberHasJSAttribute(decl), let assertion = jsConformanceAssertionBody(for: decl) {
        assertions.append(assertion)
      }

      if let initDecl = decl.as(InitializerDeclSyntax.self),
        let attribute = initDecl.attributes.firstAttribute(named: "JS")
      {
        // The first one is bound, so the rest of the expansion, such as the conformances, stays valid
        // and the build reports only this error.
        if constructor != nil {
          context.diagnose(
            Diagnostic(
              node: attribute,
              message: JSClassExpansionMessage(
                "\(macroName) classes can have at most one @JS initializer: JavaScript classes have a single constructor",
                id: "js-class-multiple-initializers",
                severity: .error
              )
            )
          )
          continue
        }
        constructor = JSConstructor(initDecl: initDecl)
        continue
      }

      if let funcDecl = decl.as(FunctionDeclSyntax.self),
        let attribute = funcDecl.attributes.firstAttribute(named: "JS")
      {
        let function = JSFunction(funcDecl: funcDecl, attribute: attribute)
        let bound = [function] + (function.asyncVariant.map { [$0] } ?? [])
        if isTypeLevel(funcDecl.modifiers) {
          staticFunctions.append(contentsOf: bound)
        } else {
          instanceFunctions.append(contentsOf: bound)
        }
        continue
      }

      if let varDecl = decl.as(VariableDeclSyntax.self),
        let attribute = varDecl.attributes.firstAttribute(named: "JS")
      {
        let collected = collectProperties(varDecl: varDecl, attribute: attribute)
        if isTypeLevel(varDecl.modifiers) {
          staticProperties.append(contentsOf: collected)
        } else {
          instanceProperties.append(contentsOf: collected)
        }
      }
    }

    diagnoseJSNameCollisions(functions: instanceFunctions, properties: instanceProperties, in: context)
    diagnoseJSNameCollisions(functions: staticFunctions, properties: staticProperties, in: context)
    diagnoseReservedJSNames(
      functions: instanceFunctions,
      properties: instanceProperties,
      on: .prototype,
      in: context
    )
    diagnoseReservedJSNames(
      functions: staticFunctions,
      properties: staticProperties,
      on: .constructor,
      in: context
    )
    diagnoseEventNameCollisions(in: classDecl.memberBlock, in: context)
    if instancesComeFromConstructor, isFinal, constructor == nil,
      !instanceFunctions.isEmpty || !instanceProperties.isEmpty
    {
      context.diagnose(
        Diagnostic(
          node: classDecl.name,
          message: JSClassExpansionMessage(
            "'\(withoutBackticks(typeName))' has instance @JS members but no @JS initializer, and JavaScript gets an instance of this class only from its constructor. Add a @JS init, or make the members static",
            id: "jsclass-instance-members-without-initializer",
            severity: .warning
          )
        )
      )
    }

    // The resolved JS class name, read by core when it builds the class. A class property, which a
    // subclass overrides, so core reads it through the concrete type's metatype.
    //
    // `_jsClassType` returns this class, written by name and not as `Self`, so a subclass without the
    // macro inherits it and core gives that subclass the JavaScript class of this one. Inside a generic
    // class, the bare name means the class with its own generic arguments. `_jsSuperclassType` returns the
    // `_jsClassType` of the superclass, which is the nearest class above with the macro, or `nil` for the
    // base `SharedObject` or `SharedRef`. A root has no JavaScript superclass, so it returns `nil`. Core
    // builds the JavaScript class of the superclass first and creates this one on it, so the JavaScript
    // chain follows the Swift chain.
    let modifiers = isRoot ? "nonisolated \(access)" : "\(access) override"
    let superclassType = isRoot ? "nil" : "super._jsClassType"
    var emitted: [DeclSyntax] = [
      "\(raw: modifiers) class var _jsName: String { \"\(raw: jsName)\" }",
      "\(raw: modifiers) class var _jsClassType: (any AnyJavaScriptClass.Type)? { \(raw: typeName).self }",
      "\(raw: modifiers) class var _jsSuperclassType: (any AnyJavaScriptClass.Type)? { \(raw: superclassType) }",
    ]

    // Direct JSI binding, split by which JS object each member decorates:
    // `_decorateClass(prototype:)` binds instance `@JS func`/`var`s (unwrapping the per-call receiver from
    // `this`); `_decorateClass(constructor:)` binds `static`/`class` ones (called on the metatype); and
    // `_constructInstance` builds an instance from the `@JS init` arguments. Both decorator phases
    // are emitted also when they bind nothing, since a class without its own phase would run the phase of
    // its superclass on its own objects. Each class binds only its own members: the inherited ones are on
    // the JavaScript class of the superclass. A subclass emits the constructor only for a `@JS init`; a
    // root always emits it (see `JSConstructor.buildAbsentConstructor`).
    let instanceReceiver = Receiver.instance(unwrapStatement: instanceUnwrapStatement)
    emitted.append(
      buildDecorateJSClassPhase(
        phase: .prototype,
        functions: instanceFunctions,
        properties: instanceProperties,
        typeName: typeName,
        instanceReceiver: instanceReceiver,
        access: access,
        isOverride: !isRoot,
        replacesInherited: mayInheritJSMembers
      )
    )
    emitted.append(
      buildDecorateJSClassPhase(
        phase: .constructor,
        functions: staticFunctions,
        properties: staticProperties,
        typeName: typeName,
        instanceReceiver: instanceReceiver,
        access: access,
        isOverride: !isRoot,
        replacesInherited: mayInheritJSMembers
      )
    )
    if let constructor {
      emitted.append(
        constructor.buildConstructor(
          typeName: typeName,
          jsName: jsName,
          access: access,
          isFinal: isFinal,
          isOverride: !isRoot
        )
      )
    } else if isRoot {
      emitted.append(JSConstructor.buildAbsentConstructor(access: access))
    }

    // The conformance assertions of the `@JS` members, which `@JS` leaves to this macro (see
    // `jsConformanceAssertionBody`).
    if let assertion = classConformanceAssertions(assertions) {
      emitted.append(assertion)
    }

    return emitted
  }

  /// The attributes that the macro adds to a member of the class: `@concurrent` on a `@JS(.concurrent)`
  /// member, which opts it out of the JS-thread stamp and onto the concurrent pool, and
  /// `@JavaScriptActor` on the other `@JS` members that need it.
  static func memberAttributes(
    for member: some DeclSyntaxProtocol,
    enclosedBy declaration: some DeclGroupSyntax
  ) -> [AttributeSyntax] {
    guard memberHasJSAttribute(member) else {
      return []
    }
    if isConcurrentJSMember(member) {
      return ["@concurrent"]
    }
    guard shouldStampJavaScriptActor(on: member, enclosedBy: declaration) else {
      return []
    }
    return ["@JavaScriptActor"]
  }
}

private struct JSClassExpansionMessage: DiagnosticMessage {
  let message: String
  let diagnosticID: MessageID
  let severity: DiagnosticSeverity

  init(_ message: String, id: String, severity: DiagnosticSeverity) {
    self.message = message
    self.diagnosticID = MessageID(domain: "ExpoModulesMacros", id: id)
    self.severity = severity
  }
}
