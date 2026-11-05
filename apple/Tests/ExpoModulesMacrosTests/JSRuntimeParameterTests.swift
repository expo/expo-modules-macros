import ExpoModulesMacrosCore
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
    failureHandler: recordIssue,
    fileID: fileID,
    filePath: filePath,
    line: line,
    column: column
  )
}

private let asyncMessage =
  "A @JS function can take the JavaScript runtime only when it's synchronous: an 'async' function can resume on another thread after an 'await', and the runtime can be used only on the JavaScript thread. Remove the parameter, or make the function synchronous."
private let labelMessage =
  "The parameter that takes the JavaScript runtime must be labeled 'in', as in 'in runtime: borrowing JavaScriptRuntime'."
private let borrowingMessage =
  "The parameter that takes the JavaScript runtime must be 'borrowing': the runtime can be used only on the JavaScript thread, and a borrowed parameter can't be kept for later without an explicit 'copy'."

@Suite("@JS runtime parameter")
struct JSRuntimeParameterTests {
  @Test
  func `A module function gets the runtime of the call, and JavaScript doesn't see the parameter`() {
    assertExpansion(
      """
      @ExpoModule
      public final class HostModule: Module {
        @JS
        func makeFunction(_ name: String, in runtime: borrowing JavaScriptRuntime) -> JavaScriptFunction {}
      }
      """,
      expandedSource: """
        public final class HostModule: Module {
          @JavaScriptActor
          func makeFunction(_ name: String, in runtime: borrowing JavaScriptRuntime) -> JavaScriptFunction {}

          public static let _jsName = "HostModule"

          @JavaScriptActor
          public func _decorateModule(object: borrowing JavaScriptObject, in runtime: JavaScriptRuntime) throws {
            object.setProperty("makeFunction") { [self] (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer, result: borrowing JavaScriptValue.Slot, runtime: borrowing JavaScriptRuntime) in
              guard arguments.count == 1 else {
                throw Exceptions.ArgumentsRangeMismatch((functionName: "makeFunction", received: arguments.count, required: 1, maximum: 1))
              }
              let arg0 = try String.decode(arguments.unownedValue(at: 0), in: runtime)
              let value = self.makeFunction(arg0, in: runtime)
              try JavaScriptFunction.encode(value, into: result, in: runtime)
            }
          }

          private func _assertTypesConformance() {
            func makeFunction(returning _: (some JavaScriptEncodable & ~Copyable).Type) {
            }
            makeFunction(returning: JavaScriptFunction.self)
          }
        }
        """
    )
  }

  @Test
  func `A function that returns nothing binds through the result-slot closure to get the runtime labeled runtime`() {
    assertExpansion(
      """
      @ExpoModule
      public final class HostModule: Module {
        @JS
        func install(_ name: String, global: Bool = false, runtime: borrowing JavaScriptRuntime) {}
      }
      """,
      expandedSource: """
        public final class HostModule: Module {
          @JavaScriptActor
          func install(_ name: String, global: Bool = false, runtime: borrowing JavaScriptRuntime) {}

          public static let _jsName = "HostModule"

          @JavaScriptActor
          public func _decorateModule(object: borrowing JavaScriptObject, in runtime: JavaScriptRuntime) throws {
            object.setProperty("install") { [self] (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer, result: borrowing JavaScriptValue.Slot, runtime: borrowing JavaScriptRuntime) in
              guard arguments.count >= 1 && arguments.count <= 2 else {
                throw Exceptions.ArgumentsRangeMismatch((functionName: "install", received: arguments.count, required: 1, maximum: 2))
              }
              let arg0 = try String.decode(arguments.unownedValue(at: 0), in: runtime)
              switch arguments.count {
              case 1:
                self.install(arg0, runtime: runtime)
              default:
                let arg1 = try Bool.decode(arguments.unownedValue(at: 1), in: runtime)
                self.install(arg0, global: arg1, runtime: runtime)
              }
            }
          }
        }
        """
    )
  }

  @Test
  func `A shared object initializer and static function get the runtime of the call`() {
    assertExpansion(
      """
      @SharedObject
      public final class Cache: SharedObject {
        @JS
        init(name: String, in runtime: borrowing JavaScriptRuntime) {}

        @JS
        static func make(runtime: borrowing JavaScriptRuntime) -> Int { 1 }
      }
      """,
      expandedSource: """
        public final class Cache: SharedObject {
          @JavaScriptActor
          init(name: String, in runtime: borrowing JavaScriptRuntime) {}
          @JavaScriptActor
          static func make(runtime: borrowing JavaScriptRuntime) -> Int { 1 }

          public override class var _jsName: String {
            "Cache"
          }

          @JavaScriptActor
          public override class func _decorateSharedObject(constructor: borrowing JavaScriptObject, in runtime: JavaScriptRuntime) throws {
            constructor.setProperty("make") { (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer, result: borrowing JavaScriptValue.Slot, runtime: borrowing JavaScriptRuntime) in
              guard arguments.count == 0 else {
                throw Exceptions.ArgumentsRangeMismatch((functionName: "make", received: arguments.count, required: 0, maximum: 0))
              }
              let value = Cache.make(runtime: runtime)
              try Int.encode(value, into: result, in: runtime)
            }
          }

          @JavaScriptActor
          public override class func _constructSharedObject(this: borrowing JavaScriptValue, arguments: borrowing JavaScriptValuesBuffer, in runtime: JavaScriptRuntime) throws -> SharedObject? {
            guard arguments.count == 1 else {
              throw Exceptions.ArgumentsRangeMismatch((functionName: "Cache", received: arguments.count, required: 1, maximum: 1))
            }
            let arg0 = try String.decode(arguments.unownedValue(at: 0), in: runtime)
            return Cache(name: arg0, in: runtime)
          }
        }
        """
    )
  }

  @Test
  func `A function with a closure argument decodes the closure and passes the runtime`() {
    assertExpansion(
      """
      @ExpoModule
      public final class HostModule: Module {
        @JS
        func observe(_ listener: @escaping (String) -> Void, in runtime: borrowing JavaScriptRuntime) {}
      }
      """,
      expandedSource: """
        public final class HostModule: Module {
          @JavaScriptActor
          func observe(_ listener: @escaping (String) -> Void, in runtime: borrowing JavaScriptRuntime) {}

          public static let _jsName = "HostModule"

          @JavaScriptActor
          public func _decorateModule(object: borrowing JavaScriptObject, in runtime: JavaScriptRuntime) throws {
            object.setProperty("observe") { [self] (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer, result: borrowing JavaScriptValue.Slot, runtime: borrowing JavaScriptRuntime) in
              guard arguments.count == 1 else {
                throw Exceptions.ArgumentsRangeMismatch((functionName: "observe", received: arguments.count, required: 1, maximum: 1))
              }
              let arg0Callback = try JavaScriptCallback.decode(arguments.unownedValue(at: 0), in: runtime)
              let arg0: (String) -> Void = { @Sendable p0 in
                arg0Callback.invokeDetached(p0, argumentCount: 1) { _values, _arguments, _runtime in
                  try _arguments.emplace(_values, at: 0, in: _runtime)
                }
              }
              self.observe(arg0, in: runtime)
            }
          }
        }
        """
    )
  }

  @Test
  func `A subclass initializer gets the runtime of the call like the base class initializer`() {
    assertExpansion(
      """
      @SharedObject
      open class Shape: SharedObject {
        @JS
        init(name: String, in runtime: borrowing JavaScriptRuntime) {}
      }

      @SharedObject
      public final class Circle: Shape {
        @JS
        init(radius: Double, in runtime: borrowing JavaScriptRuntime) {
          super.init(name: "circle", in: runtime)
        }
      }
      """,
      expandedSource: """
        open class Shape: SharedObject {
          @JavaScriptActor
          init(name: String, in runtime: borrowing JavaScriptRuntime) {}

          public override class var _jsName: String {
            "Shape"
          }

          @JavaScriptActor
          public override class func _constructSharedObject(this: borrowing JavaScriptValue, arguments: borrowing JavaScriptValuesBuffer, in runtime: JavaScriptRuntime) throws -> SharedObject? {
            guard self == Shape.self else {
              return nil
            }
            guard arguments.count == 1 else {
              throw Exceptions.ArgumentsRangeMismatch((functionName: "Shape", received: arguments.count, required: 1, maximum: 1))
            }
            let arg0 = try String.decode(arguments.unownedValue(at: 0), in: runtime)
            return Shape(name: arg0, in: runtime)
          }
        }
        public final class Circle: Shape {
          @JavaScriptActor
          init(radius: Double, in runtime: borrowing JavaScriptRuntime) {
            super.init(name: "circle", in: runtime)
          }

          public override class var _jsName: String {
            "Circle"
          }

          @JavaScriptActor
          public override class func _constructSharedObject(this: borrowing JavaScriptValue, arguments: borrowing JavaScriptValuesBuffer, in runtime: JavaScriptRuntime) throws -> SharedObject? {
            guard arguments.count == 1 else {
              throw Exceptions.ArgumentsRangeMismatch((functionName: "Circle", received: arguments.count, required: 1, maximum: 1))
            }
            let arg0 = try Double.decode(arguments.unownedValue(at: 0), in: runtime)
            return Circle(radius: arg0, in: runtime)
          }
        }
        """
    )
  }

  // The diagnostics are tested on members outside a class, like the other `@JS` diagnostics: inside an
  // `@ExpoModule` class, the test support reports them one line below the member.

  @Test
  func `An async function can't take the runtime`() {
    assertExpansion(
      """
      @JS
      func load(runtime: borrowing JavaScriptRuntime) async {}
      """,
      expandedSource: """
        func load(runtime: borrowing JavaScriptRuntime) async {}
        """,
      diagnostics: [DiagnosticSpec(message: asyncMessage, line: 2, column: 20)]
    )
  }

  @Test
  func `A function with a promise-returning variant can't take the runtime`() {
    assertExpansion(
      """
      @JS(.withAsync("loadAsync"))
      func load(runtime: borrowing JavaScriptRuntime) {}
      """,
      expandedSource: """
        func load(runtime: borrowing JavaScriptRuntime) {}
        """,
      diagnostics: [
        DiagnosticSpec(
          message:
            "A @JS function can take the JavaScript runtime only when it's synchronous: the variant that '.withAsync' adds runs the function on the concurrent thread pool, and the runtime can be used only on the JavaScript thread. Remove the parameter, or remove '.withAsync'.",
          line: 2,
          column: 20
        )
      ]
    )
  }

  @Test
  func `The runtime must be the last parameter`() {
    assertExpansion(
      """
      @JS
      func load(runtime: borrowing JavaScriptRuntime, name: String) {}
      """,
      expandedSource: """
        func load(runtime: borrowing JavaScriptRuntime, name: String) {}
        """,
      diagnostics: [
        DiagnosticSpec(
          message:
            "The JavaScript runtime must be the last parameter of a @JS function or initializer, and only one parameter can take it. Move it to the end as 'in runtime: borrowing JavaScriptRuntime'.",
          line: 2,
          column: 11
        )
      ]
    )
  }

  @Test
  func `A runtime parameter with another label gets a fix-it that keeps its name`() {
    assertExpansion(
      """
      @JS
      func install(using rt: borrowing JavaScriptRuntime) {}
      """,
      expandedSource: """
        func install(using rt: borrowing JavaScriptRuntime) {}
        """,
      diagnostics: [
        DiagnosticSpec(
          message: labelMessage,
          line: 2,
          column: 14,
          fixIts: [FixItSpec(message: "Label the parameter 'in'")]
        )
      ],
      fixedSource: """
        @JS
        func install(in rt: borrowing JavaScriptRuntime) {}
        """
    )
  }

  @Test
  func `An unlabeled runtime parameter gets a fix-it that labels it in`() {
    assertExpansion(
      """
      @JS
      func install(_ runtime: borrowing JavaScriptRuntime) {}
      """,
      expandedSource: """
        func install(_ runtime: borrowing JavaScriptRuntime) {}
        """,
      diagnostics: [
        DiagnosticSpec(
          message: labelMessage,
          line: 2,
          column: 14,
          fixIts: [FixItSpec(message: "Label the parameter 'in'")]
        )
      ],
      fixedSource: """
        @JS
        func install(in runtime: borrowing JavaScriptRuntime) {}
        """
    )
  }

  @Test
  func `A runtime parameter with only a name gets a fix-it that keeps it as the name`() {
    assertExpansion(
      """
      @JS
      func install(rt: borrowing JavaScriptRuntime) {}
      """,
      expandedSource: """
        func install(rt: borrowing JavaScriptRuntime) {}
        """,
      diagnostics: [
        DiagnosticSpec(
          message: labelMessage,
          line: 2,
          column: 14,
          fixIts: [FixItSpec(message: "Label the parameter 'in'")]
        )
      ],
      fixedSource: """
        @JS
        func install(in rt: borrowing JavaScriptRuntime) {}
        """
    )
  }

  @Test
  func `An escaped label is accepted`() {
    assertExpansion(
      """
      @JS
      func install(`in` runtime: borrowing JavaScriptRuntime) {}
      @JS
      func uninstall(`runtime`: borrowing JavaScriptRuntime) {}
      """,
      expandedSource: """
        func install(`in` runtime: borrowing JavaScriptRuntime) {}
        func uninstall(`runtime`: borrowing JavaScriptRuntime) {}
        """
    )
  }

  @Test
  func `A .concurrent function can't take the runtime`() {
    assertExpansion(
      """
      @JS(.concurrent)
      func load(in runtime: borrowing JavaScriptRuntime) async {}
      """,
      expandedSource: """
        func load(in runtime: borrowing JavaScriptRuntime) async {}
        """,
      diagnostics: [
        DiagnosticSpec(
          message:
            "A @JS function can take the JavaScript runtime only when it's synchronous: '.concurrent' runs the body on the concurrent thread pool, and the runtime can be used only on the JavaScript thread. Remove the parameter.",
          line: 2,
          column: 23
        )
      ]
    )
  }

  @Test
  func `Only one parameter can take the runtime`() {
    assertExpansion(
      """
      @JS
      func load(in first: borrowing JavaScriptRuntime, in second: borrowing JavaScriptRuntime) {}
      """,
      expandedSource: """
        func load(in first: borrowing JavaScriptRuntime, in second: borrowing JavaScriptRuntime) {}
        """,
      diagnostics: [
        DiagnosticSpec(
          message:
            "The JavaScript runtime must be the last parameter of a @JS function or initializer, and only one parameter can take it. Move it to the end as 'in runtime: borrowing JavaScriptRuntime'.",
          line: 2,
          column: 11
        )
      ]
    )
  }

  @Test
  func `An optional runtime parameter gets a fix-it that removes the optional`() {
    assertExpansion(
      """
      @JS
      func install(in runtime: borrowing JavaScriptRuntime?) {}
      """,
      expandedSource: """
        func install(in runtime: borrowing JavaScriptRuntime?) {}
        """,
      diagnostics: [
        DiagnosticSpec(
          message:
            "The parameter that takes the JavaScript runtime can't be optional: the binding always passes the runtime of the call.",
          line: 2,
          column: 36,
          fixIts: [FixItSpec(message: "Remove the optional")]
        )
      ],
      fixedSource: """
        @JS
        func install(in runtime: borrowing JavaScriptRuntime) {}
        """
    )
  }

  @Test
  func `An inout runtime parameter gets only the borrowing error`() {
    assertExpansion(
      """
      @JS
      func install(in runtime: inout JavaScriptRuntime) {}
      """,
      expandedSource: """
        func install(in runtime: inout JavaScriptRuntime) {}
        """,
      diagnostics: [
        DiagnosticSpec(
          message: borrowingMessage,
          line: 2,
          column: 26,
          fixIts: [FixItSpec(message: "Mark the parameter 'borrowing'")]
        )
      ],
      fixedSource: """
        @JS
        func install(in runtime: borrowing JavaScriptRuntime) {}
        """
    )
  }

  @Test
  func `A runtime parameter that isn't borrowing gets a fix-it`() {
    assertExpansion(
      """
      @JS
      func install(runtime: JavaScriptRuntime) {}
      @JS
      func uninstall(runtime: consuming JavaScriptRuntime) {}
      """,
      expandedSource: """
        func install(runtime: JavaScriptRuntime) {}
        func uninstall(runtime: consuming JavaScriptRuntime) {}
        """,
      diagnostics: [
        DiagnosticSpec(
          message: borrowingMessage,
          line: 2,
          column: 23,
          fixIts: [FixItSpec(message: "Mark the parameter 'borrowing'")]
        ),
        DiagnosticSpec(
          message: borrowingMessage,
          line: 4,
          column: 25,
          fixIts: [FixItSpec(message: "Mark the parameter 'borrowing'")]
        ),
      ],
      fixedSource: """
        @JS
        func install(runtime: borrowing JavaScriptRuntime) {}
        @JS
        func uninstall(runtime: borrowing JavaScriptRuntime) {}
        """
    )
  }
}
