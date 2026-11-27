import SwiftSyntax

/// The type aliases declared in the body of a class whose aliased type holds a tuple (see
/// `TupleConversion`), resolved to that type. A macro sees only the declaration it's attached to, so
/// `@ExpoModule` and `@SharedObject` collect the aliases from their class body, and resolve them in
/// the `@JS` members they bind before reading the members' types: an alias of a tuple can't convert
/// through `decode` / `encode` under its own name, because the tuple can't conform.
///
/// An alias declared anywhere else (at file level, in an extension or in another type) isn't visible
/// to the macros, so it converts under its own name and fails its conformance assertion. A generic
/// alias isn't resolved either.
internal struct TupleTypeAliases {
  /// The resolved type of each alias, by name.
  private let resolved: [String: TypeSyntax]

  init(in memberBlock: MemberBlockSyntax) {
    var declared: [String: TypeSyntax] = [:]
    for member in memberBlock.members {
      guard let alias = member.decl.as(TypeAliasDeclSyntax.self), alias.genericParameterClause == nil else {
        continue
      }
      declared[alias.name.text] = alias.initializer.value
    }
    // Aliases may refer to each other, so resolve each one once with cycle detection. An alias that
    // refers back to itself (directly or transitively) is invalid Swift and is left unresolved,
    // avoiding exponential expansion on cyclic definitions.
    let resolved = AliasResolver(declared: declared).resolveAll()
    self.resolved = resolved.filter { tupleConversion(of: $0.value) != nil }
  }

  /// True when the class body declares no alias that holds a tuple.
  var isEmpty: Bool {
    return resolved.isEmpty
  }

  /// `node` with each reference to an alias that holds a tuple replaced by the aliased type.
  func resolving<Node: SyntaxProtocol>(_ node: Node) -> Node {
    guard !resolved.isEmpty else {
      return node
    }
    return AliasRewriter(lookup: { resolved[$0] }).rewrite(node).cast(Node.self)
  }
}

/// Resolves declared aliases through each other with memoized DFS and cycle detection. Any alias
/// that reaches a cycle is omitted from the resolved map.
private final class AliasResolver {
  private enum State {
    case visiting
    case resolved(TypeSyntax)
    case cyclic
  }

  private let declared: [String: TypeSyntax]
  private var states: [String: State] = [:]

  init(declared: [String: TypeSyntax]) {
    self.declared = declared
  }

  func resolveAll() -> [String: TypeSyntax] {
    var result: [String: TypeSyntax] = [:]
    for name in declared.keys {
      if let resolved = resolve(name) {
        result[name] = resolved
      }
    }
    return result
  }

  private func resolve(_ name: String) -> TypeSyntax? {
    switch states[name] {
    case .resolved(let type):
      return type
    case .visiting, .cyclic:
      return nil
    case nil:
      break
    }
    guard let body = declared[name] else {
      return nil
    }
    states[name] = .visiting

    var hitCycle = false
    let rewriter = AliasRewriter { refName in
      guard self.declared[refName] != nil else {
        return nil
      }
      guard let resolved = self.resolve(refName) else {
        hitCycle = true
        return nil
      }
      return resolved
    }
    let rewritten = rewriter.rewrite(body).cast(TypeSyntax.self)
    if hitCycle {
      states[name] = .cyclic
      return nil
    }
    states[name] = .resolved(rewritten)
    return rewritten
  }
}

/// Replaces each type reference to an alias by the aliased type: a bare name (`Pair`) or one qualified
/// with `Self` (`Self.Pair`). A name with generic arguments isn't an alias reference, since the
/// resolved aliases aren't generic.
private final class AliasRewriter: SyntaxRewriter {
  let lookup: (String) -> TypeSyntax?

  init(lookup: @escaping (String) -> TypeSyntax?) {
    self.lookup = lookup
    super.init(viewMode: .sourceAccurate)
  }

  override func visit(_ node: IdentifierTypeSyntax) -> TypeSyntax {
    guard node.genericArgumentClause == nil, let aliased = lookup(node.name.text) else {
      return super.visit(node)
    }
    return aliased.with(\.leadingTrivia, node.leadingTrivia).with(\.trailingTrivia, node.trailingTrivia)
  }

  override func visit(_ node: MemberTypeSyntax) -> TypeSyntax {
    guard node.baseType.as(IdentifierTypeSyntax.self)?.name.text == "Self",
      node.genericArgumentClause == nil,
      let aliased = lookup(node.name.text)
    else {
      return super.visit(node)
    }
    return aliased.with(\.leadingTrivia, node.leadingTrivia).with(\.trailingTrivia, node.trailingTrivia)
  }
}
