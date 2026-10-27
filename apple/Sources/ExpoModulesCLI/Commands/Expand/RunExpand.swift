#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// The options of `expand`, parsed by `ScannerCLI`.
struct ExpandOptions: Equatable {
  var files: [String] = []
  var symbols: [String] = []
  var json = false
  var diagnosticsOnly = false
}

extension Scanner {
  /// Runs `expand`: expands the macros in each file with `expander` and prints the result.
  ///
  /// As text, the expanded source goes to stdout and the diagnostics go to stderr in the
  /// `<file>:<line>:<column>: <severity>: <message>` format of the compiler. The exit code is `1`
  /// when there is an error diagnostic. With `--json`, the report goes to stdout and the exit code
  /// is `0` also with error diagnostics, because the report holds them; `1` then means that encoding
  /// failed. An input that can't be expanded (a missing file, a directory, a file that isn't Swift, a
  /// symbol that no file declares) is a usage error, `2`.
  static func runExpand(options: ExpandOptions, expander: MacroExpander) -> Int32 {
    var sources: [(file: String, source: String)] = []
    for file in options.files {
      guard isDirectory(atPath: file) != true else {
        return expandInputError("expand takes files, but '\(file)' is a directory")
      }
      guard file.hasSuffix(".swift") else {
        return expandInputError("expand takes .swift files, but got '\(file)'")
      }
      guard let source = try? String(contentsOfFile: file, encoding: .utf8) else {
        return expandInputError("could not read '\(file)'")
      }
      sources.append((file, source))
    }

    let files = sources.map { expander($0.source, $0.file, options.symbols) }

    let found = Set(files.flatMap { $0.expansions.compactMap(\.symbol) })
    if let missing = options.symbols.first(where: { !found.contains($0) }) {
      return expandInputError(
        "no declaration of '\(missing)' in the given files; name a type ('Module'), a nested type "
          + "('Module.Options') or a member ('Module.method')"
      )
    }

    let result = ExpandResult(
      schemaVersion: expandSchemaVersion,
      files: options.diagnosticsOnly
        ? files.map { ExpandedFile(file: $0.file, expansions: [], diagnostics: $0.diagnostics) }
        : files
    )

    if options.json {
      do {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(result)
        writeToStandardOutput(String(decoding: data, as: UTF8.self) + "\n")
        return 0
      } catch {
        writeToStandardError("error: failed to encode results: \(error)\n")
        return 1
      }
    }

    writeToStandardOutput(renderExpansions(result.files))
    writeToStandardError(renderDiagnostics(result.files))
    if options.diagnosticsOnly {
      writeToStandardError(renderSummary(result.files))
    }
    let hasErrors = files.contains { $0.diagnostics.contains { $0.severity == .error } }
    return hasErrors ? 1 : 0
  }
}

/// The expanded sources as text. A single expansion is printed as it is; more than one each get a
/// `// <file>` or `// <file>: <symbol>` header and are separated by an empty line.
func renderExpansions(_ files: [ExpandedFile]) -> String {
  let expansions = files.flatMap { file in file.expansions.map { (file: file.file, expansion: $0) } }
  if expansions.count == 1, let only = expansions.first {
    return withTrailingNewline(only.expansion.source)
  }
  return expansions.map { file, expansion in
    let header = expansion.symbol.map { "// \(file): \($0)" } ?? "// \(file)"
    return "\(header)\n\n" + withTrailingNewline(expansion.source)
  }
  .joined(separator: "\n")
}

/// The diagnostics in the compiler's format, one line each, followed by their notes and Fix-Its.
func renderDiagnostics(_ files: [ExpandedFile]) -> String {
  var text = ""
  for file in files {
    for diagnostic in file.diagnostics {
      text +=
        "\(file.file):\(diagnostic.line):\(diagnostic.column): \(diagnostic.severity.rawValue): \(diagnostic.message)\n"
      for note in diagnostic.notes {
        text += "\(file.file):\(note.line):\(note.column): note: \(note.message)\n"
      }
      for fixIt in diagnostic.fixIts {
        text += "\(file.file):\(diagnostic.line):\(diagnostic.column): note: fix-it: \(fixIt)\n"
      }
    }
  }
  return text
}

/// The summary line of `--diagnostics-only`, for example `1 error and 2 warnings in 3 files`.
func renderSummary(_ files: [ExpandedFile]) -> String {
  let diagnostics = files.flatMap(\.diagnostics)
  let errors = diagnostics.filter { $0.severity == .error }.count
  let warnings = diagnostics.filter { $0.severity == .warning }.count
  let checked = count(files.count, "file")
  if errors == 0 && warnings == 0 {
    return "No macro errors or warnings in \(checked).\n"
  }
  let parts = [errors > 0 ? count(errors, "error") : nil, warnings > 0 ? count(warnings, "warning") : nil]
  return "\(parts.compactMap { $0 }.joined(separator: " and ")) in \(checked).\n"
}

private func count(_ n: Int, _ noun: String) -> String {
  "\(n) \(noun)\(n == 1 ? "" : "s")"
}

private func withTrailingNewline(_ text: String) -> String {
  text.hasSuffix("\n") ? text : text + "\n"
}

/// Reports an input that `expand` can't take on stderr and returns the usage exit code.
private func expandInputError(_ message: String) -> Int32 {
  writeToStandardError("error: \(message)\n")
  return 2
}
