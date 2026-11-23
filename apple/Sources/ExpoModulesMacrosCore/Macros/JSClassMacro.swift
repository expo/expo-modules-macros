import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

/// Member macro applied to a class, which gives it a JavaScript class. Scans the class body for
/// declarations marked with `@JS` and binds them through the hooks of `AnyJavaScriptClass` that core
/// calls when it builds the JavaScript class. The class's JavaScript name is emitted as `_jsName`, and
/// its place in the JavaScript class chain as `_jsClassType` and `_jsSuperclassType`.
///
///   @JSClass
///   public final class Point {
///     @JS
///     init(x: Double, y: Double) { ... }
///
///     @JS
///     func length() -> Double { ... }
///   }
///
/// The class doesn't need a superclass. A class whose superclass doesn't conform to
/// `AnyJavaScriptClass` is the root of its JavaScript class chain: it implements the hooks, and its
/// JavaScript class has no superclass. A subclass of another `@JSClass` class overrides the hooks, and
/// its JavaScript class extends the one of that class. The compiler tells the two apart: it passes
/// `AnyJavaScriptClass` in the conformances of the member role only when no superclass conforms yet.
///
/// Unlike a shared object, the native instance has no registry ID and no events, and core doesn't map
/// it back to its JavaScript object. `@SharedObject` is the macro for a `SharedObject` subclass.
///
/// As an extension macro, it adds the `AnyJavaScriptClass` and `JavaScriptDecodable` conformances to a
/// root, and an `@unchecked Sendable` conformance when the class isn't `Sendable` yet. A root isn't
/// `JavaScriptEncodable`: core doesn't map a native instance back to its JavaScript object, so a `@JS`
/// member that returns the class fails the conformance check of the class macro.
public struct JSClassMacro: MemberMacro {
  public static func expansion(
    of node: AttributeSyntax,
    providingMembersOf declaration: some DeclGroupSyntax,
    conformingTo protocols: [TypeSyntax],
    in context: some MacroExpansionContext
  ) throws -> [DeclSyntax] {
    guard let classDecl = declaration.as(ClassDeclSyntax.self) else {
      throw MacroExpansionErrorMessage("@JSClass can only be applied to a class")
    }
    // `@SharedObject` reports the class, so this macro adds nothing that would collide with its members.
    if hasSharedObjectAttribute(classDecl) {
      return []
    }
    diagnoseNonPublicClass(
      classDecl,
      macroName: "@JSClass",
      reason: "export it",
      idPrefix: "jsclass",
      in: context
    )
    if inheritsFromAny(classDecl, names: sharedObjectBaseNames) {
      context.diagnose(sharedObjectSuperclassDiagnostic(for: node))
    }

    let typeName = classDecl.name.text
    let isRoot = isRootClass(classDecl, conformingTo: protocols)
    // A subclass of another class with a JavaScript class gets the members of that class through the
    // prototype chain. The JavaScript class of `SharedObject` and `SharedRef` doesn't bind accessors
    // that a function of this class would call, as `@SharedObject` assumes too.
    let mayInheritJSMembers = !isRoot && !inheritsFromAny(classDecl, names: ["SharedObject", "SharedRef"])
    // An instance binding recovers its receiver with `_native(from:)`, which reads the native state that
    // core attaches to the JavaScript object of the instance, and throws on a foreign object or a type
    // mismatch.
    let expansion = JSClassExpansion(
      classDecl: classDecl,
      macroAttribute: node,
      macroName: "@JSClass",
      instanceUnwrapStatement: "let _self = try \(typeName)._native(from: this.asObject(in: runtime))",
      mayInheritJSMembers: mayInheritJSMembers,
      isRoot: isRoot
    )
    return try expansion.members(in: context)
  }
}

extension JSClassMacro: MemberAttributeMacro {
  public static func expansion(
    of node: AttributeSyntax,
    attachedTo declaration: some DeclGroupSyntax,
    providingAttributesFor member: some DeclSyntaxProtocol,
    in context: some MacroExpansionContext
  ) throws -> [AttributeSyntax] {
    if let classDecl = declaration.as(ClassDeclSyntax.self), hasSharedObjectAttribute(classDecl) {
      return []
    }
    return JSClassExpansion.memberAttributes(for: member, enclosedBy: declaration)
  }
}

extension JSClassMacro: ExtensionMacro {
  public static func expansion(
    of node: AttributeSyntax,
    attachedTo declaration: some DeclGroupSyntax,
    providingExtensionsOf type: some TypeSyntaxProtocol,
    conformingTo protocols: [TypeSyntax],
    in context: some MacroExpansionContext
  ) throws -> [ExtensionDeclSyntax] {
    guard let classDecl = declaration.as(ClassDeclSyntax.self), !hasSharedObjectAttribute(classDecl) else {
      return []
    }
    var extensions: [ExtensionDeclSyntax] = []
    if let conformance = rootConformanceExtension(for: type, of: classDecl, conformingTo: protocols) {
      extensions.append(conformance)
    }
    // A superclass in the expanded files has a JavaScript class, so it got `@unchecked Sendable` from its
    // own macro, as the compiler would tell.
    if !inheritsFromExpandedJSClass(classDecl),
      let sendable = uncheckedSendableExtension(for: type, of: declaration, conformingTo: protocols)
    {
      extensions.append(sendable)
    }
    return extensions
  }
}

/// The base classes and the protocol of the shared objects. A class that inherits one of them is a
/// shared object, whose macro is `@SharedObject`.
private let sharedObjectBaseNames: Set<String> = ["SharedObject", "SharedRef", "AnySharedObject"]

/// The conformances of a root class. Core implements `JavaScriptDecodable` for every
/// `AnyJavaScriptClass`: it reads the native instance from the native state that it attaches to the
/// JavaScript object, as `_native(from:)` does. So the class only declares the conformance.
private let rootConformances = ["AnyJavaScriptClass", "JavaScriptDecodable"]

private func hasSharedObjectAttribute(_ classDecl: ClassDeclSyntax) -> Bool {
  return classDecl.attributes.firstAttribute(named: "SharedObject") != nil
}

/// Whether the class is the root of its JavaScript class chain. The compiler passes `AnyJavaScriptClass`
/// in `protocols` only when the class doesn't conform yet, also through a superclass. A class that
/// names `AnyJavaScriptClass` in its clause conforms, but implements the hooks itself, so it is a root
/// too. `expand` passes the conformance for every class, so a class whose superclass has a JavaScript
/// class by its name is a subclass there (see `ExpandHints`).
private func isRootClass(_ classDecl: ClassDeclSyntax, conformingTo protocols: [TypeSyntax]) -> Bool {
  if inheritsProtocol(named: "AnyJavaScriptClass", in: classDecl) {
    return true
  }
  return protocols.contains { $0.trimmedDescription == "AnyJavaScriptClass" } && !namesJSSuperclass(classDecl)
}

/// Whether the superclass in the clause has a JavaScript class, by its name: a shared object base, or
/// a class that `expand` found with a JavaScript class. The compiler doesn't need it, because it leaves
/// the conformances of the superclass out of `protocols`.
private func namesJSSuperclass(_ classDecl: ClassDeclSyntax) -> Bool {
  return inheritsFromAny(classDecl, names: sharedObjectBaseNames) || inheritsFromExpandedJSClass(classDecl)
}

/// Whether `expand` found a JavaScript class for the superclass, the first type of the clause.
private func inheritsFromExpandedJSClass(_ classDecl: ClassDeclSyntax) -> Bool {
  guard let names = ExpandHints.jsClassNames,
    let superclass = classDecl.inheritanceClause?.inheritedTypes.first,
    let name = baseIdentifier(of: superclass.type)
  else {
    return false
  }
  return names.contains(name)
}

/// The conformances that a root class gets, or `nil` when it has them all. Each one is added only when
/// the compiler passes it and the clause doesn't name it, as for `Sendable`. The conformances are
/// `nonisolated`, so core can use them on any thread also when the module builds with
/// `-default-isolation MainActor`.
private func rootConformanceExtension(
  for type: some TypeSyntaxProtocol,
  of classDecl: ClassDeclSyntax,
  conformingTo protocols: [TypeSyntax]
) -> ExtensionDeclSyntax? {
  guard !namesJSSuperclass(classDecl) else {
    return nil
  }
  let missing = rootConformances.filter { name in
    protocols.contains { $0.trimmedDescription == name } && !inheritsProtocol(named: name, in: classDecl)
  }
  guard !missing.isEmpty else {
    return nil
  }
  let list = missing.map { "nonisolated \($0)" }.joined(separator: ", ")
  let conformance: DeclSyntax = "extension \(type.trimmed): \(raw: list) {}"
  return conformance.cast(ExtensionDeclSyntax.self)
}

/// The warning for `@JSClass` on a class whose clause names a shared object base. The class is a shared
/// object, so the macro works, but `@SharedObject` checks the class as a shared object. The fix-it
/// replaces the name of the attribute and keeps its arguments.
private func sharedObjectSuperclassDiagnostic(for node: AttributeSyntax) -> Diagnostic {
  let name = node.attributeName
  let fixIt = FixIt(
    message: JSClassFixItMessage("Use '@SharedObject'", id: "jsclass-use-shared-object"),
    changes: [
      .replace(
        oldNode: Syntax(name),
        newNode: Syntax(
          IdentifierTypeSyntax(name: .identifier("SharedObject")).with(\.trailingTrivia, name.trailingTrivia)
        )
      )
    ]
  )
  return Diagnostic(
    node: node,
    message: JSClassDiagnosticMessage(
      "This class inherits from a shared object, so use @SharedObject instead of @JSClass",
      id: "jsclass-shared-object-superclass",
      severity: .warning
    ),
    fixIts: [fixIt]
  )
}

private struct JSClassDiagnosticMessage: DiagnosticMessage {
  let message: String
  let diagnosticID: MessageID
  let severity: DiagnosticSeverity

  init(_ message: String, id: String, severity: DiagnosticSeverity) {
    self.message = message
    self.diagnosticID = MessageID(domain: "ExpoModulesMacros", id: id)
    self.severity = severity
  }
}

private struct JSClassFixItMessage: FixItMessage {
  let message: String
  let fixItID: MessageID

  init(_ message: String, id: String) {
    self.message = message
    self.fixItID = MessageID(domain: "ExpoModulesMacros", id: id)
  }
}
