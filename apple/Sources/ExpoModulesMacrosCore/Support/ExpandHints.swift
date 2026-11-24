import SwiftSyntax

/// What the `expand` command knows about the files that it expands, for the macros that read more than
/// their own declaration. The compiler tells a macro which conformances a class already has, through the
/// `conformingTo` list of its roles. `expand` passes every conformance of the macro declaration for every
/// class, so it sets these hints instead. They are `nil` in the compiler and in the expansion tests.
///
/// A class is in the hints by its qualified name (see `qualifiedName(of:in:)`), and its superclass is
/// found by name in the scope of the class, as Swift does. So two classes with the same name in
/// different types are different classes. Two classes with the same qualified name, for example in two
/// modules, count as one.
public struct ExpandHints: Sendable {
  /// The qualified names of the classes in the expanded files whose superclass has a JavaScript class:
  /// `SharedObject`, `SharedRef`, a class with `@JSClass` or `@SharedObject`, or a class that inherits
  /// from one of them. `@JSClass` treats such a class as a subclass. A superclass in another file or
  /// package isn't found, so `expand` shows such a class as a root.
  public var jsSubclassNames: Set<String>

  /// The qualified names of the classes in the expanded files whose superclass is a shared object:
  /// `SharedObject`, `SharedRef`, a class with `@SharedObject`, or a class that inherits from one of
  /// them. `@JSClass` reports such a class.
  public var sharedObjectSubclassNames: Set<String>

  public init(jsSubclassNames: Set<String>, sharedObjectSubclassNames: Set<String>) {
    self.jsSubclassNames = jsSubclassNames
    self.sharedObjectSubclassNames = sharedObjectSubclassNames
  }

  /// The hints of the files that `expand` expands now.
  @TaskLocal public static var current: ExpandHints?

  /// Whether the superclass of `classDecl` has a JavaScript class. `lexicalContext` holds the
  /// declarations that enclose the class, innermost first, as a macro gets them.
  public func superclassHasJSClass(_ classDecl: ClassDeclSyntax, in lexicalContext: [Syntax]) -> Bool {
    return jsSubclassNames.contains(Self.qualifiedName(of: classDecl, in: lexicalContext))
  }

  /// Whether the superclass of `classDecl` is a shared object. `lexicalContext` holds the declarations
  /// that enclose the class, innermost first, as a macro gets them.
  public func superclassIsSharedObject(_ classDecl: ClassDeclSyntax, in lexicalContext: [Syntax]) -> Bool {
    return sharedObjectSubclassNames.contains(Self.qualifiedName(of: classDecl, in: lexicalContext))
  }

  /// The name of `classDecl` qualified with the types that `scopes` declare or extend, innermost first:
  /// `Outer.Circle` for a class in `Outer` or in an extension of it. Other scopes, such as a function
  /// that declares a local class, add nothing. Backticks and generic arguments are left out.
  public static func qualifiedName(of classDecl: ClassDeclSyntax, in scopes: some Sequence<Syntax>) -> String {
    var components = [withoutBackticks(classDecl.name.text)]
    for scope in scopes {
      if let extensionDecl = scope.as(ExtensionDeclSyntax.self) {
        components.append(typeSpelling(of: extensionDecl.extendedType) ?? extensionDecl.extendedType.trimmedDescription)
      } else if let name = typeName(of: scope) {
        components.append(withoutBackticks(name))
      }
    }
    return components.reversed().joined(separator: ".")
  }

  /// The superclass that `classDecl` names, spelled as `qualifiedName(of:in:)` spells names: `Base`,
  /// `Outer.Base` for `Outer.Base<Int>`. It is the first type of the clause, which may be a protocol.
  /// `nil` when the class has no clause or the type isn't a plain or qualified name.
  public static func superclassSpelling(of classDecl: ClassDeclSyntax) -> String? {
    return classDecl.inheritanceClause?.inheritedTypes.first.flatMap { typeSpelling(of: $0.type) }
  }
}

/// The name of a type declaration, or `nil` for any other node.
private func typeName(of node: Syntax) -> String? {
  if let classDecl = node.as(ClassDeclSyntax.self) {
    return classDecl.name.text
  }
  if let structDecl = node.as(StructDeclSyntax.self) {
    return structDecl.name.text
  }
  if let enumDecl = node.as(EnumDeclSyntax.self) {
    return enumDecl.name.text
  }
  if let actorDecl = node.as(ActorDeclSyntax.self) {
    return actorDecl.name.text
  }
  if let protocolDecl = node.as(ProtocolDeclSyntax.self) {
    return protocolDecl.name.text
  }
  return nil
}

/// A simple or qualified type name as written, without backticks or generic arguments, or `nil` for any
/// other kind of type.
private func typeSpelling(of type: TypeSyntax) -> String? {
  if let identifier = type.as(IdentifierTypeSyntax.self) {
    return withoutBackticks(identifier.name.text)
  }
  if let member = type.as(MemberTypeSyntax.self), let base = typeSpelling(of: member.baseType) {
    return base + "." + withoutBackticks(member.name.text)
  }
  return nil
}
