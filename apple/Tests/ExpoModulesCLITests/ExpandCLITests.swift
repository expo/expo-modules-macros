import Foundation
import Testing

@testable import ExpoModulesCLI

/// An expander that records nothing and reports the symbols in `declared` as found.
private func stubExpander(declaring declared: Set<String> = []) -> MacroExpander {
  { _, file, symbols in
    ExpandedFile(
      file: file,
      expansions: symbols.filter(declared.contains).map { Expansion(symbol: $0, source: "") },
      diagnostics: []
    )
  }
}

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
  func `expand takes only existing .swift files`() throws {
    try withFile { file, directory in
      let expander = stubExpander()
      #expect(ScannerCLI.run(arguments: ["expand", directory], expander: expander) == 2)
      #expect(ScannerCLI.run(arguments: ["expand", file + ".txt"], expander: expander) == 2)
      #expect(ScannerCLI.run(arguments: ["expand", directory + "/Missing.swift"], expander: expander) == 2)
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
  func `The summary counts errors, warnings and files`() {
    let warning = ExpansionDiagnostic(severity: .warning, message: "w", line: 1, column: 1)
    let clean = ExpandedFile(file: "A.swift", expansions: [], diagnostics: [])
    let broken = ExpandedFile(file: "B.swift", expansions: [], diagnostics: [diagnostic, warning, warning])
    #expect(renderSummary([clean]) == "No macro errors or warnings in 1 file.\n")
    #expect(renderSummary([clean, broken]) == "1 error and 2 warnings in 2 files.\n")
  }
}
