import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros

/// Reports each `@JS` member whose JavaScript name an earlier `@JS` member already binds on the same
/// JavaScript object. Pass the members of one object only: a shared object's static members bind onto
/// the constructor and its instance members onto the prototype, so the two sets are checked separately.
internal func diagnoseJSNameCollisions(
  functions: [JSFunction],
  properties: [JSProperty],
  in context: some MacroExpansionContext
) {
  // Each member binds with its own `setProperty` or `defineProperty` call, so of two members with one
  // name, JavaScript would reach only one. Members are compared in source order, so the error lands on
  // every member after the first, whichever kind each one is.
  let members =
    functions.map { BoundMember(jsName: $0.jsName, kind: "function", nameToken: $0.nameToken) }
    + properties.map { BoundMember(jsName: $0.jsName, kind: "property", nameToken: $0.nameToken) }
  var firstMembers: [String: BoundMember] = [:]

  for member in members.sorted(by: { $0.nameToken.position < $1.nameToken.position }) {
    guard let first = firstMembers[member.jsName] else {
      firstMembers[member.jsName] = member
      continue
    }
    context.diagnose(
      Diagnostic(
        node: member.nameToken,
        message: JSNameCollisionMessage(
          "The JavaScript name '\(member.jsName)' is already bound by an earlier @JS \(first.kind). A JavaScript object holds one member per name, so JavaScript could reach only one of them. Give one of them another name with @JS(\"...\")."
        ),
        notes: [
          Note(
            node: Syntax(first.nameToken),
            message: JSNameCollisionNote("'\(member.jsName)' is first bound here"))
        ]
      ))
  }
}

private struct BoundMember {
  let jsName: String
  let kind: String
  let nameToken: TokenSyntax
}

private struct JSNameCollisionMessage: DiagnosticMessage {
  let message: String
  let diagnosticID = MessageID(domain: "ExpoModulesMacros", id: "js-name-collision")
  let severity: DiagnosticSeverity = .error

  init(_ message: String) {
    self.message = message
  }
}

private struct JSNameCollisionNote: NoteMessage {
  let message: String
  let noteID = MessageID(domain: "ExpoModulesMacros", id: "js-name-collision-first")

  init(_ message: String) {
    self.message = message
  }
}
