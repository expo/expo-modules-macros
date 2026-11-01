import ExpoModulesCLI
import ExpoModulesMacrosCore
import Foundation
import Testing

@Suite("expand")
struct ExpandTests {
  private let module = """
    import ExpoModulesCore

    @ExpoModule
    public final class MyModule: Module {
      @JS
      func greet(name: String) -> String { "Hi" }

      @JS
      func add(_ a: Double, _ b: Double) -> Double { a + b }

      @Record
      struct Options {
        var verbose: Bool = false
      }
    }
    """

  @Test
  func `Expands the whole file without symbols`() throws {
    let result = expandMacros(source: module, file: "MyModule.swift", symbols: [])
    #expect(result.file == "MyModule.swift")
    #expect(result.diagnostics.isEmpty)
    let expansion = try #require(result.expansions.only)
    #expect(expansion.symbol == nil)
    #expect(expansion.source.contains("public static let _jsName = \"MyModule\""))
    #expect(expansion.source.contains("object.setProperty(\"greet\")"))
    #expect(expansion.source.contains("object.setProperty(\"add\")"))
    #expect(expansion.source.contains("extension MyModule.Options: nonisolated Record {"))
    #expect(!expansion.source.contains("@JS"))
  }

  @Test
  func `Passes the Sendable conformance like the compiler`() throws {
    let source = """
      @ExpoModule
      public final class MyModule: Module {}

      @SharedObject
      public final class Cache: SharedObject {}

      @SharedObject
      public final class Session: SharedObject, @unchecked Sendable {}
      """
    let result = expandMacros(source: source, file: "MyModule.swift", symbols: [])
    let expansion = try #require(result.expansions.only)
    #expect(expansion.source.contains("extension MyModule: @unchecked Sendable {"))
    #expect(expansion.source.contains("extension Cache: @unchecked Sendable {"))
    #expect(!expansion.source.contains("extension Session"))
  }

  @Test
  func `A member symbol expands the type with only that member`() throws {
    let result = expandMacros(source: module, file: "MyModule.swift", symbols: ["MyModule.greet"])
    let expansion = try #require(result.expansions.only)
    #expect(expansion.symbol == "MyModule.greet")
    #expect(expansion.source.hasPrefix("public final class MyModule: Module {"))
    #expect(expansion.source.contains("object.setProperty(\"greet\")"))
    #expect(!expansion.source.contains("add"))
    #expect(!expansion.source.contains("struct Options"))
  }

  @Test
  func `A nested type symbol prints the type without its indentation and the extensions its macros add`() throws {
    let result = expandMacros(source: module, file: "MyModule.swift", symbols: ["MyModule.Options"])
    let expansion = try #require(result.expansions.only)
    #expect(expansion.source.hasPrefix("struct Options {\n  var verbose: Bool = false\n"))
    #expect(expansion.source.contains("\n}\n\nextension MyModule.Options: nonisolated Record {"))
    #expect(!expansion.source.contains("_jsName"))
  }

  @Test
  func `A member inside #if keeps the #if block`() throws {
    let source = """
      @ExpoModule
      public final class MyModule: Module {
        #if os(iOS)
        @JS
        func vibrate() {}
        #endif

        @JS
        func other() {}
      }
      """
    let result = expandMacros(source: source, file: "MyModule.swift", symbols: ["MyModule.vibrate"])
    let expansion = try #require(result.expansions.only)
    #expect(expansion.source.contains("#if os(iOS)"))
    #expect(expansion.source.contains("func vibrate()"))
    #expect(!expansion.source.contains("other"))
  }

  @Test
  func `A symbol that the file doesn't declare has no expansion`() {
    let result = expandMacros(source: module, file: "MyModule.swift", symbols: ["MyModule.missing", "Other"])
    #expect(result.expansions.isEmpty)
  }

  @Test
  func `Reports macro diagnostics at their location in the original file`() throws {
    let source = """
      @ExpoModule
      public final class MyModule: Module {
        @JS
        func ok() {}

        @Record
        enum Wrong { case a }
      }
      """
    let result = expandMacros(source: source, file: "MyModule.swift", symbols: [])
    let diagnostic = try #require(result.diagnostics.only)
    #expect(diagnostic.severity == .error)
    #expect(diagnostic.message == "@Record can only be applied to a struct or class")
    #expect(diagnostic.line == 6)
    #expect(diagnostic.column == 3)
  }

  @Test
  func `With symbols, reports only the diagnostics inside their declarations`() {
    let source = """
      @ExpoModule
      public final class MyModule: Module {
        @JS
        func ok() {}

        @Record
        enum Wrong { case a }
      }
      """
    #expect(expandMacros(source: source, file: "f.swift", symbols: ["MyModule.ok"]).diagnostics.isEmpty)
    #expect(expandMacros(source: source, file: "f.swift", symbols: ["MyModule.Wrong"]).diagnostics.count == 1)
    #expect(expandMacros(source: source, file: "f.swift", symbols: ["MyModule"]).diagnostics.count == 1)
  }

  @Test
  func `Reports a diagnostic in a member at its line, also when the module adds attributes to the member`() throws {
    // `@ExpoModule` adds `@JavaScriptActor` to `take`, so the `@JS` macro gets a declaration with one
    // more line. The same declaration in `Plain` gets no attribute.
    let source = """
      public final class Plain {
        @JS
        func take(callbacks: [() -> Void]) {}
      }

      @ExpoModule
      public final class MyModule: Module {
        @JS
        func take(callbacks: [() -> Void]) {}

        @JS func takeOnOneLine(callbacks: [() -> Void]) {}
      }
      """
    let diagnostics = expandMacros(source: source, file: "f.swift", symbols: []).diagnostics
    #expect(diagnostics.map { [$0.line, $0.column] } == [[3, 25], [9, 25], [11, 38]])

    let member = expandMacros(source: source, file: "f.swift", symbols: ["MyModule.take"]).diagnostics
    #expect(member.map { [$0.line, $0.column] } == [[9, 25]])
  }

  @Test
  func `Maps the edits of a Fix-It to the bytes that it changes in the original file`() throws {
    // `@ExpoModule` adds `@JavaScriptActor` to `load`, so the declaration that `@JS` gets is longer
    // than the one in the file, and the Fix-It replaces the whole signature.
    let source = """
      final class Plain {
        @JS(.concurrent)
        func load() throws -> Int { 1 }
      }

      @ExpoModule
      public final class MyModule: Module {
        @JS(.concurrent)
        func load() throws -> Int { 1 }

        @JS
        func map(_ transform: (Int) -> Int) {}
      }
      """
    let diagnostics = expandMacros(source: source, file: "f.swift", symbols: []).diagnostics
    #expect(
      diagnostics.map(\.fixIts) == [
        ["Mark the function 'async'"], ["Mark the function 'async'"], ["Mark the closure 'throws'"],
      ]
    )
    let edits = try diagnostics.map { try #require($0.fixItEdits.only?.only) }
    // Each edit inserts the keyword in front of `throws` or `->`, and replaces the 8 bytes after it
    // with themselves, so that `fix` can check them.
    #expect(edits.map(\.original) == ["throws -", "throws -", "-> Int) "])
    #expect(edits.map(\.replacement) == ["async throws -", "async throws -", "throws -> Int) "])
    let text = Array(source.utf8)
    #expect(edits.allSatisfy { text[$0.offset...].starts(with: Array($0.original.utf8)) })
  }

  @Test
  func `A syntax error has no Fix-It edits`() throws {
    let result = expandMacros(source: "struct S {\n  func f( {}\n}\n", file: "f.swift", symbols: [])
    #expect(result.diagnostics.contains { !$0.fixIts.isEmpty })
    #expect(result.diagnostics.allSatisfy { $0.fixItEdits.isEmpty })
  }

  @Test
  func `Reports a diagnostic and maps a Fix-It in a property that swift-syntax rewrites before a macro gets it`() throws
  {
    // The closure in the initializer of `onA` makes the macro system rewrite the property, so the
    // declaration that `@Event` gets doesn't map back to the file by its start.
    let source = """
      @ExpoModule
      public final class MyModule: Module {
        @Event let onA: F = make { 1 }
        @Event let onB: F
      }
      """
    let diagnostics = expandMacros(source: source, file: "f.swift", symbols: []).diagnostics
    #expect(diagnostics.map { [$0.line, $0.column] } == [[3, 10], [4, 10]])
    let text = Array(source.utf8)
    let edits = try diagnostics.map { try #require($0.fixItEdits.only?.only) }
    #expect(edits.allSatisfy { text[$0.offset...].starts(with: Array($0.original.utf8)) })
    #expect(edits.allSatisfy { $0.original.hasPrefix("let") && $0.replacement.hasPrefix("var") })
  }

  @Test
  func `A member symbol keeps the type aliases of its type`() throws {
    let source = """
      @ExpoModule
      public final class MyModule: Module {
        typealias Point = (x: Double, y: Double)

        @JS
        func move(to point: Point) {}
      }
      """
    let expansion = try #require(
      expandMacros(source: source, file: "f.swift", symbols: ["MyModule.move"]).expansions.only
    )
    #expect(expansion.source.contains("typealias Point = (x: Double, y: Double)"))
    #expect(expansion.source.contains("JavaScriptValue.decodeTuple("))
  }

  @Test
  func `A member in an extension prints only that extension`() throws {
    let source = """
      extension MyModule {
        @JS
        func fromExtension() {}
      }

      extension MyModule {
        func helper() {}
      }
      """
    let expansion = try #require(
      expandMacros(source: source, file: "f.swift", symbols: ["MyModule.fromExtension"]).expansions.only
    )
    #expect(expansion.source.contains("func fromExtension()"))
    #expect(!expansion.source.contains("helper"))
  }

  @Test
  func `A nested type symbol leaves out the extensions of a top-level type with the same name`() throws {
    let source = """
      @ExpoModule
      public final class MyModule: Module {
        @Record
        struct Options {
          var verbose: Bool = false
        }
      }

      @Record
      struct Options {
        var top: Int = 0
      }
      """
    let expansion = try #require(
      expandMacros(source: source, file: "f.swift", symbols: ["MyModule.Options"]).expansions.only
    )
    #expect(expansion.source.contains("extension MyModule.Options: nonisolated Record {"))
    #expect(!expansion.source.contains("extension Options: nonisolated Record {"))
  }

  @Test
  func `A member symbol is written without backticks`() throws {
    let source = """
      @ExpoModule
      public final class MyModule: Module {
        @JS
        func `default`() {}
      }
      """
    let result = expandMacros(source: source, file: "f.swift", symbols: ["MyModule.default"])
    #expect(result.expansions.only?.symbol == "MyModule.default")
  }

  @Test
  func `Reports syntax errors in the file`() throws {
    let result = expandMacros(source: "struct S {\n  func f( {}\n}\n", file: "f.swift", symbols: [])
    #expect(result.diagnostics.contains { $0.severity == .error && $0.line == 2 })
  }
}

@Suite("fix")
struct FixTests {
  private let expander = MacroExpander(attributeNames: Set(ProvidedMacro.all.map(\.name)), expand: expandMacros)

  @Test
  func `Applies the Fix-Its in place, also those that a macro reports after the first is applied`() throws {
    // `@ViewProps` stops at its first error, so `fix` expands the file again for the next ones.
    let source = """
      @ExpoModule
      public final class MyModule: Module {
        @JS(.concurrent)
        func load() -> Int { 1 }
      }

      @ViewProps
      struct Props {
        @Field
        var title: String = ""
        @Field var size: Double = 0
        var onTap: (() -> Void)?
      }

      """
    try withFile(source) { file in
      #expect(ScannerCLI.run(arguments: ["fix", "--dry-run", file], expander: expander) == 0)
      let unchanged = try String(contentsOfFile: file, encoding: .utf8)
      #expect(unchanged == source)

      #expect(ScannerCLI.run(arguments: ["fix", file], expander: expander) == 0)
      let fixed = try String(contentsOfFile: file, encoding: .utf8)
      #expect(
        fixed == """
          @ExpoModule
          public final class MyModule: Module {
            @JS(.concurrent)
            func load() async -> Int { 1 }
          }

          @ViewProps
          struct Props {
            var title: String = ""
            var size: Double = 0
            var onTap: () -> Void
          }

          """
      )
      #expect(expandMacros(source: fixed, file: file, symbols: []).diagnostics.isEmpty)
    }
  }

  @Test
  func `With a symbol, applies only the Fix-Its inside its declaration`() throws {
    let source = """
      @ExpoModule
      public final class MyModule: Module {
        @JS(.concurrent)
        func load() -> Int { 1 }

        @JS(.concurrent)
        func save() {}
      }

      """
    try withFile(source) { file in
      #expect(ScannerCLI.run(arguments: ["fix", "--symbol", "MyModule.save", file], expander: expander) == 0)
      let fixed = try String(contentsOfFile: file, encoding: .utf8)
      #expect(fixed.contains("func load() -> Int { 1 }"))
      #expect(fixed.contains("func save() async {}"))
    }
  }

  @Test
  func `Edits only the declaration with the diagnostic, also when one with the same text follows closely`() throws {
    // `@ExpoModule` adds attributes to `a`, so the position that the macro system maps from the
    // declaration that `@Event` or `@JS` gets is past the declaration and in the next one.
    let source = """
      @ExpoModule
      public final class MyModule: Module {
        @Event(.inline) let a: F; struct S { let a: F }
        @JS(.concurrent) func b() {}; func b() {}
      }

      """
    try withFile(source) { file in
      #expect(ScannerCLI.run(arguments: ["fix", file], expander: expander) == 0)
      let fixed = try String(contentsOfFile: file, encoding: .utf8)
      #expect(fixed.contains("@Event(.inline) var a: F; struct S { let a: F }"))
      #expect(fixed.contains("@JS(.concurrent) func b() async {}; func b() {}"))
    }
  }

  @Test
  func `Applies the Fix-Its of warnings, and with --only-errors only those of errors`() throws {
    let source = """
      @ExpoModule
      final class MyModule: Module {
        @JS(.concurrent)
        func load() -> Int { 1 }
      }

      """
    try withFile(source) { file in
      #expect(ScannerCLI.run(arguments: ["fix", "--only-errors", file], expander: expander) == 0)
      let errorsFixed = try String(contentsOfFile: file, encoding: .utf8)
      #expect(errorsFixed.contains("\nfinal class MyModule: Module {"))
      #expect(errorsFixed.contains("func load() async -> Int { 1 }"))

      #expect(ScannerCLI.run(arguments: ["fix", file], expander: expander) == 0)
      let allFixed = try String(contentsOfFile: file, encoding: .utf8)
      #expect(allFixed.contains("\npublic final class MyModule: Module {"))
    }
  }

  private func withFile(_ source: String, _ body: (_ file: String) throws -> Void) throws {
    let fileManager = FileManager.default
    let root = fileManager.temporaryDirectory.appendingPathComponent(
      "macros-fix-\(ProcessInfo.processInfo.globallyUniqueString)"
    )
    defer { try? fileManager.removeItem(at: root) }
    try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
    let file = root.appendingPathComponent("MyModule.swift")
    try source.write(to: file, atomically: true, encoding: .utf8)
    try body(file.path)
  }
}

extension Array {
  /// The only element, or `nil` when there is not exactly one.
  fileprivate var only: Element? {
    count == 1 ? first : nil
  }
}
