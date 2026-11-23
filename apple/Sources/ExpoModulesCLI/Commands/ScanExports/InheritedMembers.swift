/// Adds to each `@SharedObject` and `@JSClass` class its `superclass`, the nearest one with either macro,
/// and the `@JS` members it inherits from it. A `@SharedObject` class can name a `@JSClass` class as
/// its superclass, and the scan resolves that chain too. A `@JSClass` class can't extend a shared
/// object: the macro reports it.
///
/// Core builds the JavaScript class of a subclass on the JavaScript class of its nearest superclass
/// with the macro, so an instance and the constructor of the subclass get the members of that class
/// through their prototype chains. The reported surface of a subclass lists the inherited members, with
/// `inheritedFrom`, before its own. So a consumer can generate the same type as for any other class, or
/// a class that extends the superclass and leaves the inherited members out.

extension ExportedSurface {
  /// This surface with the `superclass` of each `@SharedObject` and `@JSClass` class and the members it
  /// inherits. Runs after `resolvingRefs()`, so the refs in an inherited member are resolved from the
  /// superclass that declares it, as Swift resolves them.
  ///
  /// The superclass is looked up from the scope that encloses the class, the way `RefIndex` looks up a
  /// ref. The lookup goes on through `plainClasses`, the classes without a macro, as the chain does at
  /// run time (see `SuperclassResolver`).
  ///
  /// A superclass declared more than once, in `#if` branches, contributes the members of each
  /// declaration whose platforms overlap the platforms of the class. Each member keeps its own
  /// `platforms`. When a class without the macro on the way is declared in `#if` branches that lead to
  /// different superclasses, each platform of the class inherits from the superclass that its branch
  /// leads to. An inherited member then keeps only the platforms that lead to its class, and
  /// `superclass` is the name that the class writes, without a `jsName`.
  ///
  /// The members merge the way the prototype chain resolves them: the inherited ones first, then the
  /// class's own. An own member replaces an inherited function or property with the same JS name or
  /// symbol, separately for static and instance members. Events are kept from both: an event is a stored
  /// property that emits under its JS name, so a subclass can't replace an inherited one, and both are
  /// sent. The `@JS init` isn't inherited: core doesn't construct a subclass through the initializer of
  /// its superclass.
  ///
  /// A class that inherits `SharedRef` through its superclasses gets the `T` of the nearest one that
  /// names it, with the nearest `nativeRefType` override: its own, or one of a class on the way.
  func mergingInheritedMembers(through plainClasses: [PlainClassDeclaration]) -> ExportedSurface {
    let resolver = SuperclassResolver(surface: self, plainClasses: plainClasses)
    let declarations = Dictionary(grouping: sharedObjects + classes, by: \.name)

    // `chain` holds the classes being merged, so a malformed cycle in the inheritance ends instead of
    // recursing forever.
    func merged(_ jsClass: ExportedJSClass, chain: Set<String>) -> ExportedJSClass {
      var result = jsClass
      let groups = resolver.resolutions(of: jsClass)
      result.superclass = superclass(of: jsClass, in: groups)
      // With one group, every platform of the class inherits the same members, so they keep their own
      // platforms.
      let limitsPlatforms = groups.count > 1

      var functions: [ExportedFunction] = []
      var properties: [ExportedProperty] = []
      var events: [ExportedEvent] = []
      var sharedRef: ExportedSharedRef? = nil
      for group in groups {
        let nativeRefType = jsClass.ownNativeRefType ?? group.nativeRefType
        switch group.target {
        case .unresolved:
          continue

        case .base(let baseSharedRef):
          if sharedRef == nil, let baseSharedRef {
            sharedRef = ExportedSharedRef(
              native: baseSharedRef.native,
              nativeRefType: nativeRefType ?? baseSharedRef.nativeRefType
            )
          }

        case .jsClass(let name, _):
          guard !chain.contains(name) else {
            continue
          }
          let platforms = Set(group.platforms)
          let parents = (declarations[name] ?? [])
            .filter { declaration in declaration.platforms.contains { platforms.contains($0.name) } }
            .map { merged($0, chain: chain.union([jsClass.name])) }
          func inherited<Member: InheritedMember>(_ members: [Member], from parent: String) -> [Member] {
            let members = members.map { $0.inherited(from: parent) }
            return limitsPlatforms ? members.compactMap { $0.limited(to: platforms) } : members
          }
          for parent in parents {
            functions += inherited(parent.functions, from: parent.name)
            properties += inherited(parent.properties, from: parent.name)
            events += inherited(parent.events, from: parent.name)
          }
          // Every declaration of a superclass names the same superclass in practice, so the first one
          // that inherits `SharedRef` stands for all of them.
          if sharedRef == nil, let inherited = parents.lazy.compactMap(\.sharedRef).first {
            sharedRef = ExportedSharedRef(
              native: inherited.native,
              nativeRefType: nativeRefType ?? inherited.nativeRefType
            )
          }
        }
      }

      let ownMembers = Set(
        jsClass.functions.map { MemberKey(jsName: $0.jsName, symbol: $0.symbol, isStatic: $0.isStatic) }
          + jsClass.properties.map { MemberKey(jsName: $0.jsName, symbol: $0.symbol, isStatic: $0.isStatic) }
      )
      result.functions =
        functions.filter {
          !ownMembers.contains(MemberKey(jsName: $0.jsName, symbol: $0.symbol, isStatic: $0.isStatic))
        }
        + jsClass.functions
      result.properties =
        properties.filter {
          !ownMembers.contains(MemberKey(jsName: $0.jsName, symbol: $0.symbol, isStatic: $0.isStatic))
        }
        + jsClass.properties
      result.events = events + jsClass.events
      if result.sharedRef == nil {
        result.sharedRef = sharedRef
      }
      return result
    }

    return ExportedSurface(
      modules: modules,
      sharedObjects: sharedObjects.map { merged($0, chain: []) },
      classes: classes.map { merged($0, chain: []) },
      records: records,
      enums: enums,
      unions: unions,
      views: views
    )
  }
}

/// The `superclass` of `jsClass`: the superclass that every platform of the class leads to, or the
/// name that the class writes, without a `jsName`, when different platforms lead to different ones.
private func superclass(
  of jsClass: ExportedJSClass,
  in groups: [SuperclassResolver.Group]
) -> ExportedSuperclass? {
  guard let target = groups.first?.target else {
    return nil
  }
  guard groups.count == 1 else {
    return jsClass.declaredSuperclass.map { ExportedSuperclass(name: $0, jsName: nil) }
  }
  switch target {
  case .jsClass(let name, let jsName):
    return ExportedSuperclass(name: name, jsName: jsName)
  case .unresolved(let spelling):
    return ExportedSuperclass(name: spelling, jsName: nil)
  case .base:
    return nil
  }
}

/// Where the superclass of a `@SharedObject` or `@JSClass` class leads on one platform, as
/// `SuperclassResolver` finds it.
enum SuperclassTarget: Equatable {
  /// The nearest superclass with `@SharedObject` or `@JSClass`, by its qualified `name`.
  case jsClass(name: String, jsName: String)

  /// No superclass has either macro: the chain ends at `SharedObject`, `SharedRef`, a class without a
  /// superclass, or a protocol that the class names instead (`AnySharedObject`, `AnyJavaScriptClass`,
  /// `Sendable`). `sharedRef` is set when a class without the macro on the way names `SharedRef<T>`.
  case base(sharedRef: ExportedSharedRef?)

  /// A superclass that the scan doesn't declare as a class, by its spelling: a class in another
  /// package, a protocol, or a class in a cycle of classes without the macro.
  case unresolved(spelling: String)
}

/// Finds the nearest superclass with `@SharedObject` or `@JSClass` of a class with either macro, through
/// the classes without a macro between them, as core does at run time.
struct SuperclassResolver {
  /// The platforms of a class that lead to the same `target`.
  struct Group: Equatable {
    let target: SuperclassTarget

    /// The nearest `nativeRefType` override of the classes without the macro on the way, or `.none`,
    /// on the first of `platforms`.
    let nativeRefType: String??

    /// The names of the platforms, in the order of the platforms of the class.
    var platforms: [String]
  }

  private enum Entry {
    /// A class with `@SharedObject` or `@JSClass`.
    case jsClass(name: String, jsName: String)
    /// The declarations of a class without a macro, more than one when it is declared in `#if`
    /// branches.
    case plainClass([PlainClassDeclaration])
    /// A record, an enum or a union, which no class inherits.
    case other
  }

  /// A declaration's qualified name -> its entry.
  private var entries: [String: Entry] = [:]

  /// The classes with `@SharedObject` or `@JSClass`.
  private let jsClasses: [ExportedJSClass]

  init(surface: ExportedSurface, plainClasses: [PlainClassDeclaration]) {
    for name in surface.records.map(\.name) + surface.enums.map(\.name) + surface.unions.map(\.name) {
      entries[name] = .other
    }
    for (name, declarations) in Dictionary(grouping: plainClasses, by: \.name) {
      entries[name] = .plainClass(declarations)
    }
    jsClasses = surface.sharedObjects + surface.classes
    for jsClass in jsClasses {
      entries[jsClass.name] = .jsClass(name: jsClass.name, jsName: jsClass.jsName)
    }
  }

  /// Where the superclass of `jsClass` leads, with the platforms of the class grouped by the
  /// target they lead to. One group when every platform leads to the same target.
  func resolutions(of jsClass: ExportedJSClass) -> [Group] {
    var groups: [Group] = []
    for platform in jsClass.platforms.map(\.name) {
      let (target, nativeRefType, _) = resolve(jsClass, on: platform)
      if let index = groups.firstIndex(where: { $0.target == target }) {
        groups[index].platforms.append(platform)
      } else {
        groups.append(Group(target: target, nativeRefType: nativeRefType, platforms: [platform]))
      }
    }
    return groups
  }

  /// The names, without the types they are nested in, of the superclasses on the way that the scan
  /// doesn't declare under the name as written. A qualified name that is found only without its
  /// qualifiers counts too, since the class it names can be in a file that the scan hasn't parsed.
  func unresolvedSuperclassNames() -> Set<String> {
    var names: Set<String> = []
    for jsClass in jsClasses {
      for platform in jsClass.platforms.map(\.name) {
        names.formUnion(resolve(jsClass, on: platform).missingNames)
      }
    }
    return names
  }

  /// Follows the superclass of `jsClass` on `platform` through the classes without a macro until
  /// it reaches a class with a macro, the base class, or a name that the scan doesn't declare as a class.
  /// It follows the declaration of a class without a macro that builds on `platform`.
  ///
  /// `missingNames` are the names, without their qualifiers, that the lookup didn't find as written. A
  /// qualified name is then looked up without its leading components, which can name a module the scan
  /// doesn't see.
  private func resolve(
    _ jsClass: ExportedJSClass,
    on platform: String
  ) -> (target: SuperclassTarget, nativeRefType: String??, missingNames: Set<String>) {
    var spelling = jsClass.declaredSuperclass
    var scope = enclosingScope(of: jsClass.name)
    var nativeRefType: String?? = .none
    var missingNames: Set<String> = []
    var visited: Set<String> = []

    while let current = spelling {
      var entry = scopedLookup(current, in: scope, entries: entries, dropsQualifiers: false)
      if entry == nil {
        if let name = current.split(separator: ".").last {
          missingNames.insert(String(name))
        }
        entry = scopedLookup(current, in: scope, entries: entries)
      }
      switch entry {
      case .jsClass(let name, let jsName):
        return (.jsClass(name: name, jsName: jsName), nativeRefType, missingNames)

      case .plainClass(let declarations):
        guard
          let declaration = declarations.first(where: { declaration in
            declaration.platforms.contains { $0.name == platform }
          }),
          visited.insert(declaration.name).inserted
        else {
          return (.unresolved(spelling: current), nativeRefType, missingNames)
        }
        nativeRefType = nativeRefType ?? declaration.ownNativeRefType
        guard let superclass = declaration.declaredSuperclass else {
          return (.base(sharedRef: declaration.sharedRef), nativeRefType, missingNames)
        }
        spelling = superclass
        scope = enclosingScope(of: declaration.name)

      case .other, nil:
        return (.unresolved(spelling: current), nativeRefType, missingNames)
      }
    }
    return (.base(sharedRef: nil), nativeRefType, missingNames)
  }
}

/// The qualified name of the type that encloses the declaration named `name`, empty at file scope.
private func enclosingScope(of name: String) -> String {
  return name.split(separator: ".").dropLast().joined(separator: ".")
}

/// A member that a class can inherit, which records the class that declares it.
private protocol InheritedMember {
  var inheritedFrom: String? { get set }
  var platforms: [ExportedPlatform] { get set }
}

extension InheritedMember {
  /// This member as a member of a subclass of `className`: `inheritedFrom` stays when the member is
  /// inherited already, and becomes `className` otherwise.
  fileprivate func inherited(from className: String) -> Self {
    var member = self
    member.inheritedFrom = inheritedFrom ?? className
    return member
  }

  /// This member with only the `platforms` named in `names`, or `nil` when it has none of them.
  fileprivate func limited(to names: Set<String>) -> Self? {
    var member = self
    member.platforms = platforms.filter { names.contains($0.name) }
    return member.platforms.isEmpty ? nil : member
  }
}

extension ExportedFunction: InheritedMember {}
extension ExportedProperty: InheritedMember {}
extension ExportedEvent: InheritedMember {}

/// A member's slot on the JavaScript side: static members live on the constructor and instance members
/// on the prototype, so the two don't replace each other.
/// The key a member binds under: its JS name or its symbol, one of which is set.
private struct MemberKey: Hashable {
  let jsName: String?
  let symbol: ExportedSymbol?
  let isStatic: Bool
}
