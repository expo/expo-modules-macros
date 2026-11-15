import SwiftDiagnostics
import SwiftSyntax

/// The fix-it changes that remove an attribute or a modifier, such as `static`, from a declaration.
/// The token after it takes over its trivia: the line break, indentation and comments before it, and
/// the comments after it. That token's own leading whitespace is left out unless a comment comes before
/// it, so `@Field var size` and `@Field` on its own line both become `var size` on the line of the
/// attribute, and `@Field // note` keeps the line break after the comment. The element is removed with
/// its trivia, so it doesn't leave a blank line behind.
///
/// The changes edit only the element and the trivia around it, not the whole declaration: in a module,
/// the declaration that a macro gets also has the attributes that `@ExpoModule` adds, which aren't in
/// the file. They follow the attributes in the file and can take over the trivia after them, so the
/// token after an attribute, and its trivia, may not be in the file. An attribute after another one is
/// therefore removed with the whitespace before it, back to the attribute before it, and the trivia
/// after it is left as it is: `@Event @JS var` becomes `@Event var`.
internal func removalChanges(of element: some SyntaxProtocol) -> [FixIt.Change] {
  if let list = element.parent?.as(AttributeListSyntax.self), list.first?.id != element.id,
    let previous = element.previousToken(viewMode: .sourceAccurate)
  {
    return [
      .replaceText(
        range: previous.endPositionBeforeTrailingTrivia..<element.endPositionBeforeTrailingTrivia,
        with: "",
        in: Syntax(element)
      )
    ]
  }
  var changes: [FixIt.Change] = [
    .replaceText(range: element.position..<element.endPosition, with: "", in: Syntax(element))
  ]
  if let next = element.lastToken(viewMode: .sourceAccurate)?.nextToken(viewMode: .sourceAccurate) {
    let comments = Trivia(pieces: element.trailingTrivia.pieces.drop(while: \.isWhitespace))
    let ownTrivia =
      comments.isEmpty ? Trivia(pieces: next.leadingTrivia.pieces.drop(while: \.isWhitespace)) : next.leadingTrivia
    changes.append(.replaceLeadingTrivia(token: next, newTrivia: element.leadingTrivia + comments + ownTrivia))
  }
  return changes
}

/// The attribute without the argument. The argument before it keeps its comma only when another
/// argument follows, and an attribute left without arguments loses its parentheses, so removing the
/// only option of `@JS(.withAsync("loadAsync"))` gives `@JS`.
internal func removingArgument(_ argument: LabeledExprSyntax, from attribute: AttributeSyntax) -> AttributeSyntax {
  guard let arguments = attribute.arguments?.as(LabeledExprListSyntax.self) else {
    return attribute
  }
  var remaining = Array(arguments)
  remaining.removeAll { $0.id == argument.id }
  if remaining.isEmpty {
    return
      attribute
      .with(\.leftParen, nil)
      .with(\.arguments, nil)
      .with(\.rightParen, nil)
      .with(\.attributeName, attribute.attributeName.with(\.trailingTrivia, attribute.trailingTrivia))
  }
  if let last = remaining.indices.last {
    remaining[last] = remaining[last].with(\.trailingComma, nil)
  }
  return attribute.with(\.arguments, .argumentList(LabeledExprListSyntax(remaining)))
}
