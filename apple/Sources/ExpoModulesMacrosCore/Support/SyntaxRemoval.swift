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
///   blank line behind. When a comment comes before it on its line, only the element and the spaces
///   before it are deleted, so `/* keep */ @Field` keeps the comment.
///
/// The change doesn't touch the token after the element: in a module, the declaration that a macro
/// gets also has the attributes that `@ExpoModule` and `@SharedObject` add after the attributes in the
/// file, and they can take over the trivia after the last one. Only the decision whether an element
/// is alone on its line reads that trivia. When the token after the element may be such an attribute
/// and a line comment ends the line before the element, the line break stays, because deleting it
/// could join the rest of the element's line to the comment.
internal func removalChanges(of element: some SyntaxProtocol) -> [FixIt.Change] {
  let textStart = element.positionAfterSkippingLeadingTrivia
  let textEnd = element.endPositionBeforeTrailingTrivia
  let previousTrivia = element.previousToken(viewMode: .sourceAccurate)?.trailingTrivia ?? []
  let triviaBefore = previousTrivia + element.leadingTrivia
  let next = element.lastToken(viewMode: .sourceAccurate)?.nextToken(viewMode: .sourceAccurate)
  let withSpacesBefore = textStart.advanced(by: -trailingSpacesLength(of: triviaBefore))..<textEnd
  let range: Range<AbsolutePosition>
  if !triviaBefore.contains(where: \.isNewline) {
    range = withSpacesBefore
  } else if !isFollowedByLineBreak(element, next: next) {
    let spacesAfter = element.trailingTrivia.pieces.prefix(while: isSpace).reduce(0) { $0 + $1.sourceLength.utf8Length }
    range = textStart..<textEnd.advanced(by: spacesAfter)
  } else if let lineBreak = lineBreak(before: element, after: previousTrivia),
    !(endsWithLineComment(lineBreak.triviaBefore) && mayBeAddedAttribute(next))
  {
    range = lineBreak.start..<textEnd
  } else {
    range = withSpacesBefore
  }
  return [.replaceText(range: range, with: "", in: Syntax(element))]
}

/// The attributes that `@ExpoModule` and `@SharedObject` add to their members.
private let addedAttributeNames: Set<String> = ["JavaScriptActor", "concurrent", "ModuleDefinitionBuilder"]

/// True when the token starts an attribute that `@ExpoModule` or `@SharedObject` may have added, so
/// its trivia may not be in the file.
private func mayBeAddedAttribute(_ token: TokenSyntax?) -> Bool {
  guard let attribute = token?.parent?.as(AttributeSyntax.self), attribute.atSign.id == token?.id else {
    return false
  }
  return addedAttributeNames.contains(attribute.attributeName.trimmedDescription)
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
private func isFollowedByLineBreak(_ element: some SyntaxProtocol, next: TokenSyntax?) -> Bool {
  let nextTrivia = next?.leadingTrivia ?? []
  return (element.trailingTrivia + nextTrivia).pieces.first { !isSpace($0) }?.isNewline ?? false
}

/// The line break right before the element, when only spaces come between them: the position to
/// delete from to remove the line of the element (a run of line breaks keeps all but the last one),
/// and the trivia before the line break. `nil` when the line break isn't in the leading trivia of the
/// element, or when a comment comes after it.
private func lineBreak(
  before element: some SyntaxProtocol,
  after previousTrivia: Trivia
) -> (start: AbsolutePosition, triviaBefore: [TriviaPiece])? {
  let pieces = Array(element.leadingTrivia.pieces)
  guard let index = pieces.lastIndex(where: \.isNewline), pieces[(index + 1)...].allSatisfy(isSpace) else {
    return nil
  }
  let start = element.position.advanced(by: pieces[..<index].reduce(0) { $0 + $1.sourceLength.utf8Length })
  let length = pieces[index].sourceLength.utf8Length
  let lineBreakLength: Int
  if case .carriageReturnLineFeeds = pieces[index] {
    lineBreakLength = 2
  } else {
    lineBreakLength = 1
  }
  // In a run, the line breaks that stay end the line before the deleted one.
  let triviaBefore = length > lineBreakLength ? [pieces[index]] : Array(previousTrivia.pieces) + pieces[..<index]
  return (start.advanced(by: length - lineBreakLength), triviaBefore)
}

/// True when a line comment ends the trivia, before any spaces.
private func endsWithLineComment(_ trivia: [TriviaPiece]) -> Bool {
  switch trivia.last(where: { !isSpace($0) }) {
  case .lineComment, .docLineComment:
    return true
  default:
    return false
  }
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
