import Foundation
import Testing

@testable import ExpoModulesCLI

/// An error at line 1 with one Fix-It for each element of `fixIts`, with the given edits.
private func diagnostic(_ fixIts: [(message: String, edits: [ExpansionEdit])]) -> ExpansionDiagnostic {
  ExpansionDiagnostic(
    severity: .error,
    message: "broken",
    line: 1,
    column: 1,
    fixIts: fixIts.map(\.message),
    fixItEdits: fixIts.map(\.edits)
  )
}

/// An expander that reports, for each `(old, new)` in `replacements` whose `old` the source contains,
/// an error with a Fix-It that replaces its first occurrence with `new`.
private func replacingExpander(_ replacements: [(old: String, new: String)]) -> MacroExpander {
  MacroExpander(attributeNames: ["ExpoModule"]) { source, file, _ in
    let text = Array(source.utf8)
    let diagnostics = replacements.compactMap { old, new -> ExpansionDiagnostic? in
      let needle = Array(old.utf8)
      guard let offset = text.indices.first(where: { text[$0...].starts(with: needle) }) else {
        return nil
      }
      return diagnostic([("Replace '\(old)'", [ExpansionEdit(offset: offset, original: old, replacement: new)])])
    }
    return ExpandedFile(file: file, expansions: [Expansion(symbol: nil, source: "")], diagnostics: diagnostics)
  }
}

@Suite("fix")
struct FixCLITests {
  @Test
  func `Applies the edits of each Fix-It`() {
    let fixed = applyFixIts(
      to: "func load() -> Int",
      diagnostics: [
        diagnostic([("Mark the function 'async'", [ExpansionEdit(offset: 12, original: "", replacement: "async ")])]),
        diagnostic([("Rename", [ExpansionEdit(offset: 5, original: "load", replacement: "fetch")])]),
      ]
    )
    #expect(fixed.source == "func fetch() async -> Int")
    #expect(fixed.fixIts.map(\.message) == ["Mark the function 'async'", "Rename"])
    #expect(fixed.fixIts.allSatisfy { $0.skipReason == nil })
  }

  @Test
  func `Skips a Fix-It whose original text isn't in the file`() {
    let fixed = applyFixIts(
      to: "func load()",
      diagnostics: [
        diagnostic([("Rename", [ExpansionEdit(offset: 5, original: "save", replacement: "fetch")])]),
        diagnostic([("Out of range", [ExpansionEdit(offset: 100, original: "", replacement: "x")])]),
        diagnostic([("Not mapped", [])]),
      ]
    )
    #expect(fixed.source == "func load()")
    #expect(fixed.fixIts.map(\.skipReason) == Array(repeating: "its edits aren't in the file", count: 3))
  }

  @Test
  func `Skips a Fix-It that overlaps an earlier one, or inserts at the same offset`() {
    let fixed = applyFixIts(
      to: "func load()",
      diagnostics: [
        diagnostic([("First", [ExpansionEdit(offset: 5, original: "load", replacement: "fetch")])]),
        diagnostic([("Overlapping", [ExpansionEdit(offset: 7, original: "ad", replacement: "")])]),
        diagnostic([("Same offset", [ExpansionEdit(offset: 5, original: "", replacement: "x")])]),
        diagnostic([("After", [ExpansionEdit(offset: 9, original: "", replacement: "Data")])]),
      ]
    )
    #expect(fixed.source == "func fetchData()")
    #expect(fixed.fixIts.map(\.skipReason) == [nil, "it overlaps another Fix-It", "it overlaps another Fix-It", nil])
  }

  @Test
  func `Skips a diagnostic with more than one Fix-It, and leaves out one with the same edits as an earlier one`() {
    let rename = ExpansionEdit(offset: 5, original: "load", replacement: "fetch")
    let fixed = applyFixIts(
      to: "func load()",
      diagnostics: [
        diagnostic([("Rename", [rename]), ("Remove", [ExpansionEdit(offset: 5, original: "load", replacement: "")])]),
        diagnostic([("Rename", [rename])]),
        diagnostic([("Rename", [rename])]),
      ]
    )
    #expect(fixed.source == "func fetch()")
    #expect(
      fixed.fixIts.map(\.skipReason) == [
        "the diagnostic has 2 Fix-Its to choose from", "the diagnostic has 2 Fix-Its to choose from", nil,
      ]
    )
  }

  @Test
  func `Leaves out the Fix-Its of a diagnostic without edits, such as a syntax error`() {
    let syntaxError = ExpansionDiagnostic(
      severity: .error,
      message: "expected ')'",
      line: 1,
      column: 1,
      fixIts: ["insert ')'"]
    )
    let fixed = applyFixIts(to: "func load(", diagnostics: [syntaxError])
    #expect(fixed.source == "func load(")
    #expect(fixed.fixIts.isEmpty)
  }

  @Test
  func `Expands the file again until no Fix-It applies`() {
    // Each replacement makes the next one possible, as a macro that stops at its first error does.
    let expander = replacingExpander([("a", "b"), ("b", "c"), ("c", "d")])
    let source = "let x = \"a\""
    let first = expander.expand(source, "f.swift", [])
    let fixed = fixSource(source, expanded: first, symbols: [], expander: expander)
    #expect(fixed.source == "let x = \"d\"")
    #expect(fixed.applied.count == 3)
  }

  @Test
  func `Stops after the maximum number of passes`() {
    let expander = replacingExpander([("a", "aa")])
    let source = "a"
    let fixed = fixSource(source, expanded: expander.expand(source, "f.swift", []), symbols: [], expander: expander)
    #expect(fixed.source == String(repeating: "a", count: maxFixPasses + 1))
    #expect(fixed.applied.count == maxFixPasses)
    #expect(fixed.reachedPassLimit)
    #expect(
      renderSkippedFixIts(fixed, file: "f.swift")
        == "f.swift: warning: stopped after \(maxFixPasses) passes; run fix again for the Fix-Its left\n"
    )

    let once = replacingExpander([("a", "b")])
    #expect(!fixSource("a", expanded: once.expand("a", "f.swift", []), symbols: [], expander: once).reachedPassLimit)
  }

  @Test
  func `With onlyErrors, applies only the Fix-Its of errors`() {
    let warning = ExpansionDiagnostic(
      severity: .warning,
      message: "not public",
      line: 1,
      column: 1,
      fixIts: ["Make it public"],
      fixItEdits: [[ExpansionEdit(offset: 0, original: "", replacement: "public ")]]
    )
    let error = diagnostic([("Rename", [ExpansionEdit(offset: 5, original: "load", replacement: "fetch")])])
    let source = "func load()"
    // Reports the diagnostics only for the original source, so the next pass applies nothing.
    let expander = MacroExpander(attributeNames: []) { text, file, _ in
      ExpandedFile(file: file, expansions: [], diagnostics: text == source ? [warning, error] : [])
    }
    let expanded = expander.expand(source, "f.swift", [])

    let all = fixSource(source, expanded: expanded, symbols: [], expander: expander)
    #expect(all.source == "public func fetch()")
    let errors = fixSource(source, expanded: expanded, symbols: [], onlyErrors: true, expander: expander)
    #expect(errors.source == "func fetch()")
    #expect(errors.fixIts.map(\.message) == ["Rename"])
  }

  @Test
  func `Prints the applied Fix-Its, and a warning for each skipped one`() {
    let fixed = FixedSource(
      source: "",
      fixIts: [
        FixItReport(line: 3, column: 5, message: "Mark the function 'async'", skipReason: nil),
        FixItReport(line: 7, column: 1, message: "Rename", skipReason: "it overlaps another Fix-It"),
      ]
    )
    #expect(renderAppliedFixIts(fixed, file: "f.swift") == "f.swift:3:5: fix-it: Mark the function 'async'\n")
    #expect(
      renderSkippedFixIts(fixed, file: "f.swift")
        == "f.swift:7:1: warning: skipped fix-it 'Rename': it overlaps another Fix-It\n"
    )
  }

  @Test
  func `A file that can't be written exits with 1, and the other files are still fixed`() throws {
    try withFile("let x = \"a\"\n") { file in
      let other = URL(fileURLWithPath: file).deletingLastPathComponent().appendingPathComponent("Other.swift").path
      try "let y = \"a\"\n".write(toFile: other, atomically: true, encoding: .utf8)
      // Removing the first file while it is expanded makes its write fail.
      let replacing = replacingExpander([("a", "b")])
      let expander = MacroExpander(attributeNames: replacing.attributeNames) { source, path, symbols in
        if path == file {
          try? FileManager.default.removeItem(atPath: file)
        }
        return replacing.expand(source, path, symbols)
      }
      #expect(ScannerCLI.run(arguments: ["fix", file, other], expander: expander) == 1)
      let fixed = try String(contentsOfFile: other, encoding: .utf8)
      #expect(fixed == "let y = \"b\"\n")
    }
  }

  @Test
  func `Keeps the byte order mark, the line endings and the non-ASCII text of the file`() throws {
    try withFile("") { file in
      let bom: [UInt8] = [0xEF, 0xBB, 0xBF]
      try Data(bom + Array("// Zürich 🌍\r\nlet x = \"a\"\r\n".utf8)).write(to: URL(fileURLWithPath: file))
      #expect(ScannerCLI.run(arguments: ["fix", file], expander: replacingExpander([("a", "b")])) == 0)
      let written = try Data(contentsOf: URL(fileURLWithPath: file))
      #expect(Array(written) == bom + Array("// Zürich 🌍\r\nlet x = \"b\"\r\n".utf8))
    }
  }

  #if !os(Windows)
  // Creating a symbolic link on Windows needs a privilege that CI doesn't have.
  @Test
  func `Writes through a symbolic link, which keeps pointing to the file`() throws {
    try withFile("let x = \"a\"\n") { file in
      let link = URL(fileURLWithPath: file).deletingLastPathComponent().appendingPathComponent("Link.swift").path
      try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: file)
      #expect(ScannerCLI.run(arguments: ["fix", link], expander: replacingExpander([("a", "b")])) == 0)
      let destination = try FileManager.default.destinationOfSymbolicLink(atPath: link)
      #expect(destination == file)
      let fixed = try String(contentsOfFile: file, encoding: .utf8)
      #expect(fixed == "let x = \"b\"\n")
    }
  }
  #endif

  @Test
  func `Equality and the JSON report leave out the Fix-It edits`() throws {
    let withEdits = diagnostic([("Rename", [ExpansionEdit(offset: 5, original: "load", replacement: "fetch")])])
    let decoded = try JSONDecoder().decode(ExpansionDiagnostic.self, from: JSONEncoder().encode(withEdits))
    #expect(decoded.fixItEdits.isEmpty)
    #expect(decoded == withEdits)
  }

  @Test
  func `--dry-run doesn't write the file, and fix does`() throws {
    try withFile("let x = \"a\"\n") { file in
      let expander = replacingExpander([("a", "b")])
      #expect(ScannerCLI.run(arguments: ["fix", "--dry-run", file], expander: expander) == 0)
      let unchanged = try String(contentsOfFile: file, encoding: .utf8)
      #expect(unchanged == "let x = \"a\"\n")
      #expect(ScannerCLI.run(arguments: ["fix", file], expander: expander) == 0)
      let fixed = try String(contentsOfFile: file, encoding: .utf8)
      #expect(fixed == "let x = \"b\"\n")
    }
  }

  @Test(arguments: [
    ["fix"],
    ["fix", "--json", "File.swift"],
    ["fix", "--diagnostics-only", "File.swift"],
    ["fix", "--define", "DEBUG", "File.swift"],
    ["expand", "--dry-run", "File.swift"],
    ["expand", "--only-errors", "File.swift"],
    ["scan-modules", "--dry-run", "/tmp"],
  ])
  func `Rejects the options that fix doesn't take, and the options of fix elsewhere`(arguments: [String]) {
    #expect(ScannerCLI.run(arguments: arguments, expander: replacingExpander([])) == 2)
  }

  @Test
  func `fix without an expander is a usage error`() {
    #expect(ScannerCLI.run(arguments: ["fix", "File.swift"]) == 2)
  }

  @Test
  func `fix takes only existing .swift files and directories`() throws {
    try withFile("") { file in
      #expect(ScannerCLI.run(arguments: ["fix", file + ".txt"], expander: replacingExpander([])) == 2)
    }
  }

  @Test
  func `The summary counts the Fix-Its and the files`() {
    #expect(renderFixSummary(applied: 0, files: 0, dryRun: false) == "No Fix-Its to apply.\n")
    #expect(renderFixSummary(applied: 1, files: 1, dryRun: false) == "Applied 1 Fix-It in 1 file.\n")
    #expect(renderFixSummary(applied: 3, files: 2, dryRun: true) == "Would apply 3 Fix-Its in 2 files.\n")
  }

  private func withFile(_ contents: String, _ body: (_ file: String) throws -> Void) throws {
    let fileManager = FileManager.default
    let root = fileManager.temporaryDirectory.appendingPathComponent(
      "scanner-fix-\(ProcessInfo.processInfo.globallyUniqueString)"
    )
    defer { try? fileManager.removeItem(at: root) }
    try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
    let file = root.appendingPathComponent("MyModule.swift")
    try contents.write(to: file, atomically: true, encoding: .utf8)
    try body(file.path)
  }
}
