import ExpoModulesMacros
import ExpoModulesCLI
import Testing

@Suite("expand")
struct ExpandTests {
  private let module = """
    import ExpoModulesCore

    @ExpoModule
    final class MyModule: Module {
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
    #expect(expansion.source.contains("extension MyModule.Options: Record {"))
    #expect(!expansion.source.contains("@JS"))
  }

  @Test
  func `A member symbol expands the type with only that member`() throws {
    let result = expandMacros(source: module, file: "MyModule.swift", symbols: ["MyModule.greet"])
    let expansion = try #require(result.expansions.only)
    #expect(expansion.symbol == "MyModule.greet")
    #expect(expansion.source.hasPrefix("final class MyModule: Module {"))
    #expect(expansion.source.contains("object.setProperty(\"greet\")"))
    #expect(!expansion.source.contains("add"))
    #expect(!expansion.source.contains("struct Options"))
  }

  @Test
  func `A nested type symbol prints the type without its indentation and the extensions its macros add`() throws {
    let result = expandMacros(source: module, file: "MyModule.swift", symbols: ["MyModule.Options"])
    let expansion = try #require(result.expansions.only)
    #expect(expansion.source.hasPrefix("struct Options {\n  var verbose: Bool = false\n"))
    #expect(expansion.source.contains("\n}\n\nextension MyModule.Options: Record {"))
    #expect(!expansion.source.contains("_jsName"))
  }

  @Test
  func `A member inside #if keeps the #if block`() throws {
    let source = """
      @ExpoModule
      final class MyModule: Module {
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
      final class MyModule: Module {
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
      final class MyModule: Module {
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
      final class Plain {
        @JS
        func take(callbacks: [() -> Void]) {}
      }

      @ExpoModule
      final class MyModule: Module {
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
  func `A member symbol keeps the type aliases of its type`() throws {
    let source = """
      @ExpoModule
      final class MyModule: Module {
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
      final class MyModule: Module {
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
    #expect(expansion.source.contains("extension MyModule.Options: Record {"))
    #expect(!expansion.source.contains("extension Options: Record {"))
  }

  @Test
  func `A member symbol is written without backticks`() throws {
    let source = """
      @ExpoModule
      final class MyModule: Module {
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

extension Array {
  /// The only element, or `nil` when there is not exactly one.
  fileprivate var only: Element? {
    count == 1 ? first : nil
  }
}
