import SwiftSyntaxMacrosGenericTestSupport
import Testing

/// Records an `assertMacroExpansion` failure as a Swift Testing issue. A failure in a diagnostic,
/// note or Fix-It points at its spec, and any other failure points at the assertion call.
func recordIssue(_ failure: TestFailureSpec) {
  Issue.record(
    Comment(rawValue: failure.message),
    sourceLocation: Testing.SourceLocation(
      fileID: failure.location.fileID,
      filePath: failure.location.filePath,
      line: failure.location.line,
      column: failure.location.column
    )
  )
}
