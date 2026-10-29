/// Adds to each `@SharedObject` class the `@JS` members it inherits from scanned `@SharedObject`
/// superclasses.
///
/// The `@SharedObject` macro binds the members of the superclass on the JavaScript objects of the
/// subclass too, since core builds each JavaScript class on the base `SharedObject` class and not on the
/// JavaScript class of the superclass. So the reported surface of a subclass lists the inherited members
/// as its own, and a consumer generates the same type as for any other class.

extension ExportedSurface {
  /// This surface with the inherited members added to each shared object. Runs after
  /// `resolvingRefs()`, so the refs in an inherited member are resolved from the superclass that
  /// declares it, as Swift resolves them.
  ///
  /// The superclass is looked up from the scope that encloses the class, the way `RefIndex` looks up a
  /// ref. A superclass the scan doesn't report as a shared object (a protocol, a class without
  /// `@SharedObject`, or a class from another module) ends the chain, so nothing is inherited through it.
  ///
  /// The members merge the way the macro binds them: the inherited ones first, then the class's own. An
  /// own member replaces an inherited function or property with the same JS name, separately for static
  /// and instance members, and an own event replaces an inherited event with the same JS name. The
  /// `@JS init` isn't inherited: core doesn't construct a subclass through the initializer of its
  /// superclass.
  ///
  /// A class that inherits `SharedRef` through its superclass gets the `sharedRef` of the superclass,
  /// with the class's own `nativeRefType` override when it has one.
  func mergingInheritedMembers() -> ExportedSurface {
    let index = RefIndex(surface: self)
    // The first declaration of each name wins, as in `RefIndex`.
    var declarations: [String: ExportedSharedObject] = [:]
    for sharedObject in sharedObjects where declarations[sharedObject.name] == nil {
      declarations[sharedObject.name] = sharedObject
    }

    // `chain` holds the classes being merged, so a malformed cycle in the inheritance ends instead of
    // recursing forever.
    func merged(_ sharedObject: ExportedSharedObject, chain: Set<String>) -> ExportedSharedObject {
      let scope = sharedObject.name.split(separator: ".").dropLast().joined(separator: ".")
      guard let superclass = sharedObject.superclass,
        let entry = index.lookup(superclass, in: scope),
        entry.kind == .sharedObject,
        !chain.contains(entry.name),
        let declaration = declarations[entry.name]
      else {
        return sharedObject
      }
      let parent = merged(declaration, chain: chain.union([sharedObject.name]))
      var result = sharedObject

      let ownMembers = Set(
        sharedObject.functions.map { MemberKey(jsName: $0.jsName, isStatic: $0.isStatic) }
          + sharedObject.properties.map { MemberKey(jsName: $0.jsName, isStatic: $0.isStatic) }
      )
      result.functions =
        parent.functions.filter { !ownMembers.contains(MemberKey(jsName: $0.jsName, isStatic: $0.isStatic)) }
        + sharedObject.functions
      result.properties =
        parent.properties.filter { !ownMembers.contains(MemberKey(jsName: $0.jsName, isStatic: $0.isStatic)) }
        + sharedObject.properties

      let ownEvents = Set(sharedObject.events.map(\.jsName))
      result.events = parent.events.filter { !ownEvents.contains($0.jsName) } + sharedObject.events

      if result.sharedRef == nil, let inherited = parent.sharedRef {
        result.sharedRef = ExportedSharedRef(
          native: inherited.native,
          nativeRefType: sharedObject.ownNativeRefType ?? inherited.nativeRefType
        )
      }
      return result
    }

    return ExportedSurface(
      modules: modules,
      sharedObjects: sharedObjects.map { merged($0, chain: []) },
      records: records,
      enums: enums,
      unions: unions
    )
  }
}

/// A member's slot on the JavaScript side: static members live on the constructor and instance members
/// on the prototype, so the two don't replace each other.
private struct MemberKey: Hashable {
  let jsName: String
  let isStatic: Bool
}
