import SwiftDiagnostics
import SwiftSyntax

/// The fix-it change that removes an attribute or a modifier, such as `static`, from a declaration.
/// It only deletes text, and keeps the comments and line breaks around the element:
///
/// - An element on the line of the token before it is deleted with the spaces before it, so
///   `@Event @JS var` becomes `@Event var`.
/// - An element that starts its line and is followed by more on that line is deleted with the spaces
///   after it, so `@Field var size` becomes `var size`, and `@Field // note` keeps the comment.
/// - An element alone on its line is deleted with the line break before it, so it doesn't leave a
///   blank line behind.
///
/// The change doesn't touch the token after the element: in a module, the declaration that a macro
/// gets also has the attributes that `@ExpoModule` adds after the attributes in the file, and they can
/// take over the trivia after the last one. Only the decision whether an element is alone on its line
/// reads that trivia, and at worst it joins the next line to the line before the element.
internal func removalChanges(of element: some SyntaxProtocol) -> [FixIt.Change] {
  let textStart = element.positionAfterSkippingLeadingTrivia
  let textEnd = element.endPositionBeforeTrailingTrivia
  let previousTrivia = element.previousToken(viewMode: .sourceAccurate)?.trailingTrivia ?? []
  let range: Range<AbsolutePosition>
  if !(previousTrivia + element.leadingTrivia).contains(where: \.isNewline) {
    range = textStart.advanced(by: -trailingSpacesLength(of: previousTrivia + element.leadingTrivia))..<textEnd
  } else if isFollowedByLineBreak(element), let lineBreak = lastLineBreakStart(in: element) {
    range = lineBreak..<textEnd
  } else {
    let spacesAfter = element.trailingTrivia.pieces.prefix(while: isSpace).reduce(0) { $0 + $1.sourceLength.utf8Length }
    range = textStart..<textEnd.advanced(by: spacesAfter)
  }
  return [.replaceText(range: range, with: "", in: Syntax(element))]
}

private func isSpace(_ piece: TriviaPiece) -> Bool {
  switch piece {
  case .spaces, .tabs:
    return true
  default:
    return false
  }
}

/// The length of the spaces and tabs at the end of the trivia.
private func trailingSpacesLength(of trivia: Trivia) -> Int {
  return trivia.pieces.reversed().prefix(while: isSpace).reduce(0) { $0 + $1.sourceLength.utf8Length }
}

/// True when only spaces come between the element and the next line break.
private func isFollowedByLineBreak(_ element: some SyntaxProtocol) -> Bool {
  let nextTrivia =
    element.lastToken(viewMode: .sourceAccurate)?.nextToken(viewMode: .sourceAccurate)?.leadingTrivia ?? []
  return (element.trailingTrivia + nextTrivia).pieces.first { !isSpace($0) }?.isNewline ?? false
}

/// The position of the last line break in the leading trivia of the element, so that deleting from it
/// removes the line of the element. A run of line breaks keeps all but the last one.
private func lastLineBreakStart(in element: some SyntaxProtocol) -> AbsolutePosition? {
  var position = element.position
  var lastLineBreak: AbsolutePosition?
  for piece in element.leadingTrivia.pieces {
    let length = piece.sourceLength.utf8Length
    switch piece {
    case .newlines, .carriageReturns:
      lastLineBreak = position.advanced(by: length - 1)
    case .carriageReturnLineFeeds:
      lastLineBreak = position.advanced(by: length - 2)
    default:
      break
    }
    position = position.advanced(by: length)
  }
  return lastLineBreak
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
