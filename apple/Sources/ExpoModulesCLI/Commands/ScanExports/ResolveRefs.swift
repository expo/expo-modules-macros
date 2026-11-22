/// Fills in each `.ref`'s `refKind` once the whole scan is done.
///
/// A `TypeNode` is parsed from one `TypeSyntax` in isolation, so at parse time a name like `Status` is
/// just a name: the parser has no idea whether the scan will turn up an `@Record`, an `Enumerable`
/// enum, or nothing at all. Resolution is therefore a second pass over the collected surface, run once
/// every file has been walked.
///
/// A name is looked up the way Swift looks it up: from the type the use site is written in, outward to
/// file scope. In `Options`, `Encoding` names `Options.Encoding` when the scan declares one, else a
/// file-scope `Encoding`.
///
/// Three things change on a resolved ref:
/// - `name` becomes the declaration's qualified name, so a consumer can match it to the declaration
///   without repeating the scoped lookup.
/// - `refKind` names which kind declares it, so a consumer doesn't repeat this lookup.
/// - the `typeof` category is corrected for an enum, which crosses as its raw value rather than as an
///   object. That correction is the reason this can't be left to the consumer: the scanner is the only
///   side that knows the enum's `rawType`.
///
/// A name the scan never declared keeps its spelling, `refKind: nil`, and its `object` category. Not
/// an error: it is a platform convertible (`CGPoint`, `URL`) or a type from another module, and the
/// consumer's own catalog decides.

/// The declared names of a scanned surface, each mapped to how it should be reported at a use site.
/// Built once per scan and used for every ref lookup.
struct RefIndex {
  /// The declaration a ref resolves to.
  struct Entry: Equatable {
    /// The declaration's qualified name.
    let name: String
    let kind: RefKind
    /// The JS category a ref to the declaration crosses as.
    let jsType: JSType
    /// A `@SharedObject`'s JS name, `nil` for every other kind.
    var jsName: String? = nil
  }

  /// A declaration's qualified name -> its entry.
  private var entries: [String: Entry] = [:]

  init(surface: ExportedSurface) {
    for record in surface.records {
      entries[record.name] = Entry(name: record.name, kind: .record, jsType: .object)
    }
    for sharedObject in surface.sharedObjects {
      entries[sharedObject.name] = Entry(
        name: sharedObject.name,
        kind: .sharedObject,
        jsType: .object,
        jsName: sharedObject.jsName
      )
    }
    for union in surface.unions {
      // A union crosses as whichever alternative matched, so its category is only meaningful per
      // member. `object` is the honest coarse answer; the consumer reads `members` for the real shape.
      entries[union.name] = Entry(name: union.name, kind: .union, jsType: .object)
    }
    for enumeration in surface.enums {
      entries[enumeration.name] = Entry(
        name: enumeration.name,
        kind: .enum,
        jsType: jsType(ofRawType: enumeration.rawType)
      )
    }
  }

  /// The declaration a ref to `name` written inside the type `scope` resolves to, or `nil` when the
  /// scan declares no such type. `scope` is the qualified name of the type the use site is written
  /// in.
  ///
  /// The name is first looked up in `scope` and then in each enclosing scope out to file scope, so the
  /// innermost declaration wins, as in Swift. A leading `Self.` names `scope` itself, so it is dropped
  /// before the lookup. When that finds nothing, the leading components of a qualified spelling are
  /// dropped one at a time (`Media.Status` -> `Status`): a use site may qualify a name with a module
  /// the scan doesn't see, which is how the conformance and raw-type checks already match names.
  func lookup(_ name: String, in scope: String) -> Entry? {
    return scopedLookup(name, in: scope, entries: entries)
  }
}

/// The entry that a use of `name` written inside the type `scope` names, from `entries` keyed by
/// qualified name. Swift's lookup rules, as `RefIndex.lookup(_:in:)` documents them. Without
/// `dropsQualifiers`, a qualified spelling isn't looked up without its leading components.
func scopedLookup<Entry>(
  _ name: String,
  in scope: String,
  entries: [String: Entry],
  dropsQualifiers: Bool = true
) -> Entry? {
  let name = name.hasPrefix("Self.") ? String(name.dropFirst("Self.".count)) : name
  var components = scope.split(separator: ".").map(String.init)
  while true {
    if let entry = entries[(components + [name]).joined(separator: ".")] {
      return entry
    }
    if components.isEmpty {
      break
    }
    components.removeLast()
  }
  guard dropsQualifiers else {
    return nil
  }
  var suffix = name.split(separator: ".").map(String.init).dropFirst()
  while !suffix.isEmpty {
    if let entry = entries[suffix.joined(separator: ".")] {
      return entry
    }
    suffix = suffix.dropFirst()
  }
  return nil
}

/// The JS category a raw-value enum crosses as: its raw value's. A bare `Enumerable` conformance with
/// no raw type has nothing to go on, so it stays an object.
private func jsType(ofRawType rawType: TypeNode?) -> JSType {
  guard let rawType, let jsType = rawType.jsType else {
    return .object
  }
  return jsType
}

extension TypeNode {
  /// This node with every `.ref` in it resolved against `index` from the type `scope`, recursively.
  /// Returns an unchanged node when nothing in it resolves.
  func resolvingRefs(using index: RefIndex, in scope: String) -> TypeNode {
    switch self {
    case .primitive, .unknown:
      return self
    case .sharedRef:
      // The native type never reaches JS, so it isn't looked up among the scanned declarations.
      return self
    case .ref(let name, _, _):
      guard let entry = index.lookup(name, in: scope) else {
        return self
      }
      // Only an enum crosses as something other than an object, so only it carries an override.
      return .ref(
        name: entry.name,
        refKind: entry.kind,
        jsTypeOverride: entry.jsType == .object ? nil : entry.jsType
      )
    case .optional(let wrapped):
      return .optional(wrapped: wrapped.resolvingRefs(using: index, in: scope))
    case .array(let element):
      return .array(element: element.resolvingRefs(using: index, in: scope))
    case .dictionary(let key, let value):
      return .dictionary(
        key: key.resolvingRefs(using: index, in: scope),
        value: value.resolvingRefs(using: index, in: scope)
      )
    case .promise(let value):
      return .promise(value: value.resolvingRefs(using: index, in: scope))
    case .tuple(let elements, let name):
      return .tuple(elements: elements.map { $0.resolvingRefs(using: index, in: scope) }, name: name)
    case .object(let properties, let name):
      return .object(
        properties: properties.map {
          TypeNodeProperty(name: $0.name, type: $0.type.resolvingRefs(using: index, in: scope))
        },
        name: name
      )
    case .function(let parameters, let returns, let isAsync, let isThrowing):
      return .function(
        parameters: parameters.map { $0.resolvingRefs(using: index, in: scope) },
        returns: returns?.resolvingRefs(using: index, in: scope),
        isAsync: isAsync,
        isThrowing: isThrowing
      )
    }
  }
}

extension ExportedSurface {
  /// This surface with every `.ref` in every reported type resolved against its own declarations. The
  /// second pass `scanExports` runs once the walk is done.
  ///
  /// Each type's refs are looked up from that type, so a ref resolves to a type nested in it before
  /// one at file scope. Only the boundary types are rewritten; names, flags, and ordering are
  /// untouched. The declared types (a record's own name, a union's members) are not themselves refs,
  /// so they carry no `refKind`: it is the *use sites* that gain one.
  func resolvingRefs() -> ExportedSurface {
    let index = RefIndex(surface: self)
    return ExportedSurface(
      modules: modules.map { module in
        var resolved = module
        resolved.functions = module.functions.map { $0.resolvingRefs(using: index, in: module.name) }
        resolved.properties = module.properties.map { $0.resolvingRefs(using: index, in: module.name) }
        resolved.events = module.events.map { $0.resolvingRefs(using: index, in: module.name) }
        resolved.classes = module.classes.map { exportedClass in
          guard let entry = index.lookup(exportedClass.name, in: module.name),
            entry.kind == .sharedObject
          else {
            return exportedClass
          }
          return ExportedClass(name: entry.name, jsName: entry.jsName)
        }
        return resolved
      },
      sharedObjects: sharedObjects.map { sharedObject in
        var resolved = sharedObject
        if let initializer = sharedObject.initializer {
          resolved.initializer?.parameters = initializer.parameters.map {
            $0.resolvingRefs(using: index, in: sharedObject.name)
          }
        }
        resolved.functions = sharedObject.functions.map { $0.resolvingRefs(using: index, in: sharedObject.name) }
        resolved.properties = sharedObject.properties.map { $0.resolvingRefs(using: index, in: sharedObject.name) }
        resolved.events = sharedObject.events.map { $0.resolvingRefs(using: index, in: sharedObject.name) }
        return resolved
      },
      records: records.map { record in
        var resolved = record
        resolved.properties = record.properties.map { property in
          var resolvedProperty = property
          resolvedProperty.type = property.type.resolvingRefs(using: index, in: record.name)
          return resolvedProperty
        }
        return resolved
      },
      // An enum's raw type is a primitive or an unscanned spelling, never a ref to another scanned
      // type, so there is nothing in one to resolve.
      enums: enums,
      unions: unions.map { union in
        var resolved = union
        resolved.members = union.members.map { member in
          var resolvedMember = member
          resolvedMember.type = member.type.resolvingRefs(using: index, in: union.name)
          return resolvedMember
        }
        return resolved
      },
      // The props and events are written in a `@ViewProps` struct, so their refs are looked up from it.
      // `joiningViewProps(_:)` runs first and sets the `scope` of each one to the qualified name of its
      // struct, which is the view's `propsType` or a struct that it extends.
      views: views.map { view in
        var resolved = view
        resolved.props = view.props?.map { prop in
          var resolvedProp = prop
          resolvedProp.type = prop.type.resolvingRefs(using: index, in: prop.scope ?? view.propsType)
          return resolvedProp
        }
        resolved.events = view.events?.map { event in
          var resolvedEvent = event
          resolvedEvent.payload = event.payload?.resolvingRefs(using: index, in: event.scope ?? view.propsType)
          return resolvedEvent
        }
        return resolved
      }
    )
  }

  /// This surface with the props and events of each view's `@ViewProps` struct copied into the view.
  /// The struct is looked up from the view like a ref, by its name without generic arguments, so it
  /// may be declared in another file or nested (`CardView.Props`). A found struct gives the view its
  /// qualified name as `propsType`. A view whose struct the scan doesn't declare keeps `props` and
  /// `events` at `nil`, and `propsType` as written.
  ///
  /// A struct declared more than once, in `#if` branches, contributes the props and events of each
  /// declaration whose platforms overlap the platforms of the view, as a superclass does in
  /// `mergingInheritedMembers()`. Each prop and event keeps its own `platforms`. A view that builds on
  /// none of those platforms is treated as one whose struct the scan doesn't declare.
  ///
  /// The props and events of a struct that `@ViewProps(extending:)` names come after the own ones, as
  /// the macro orders `PropName.allCases`, because JavaScript sets them on the view by their own names.
  func joiningViewProps(_ declarations: [ViewPropsDeclaration]) -> ExportedSurface {
    let entries = Dictionary(grouping: declarations, by: \.name)
    return ExportedSurface(
      modules: modules,
      sharedObjects: sharedObjects,
      records: records,
      enums: enums,
      unions: unions,
      views: views.map { view in
        let platforms = Set(view.platforms.map(\.name))
        guard let name = view.propsTypeLookupName,
          let variants = viewPropsVariants(named: name, in: view.name, platforms: platforms, entries: entries)
        else {
          return view
        }
        let members = viewPropsMembers(of: variants, platforms: platforms, entries: entries)
        var joined = view
        joined.propsType = variants[0].name
        joined.props = members.props
        joined.events = members.events
        return joined
      }
    )
  }
}

/// The declarations of the `@ViewProps` struct that `name` names from `scope`, which build on one of the
/// given platforms, or `nil` when there is none.
private func viewPropsVariants(
  named name: String,
  in scope: String,
  platforms: Set<String>,
  entries: [String: [ViewPropsDeclaration]]
) -> [ViewPropsDeclaration]? {
  let variants = scopedLookup(name, in: scope, entries: entries)?.filter { declaration in
    declaration.platforms.contains { platforms.contains($0.name) }
  }
  guard let variants, !variants.isEmpty else {
    return nil
  }
  return variants
}

/// The props and events of the declarations of one `@ViewProps` struct, then those of the struct that it
/// extends, and so on. Each one gets the name of its struct as its `scope`, which `resolvingRefs()` looks
/// its refs up from. A base that the scan doesn't declare adds nothing. `visited` holds the structs that
/// extend this one, to stop at a cycle, which the compiler rejects.
private func viewPropsMembers(
  of variants: [ViewPropsDeclaration],
  platforms: Set<String>,
  entries: [String: [ViewPropsDeclaration]],
  visited: Set<String> = []
) -> (props: [ExportedViewProp], events: [ExportedViewEvent]) {
  let name = variants[0].name
  guard !visited.contains(name) else {
    return ([], [])
  }
  var props = variants.flatMap(\.props).map { prop in
    var scoped = prop
    scoped.scope = name
    return scoped
  }
  var events = variants.flatMap(\.events).map { event in
    var scoped = event
    scoped.scope = name
    return scoped
  }
  // The declarations in `#if` branches can each extend props. Each base is joined once.
  var baseNames: [String] = []
  for case let baseName? in variants.map(\.baseLookupName) where !baseNames.contains(baseName) {
    baseNames.append(baseName)
  }
  for baseName in baseNames {
    guard let baseVariants = viewPropsVariants(named: baseName, in: name, platforms: platforms, entries: entries)
    else {
      continue
    }
    let base = viewPropsMembers(
      of: baseVariants,
      platforms: platforms,
      entries: entries,
      visited: visited.union([name])
    )
    props += base.props
    events += base.events
  }
  return (props, events)
}

extension ExportedParameter {
  fileprivate func resolvingRefs(using index: RefIndex, in scope: String) -> ExportedParameter {
    var resolved = self
    resolved.type = type.resolvingRefs(using: index, in: scope)
    return resolved
  }
}

extension ExportedFunction {
  fileprivate func resolvingRefs(using index: RefIndex, in scope: String) -> ExportedFunction {
    var resolved = self
    resolved.parameters = parameters.map { $0.resolvingRefs(using: index, in: scope) }
    resolved.returns = returns?.resolvingRefs(using: index, in: scope)
    return resolved
  }
}

extension ExportedProperty {
  fileprivate func resolvingRefs(using index: RefIndex, in scope: String) -> ExportedProperty {
    var resolved = self
    resolved.type = type?.resolvingRefs(using: index, in: scope)
    return resolved
  }
}

extension ExportedEvent {
  fileprivate func resolvingRefs(using index: RefIndex, in scope: String) -> ExportedEvent {
    var resolved = self
    resolved.payload = payload?.resolvingRefs(using: index, in: scope)
    return resolved
  }
}
