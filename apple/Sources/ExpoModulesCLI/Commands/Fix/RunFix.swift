#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// The options of `fix`, parsed by `ScannerCLI`.
struct FixOptions: Equatable {
  var paths: [String] = []
  var symbols: [String] = []
  var dryRun = false
}

/// A Fix-It that `fix` applied or skipped, at the location of its diagnostic.
struct FixItReport: Equatable {
  let line: Int
  let column: Int
  let message: String

  /// Why `fix` skipped the Fix-It, or `nil` when it applied it.
  let skipReason: String?
}

/// The result of applying the Fix-Its of one file.
struct FixedSource: Equatable {
  /// The source with the applied Fix-Its.
  let source: String
  let fixIts: [FixItReport]

  var applied: [FixItReport] {
    fixIts.filter { $0.skipReason == nil }
  }
}

extension Scanner {
  /// Runs `fix`: expands the macros in each file like `expand` and applies the Fix-Its of their
  /// diagnostics to the file, in place (see `fixSource`). It doesn't format the file.
  ///
  /// Each applied Fix-It is printed to stdout as `<file>:<line>:<column>: fix-it: <message>`, followed
  /// by a summary, and each skipped one to stderr as a warning. With `--dry-run`, the files aren't
  /// written. The exit code is `0` also when a Fix-It is skipped, `1` when a file can't be written, and
  /// `2` for an input that `expand` doesn't take.
  static func runFix(options: FixOptions, expander: MacroExpander) -> Int32 {
    let sources: [(source: String, expanded: ExpandedFile)]
    switch expandSources(options: ExpandOptions(paths: options.paths, symbols: options.symbols), expander: expander) {
    case .success(let expanded):
      sources = expanded
    case .failure(let error):
      writeToStandardError("error: \(error.message)\n")
      return 2
    }

    var appliedCount = 0
    var fixedFiles = 0
    for (source, expanded) in sources {
      let fixed = fixSource(source, expanded: expanded, symbols: options.symbols, expander: expander)
      for fixIt in fixed.fixIts {
        let location = "\(expanded.file):\(fixIt.line):\(fixIt.column)"
        if let reason = fixIt.skipReason {
          writeToStandardError("\(location): warning: skipped fix-it '\(fixIt.message)': \(reason)\n")
        } else {
          writeToStandardOutput("\(location): fix-it: \(fixIt.message)\n")
        }
      }
      guard !fixed.applied.isEmpty else {
        continue
      }
      appliedCount += fixed.applied.count
      fixedFiles += 1
      if !options.dryRun {
        do {
          try Data(fixed.source.utf8).write(to: URL(fileURLWithPath: expanded.file), options: .atomic)
        } catch {
          writeToStandardError("error: could not write '\(expanded.file)': \(error)\n")
          return 1
        }
      }
    }

    writeToStandardOutput(renderFixSummary(applied: appliedCount, files: fixedFiles, dryRun: options.dryRun))
    return 0
  }
}

/// The most times that `fixSource` expands a file again after applying Fix-Its.
let maxFixPasses = 10

/// Applies the Fix-Its of `expanded`, the expansion of `source`, to `source`. A macro can stop at its
/// first error, so after applying Fix-Its, this expands the result again and applies the new Fix-Its,
/// until none applies or after `maxFixPasses` passes. The location of an applied Fix-It is in the
/// source of its pass. The skipped Fix-Its are those of the last pass.
func fixSource(
  _ source: String,
  expanded: ExpandedFile,
  symbols: [String],
  expander: MacroExpander
) -> FixedSource {
  var fixed = applyFixIts(to: source, diagnostics: expanded.diagnostics)
  var applied = fixed.applied
  for _ in 1..<maxFixPasses where !fixed.applied.isEmpty {
    let diagnostics = expander.expand(fixed.source, expanded.file, symbols).diagnostics
    fixed = applyFixIts(to: fixed.source, diagnostics: diagnostics)
    applied += fixed.applied
  }
  return FixedSource(source: fixed.source, fixIts: applied + fixed.fixIts.filter { $0.skipReason != nil })
}

/// Applies the Fix-Its of `diagnostics` to `source`, which is the file that they were reported for.
///
/// A diagnostic with more than one Fix-It is skipped, because they are alternatives. So is a Fix-It
/// whose edits aren't in the file, or whose edits overlap the edits of a Fix-It before it. A Fix-It
/// with the same edits as one before it, which a macro can report twice, is left out. A diagnostic
/// without `fixItEdits`, such as a syntax error, is left out too.
func applyFixIts(to source: String, diagnostics: [ExpansionDiagnostic]) -> FixedSource {
  let text = Array(source.utf8)
  var accepted: [ExpansionEdit] = []
  var reports: [FixItReport] = []

  for diagnostic in diagnostics
  where !diagnostic.fixIts.isEmpty && diagnostic.fixItEdits.count == diagnostic.fixIts.count {
    let report = { (message: String, reason: String?) in
      reports.append(
        FixItReport(line: diagnostic.line, column: diagnostic.column, message: message, skipReason: reason)
      )
    }
    guard diagnostic.fixIts.count == 1, let message = diagnostic.fixIts.first, let edits = diagnostic.fixItEdits.first
    else {
      for message in diagnostic.fixIts {
        report(message, "the diagnostic has \(diagnostic.fixIts.count) Fix-Its to choose from")
      }
      continue
    }
    if !edits.isEmpty && edits.allSatisfy(accepted.contains) {
      continue
    }
    guard !edits.isEmpty, edits.allSatisfy({ matches($0, in: text) }) else {
      report(message, "its edits aren't in the file")
      continue
    }
    let overlaps = edits.enumerated().contains { index, edit in
      (accepted + edits.prefix(index)).contains { overlap(edit, $0) }
    }
    guard !overlaps else {
      report(message, "it overlaps another Fix-It")
      continue
    }
    accepted += edits
    report(message, nil)
  }

  var fixed = text
  for edit in accepted.sorted(by: { $0.offset > $1.offset }) {
    fixed.replaceSubrange(edit.offset..<(edit.offset + edit.original.utf8.count), with: Array(edit.replacement.utf8))
  }
  return FixedSource(source: String(decoding: fixed, as: UTF8.self), fixIts: reports)
}

/// Whether `text` has the original text of `edit` at its offset.
private func matches(_ edit: ExpansionEdit, in text: [UInt8]) -> Bool {
  let original = Array(edit.original.utf8)
  return edit.offset >= 0 && edit.offset + original.count <= text.count
    && text[edit.offset..<(edit.offset + original.count)].elementsEqual(original)
}

/// Whether two edits change the same bytes, or insert at the same offset, where their order would
/// matter.
private func overlap(_ a: ExpansionEdit, _ b: ExpansionEdit) -> Bool {
  let aEnd = a.offset + a.original.utf8.count
  let bEnd = b.offset + b.original.utf8.count
  return a.offset == b.offset || (a.offset < bEnd && b.offset < aEnd)
}

/// The summary line of `fix`, for example `Applied 3 Fix-Its in 2 files.`
func renderFixSummary(applied: Int, files: Int, dryRun: Bool) -> String {
  guard applied > 0 else {
    return "No Fix-Its to apply.\n"
  }
  let fixIts = "\(applied) Fix-It\(applied == 1 ? "" : "s")"
  let fileCount = "\(files) file\(files == 1 ? "" : "s")"
  return "\(dryRun ? "Would apply" : "Applied") \(fixIts) in \(fileCount).\n"
}
