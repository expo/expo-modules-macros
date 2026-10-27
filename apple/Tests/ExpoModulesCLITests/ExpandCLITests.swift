import Foundation
import Testing

@testable import ExpoModulesCLI

/// An expander that reports the symbols in `declared` as found, with an empty expansion each (or
/// one for the whole file without symbols), and returns `diagnostics` for every file.
private func stubExpander(
  declaring declared: Set<String> = [],
  diagnostics: [ExpansionDiagnostic] = []
) -> MacroExpander {
  MacroExpander(attributeNames: ["ExpoModule", "ViewProps"]) { _, file, symbols in
    ExpandedFile(
      file: file,
      expansions: symbols.isEmpty
        ? [Expansion(symbol: nil, source: "")]
        : symbols.filter(declared.contains).map { Expansion(symbol: $0, source: "") },
      diagnostics: diagnostics
    )
  }
}

private let error = ExpansionDiagnostic(severity: .error, message: "broken", line: 1, column: 1)

/// Covers the argument handling and the input errors of `expand`. The expansion itself is covered by
/// `ExpandTests` in the macro tests, where the macros are available.
@Suite("expand CLI")
struct ExpandCLITests {
  @Test
  func `expand without an expander is a usage error`() {
    #expect(ScannerCLI.run(arguments: ["expand", "File.swift"]) == 2)
  }

  @Test
  func `expand without files is a usage error`() {
    #expect(ScannerCLI.run(arguments: ["expand", "--json"], expander: stubExpander()) == 2)
  }

  @Test(arguments: [["expand", "--symbol"], ["expand", "File.swift", "--symbol"]])
  func `--symbol without its value is a usage error`(arguments: [String]) {
    #expect(ScannerCLI.run(arguments: arguments, expander: stubExpander()) == 2)
  }

  @Test(arguments: [
    ["scan-modules", "--json", "/tmp"],
    ["scan-exports", "--symbol", "MyModule", "/tmp"],
    ["scan-exports", "--diagnostics-only", "/tmp"],
  ])
  func `The scans reject the expand options`(arguments: [String]) {
    #expect(ScannerCLI.run(arguments: arguments, expander: stubExpander()) == 2)
  }

  @Test
  func `expand rejects the scan-modules options`() {
    #expect(ScannerCLI.run(arguments: ["expand", "--define", "DEBUG", "File.swift"], expander: stubExpander()) == 2)
  }

  @Test
  func `expand takes only existing .swift files and directories`() throws {
    try withFile { file, directory in
      let expander = stubExpander()
      #expect(ScannerCLI.run(arguments: ["expand", file + ".txt"], expander: expander) == 2)
      #expect(ScannerCLI.run(arguments: ["expand", directory + "/Missing.swift"], expander: expander) == 2)
      #expect(ScannerCLI.run(arguments: ["expand", directory + "/Missing"], expander: expander) == 2)
    }
  }

  @Test
  func `A directory expands the files that use one of the macros, and skips test and dependency directories`() throws {
    try withTree([
      ("ios/MyModule.swift", "@ExpoModule\nfinal class MyModule: Module {}\n"),
      ("ios/Props.swift", "@ViewProps\nstruct Props {}\n"),
      ("ios/Helpers.swift", "struct Helpers {}\n"),
      ("ios/Notes.txt", "@ExpoModule"),
      ("ios/Tests/MyModuleTests.swift", "@ExpoModule\nfinal class TestModule: Module {}\n"),
      ("ios/Pods/Dependency.swift", "@ExpoModule\nfinal class Dependency: Module {}\n"),
    ]) { root in
      let result = try expandFiles(options: ExpandOptions(paths: [root + "/ios"]), expander: stubExpander()).get()
      #expect(
        result.files.map { URL(fileURLWithPath: $0.file).lastPathComponent } == ["MyModule.swift", "Props.swift"]
      )
      // Files from a directory have absolute paths.
      #expect(result.files.allSatisfy { URL(fileURLWithPath: $0.file).baseURL == nil })
    }
  }

  @Test
  func `A file is always expanded, and only once when a directory also contains it`() throws {
    try withTree([
      ("ios/Helpers.swift", "struct Helpers {}\n"),
      ("ios/MyModule.swift", "@ExpoModule\nfinal class MyModule: Module {}\n"),
    ]) { root in
      let options = ExpandOptions(paths: [root + "/ios/Helpers.swift", root + "/ios/MyModule.swift", root + "/ios"])
      let result = try expandFiles(options: options, expander: stubExpander()).get()
      #expect(result.files.map(\.file) == [root + "/ios/Helpers.swift", root + "/ios/MyModule.swift"])
    }
  }

  @Test
  func `A directory without macros expands nothing`() throws {
    try withTree([("ios/Helpers.swift", "struct Helpers {}\n")]) { root in
      let result = try expandFiles(options: ExpandOptions(paths: [root]), expander: stubExpander()).get()
      #expect(result.files.isEmpty)
      #expect(ScannerCLI.run(arguments: ["expand", "--diagnostics-only", root], expander: stubExpander()) == 0)
    }
  }

  @Test
  func `A symbol that no file declares is a usage error`() throws {
    try withFile { file, _ in
      let expander = stubExpander(declaring: ["MyModule"])
      let arguments = ["expand", "--diagnostics-only", "--symbol", "MyModule", "--symbol", "Other", file]
      #expect(ScannerCLI.run(arguments: arguments, expander: expander) == 2)
    }
  }

  @Test
  func `An error diagnostic exits with 1 as text and with 0 as JSON`() throws {
    try withFile { file, _ in
      let expander = stubExpander(diagnostics: [error])
      #expect(ScannerCLI.run(arguments: ["expand", "--diagnostics-only", file], expander: expander) == 1)
      #expect(ScannerCLI.run(arguments: ["expand", "--json", "--diagnostics-only", file], expander: expander) == 0)
      #expect(ScannerCLI.run(arguments: ["expand", "--diagnostics-only", file], expander: stubExpander()) == 0)
    }
  }

  @Test
  func `--diagnostics-only leaves out the expansions and keeps the diagnostics`() throws {
    try withFile { file, _ in
      var options = ExpandOptions(paths: [file], diagnosticsOnly: true)
      let result = try expandFiles(options: options, expander: stubExpander(diagnostics: [error])).get()
      #expect(result.files.map(\.expansions) == [[]])
      #expect(result.files.map(\.diagnostics) == [[error]])

      options.diagnosticsOnly = false
      let full = try expandFiles(options: options, expander: stubExpander(diagnostics: [error])).get()
      #expect(full.files.map(\.expansions.count) == [1])
    }
  }

  /// Writes a `.swift` file into a fresh temporary directory and hands both paths to `body`. The
  /// directory is removed afterward.
  private func withFile(_ body: (_ file: String, _ directory: String) throws -> Void) throws {
    let fileManager = FileManager.default
    let root = fileManager.temporaryDirectory.appendingPathComponent(
      "scanner-expand-\(ProcessInfo.processInfo.globallyUniqueString)"
    )
    defer { try? fileManager.removeItem(at: root) }
    try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
    let file = root.appendingPathComponent("MyModule.swift")
    try "@ExpoModule\nfinal class MyModule: Module {}\n".write(to: file, atomically: true, encoding: .utf8)
    try body(file.path, root.path)
  }

  /// Writes `files` (relative path, contents) into a fresh temporary directory and hands its
  /// absolute, standardized path to `body`. The directory is removed afterward.
  private func withTree(_ files: [(String, String)], _ body: (_ root: String) throws -> Void) throws {
    let fileManager = FileManager.default
    let root = fileManager.temporaryDirectory.appendingPathComponent(
      "scanner-expand-\(ProcessInfo.processInfo.globallyUniqueString)"
    )
    defer { try? fileManager.removeItem(at: root) }
    for (relativePath, contents) in files {
      let url = root.appendingPathComponent(relativePath)
      try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
      try contents.write(to: url, atomically: true, encoding: .utf8)
    }
    try body(root.standardizedFileURL.path)
  }
}

@Suite("expand output")
struct ExpandOutputTests {
  private let diagnostic = ExpansionDiagnostic(
    severity: .error,
    message: "@Record can only be applied to a struct or class",
    line: 6,
    column: 3,
    notes: [ExpansionNote(message: "declared here", line: 2, column: 1)],
    fixIts: ["remove '@Record'"]
  )

  @Test
  func `A single expansion is printed without a header`() {
    let files = [
      ExpandedFile(file: "A.swift", expansions: [Expansion(symbol: nil, source: "struct A {}")], diagnostics: [])
    ]
    #expect(renderExpansions(files) == "struct A {}\n")
  }

  @Test
  func `More than one expansion gets a header each`() {
    let files = [
      ExpandedFile(file: "A.swift", expansions: [Expansion(symbol: "A", source: "struct A {}\n")], diagnostics: []),
      ExpandedFile(file: "B.swift", expansions: [Expansion(symbol: nil, source: "struct B {}")], diagnostics: []),
    ]
    #expect(renderExpansions(files) == "// A.swift: A\n\nstruct A {}\n\n// B.swift\n\nstruct B {}\n")
  }

  @Test
  func `Diagnostics use the compiler's format, with notes and Fix-Its`() {
    let files = [ExpandedFile(file: "A.swift", expansions: [], diagnostics: [diagnostic])]
    #expect(
      renderDiagnostics(files) == """
        A.swift:6:3: error: @Record can only be applied to a struct or class
        A.swift:2:1: note: declared here
        A.swift:6:3: note: fix-it: remove '@Record'

        """
    )
  }

  @Test
  func `The JSON leaves out the symbol of a whole-file expansion`() throws {
    let result = ExpandResult(
      schemaVersion: expandSchemaVersion,
      files: [
        ExpandedFile(
          file: "A.swift",
          expansions: [Expansion(symbol: nil, source: "a"), Expansion(symbol: "A", source: "b")],
          diagnostics: []
        )
      ]
    )
    let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(result)) as? [String: Any]
    let files = try #require(json?["files"] as? [[String: Any]])
    let expansions = try #require(files.first?["expansions"] as? [[String: Any]])
    #expect(expansions.map { $0.keys.sorted() } == [["source"], ["source", "symbol"]])
  }

  @Test
  func `The summary counts errors, warnings and files`() {
    let warning = ExpansionDiagnostic(severity: .warning, message: "w", line: 1, column: 1)
    let clean = ExpandedFile(file: "A.swift", expansions: [], diagnostics: [])
    let broken = ExpandedFile(file: "B.swift", expansions: [], diagnostics: [diagnostic, warning, warning])
    #expect(renderSummary([clean]) == "No macro errors or warnings in 1 file.\n")
    #expect(renderSummary([clean, broken]) == "1 error and 2 warnings in 2 files.\n")
  }
}
