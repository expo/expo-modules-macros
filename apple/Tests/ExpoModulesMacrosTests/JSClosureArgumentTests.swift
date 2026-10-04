import ExpoModulesMacros
import SwiftSyntax
import SwiftSyntaxMacroExpansion
import SwiftSyntaxMacros
import SwiftSyntaxMacrosGenericTestSupport
import Testing

private let macroSpecs: [String: MacroSpec] = [
  "JS": MacroSpec(type: JSMacro.self),
  "ExpoModule": MacroSpec(type: ExpoModuleMacro.self, conformances: ["AnyModule"]),
  "SharedObject": MacroSpec(type: SharedObjectMacro.self),
]

private func assertExpansion(
  _ original: String,
  expandedSource expected: String,
  diagnostics: [DiagnosticSpec] = [],
  fixedSource: String? = nil,
  sourceLocation: Testing.SourceLocation = #_sourceLocation,
  fileID: StaticString = #fileID,
  filePath: StaticString = #filePath,
  line: UInt = #line,
  column: UInt = #column
) {
  assertMacroExpansion(
    original,
    expandedSource: expected,
    diagnostics: diagnostics,
    macroSpecs: macroSpecs,
    fixedSource: fixedSource,
    indentationWidth: .spaces(2),
    failureHandler: { spec in
      Issue.record(Comment(rawValue: spec.message), sourceLocation: sourceLocation)
    },
    fileID: fileID,
    filePath: filePath,
    line: line,
    column: column
  )
}

@Suite("@JS closure arguments")
struct JSClosureArgumentTests {
  @Test
  func `Non-throwing Void closure is wrapped with invokeDetached`() {
    assertExpansion(
      """
      @ExpoModule
      final class MyModule: Module {
        @JS
        func subscribe(onChange: @escaping (Int) -> Void) {}
      }
      """,
      expandedSource: """
        final class MyModule: Module {
          @JavaScriptActor
          func subscribe(onChange: @escaping (Int) -> Void) {}

          public static let _jsName = "MyModule"

          public func _synthesizedDefinition() -> [AnyDefinition] {
            return []
          }

          @JavaScriptActor
          public func _decorateModule(object: borrowing JavaScriptObject, in runtime: JavaScriptRuntime) throws {
            object.setProperty("subscribe") { [self] (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer) in
              guard arguments.count == 1 else {
                throw Exceptions.ArgumentsRangeMismatch((functionName: "subscribe", received: arguments.count, required: 1, maximum: 1))
              }
              let arg0Function = try JavaScriptFunctionHandle(arguments.unownedValue(at: 0), in: runtime)
              let arg0: (Int) -> Void = { @Sendable p0 in
                arg0Function.invokeDetached { runtime in
                  try [Int.encode(p0, in: runtime)]
                }
              }
              self.subscribe(onChange: arg0)
              return .undefined
            }
          }
        }
        """
    )
  }

  @Test
  func `Throwing closure blocks, decodes its result, and asserts both directions`() {
    assertExpansion(
      """
      @ExpoModule
      final class MyModule: Module {
        @JS
        func measure(name: String, layout: (Point, Int) throws -> Size) throws {}
      }
      """,
      expandedSource: """
        final class MyModule: Module {
          @JavaScriptActor
          func measure(name: String, layout: (Point, Int) throws -> Size) throws {}

          private func _assertTypesConformance_measure() {
            func measure<A0: JavaScriptDecodable, E0: JavaScriptEncodable>(_: A0.Type, _: E0.Type) {
            }
            measure(Size.self, Point.self)
          }

          public static let _jsName = "MyModule"

          public func _synthesizedDefinition() -> [AnyDefinition] {
            return []
          }

          @JavaScriptActor
          public func _decorateModule(object: borrowing JavaScriptObject, in runtime: JavaScriptRuntime) throws {
            object.setProperty("measure") { [self] (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer) in
              guard arguments.count == 2 else {
                throw Exceptions.ArgumentsRangeMismatch((functionName: "measure", received: arguments.count, required: 2, maximum: 2))
              }
              let arg0 = try String.decode(arguments.unownedValue(at: 0), in: runtime)
              let arg1Function = try JavaScriptFunctionHandle(arguments.unownedValue(at: 1), in: runtime)
              let arg1: (Point, Int) throws -> Size = { @Sendable p0, p1 in
                try arg1Function.invokeBlocking { runtime in
                  try [Point.encode(p0, in: runtime), Int.encode(p1, in: runtime)]
                } decodeResult: { result, runtime in
                  try Size.decode(result, in: runtime)
                }
              }
              try self.measure(name: arg0, layout: arg1)
              return .undefined
            }
          }
        }
        """
    )
  }

  @Test
  func `Async throwing closure in an async function is created in the decode phase`() {
    assertExpansion(
      """
      @ExpoModule
      final class MyModule: Module {
        @JS
        func load(fetch: @escaping @Sendable (Request) async throws -> Data) async throws -> Int { 0 }
      }
      """,
      expandedSource: """
        final class MyModule: Module {
          @JavaScriptActor
          func load(fetch: @escaping @Sendable (Request) async throws -> Data) async throws -> Int { 0 }

          private func _assertTypesConformance_load() {
            func load<A0: JavaScriptDecodable, E0: JavaScriptEncodable>(_: A0.Type, _: E0.Type) {
            }
            load(Data.self, Request.self)
          }

          public static let _jsName = "MyModule"

          public func _synthesizedDefinition() -> [AnyDefinition] {
            return []
          }

          @JavaScriptActor
          public func _decorateModule(object: borrowing JavaScriptObject, in runtime: JavaScriptRuntime) throws {
            object.setProperty("load") { [self] (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer) in
              guard arguments.count == 1 else {
                throw Exceptions.ArgumentsRangeMismatch((functionName: "load", received: arguments.count, required: 1, maximum: 1))
              }
              let arg0Function = try JavaScriptFunctionHandle(arguments.unownedValue(at: 0), in: runtime)
              let arg0: @Sendable (Request) async throws -> Data = { @Sendable p0 in
                try await arg0Function.invokeAsync { runtime in
                  try [Request.encode(p0, in: runtime)]
                } decodeResult: { result, runtime in
                  try Data.decode(result, in: runtime)
                }
              }
              return {
                let result = try await self.load(fetch: arg0)
                return try await runtime.execute {
                  return try Int.encode(result, in: runtime)
                }
              }
            }
          }
        }
        """
    )
  }

  @Test
  func `Non-throwing async closure reports a JS error through the handle`() {
    assertExpansion(
      """
      @ExpoModule
      final class MyModule: Module {
        @JS
        func run(task: () async -> Void) {}
      }
      """,
      expandedSource: """
        final class MyModule: Module {
          @JavaScriptActor
          func run(task: () async -> Void) {}

          public static let _jsName = "MyModule"

          public func _synthesizedDefinition() -> [AnyDefinition] {
            return []
          }

          @JavaScriptActor
          public func _decorateModule(object: borrowing JavaScriptObject, in runtime: JavaScriptRuntime) throws {
            object.setProperty("run") { [self] (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer) in
              guard arguments.count == 1 else {
                throw Exceptions.ArgumentsRangeMismatch((functionName: "run", received: arguments.count, required: 1, maximum: 1))
              }
              let arg0Function = try JavaScriptFunctionHandle(arguments.unownedValue(at: 0), in: runtime)
              let arg0: () async -> Void = { @Sendable in
                do {
                  try await arg0Function.invokeAsync { runtime in
                    []
                  }
                } catch {
                  arg0Function.reportError(error)
                }
              }
              self.run(task: arg0)
              return .undefined
            }
          }
        }
        """
    )
  }

  @Test
  func `Trailing optional closure is nil when omitted and decodes through decodeIfPresent`() {
    assertExpansion(
      """
      @ExpoModule
      final class MyModule: Module {
        @JS
        func start(onDone: ((Bool) throws -> Void)?) {}
      }
      """,
      expandedSource: """
        final class MyModule: Module {
          @JavaScriptActor
          func start(onDone: ((Bool) throws -> Void)?) {}

          public static let _jsName = "MyModule"

          public func _synthesizedDefinition() -> [AnyDefinition] {
            return []
          }

          @JavaScriptActor
          public func _decorateModule(object: borrowing JavaScriptObject, in runtime: JavaScriptRuntime) throws {
            object.setProperty("start") { [self] (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer) in
              guard arguments.count >= 0 && arguments.count <= 1 else {
                throw Exceptions.ArgumentsRangeMismatch((functionName: "start", received: arguments.count, required: 0, maximum: 1))
              }
              switch arguments.count {
              case 0:
                self.start(onDone: nil)
              default:
                let arg0: ((Bool) throws -> Void)?
                if let arg0Function = try JavaScriptFunctionHandle.decodeIfPresent(arguments.unownedValue(at: 0), in: runtime) {
                  arg0 = { @Sendable p0 in
                    try arg0Function.invokeBlocking { runtime in
                      try [Bool.encode(p0, in: runtime)]
                    }
                  }
                } else {
                  arg0 = nil
                }
                self.start(onDone: arg0)
              }
              return .undefined
            }
          }
        }
        """
    )
  }

  @Test
  func `@JS init wraps a closure argument the same way`() {
    assertExpansion(
      """
      @SharedObject
      final class Watcher: SharedObject {
        @JS
        init(onEvent: @escaping (String) -> Void) {}
      }
      """,
      expandedSource: """
        final class Watcher: SharedObject {
          @JavaScriptActor
          init(onEvent: @escaping (String) -> Void) {}

          public static func _synthesizedClassDefinition() -> ClassDefinition {
            return Class("Watcher", Watcher.self) {
            }
          }

          @JavaScriptActor
          public override class func _constructSharedObject(this: JavaScriptValue, arguments: borrowing JavaScriptValuesBuffer, in runtime: JavaScriptRuntime) throws -> SharedObject? {
            guard arguments.count == 1 else {
              throw Exceptions.ArgumentsRangeMismatch((functionName: "Watcher", received: arguments.count, required: 1, maximum: 1))
            }
            let arg0Function = try JavaScriptFunctionHandle(arguments.unownedValue(at: 0), in: runtime)
            let arg0: (String) -> Void = { @Sendable p0 in
              arg0Function.invokeDetached { runtime in
                try [String.encode(p0, in: runtime)]
              }
            }
            return Watcher(onEvent: arg0)
          }
        }
        """
    )
  }

  // MARK: - Diagnostics

  @Test
  func `Non-throwing closure that returns a value is an error with an insert-throws fix-it`() {
    assertExpansion(
      """
      @ExpoModule
      final class MyModule: Module {
        @JS
        func sort(compare: (Int, Int) -> Bool) {}
      }
      """,
      expandedSource: """
        final class MyModule: Module {
          @JavaScriptActor
          func sort(compare: (Int, Int) -> Bool) {}

          public static let _jsName = "MyModule"

          public func _synthesizedDefinition() -> [AnyDefinition] {
            return []
          }

          @JavaScriptActor
          public func _decorateModule(object: borrowing JavaScriptObject, in runtime: JavaScriptRuntime) throws {
            object.setProperty("sort") { [self] (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer) in
              guard arguments.count == 1 else {
                throw Exceptions.ArgumentsRangeMismatch((functionName: "sort", received: arguments.count, required: 1, maximum: 1))
              }
              let arg0Function = try JavaScriptFunctionHandle(arguments.unownedValue(at: 0), in: runtime)
              let arg0: (Int, Int) -> Bool = { @Sendable p0, p1 in
                try arg0Function.invokeBlocking { runtime in
                  try [Int.encode(p0, in: runtime), Int.encode(p1, in: runtime)]
                } decodeResult: { result, runtime in
                  try Bool.decode(result, in: runtime)
                }
              }
              self.sort(compare: arg0)
              return .undefined
            }
          }
        }
        """,
      diagnostics: [
        DiagnosticSpec(
          message:
            "A @JS closure argument that returns a value must be 'throws': when the JavaScript function throws, the closure has no value to return.",
          line: 5,
          column: 22,
          severity: .error,
          fixIts: [FixItSpec(message: "Mark the closure 'throws'")]
        )
      ]
    )
  }

  // The two tests below apply the fix-it and check the resulting source. They mark `@JS` on its own
  // rather than inside an `@ExpoModule` class: `assertMacroExpansion` maps a fix-it back onto the
  // original source through the node it is anchored to, and for a member that the enclosing
  // `@ExpoModule` expansion re-emits that mapping lands at the wrong offset.
  @Test
  func `The insert-throws fix-it marks a closure throws`() {
    assertExpansion(
      """
      @JS
      func sort(compare: (Int, Int) -> Bool) {}
      """,
      expandedSource: """
        func sort(compare: (Int, Int) -> Bool) {}
        """,
      diagnostics: [
        DiagnosticSpec(
          message:
            "A @JS closure argument that returns a value must be 'throws': when the JavaScript function throws, the closure has no value to return.",
          line: 2,
          column: 20,
          severity: .error,
          fixIts: [FixItSpec(message: "Mark the closure 'throws'")]
        )
      ],
      fixedSource: """
        @JS
        func sort(compare: (Int, Int) throws -> Bool) {}
        """
    )
  }

  @Test
  func `The insert-throws fix-it puts 'throws' after an existing 'async'`() {
    assertExpansion(
      """
      @JS
      func fetch(load: (String) async -> Int) {}
      """,
      expandedSource: """
        func fetch(load: (String) async -> Int) {}
        """,
      diagnostics: [
        DiagnosticSpec(
          message:
            "A @JS closure argument that returns a value must be 'throws': when the JavaScript function throws, the closure has no value to return.",
          line: 2,
          column: 18,
          severity: .error,
          fixIts: [FixItSpec(message: "Mark the closure 'throws'")]
        )
      ],
      fixedSource: """
        @JS
        func fetch(load: (String) async throws -> Int) {}
        """
    )
  }

  @Test
  func `Closures outside an argument position are errors`() {
    assertExpansion(
      """
      @JS
      func makeHandler() -> (Int) -> Void { { _ in } }
      @JS
      var onChange: (Int) -> Void = { _ in }
      @JS
      func subscribe(handlers: [(Int) -> Void]) {}
      """,
      expandedSource: """
        func makeHandler() -> (Int) -> Void { { _ in } }
        var onChange: (Int) -> Void = { _ in }
        func subscribe(handlers: [(Int) -> Void]) {}
        """,
      diagnostics: [
        DiagnosticSpec(
          message: "A @JS function can't return a closure: a native closure can't be encoded to a JavaScript function.",
          line: 2,
          column: 23,
          severity: .error
        ),
        DiagnosticSpec(
          message: "A @JS property can't have a closure type: a native closure can't be encoded to a JavaScript function.",
          line: 4,
          column: 15,
          severity: .error
        ),
        DiagnosticSpec(
          message:
            "A closure in a @JS argument must be the argument's own type, optionally wrapped in an optional. Closures inside other types, such as arrays or dictionaries, aren't supported.",
          line: 6,
          column: 27,
          severity: .error
        ),
      ]
    )
  }

  @Test
  func `Unsupported closure shapes are errors`() {
    assertExpansion(
      """
      @JS
      func a(callback: @MainActor (Int) -> Void) {}
      @JS
      func b(callback: (Int) throws(MyError) -> Void) {}
      @JS
      func c(callback: ((Int) -> Void) throws -> Void) {}
      @JS
      func d(callback: (Any) -> Void) {}
      """,
      expandedSource: """
        func a(callback: @MainActor (Int) -> Void) {}
        func b(callback: (Int) throws(MyError) -> Void) {}
        func c(callback: ((Int) -> Void) throws -> Void) {}
        func d(callback: (Any) -> Void) {}
        """,
      diagnostics: [
        DiagnosticSpec(
          message:
            "'@MainActor' isn't supported on a @JS closure argument. The closure calls JavaScript through its own thread hop, so only '@escaping' and '@Sendable' are allowed.",
          line: 2,
          column: 18,
          severity: .error
        ),
        DiagnosticSpec(
          message:
            "A @JS closure argument can't use typed throws: the error from JavaScript can be any error. Write 'throws' without a type.",
          line: 4,
          column: 24,
          severity: .error
        ),
        DiagnosticSpec(
          message: "A @JS closure argument can't take or return another closure.",
          line: 6,
          column: 19,
          severity: .error
        ),
        DiagnosticSpec(
          message:
            "A @JS closure argument can't use the free-form 'Any'. Use a concrete type, or 'JavaScriptValue' to pass a JS value through unchanged.",
          line: 8,
          column: 19,
          severity: .error
        ),
      ]
    )
  }
}
