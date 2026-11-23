import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

/// Member macro applied to a `SharedObject` subclass, direct or not (a `SharedRef<T>` subclass too).
/// Scans the class body for declarations marked with `@JS` and binds them directly through overrides of
/// the `SharedObject` hooks core calls when it builds the JavaScript class. The class's JavaScript name
/// is emitted as a `_jsName` override, and its place in the JavaScript class chain as `_jsClassType` and
/// `_jsSuperclassType` overrides.
///
///   @SharedObject
///   public final class Cache: SharedObject {
///     @JS
///     init(name: String) { self.name = name }
///
///     @JS
///     func get(_ key: String) -> String? { ... }
///
///     @JS
///     var size: Int { 42 }
///   }
///
/// The companion `@ExpoModule(classes: [Cache.self])` registers the class with the module, which
/// exposes it in its JavaScript object.
///
/// As an extension macro, it adds an `AnySharedObject` conformance when the class doesn't conform
/// yet, and an `@unchecked Sendable` conformance when the class isn't `Sendable` yet.
///
/// The members and their attributes come from `JSClassExpansion`. This macro adds what is specific to
/// shared objects: the check for a superclass, the receiver of an instance binding, and the
/// `AnySharedObject` conformance.
public struct SharedObjectMacro: MemberMacro {
  public static func expansion(
    of node: AttributeSyntax,
    providingMembersOf declaration: some DeclGroupSyntax,
    conformingTo protocols: [TypeSyntax],
    in context: some MacroExpansionContext
  ) throws -> [DeclSyntax] {
    guard let classDecl = declaration.as(ClassDeclSyntax.self) else {
      throw MacroExpansionErrorMessage("@SharedObject can only be applied to a class")
    }
    // `@JSClass` adds nothing to a class with this macro, so this one reports the class.
    if let jsClassAttribute = classDecl.attributes.firstAttribute(named: "JSClass") {
      throw DiagnosticsError(diagnostics: [bothMacrosDiagnostic(for: jsClassAttribute, in: classDecl)])
    }
    diagnoseNonPublicClass(
      classDecl,
      macroName: "@SharedObject",
      reason: "export it",
      idPrefix: "sharedobject",
      in: context
    )

    // A class without an inheritance clause has no superclass, so it can't be a `SharedObject`. Any
    // other superclass isn't checked: the macro sees only this declaration, so it can't tell an
    // indirect subclass (`class Thumbnail: ImageRef`) from an unrelated class. The compiler reports a
    // class that isn't a `SharedObject` subclass on the `_jsName` override, which is always emitted.
    if classDecl.inheritanceClause == nil {
      throw DiagnosticsError(diagnostics: [missingBaseClassDiagnostic(for: classDecl)])
    }
    let typeName = classDecl.name.text

    // A superclass other than `SharedObject` or `SharedRef` may be another `@SharedObject` class, whose
    // JavaScript class is up the prototype chain of this class's prototype and constructor.
    //
    // An instance binding recovers its receiver with `native(from:as:)`, which reads the native state
    // that pairs a shared object with its JavaScript object, and throws on a foreign object or a type
    // mismatch.
    let expansion = JSClassExpansion(
      classDecl: classDecl,
      macroAttribute: node,
      macroName: "@SharedObject",
      instanceUnwrapStatement:
        "let _self = try SharedObject.native(from: this.asObject(in: runtime), as: \(typeName).self)",
      mayInheritJSMembers: !inheritsFromAny(classDecl, names: ["SharedObject", "SharedRef"]),
      // A shared object always has a `SharedObject` superclass, which implements the hooks.
      isRoot: false,
      // Core creates the JavaScript object of a shared object that native code returns.
      instancesComeFromConstructor: false
    )
    return try expansion.members(in: context)
  }
}

extension SharedObjectMacro: MemberAttributeMacro {
  public static func expansion(
    of node: AttributeSyntax,
    attachedTo declaration: some DeclGroupSyntax,
    providingAttributesFor member: some DeclSyntaxProtocol,
    in context: some MacroExpansionContext
  ) throws -> [AttributeSyntax] {
    JSClassExpansion.memberAttributes(for: member, enclosedBy: declaration)
  }
}

extension SharedObjectMacro: ExtensionMacro {
  public static func expansion(
    of node: AttributeSyntax,
    attachedTo declaration: some DeclGroupSyntax,
    providingExtensionsOf type: some TypeSyntaxProtocol,
    conformingTo protocols: [TypeSyntax],
    in context: some MacroExpansionContext
  ) throws -> [ExtensionDeclSyntax] {
    var extensions: [ExtensionDeclSyntax] = []
    if let conformance = anySharedObjectExtension(for: type, of: declaration, conformingTo: protocols) {
      extensions.append(conformance)
    }
    if let sendable = uncheckedSendableExtension(for: type, of: declaration, conformingTo: protocols) {
      extensions.append(sendable)
    }
    return extensions
  }
}

/// The `AnySharedObject` conformance that `@SharedObject` adds to its class, or `nil` when the class
/// already conforms. The compiler leaves `AnySharedObject` out of `protocols` when the class conforms,
/// also through a superclass, as every subclass of `SharedObject` does. The inheritance clause is
/// checked too, so that `expand`, which passes every declared conformance, gives the same result for a
/// class that names `SharedObject`, `SharedRef` or `AnySharedObject`, also as
/// `nonisolated AnySharedObject`. `expand` can't see that an indirect subclass
/// (`class Thumbnail: ImageRef`) conforms, so it reports the conformance for it.
///
/// The extension is empty. Only a class that has no `SharedObject` superclass gets it, and the macro
/// emits the hooks of every class as overrides of `SharedObject` members, so such a class doesn't
/// compile. The conformance is `nonisolated`, so core can use it on any thread also when the module
/// builds with `-default-isolation MainActor`.
private func anySharedObjectExtension(
  for type: some TypeSyntaxProtocol,
  of declaration: some DeclGroupSyntax,
  conformingTo protocols: [TypeSyntax]
) -> ExtensionDeclSyntax? {
  guard protocols.contains(where: { $0.trimmedDescription == "AnySharedObject" }),
    let classDecl = declaration.as(ClassDeclSyntax.self),
    !inheritsFromAny(classDecl, names: ["SharedObject", "SharedRef"]),
    !inheritsProtocol(named: "AnySharedObject", in: classDecl)
  else {
    return nil
  }
  let conformance: DeclSyntax = "extension \(type.trimmed): nonisolated AnySharedObject {}"
  return conformance.cast(ExtensionDeclSyntax.self)
}

/// The error for a `@SharedObject` class without an inheritance clause, with a fix-it that makes it
/// inherit from `SharedObject`: `class Cache {` becomes `class Cache: SharedObject {`.
private func missingBaseClassDiagnostic(for classDecl: ClassDeclSyntax) -> Diagnostic {
  // The name carries the space before `{` as trailing trivia, so move it onto the clause to keep the
  // spacing.
  let name = classDecl.name
  let clause = InheritanceClauseSyntax(
    colon: .colonToken(trailingTrivia: .space),
    inheritedTypes: InheritedTypeListSyntax([
      InheritedTypeSyntax(type: TypeSyntax(IdentifierTypeSyntax(name: .identifier("SharedObject"))))
    ])
  )
  let fixIt = FixIt(
    message: SharedObjectFixItMessage("Inherit from 'SharedObject'", id: "sharedobject-add-base-class"),
    changes: [
      .replace(
        oldNode: Syntax(classDecl),
        newNode: Syntax(
          classDecl
            .with(\.name, name.with(\.trailingTrivia, []))
            .with(\.inheritanceClause, clause.with(\.trailingTrivia, name.trailingTrivia))
        )
      )
    ]
  )
  return Diagnostic(
    node: name,
    message: SharedObjectDiagnosticMessage(
      "@SharedObject class '\(name.text)' must inherit from 'SharedObject', directly or through another class such as 'SharedRef'. Add ': SharedObject' to the class declaration",
      id: "sharedobject-missing-base-class"
    ),
    fixIts: [fixIt]
  )
}

/// The error for a class with both `@SharedObject` and `@JSClass`, with a fix-it that removes `@JSClass`.
/// The fix-it removes the attribute and the space up to the next token, so the next attribute or
/// keyword takes its place.
private func bothMacrosDiagnostic(for attribute: AttributeSyntax, in classDecl: ClassDeclSyntax) -> Diagnostic {
  let end =
    attribute.lastToken(viewMode: .sourceAccurate)?.nextToken(viewMode: .sourceAccurate)?
    .positionAfterSkippingLeadingTrivia ?? attribute.endPosition
  let fixIt = FixIt(
    message: SharedObjectFixItMessage("Remove '@JSClass'", id: "sharedobject-remove-jsclass"),
    changes: [.replaceText(range: attribute.positionAfterSkippingLeadingTrivia..<end, with: "", in: Syntax(classDecl))]
  )
  return Diagnostic(
    node: attribute,
    message: SharedObjectDiagnosticMessage(
      "A @SharedObject class can't also have @JSClass: @SharedObject gives the class its JavaScript class. Remove @JSClass",
      id: "sharedobject-with-jsclass"
    ),
    fixIts: [fixIt]
  )
}

private struct SharedObjectDiagnosticMessage: DiagnosticMessage {
  let message: String
  let diagnosticID: MessageID
  let severity: DiagnosticSeverity = .error

  init(_ message: String, id: String) {
    self.message = message
    self.diagnosticID = MessageID(domain: "ExpoModulesMacros", id: id)
  }
}

private struct SharedObjectFixItMessage: FixItMessage {
  let message: String
  let fixItID: MessageID

  init(_ message: String, id: String) {
    self.message = message
    self.fixItID = MessageID(domain: "ExpoModulesMacros", id: id)
  }
}
