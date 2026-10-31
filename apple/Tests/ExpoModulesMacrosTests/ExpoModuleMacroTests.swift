import ExpoModulesMacrosCore
import SwiftSyntax
import SwiftSyntaxMacroExpansion
import SwiftSyntaxMacros
import SwiftSyntaxMacrosGenericTestSupport
import Testing

private let macroSpecs: [String: MacroSpec] = [
  "JS": MacroSpec(type: JSMacro.self),
  "Event": MacroSpec(type: EventMacro.self),
  "ExpoModule": MacroSpec(type: ExpoModuleMacro.self, conformances: ["AnyModule"]),
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

@Suite("@ExpoModule / @JS macros")
struct ExpoModuleMacroTests {
  @Test
  func `Module with no exposed members emits the resolved name and an empty definition`() {
    assertExpansion(
      """
      @ExpoModule
      public final class MyModule: Module {
      }
      """,
      expandedSource: """
        public final class MyModule: Module {

          public static let _jsName = "MyModule"
        }
        """
    )
  }

  @Test
  func `A module class without an access modifier produces a warning with a fix-it`() {
    assertExpansion(
      """
      @ExpoModule
      final class MyModule: Module {
      }
      """,
      expandedSource: """
        final class MyModule: Module {

          public static let _jsName = "MyModule"
        }
        """,
      diagnostics: [
        DiagnosticSpec(
          message:
            "@ExpoModule class 'MyModule' should be public or open, so that the modules provider that autolinking generates in the app target can register it",
          line: 2,
          column: 7,
          severity: .warning,
          fixIts: [FixItSpec(message: "Make the class 'public'")]
        )
      ],
      fixedSource: """
        @ExpoModule
        public final class MyModule: Module {
        }
        """
    )
  }

  @Test
  func `The public fix-it replaces the access modifier of an internal module class`() {
    assertExpansion(
      """
      @ExpoModule
      internal final class MyModule: Module {
      }
      """,
      expandedSource: """
        internal final class MyModule: Module {

          public static let _jsName = "MyModule"
        }
        """,
      diagnostics: [
        DiagnosticSpec(
          message:
            "@ExpoModule class 'MyModule' should be public or open, so that the modules provider that autolinking generates in the app target can register it",
          line: 2,
          column: 1,
          severity: .warning,
          fixIts: [FixItSpec(message: "Make the class 'public'")]
        )
      ],
      fixedSource: """
        @ExpoModule
        public final class MyModule: Module {
        }
        """
    )
  }

  @Test
  func `An open module class produces no warning`() {
    assertExpansion(
      """
      @ExpoModule
      open class MyModule: Module {
      }
      """,
      expandedSource: """
        open class MyModule: Module {

          public static let _jsName = "MyModule"
        }
        """
    )
  }
  @Test
  func `Custom module name overrides the class name`() {
    assertExpansion(
      """
      @ExpoModule("CustomName")
      public final class MyModule: Module {
      }
      """,
      expandedSource: """
        public final class MyModule: Module {

          public static let _jsName = "CustomName"
        }
        """
    )
  }

  @Test
  func `Sync function is bound directly into the JS object, not described with a Function entry`() {
    assertExpansion(
      """
      @ExpoModule
      public final class MyModule: Module {
        @JS
        func greet(name: String) -> String { "Hi" }
      }
      """,
      expandedSource: """
        public final class MyModule: Module {
          @JavaScriptActor
          func greet(name: String) -> String { "Hi" }

          public static let _jsName = "MyModule"

          @JavaScriptActor
          public func _decorateModule(object: borrowing JavaScriptObject, in runtime: JavaScriptRuntime) throws {
            object.setProperty("greet") { [self] (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer, result: borrowing JavaScriptValue.Slot, runtime: borrowing JavaScriptRuntime) in
              guard arguments.count == 1 else {
                throw Exceptions.ArgumentsRangeMismatch((functionName: "greet", received: arguments.count, required: 1, maximum: 1))
              }
              let arg0 = try String.decode(arguments.unownedValue(at: 0), in: runtime)
              let value = self.greet(name: arg0)
              try String.encode(value, into: result, in: runtime)
            }
          }
        }
        """
    )
  }

  @Test
  func `Multi-argument function decodes each argument by its static type and preserves labels`() {
    assertExpansion(
      """
      @ExpoModule
      public final class MyModule: Module {
        @JS
        func add(_ a: Double, to b: Double) -> Double { a + b }
      }
      """,
      expandedSource: """
        public final class MyModule: Module {
          @JavaScriptActor
          func add(_ a: Double, to b: Double) -> Double { a + b }

          public static let _jsName = "MyModule"

          @JavaScriptActor
          public func _decorateModule(object: borrowing JavaScriptObject, in runtime: JavaScriptRuntime) throws {
            object.setProperty("add") { [self] (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer, result: borrowing JavaScriptValue.Slot, runtime: borrowing JavaScriptRuntime) in
              guard arguments.count == 2 else {
                throw Exceptions.ArgumentsRangeMismatch((functionName: "add", received: arguments.count, required: 2, maximum: 2))
              }
              let arg0 = try Double.decode(arguments.unownedValue(at: 0), in: runtime)
              let arg1 = try Double.decode(arguments.unownedValue(at: 1), in: runtime)
              let value = self.add(arg0, to: arg1)
              try Double.encode(value, into: result, in: runtime)
            }
          }
        }
        """
    )
  }

  @Test
  func `Trailing defaulted parameter widens the arity range and branches the call`() {
    assertExpansion(
      """
      @ExpoModule
      public final class MyModule: Module {
        @JS
        func resize(width: Int, height: Int = 100) -> Bool { true }
      }
      """,
      expandedSource: """
        public final class MyModule: Module {
          @JavaScriptActor
          func resize(width: Int, height: Int = 100) -> Bool { true }

          public static let _jsName = "MyModule"

          @JavaScriptActor
          public func _decorateModule(object: borrowing JavaScriptObject, in runtime: JavaScriptRuntime) throws {
            object.setProperty("resize") { [self] (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer, result: borrowing JavaScriptValue.Slot, runtime: borrowing JavaScriptRuntime) in
              guard arguments.count >= 1 && arguments.count <= 2 else {
                throw Exceptions.ArgumentsRangeMismatch((functionName: "resize", received: arguments.count, required: 1, maximum: 2))
              }
              let arg0 = try Int.decode(arguments.unownedValue(at: 0), in: runtime)
              let value: Bool
              switch arguments.count {
              case 1:
                value = self.resize(width: arg0)
              default:
                let arg1 = try Int.decode(arguments.unownedValue(at: 1), in: runtime)
                value = self.resize(width: arg0, height: arg1)
              }
              try Bool.encode(value, into: result, in: runtime)
            }
          }
        }
        """
    )
  }

  @Test
  func `Trailing optional parameter is passed nil when omitted`() {
    assertExpansion(
      """
      @ExpoModule
      public final class MyModule: Module {
        @JS
        func tag(name: String, note: String?) { }
      }
      """,
      expandedSource: """
        public final class MyModule: Module {
          @JavaScriptActor
          func tag(name: String, note: String?) { }

          public static let _jsName = "MyModule"

          @JavaScriptActor
          public func _decorateModule(object: borrowing JavaScriptObject, in runtime: JavaScriptRuntime) throws {
            object.setProperty("tag") { [self] (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer) -> Void in
              guard arguments.count >= 1 && arguments.count <= 2 else {
                throw Exceptions.ArgumentsRangeMismatch((functionName: "tag", received: arguments.count, required: 1, maximum: 2))
              }
              let arg0 = try String.decode(arguments.unownedValue(at: 0), in: runtime)
              switch arguments.count {
              case 1:
                self.tag(name: arg0, note: nil)
              default:
                let arg1 = try String?.decode(arguments.unownedValue(at: 1), in: runtime)
                self.tag(name: arg0, note: arg1)
              }
            }
          }
        }
        """
    )
  }

  @Test
  func `Only-defaulted parameters make every argument omittable (required count zero)`() {
    assertExpansion(
      """
      @ExpoModule
      public final class MyModule: Module {
        @JS
        func ping(times: Int = 1) -> Int { times }
      }
      """,
      expandedSource: """
        public final class MyModule: Module {
          @JavaScriptActor
          func ping(times: Int = 1) -> Int { times }

          public static let _jsName = "MyModule"

          @JavaScriptActor
          public func _decorateModule(object: borrowing JavaScriptObject, in runtime: JavaScriptRuntime) throws {
            object.setProperty("ping") { [self] (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer, result: borrowing JavaScriptValue.Slot, runtime: borrowing JavaScriptRuntime) in
              guard arguments.count >= 0 && arguments.count <= 1 else {
                throw Exceptions.ArgumentsRangeMismatch((functionName: "ping", received: arguments.count, required: 0, maximum: 1))
              }
              let value: Int
              switch arguments.count {
              case 0:
                value = self.ping()
              default:
                let arg0 = try Int.decode(arguments.unownedValue(at: 0), in: runtime)
                value = self.ping(times: arg0)
              }
              try Int.encode(value, into: result, in: runtime)
            }
          }
        }
        """
    )
  }

  @Test
  func `Non-primitive argument and return types get a conformance-assertion peer`() {
    assertExpansion(
      """
      @ExpoModule
      public final class MyModule: Module {
        @JS
        func transform(value: MyRecord, count: Int) -> [MyRecord] { [] }
      }
      """,
      expandedSource: """
        public final class MyModule: Module {
          @JavaScriptActor
          func transform(value: MyRecord, count: Int) -> [MyRecord] { [] }

          public static let _jsName = "MyModule"

          @JavaScriptActor
          public func _decorateModule(object: borrowing JavaScriptObject, in runtime: JavaScriptRuntime) throws {
            object.setProperty("transform") { [self] (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer, result: borrowing JavaScriptValue.Slot, runtime: borrowing JavaScriptRuntime) in
              guard arguments.count == 2 else {
                throw Exceptions.ArgumentsRangeMismatch((functionName: "transform", received: arguments.count, required: 2, maximum: 2))
              }
              let arg0 = try MyRecord.decode(arguments.unownedValue(at: 0), in: runtime)
              let arg1 = try Int.decode(arguments.unownedValue(at: 1), in: runtime)
              let value = self.transform(value: arg0, count: arg1)
              try [MyRecord].encode(value, into: result, in: runtime)
            }
          }

          private func _assertTypesConformance() {
            func transform(value _: (some JavaScriptDecodable & ~Copyable).Type, returning _: (some JavaScriptEncodable & ~Copyable).Type) {
            }
            transform(value: MyRecord.self, returning: [MyRecord].self)
          }
        }
        """
    )
  }

  @Test
  func `Optionals, arrays, String-keyed dictionaries, and sets of primitives get no conformance-assertion peer`() {
    assertExpansion(
      """
      @ExpoModule
      public final class MyModule: Module {
        @JS
        func group(values: [[Int]], weights: [String: Double]?, flags: Set<Bool>) -> Dictionary<String, Array<String?>> { [:] }
      }
      """,
      expandedSource: """
        public final class MyModule: Module {
          @JavaScriptActor
          func group(values: [[Int]], weights: [String: Double]?, flags: Set<Bool>) -> Dictionary<String, Array<String?>> { [:] }

          public static let _jsName = "MyModule"

          @JavaScriptActor
          public func _decorateModule(object: borrowing JavaScriptObject, in runtime: JavaScriptRuntime) throws {
            object.setProperty("group") { [self] (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer, result: borrowing JavaScriptValue.Slot, runtime: borrowing JavaScriptRuntime) in
              guard arguments.count == 3 else {
                throw Exceptions.ArgumentsRangeMismatch((functionName: "group", received: arguments.count, required: 3, maximum: 3))
              }
              let arg0 = try [[Int]].decode(arguments.unownedValue(at: 0), in: runtime)
              let arg1 = try [String: Double]?.decode(arguments.unownedValue(at: 1), in: runtime)
              let arg2 = try Set<Bool>.decode(arguments.unownedValue(at: 2), in: runtime)
              let value = self.group(values: arg0, weights: arg1, flags: arg2)
              try Dictionary<String, Array<String?>>.encode(value, into: result, in: runtime)
            }
          }
        }
        """
    )
  }

  @Test
  func `Containers of non-primitive types and non-String-keyed dictionaries are asserted`() {
    assertExpansion(
      """
      @ExpoModule
      public final class MyModule: Module {
        @JS
        func index(records: [[MyRecord]], names: [Int: String]) -> Set<MyRecord> { [] }
      }
      """,
      expandedSource: """
        public final class MyModule: Module {
          @JavaScriptActor
          func index(records: [[MyRecord]], names: [Int: String]) -> Set<MyRecord> { [] }

          public static let _jsName = "MyModule"

          @JavaScriptActor
          public func _decorateModule(object: borrowing JavaScriptObject, in runtime: JavaScriptRuntime) throws {
            object.setProperty("index") { [self] (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer, result: borrowing JavaScriptValue.Slot, runtime: borrowing JavaScriptRuntime) in
              guard arguments.count == 2 else {
                throw Exceptions.ArgumentsRangeMismatch((functionName: "index", received: arguments.count, required: 2, maximum: 2))
              }
              let arg0 = try [[MyRecord]].decode(arguments.unownedValue(at: 0), in: runtime)
              let arg1 = try [Int: String].decode(arguments.unownedValue(at: 1), in: runtime)
              let value = self.index(records: arg0, names: arg1)
              try Set<MyRecord>.encode(value, into: result, in: runtime)
            }
          }

          private func _assertTypesConformance() {
            func index(records _: (some JavaScriptDecodable & ~Copyable).Type, names _: (some JavaScriptDecodable & ~Copyable).Type, returning _: (some JavaScriptEncodable & ~Copyable).Type) {
            }
            index(records: [[MyRecord]].self, names: [Int: String].self, returning: Set<MyRecord>.self)
          }
        }
        """
    )
  }

  @Test
  func `Multiple non-primitive arguments get indexed decodable slots in the assertion`() {
    assertExpansion(
      """
      @ExpoModule
      public final class MyModule: Module {
        @JS
        func merge(primary: MyRecord, secondary: OtherRecord) -> MyRecord { primary }
      }
      """,
      expandedSource: """
        public final class MyModule: Module {
          @JavaScriptActor
          func merge(primary: MyRecord, secondary: OtherRecord) -> MyRecord { primary }

          public static let _jsName = "MyModule"

          @JavaScriptActor
          public func _decorateModule(object: borrowing JavaScriptObject, in runtime: JavaScriptRuntime) throws {
            object.setProperty("merge") { [self] (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer, result: borrowing JavaScriptValue.Slot, runtime: borrowing JavaScriptRuntime) in
              guard arguments.count == 2 else {
                throw Exceptions.ArgumentsRangeMismatch((functionName: "merge", received: arguments.count, required: 2, maximum: 2))
              }
              let arg0 = try MyRecord.decode(arguments.unownedValue(at: 0), in: runtime)
              let arg1 = try OtherRecord.decode(arguments.unownedValue(at: 1), in: runtime)
              let value = self.merge(primary: arg0, secondary: arg1)
              try MyRecord.encode(value, into: result, in: runtime)
            }
          }

          private func _assertTypesConformance() {
            func merge(primary _: (some JavaScriptDecodable & ~Copyable).Type, secondary _: (some JavaScriptDecodable & ~Copyable).Type, returning _: (some JavaScriptEncodable & ~Copyable).Type) {
            }
            merge(primary: MyRecord.self, secondary: OtherRecord.self, returning: MyRecord.self)
          }
        }
        """
    )
  }

  @Test
  func `Getter-only non-primitive property asserts only the encodable direction`() {
    assertExpansion(
      """
      @ExpoModule
      public final class MyModule: Module {
        @JS
        var cache: MyRecord { MyRecord() }
      }
      """,
      expandedSource: """
        public final class MyModule: Module {
          @JavaScriptActor
          var cache: MyRecord { MyRecord() }

          public static let _jsName = "MyModule"

          @JavaScriptActor
          public func _decorateModule(object: borrowing JavaScriptObject, in runtime: JavaScriptRuntime) throws {
            let cacheDescriptor = runtime.createObject()
            cacheDescriptor.setProperty("enumerable", value: true)
            cacheDescriptor.setProperty("get") { [self] (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer, result: borrowing JavaScriptValue.Slot, runtime: borrowing JavaScriptRuntime) in
              try MyRecord.encode(self.cache, into: result, in: runtime)
            }
            object.defineProperty("cache", descriptor: cacheDescriptor)
          }

          private func _assertTypesConformance() {
            func cache(_: (some JavaScriptEncodable & ~Copyable).Type) {
            }
            cache(MyRecord.self)
          }
        }
        """
    )
  }

  @Test
  func `Implicitly-unwrapped optional return normalizes to optional in the cast expression`() {
    assertExpansion(
      """
      @ExpoModule
      public final class MyModule: Module {
        @JS
        func make(count: Int) -> MyRecord! { nil }
      }
      """,
      expandedSource: """
        public final class MyModule: Module {
          @JavaScriptActor
          func make(count: Int) -> MyRecord! { nil }

          public static let _jsName = "MyModule"

          @JavaScriptActor
          public func _decorateModule(object: borrowing JavaScriptObject, in runtime: JavaScriptRuntime) throws {
            object.setProperty("make") { [self] (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer, result: borrowing JavaScriptValue.Slot, runtime: borrowing JavaScriptRuntime) in
              guard arguments.count == 1 else {
                throw Exceptions.ArgumentsRangeMismatch((functionName: "make", received: arguments.count, required: 1, maximum: 1))
              }
              let arg0 = try Int.decode(arguments.unownedValue(at: 0), in: runtime)
              let value = self.make(count: arg0)
              try MyRecord?.encode(value, into: result, in: runtime)
            }
          }

          private func _assertTypesConformance() {
            func make(returning _: (some JavaScriptEncodable & ~Copyable).Type) {
            }
            make(returning: MyRecord.self)
          }
        }
        """
    )
  }

  @Test
  func `Static function emits a static conformance-assertion peer`() {
    assertExpansion(
      """
      @ExpoModule
      public final class MyModule: Module {
        @JS
        static func describe(_ value: MyRecord) -> String { "" }
      }
      """,
      expandedSource: """
        public final class MyModule: Module {
          @JavaScriptActor
          static func describe(_ value: MyRecord) -> String { "" }

          public static let _jsName = "MyModule"

          @JavaScriptActor
          public func _decorateModule(object: borrowing JavaScriptObject, in runtime: JavaScriptRuntime) throws {
            object.setProperty("describe") { [self] (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer, result: borrowing JavaScriptValue.Slot, runtime: borrowing JavaScriptRuntime) in
              guard arguments.count == 1 else {
                throw Exceptions.ArgumentsRangeMismatch((functionName: "describe", received: arguments.count, required: 1, maximum: 1))
              }
              let arg0 = try MyRecord.decode(arguments.unownedValue(at: 0), in: runtime)
              let value = self.describe(arg0)
              try String.encode(value, into: result, in: runtime)
            }
          }

          private func _assertTypesConformance() {
            func describe(_: (some JavaScriptDecodable & ~Copyable).Type) {
            }
            describe(MyRecord.self)
          }
        }
        """
    )
  }

  @Test
  func `Void throwing function calls through with try and returns undefined`() {
    assertExpansion(
      """
      @ExpoModule
      public final class MyModule: Module {
        @JS("doReset")
        func reset() throws {}
      }
      """,
      expandedSource: """
        public final class MyModule: Module {
          @JavaScriptActor
          func reset() throws {}

          public static let _jsName = "MyModule"

          @JavaScriptActor
          public func _decorateModule(object: borrowing JavaScriptObject, in runtime: JavaScriptRuntime) throws {
            object.setProperty("doReset") { [self] (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer) -> Void in
              guard arguments.count == 0 else {
                throw Exceptions.ArgumentsRangeMismatch((functionName: "doReset", received: arguments.count, required: 0, maximum: 0))
              }
              try self.reset()
            }
          }
        }
        """
    )
  }

  @Test
  func `Async function is bound with an async binding and the async setProperty overload`() {
    assertExpansion(
      """
      @ExpoModule
      public final class MyModule: Module {
        @JS("doWork")
        func performWork() async throws {}
      }
      """,
      expandedSource: """
        public final class MyModule: Module {
          @JavaScriptActor
          func performWork() async throws {}

          public static let _jsName = "MyModule"

          @JavaScriptActor
          public func _decorateModule(object: borrowing JavaScriptObject, in runtime: JavaScriptRuntime) throws {
            object.setProperty("doWork") { [self] (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer) in
              guard arguments.count == 0 else {
                throw Exceptions.ArgumentsRangeMismatch((functionName: "doWork", received: arguments.count, required: 0, maximum: 0))
              }
              return {
                try await self.performWork()
                return .undefined()
              }
            }
          }
        }
        """
    )
  }

  @Test
  func `Async function with arguments and a return value awaits the call and converts the result`() {
    assertExpansion(
      """
      @ExpoModule
      public final class MyModule: Module {
        @JS
        func fetchValue(key: String) async throws -> Int { 0 }
      }
      """,
      expandedSource: """
        public final class MyModule: Module {
          @JavaScriptActor
          func fetchValue(key: String) async throws -> Int { 0 }

          public static let _jsName = "MyModule"

          @JavaScriptActor
          public func _decorateModule(object: borrowing JavaScriptObject, in runtime: JavaScriptRuntime) throws {
            object.setProperty("fetchValue") { [self] (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer) in
              guard arguments.count == 1 else {
                throw Exceptions.ArgumentsRangeMismatch((functionName: "fetchValue", received: arguments.count, required: 1, maximum: 1))
              }
              let arg0 = try String.decode(arguments.unownedValue(at: 0), in: runtime)
              return {
                let result = try await self.fetchValue(key: arg0)
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
  func `Non-throwing async function awaits the call without try`() {
    assertExpansion(
      """
      @ExpoModule
      public final class MyModule: Module {
        @JS
        func performWork() async {}

        @JS
        func fetchValue(key: String) async -> Int { 0 }
      }
      """,
      expandedSource: """
        public final class MyModule: Module {
          @JavaScriptActor
          func performWork() async {}
          @JavaScriptActor
          func fetchValue(key: String) async -> Int { 0 }

          public static let _jsName = "MyModule"

          @JavaScriptActor
          public func _decorateModule(object: borrowing JavaScriptObject, in runtime: JavaScriptRuntime) throws {
            object.setProperty("performWork") { [self] (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer) in
              guard arguments.count == 0 else {
                throw Exceptions.ArgumentsRangeMismatch((functionName: "performWork", received: arguments.count, required: 0, maximum: 0))
              }
              return {
                await self.performWork()
                return .undefined()
              }
            }
            object.setProperty("fetchValue") { [self] (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer) in
              guard arguments.count == 1 else {
                throw Exceptions.ArgumentsRangeMismatch((functionName: "fetchValue", received: arguments.count, required: 1, maximum: 1))
              }
              let arg0 = try String.decode(arguments.unownedValue(at: 0), in: runtime)
              return {
                let result = await self.fetchValue(key: arg0)
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
  func `Async function with a trailing optional parameter returns a body per accepted arity`() {
    assertExpansion(
      """
      @ExpoModule
      public final class MyModule: Module {
        @JS
        func find(key: String, limit: Int?) async throws -> Int { 0 }
      }
      """,
      expandedSource: """
        public final class MyModule: Module {
          @JavaScriptActor
          func find(key: String, limit: Int?) async throws -> Int { 0 }

          public static let _jsName = "MyModule"

          @JavaScriptActor
          public func _decorateModule(object: borrowing JavaScriptObject, in runtime: JavaScriptRuntime) throws {
            object.setProperty("find") { [self] (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer) in
              guard arguments.count >= 1 && arguments.count <= 2 else {
                throw Exceptions.ArgumentsRangeMismatch((functionName: "find", received: arguments.count, required: 1, maximum: 2))
              }
              let arg0 = try String.decode(arguments.unownedValue(at: 0), in: runtime)
              switch arguments.count {
              case 1:
                return {
                  let result = try await self.find(key: arg0, limit: nil)
                  return try await runtime.execute {
                    return try Int.encode(result, in: runtime)
                  }
                }
              default:
                let arg1 = try Int?.decode(arguments.unownedValue(at: 1), in: runtime)
                return {
                  let result = try await self.find(key: arg0, limit: arg1)
                  return try await runtime.execute {
                    return try Int.encode(result, in: runtime)
                  }
                }
              }
            }
          }
        }
        """
    )
  }

  @Test
  func `Getter-only property binds a get-only accessor via defineProperty`() {
    assertExpansion(
      """
      @ExpoModule
      public final class MyModule: Module {
        @JS
        var status: String { "ok" }
      }
      """,
      expandedSource: """
        public final class MyModule: Module {
          @JavaScriptActor
          var status: String { "ok" }

          public static let _jsName = "MyModule"

          @JavaScriptActor
          public func _decorateModule(object: borrowing JavaScriptObject, in runtime: JavaScriptRuntime) throws {
            let statusDescriptor = runtime.createObject()
            statusDescriptor.setProperty("enumerable", value: true)
            statusDescriptor.setProperty("get") { [self] (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer, result: borrowing JavaScriptValue.Slot, runtime: borrowing JavaScriptRuntime) in
              try String.encode(self.status, into: result, in: runtime)
            }
            object.defineProperty("status", descriptor: statusDescriptor)
          }
        }
        """
    )
  }

  @Test
  func `Lazy property binds a configurable getter that caches the value on this`() {
    assertExpansion(
      """
      @ExpoModule
      public final class MyModule: Module {
        @JS
        lazy var config: MyRecord = loadConfig()
      }
      """,
      expandedSource: """
        public final class MyModule: Module {
          @JavaScriptActor
          lazy var config: MyRecord = loadConfig()

          public static let _jsName = "MyModule"

          @JavaScriptActor
          public func _decorateModule(object: borrowing JavaScriptObject, in runtime: JavaScriptRuntime) throws {
            let configDescriptor = runtime.createObject()
            configDescriptor.setProperty("enumerable", value: true)
            configDescriptor.setProperty("configurable", value: true)
            configDescriptor.setProperty("get") { [self] (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer, result: borrowing JavaScriptValue.Slot, runtime: borrowing JavaScriptRuntime) in
              let value = try MyRecord.encode(self.config, in: runtime)
              if this.isObject() {
                this.getObject(in: runtime).defineProperty("config", value: value, options: [.enumerable])
              }
              result.emplace(value)
            }
            object.defineProperty("config", descriptor: configDescriptor)
          }

          private func _assertTypesConformance() {
            func config(_: (some JavaScriptEncodable & ~Copyable).Type) {
            }
            config(MyRecord.self)
          }
        }
        """
    )
  }

  @Test
  func `Lazy property without a type annotation encodes through toJavaScriptValue`() {
    assertExpansion(
      """
      @ExpoModule
      public final class MyModule: Module {
        @JS("token")
        lazy var cachedToken = makeToken()
      }
      """,
      expandedSource: """
        public final class MyModule: Module {
          @JavaScriptActor
          lazy var cachedToken = makeToken()

          public static let _jsName = "MyModule"

          @JavaScriptActor
          public func _decorateModule(object: borrowing JavaScriptObject, in runtime: JavaScriptRuntime) throws {
            let cachedTokenDescriptor = runtime.createObject()
            cachedTokenDescriptor.setProperty("enumerable", value: true)
            cachedTokenDescriptor.setProperty("configurable", value: true)
            cachedTokenDescriptor.setProperty("get") { [self] (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer, result: borrowing JavaScriptValue.Slot, runtime: borrowing JavaScriptRuntime) in
              let value = self.cachedToken.toJavaScriptValue(in: runtime)
              if this.isObject() {
                this.getObject(in: runtime).defineProperty("token", value: value, options: [.enumerable])
              }
              result.emplace(value)
            }
            object.defineProperty("token", descriptor: cachedTokenDescriptor)
          }
        }
        """
    )
  }

  @Test
  func `Lazy free-form property encodes through the free-form method`() {
    assertExpansion(
      """
      @ExpoModule
      public final class MyModule: Module {
        @JS
        lazy var info: [String: Any] = loadInfo()
      }
      """,
      expandedSource: """
        public final class MyModule: Module {
          @JavaScriptActor
          lazy var info: [String: Any] = loadInfo()

          public static let _jsName = "MyModule"

          @JavaScriptActor
          public func _decorateModule(object: borrowing JavaScriptObject, in runtime: JavaScriptRuntime) throws {
            let infoDescriptor = runtime.createObject()
            infoDescriptor.setProperty("enumerable", value: true)
            infoDescriptor.setProperty("configurable", value: true)
            infoDescriptor.setProperty("get") { [self] (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer, result: borrowing JavaScriptValue.Slot, runtime: borrowing JavaScriptRuntime) in
              let value = try JavaScriptValue.encodeAnyDictionary(self.info, in: runtime)
              if this.isObject() {
                this.getObject(in: runtime).defineProperty("info", value: value, options: [.enumerable])
              }
              result.emplace(value)
            }
            object.defineProperty("info", descriptor: infoDescriptor)
          }
        }
        """
    )
  }

  @Test
  func `Lazy property with an observer is still getter-only and asserts only the encodable direction`() {
    assertExpansion(
      """
      @ExpoModule
      public final class MyModule: Module {
        @JS
        lazy var cache: MyRecord = MyRecord() {
          didSet {}
        }
      }
      """,
      expandedSource: """
        public final class MyModule: Module {
          @JavaScriptActor
          lazy var cache: MyRecord = MyRecord() {
            didSet {}
          }

          public static let _jsName = "MyModule"

          @JavaScriptActor
          public func _decorateModule(object: borrowing JavaScriptObject, in runtime: JavaScriptRuntime) throws {
            let cacheDescriptor = runtime.createObject()
            cacheDescriptor.setProperty("enumerable", value: true)
            cacheDescriptor.setProperty("configurable", value: true)
            cacheDescriptor.setProperty("get") { [self] (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer, result: borrowing JavaScriptValue.Slot, runtime: borrowing JavaScriptRuntime) in
              let value = try MyRecord.encode(self.cache, in: runtime)
              if this.isObject() {
                this.getObject(in: runtime).defineProperty("cache", value: value, options: [.enumerable])
              }
              result.emplace(value)
            }
            object.defineProperty("cache", descriptor: cacheDescriptor)
          }

          private func _assertTypesConformance() {
            func cache(_: (some JavaScriptEncodable & ~Copyable).Type) {
            }
            cache(MyRecord.self)
          }
        }
        """
    )
  }

  @Test
  func `Settable stored property binds both a getter and a setter`() {
    assertExpansion(
      """
      @ExpoModule
      public final class MyModule: Module {
        @JS
        var ready: Bool = false
      }
      """,
      expandedSource: """
        public final class MyModule: Module {
          @JavaScriptActor
          var ready: Bool = false

          public static let _jsName = "MyModule"

          @JavaScriptActor
          public func _decorateModule(object: borrowing JavaScriptObject, in runtime: JavaScriptRuntime) throws {
            let readyDescriptor = runtime.createObject()
            readyDescriptor.setProperty("enumerable", value: true)
            readyDescriptor.setProperty("get") { [self] (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer, result: borrowing JavaScriptValue.Slot, runtime: borrowing JavaScriptRuntime) in
              try Bool.encode(self.ready, into: result, in: runtime)
            }
            readyDescriptor.setProperty("set") { [self] (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer, result: borrowing JavaScriptValue.Slot, runtime: borrowing JavaScriptRuntime) in
              self.ready = try Bool.decode(arguments.unownedValue(at: 0), in: runtime)
            }
            object.defineProperty("ready", descriptor: readyDescriptor)
          }
        }
        """
    )
  }

  @Test
  func `Non-primitive property captures appContext and routes through the dynamic converter`() {
    assertExpansion(
      """
      @ExpoModule
      public final class MyModule: Module {
        @JS
        var config: MyRecord
      }
      """,
      expandedSource: """
        public final class MyModule: Module {
          @JavaScriptActor
          var config: MyRecord

          public static let _jsName = "MyModule"

          @JavaScriptActor
          public func _decorateModule(object: borrowing JavaScriptObject, in runtime: JavaScriptRuntime) throws {
            let configDescriptor = runtime.createObject()
            configDescriptor.setProperty("enumerable", value: true)
            configDescriptor.setProperty("get") { [self] (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer, result: borrowing JavaScriptValue.Slot, runtime: borrowing JavaScriptRuntime) in
              try MyRecord.encode(self.config, into: result, in: runtime)
            }
            configDescriptor.setProperty("set") { [self] (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer, result: borrowing JavaScriptValue.Slot, runtime: borrowing JavaScriptRuntime) in
              self.config = try MyRecord.decode(arguments.unownedValue(at: 0), in: runtime)
            }
            object.defineProperty("config", descriptor: configDescriptor)
          }

          private func _assertTypesConformance() {
            func config(_: (some JavaScriptDecodable & ~Copyable).Type, _: (some JavaScriptEncodable & ~Copyable).Type) {
            }
            config(MyRecord.self, MyRecord.self)
          }
        }
        """
    )
  }

  @Test
  func `Implicitly-unwrapped optional property normalizes the type to optional in the cast expressions`() {
    assertExpansion(
      """
      @ExpoModule
      public final class MyModule: Module {
        @JS
        var config: MyRecord!
      }
      """,
      expandedSource: """
        public final class MyModule: Module {
          @JavaScriptActor
          var config: MyRecord!

          public static let _jsName = "MyModule"

          @JavaScriptActor
          public func _decorateModule(object: borrowing JavaScriptObject, in runtime: JavaScriptRuntime) throws {
            let configDescriptor = runtime.createObject()
            configDescriptor.setProperty("enumerable", value: true)
            configDescriptor.setProperty("get") { [self] (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer, result: borrowing JavaScriptValue.Slot, runtime: borrowing JavaScriptRuntime) in
              try MyRecord?.encode(self.config, into: result, in: runtime)
            }
            configDescriptor.setProperty("set") { [self] (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer, result: borrowing JavaScriptValue.Slot, runtime: borrowing JavaScriptRuntime) in
              self.config = try MyRecord?.decode(arguments.unownedValue(at: 0), in: runtime)
            }
            object.defineProperty("config", descriptor: configDescriptor)
          }

          private func _assertTypesConformance() {
            func config(_: (some JavaScriptDecodable & ~Copyable).Type, _: (some JavaScriptEncodable & ~Copyable).Type) {
            }
            config(MyRecord.self, MyRecord.self)
          }
        }
        """
    )
  }

  @Test
  func `Mixed members: only @JS-marked ones are picked up`() {
    assertExpansion(
      """
      @ExpoModule
      public final class MyModule: Module {
        @JS
        func greet(name: String) -> String { "Hi" }

        @JS
        var status: String { "ok" }

        func notExposed() {}
      }
      """,
      expandedSource: """
        public final class MyModule: Module {
          @JavaScriptActor
          func greet(name: String) -> String { "Hi" }
          @JavaScriptActor
          var status: String { "ok" }

          func notExposed() {}

          public static let _jsName = "MyModule"

          @JavaScriptActor
          public func _decorateModule(object: borrowing JavaScriptObject, in runtime: JavaScriptRuntime) throws {
            object.setProperty("greet") { [self] (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer, result: borrowing JavaScriptValue.Slot, runtime: borrowing JavaScriptRuntime) in
              guard arguments.count == 1 else {
                throw Exceptions.ArgumentsRangeMismatch((functionName: "greet", received: arguments.count, required: 1, maximum: 1))
              }
              let arg0 = try String.decode(arguments.unownedValue(at: 0), in: runtime)
              let value = self.greet(name: arg0)
              try String.encode(value, into: result, in: runtime)
            }
            let statusDescriptor = runtime.createObject()
            statusDescriptor.setProperty("enumerable", value: true)
            statusDescriptor.setProperty("get") { [self] (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer, result: borrowing JavaScriptValue.Slot, runtime: borrowing JavaScriptRuntime) in
              try String.encode(self.status, into: result, in: runtime)
            }
            object.defineProperty("status", descriptor: statusDescriptor)
          }
        }
        """
    )
  }

  @Test
  func `@JS(.concurrent) swaps the @JavaScriptActor stamp for @concurrent`() {
    assertExpansion(
      """
      @ExpoModule
      public final class MyModule: Module {
        @JS(.concurrent)
        func load(url: String) async throws -> String { url }
      }
      """,
      expandedSource: """
        public final class MyModule: Module {
          @concurrent
          func load(url: String) async throws -> String { url }

          public static let _jsName = "MyModule"

          @JavaScriptActor
          public func _decorateModule(object: borrowing JavaScriptObject, in runtime: JavaScriptRuntime) throws {
            object.setProperty("load") { [self] (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer) in
              guard arguments.count == 1 else {
                throw Exceptions.ArgumentsRangeMismatch((functionName: "load", received: arguments.count, required: 1, maximum: 1))
              }
              let arg0 = try String.decode(arguments.unownedValue(at: 0), in: runtime)
              return {
                let result = try await self.load(url: arg0)
                return try await runtime.execute {
                  return try String.encode(result, in: runtime)
                }
              }
            }
          }
        }
        """
    )
  }

  @Test
  func `@JS name and options combine, the name still renaming the binding`() {
    assertExpansion(
      """
      @ExpoModule
      public final class MyModule: Module {
        @JS("loadAsync", [.concurrent])
        func load(url: String) async throws -> String { url }
      }
      """,
      expandedSource: """
        public final class MyModule: Module {
          @concurrent
          func load(url: String) async throws -> String { url }

          public static let _jsName = "MyModule"

          @JavaScriptActor
          public func _decorateModule(object: borrowing JavaScriptObject, in runtime: JavaScriptRuntime) throws {
            object.setProperty("loadAsync") { [self] (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer) in
              guard arguments.count == 1 else {
                throw Exceptions.ArgumentsRangeMismatch((functionName: "loadAsync", received: arguments.count, required: 1, maximum: 1))
              }
              let arg0 = try String.decode(arguments.unownedValue(at: 0), in: runtime)
              return {
                let result = try await self.load(url: arg0)
                return try await runtime.execute {
                  return try String.encode(result, in: runtime)
                }
              }
            }
          }
        }
        """
    )
  }

  @Test
  func `@JS(.withAsync) binds a promise-returning variant that calls the function on the concurrent pool`() {
    assertExpansion(
      """
      @ExpoModule
      public final class FileModule: Module {
        @JS("textSync", .withAsync("text"))
        func text(path: String) throws -> String { path }
      }
      """,
      expandedSource: """
        public final class FileModule: Module {
          func text(path: String) throws -> String { path }

          public static let _jsName = "FileModule"

          @JavaScriptActor
          public func _decorateModule(object: borrowing JavaScriptObject, in runtime: JavaScriptRuntime) throws {
            object.setProperty("textSync") { [self] (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer, result: borrowing JavaScriptValue.Slot, runtime: borrowing JavaScriptRuntime) in
              guard arguments.count == 1 else {
                throw Exceptions.ArgumentsRangeMismatch((functionName: "textSync", received: arguments.count, required: 1, maximum: 1))
              }
              let arg0 = try String.decode(arguments.unownedValue(at: 0), in: runtime)
              let value = try self.text(path: arg0)
              try String.encode(value, into: result, in: runtime)
            }
            object.setProperty("text") { [self] (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer) in
              guard arguments.count == 1 else {
                throw Exceptions.ArgumentsRangeMismatch((functionName: "text", received: arguments.count, required: 1, maximum: 1))
              }
              let arg0 = try String.decode(arguments.unownedValue(at: 0), in: runtime)
              return {
                let result = try await { @concurrent () async throws -> String in
                  try self.text(path: arg0)
                }()
                return try await runtime.execute {
                  return try String.encode(result, in: runtime)
                }
              }
            }
          }
        }
        """
    )
  }

  @Test
  func `@JS(.withAsync) variant of a function with a trailing defaulted parameter has a call per accepted arity`() {
    assertExpansion(
      """
      @ExpoModule
      public final class LogModule: Module {
        @JS(.withAsync("writeAsync"))
        func write(_ message: String, level: Int = 0) {}
      }
      """,
      expandedSource: """
        public final class LogModule: Module {
          func write(_ message: String, level: Int = 0) {}

          public static let _jsName = "LogModule"

          @JavaScriptActor
          public func _decorateModule(object: borrowing JavaScriptObject, in runtime: JavaScriptRuntime) throws {
            object.setProperty("write") { [self] (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer) -> Void in
              guard arguments.count >= 1 && arguments.count <= 2 else {
                throw Exceptions.ArgumentsRangeMismatch((functionName: "write", received: arguments.count, required: 1, maximum: 2))
              }
              let arg0 = try String.decode(arguments.unownedValue(at: 0), in: runtime)
              switch arguments.count {
              case 1:
                self.write(arg0)
              default:
                let arg1 = try Int.decode(arguments.unownedValue(at: 1), in: runtime)
                self.write(arg0, level: arg1)
              }
            }
            object.setProperty("writeAsync") { [self] (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer) in
              guard arguments.count >= 1 && arguments.count <= 2 else {
                throw Exceptions.ArgumentsRangeMismatch((functionName: "writeAsync", received: arguments.count, required: 1, maximum: 2))
              }
              let arg0 = try String.decode(arguments.unownedValue(at: 0), in: runtime)
              switch arguments.count {
              case 1:
                return {
                  await { @concurrent () async in
                    self.write(arg0)
                  }()
                  return .undefined()
                }
              default:
                let arg1 = try Int.decode(arguments.unownedValue(at: 1), in: runtime)
                return {
                  await { @concurrent () async in
                    self.write(arg0, level: arg1)
                  }()
                  return .undefined()
                }
              }
            }
          }
        }
        """
    )
  }

  @Test
  func `@JS(.withAsync) on an async function is diagnosed on the attribute`() {
    assertExpansion(
      """
      @ExpoModule
      public final class MyModule: Module {
        @JS(.withAsync("loadAsync"))
        func load() async -> Int { 0 }
      }
      """,
      expandedSource: """
        public final class MyModule: Module {
          func load() async -> Int { 0 }

          public static let _jsName = "MyModule"

          @JavaScriptActor
          public func _decorateModule(object: borrowing JavaScriptObject, in runtime: JavaScriptRuntime) throws {
            object.setProperty("load") { [self] (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer) in
              guard arguments.count == 0 else {
                throw Exceptions.ArgumentsRangeMismatch((functionName: "load", received: arguments.count, required: 0, maximum: 0))
              }
              return {
                let result = await self.load()
                return try await runtime.execute {
                  return try Int.encode(result, in: runtime)
                }
              }
            }
          }
        }
        """,
      diagnostics: [
        DiagnosticSpec(
          message:
            "'.withAsync' adds a promise-returning variant to a synchronous function, and this function is already 'async'. Remove '.withAsync', and use '.concurrent' to run the function off the JavaScript thread.",
          line: 3,
          column: 3,
          severity: .error
        )
      ]
    )
  }

  @Test
  func `@JS(.withAsync) on a property is diagnosed on the attribute`() {
    assertExpansion(
      """
      @ExpoModule
      public final class MyModule: Module {
        @JS(.withAsync("statusAsync"))
        var status: String { "ok" }
      }
      """,
      expandedSource: """
        public final class MyModule: Module {
          var status: String { "ok" }

          public static let _jsName = "MyModule"

          @JavaScriptActor
          public func _decorateModule(object: borrowing JavaScriptObject, in runtime: JavaScriptRuntime) throws {
            let statusDescriptor = runtime.createObject()
            statusDescriptor.setProperty("enumerable", value: true)
            statusDescriptor.setProperty("get") { [self] (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer, result: borrowing JavaScriptValue.Slot, runtime: borrowing JavaScriptRuntime) in
              try String.encode(self.status, into: result, in: runtime)
            }
            object.defineProperty("status", descriptor: statusDescriptor)
          }
        }
        """,
      diagnostics: [
        DiagnosticSpec(
          message: "'.withAsync' applies only to a synchronous @JS function, not to a property or initializer.",
          line: 3,
          column: 3,
          severity: .error
        )
      ]
    )
  }

  @Test
  func `@JS(.withAsync) needs the variant's name as a string literal`() {
    assertExpansion(
      """
      @ExpoModule
      public final class MyModule: Module {
        @JS(.withAsync(variantName))
        func load() -> Int { 0 }
      }
      """,
      expandedSource: """
        public final class MyModule: Module {
          func load() -> Int { 0 }

          public static let _jsName = "MyModule"

          @JavaScriptActor
          public func _decorateModule(object: borrowing JavaScriptObject, in runtime: JavaScriptRuntime) throws {
            object.setProperty("load") { [self] (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer, result: borrowing JavaScriptValue.Slot, runtime: borrowing JavaScriptRuntime) in
              guard arguments.count == 0 else {
                throw Exceptions.ArgumentsRangeMismatch((functionName: "load", received: arguments.count, required: 0, maximum: 0))
              }
              let value = self.load()
              try Int.encode(value, into: result, in: runtime)
            }
          }
        }
        """,
      diagnostics: [
        DiagnosticSpec(
          message:
            "'.withAsync' takes the JavaScript name of the variant as a string literal, for example '.withAsync(\"loadAsync\")'.",
          line: 3,
          column: 7,
          severity: .error
        )
      ]
    )
  }

  @Test
  func `@JS(.withAsync) on a function of a global-actor type is diagnosed unless it's nonisolated`() {
    assertExpansion(
      """
      @MainActor
      @ExpoModule
      public final class MyModule: Module {
        @JS(.withAsync("loadAsync"))
        func load() {}

        @JS(.withAsync("saveAsync"))
        nonisolated func save() {}
      }
      """,
      expandedSource: """
        @MainActor
        public final class MyModule: Module {
          func load() {}
          nonisolated func save() {}

          public static let _jsName = "MyModule"

          @JavaScriptActor
          public func _decorateModule(object: borrowing JavaScriptObject, in runtime: JavaScriptRuntime) throws {
            object.setProperty("load") { [self] (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer) -> Void in
              guard arguments.count == 0 else {
                throw Exceptions.ArgumentsRangeMismatch((functionName: "load", received: arguments.count, required: 0, maximum: 0))
              }
              self.load()
            }
            object.setProperty("loadAsync") { [self] (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer) in
              guard arguments.count == 0 else {
                throw Exceptions.ArgumentsRangeMismatch((functionName: "loadAsync", received: arguments.count, required: 0, maximum: 0))
              }
              return {
                await { @concurrent () async in
                  self.load()
                }()
                return .undefined()
              }
            }
            object.setProperty("save") { [self] (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer) -> Void in
              guard arguments.count == 0 else {
                throw Exceptions.ArgumentsRangeMismatch((functionName: "save", received: arguments.count, required: 0, maximum: 0))
              }
              self.save()
            }
            object.setProperty("saveAsync") { [self] (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer) in
              guard arguments.count == 0 else {
                throw Exceptions.ArgumentsRangeMismatch((functionName: "saveAsync", received: arguments.count, required: 0, maximum: 0))
              }
              return {
                await { @concurrent () async in
                  self.save()
                }()
                return .undefined()
              }
            }
          }
        }
        """,
      diagnostics: [
        DiagnosticSpec(
          message:
            "'.withAsync' calls the function on the concurrent thread pool, so the function can't inherit '@MainActor' from 'MyModule'. Mark the function 'nonisolated'.",
          line: 4,
          column: 3,
          severity: .error
        )
      ]
    )
  }

  @Test
  func `@JS(.withAsync) on a function isolated to a global actor is diagnosed on the attribute`() {
    assertExpansion(
      """
      @ExpoModule
      public final class MyModule: Module {
        @JS(.withAsync("loadAsync"))
        @MainActor
        func load() {}
      }
      """,
      expandedSource: """
        public final class MyModule: Module {
          @MainActor
          func load() {}

          public static let _jsName = "MyModule"

          @JavaScriptActor
          public func _decorateModule(object: borrowing JavaScriptObject, in runtime: JavaScriptRuntime) throws {
            object.setProperty("load") { [self] (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer) -> Void in
              guard arguments.count == 0 else {
                throw Exceptions.ArgumentsRangeMismatch((functionName: "load", received: arguments.count, required: 0, maximum: 0))
              }
              self.load()
            }
            object.setProperty("loadAsync") { [self] (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer) in
              guard arguments.count == 0 else {
                throw Exceptions.ArgumentsRangeMismatch((functionName: "loadAsync", received: arguments.count, required: 0, maximum: 0))
              }
              return {
                await { @concurrent () async in
                  self.load()
                }()
                return .undefined()
              }
            }
          }
        }
        """,
      diagnostics: [
        DiagnosticSpec(
          message:
            "'.withAsync' calls the function on the concurrent thread pool, so the function can't be isolated to '@MainActor'.",
          line: 3,
          column: 3,
          severity: .error
        )
      ]
    )
  }

  @Test
  func `A JavaScript value parameter of a .concurrent function is diagnosed on its type`() {
    assertExpansion(
      """
      @ExpoModule
      public final class MyModule: Module {
        @JS(.concurrent)
        func load(_ object: borrowing JavaScriptObject) async {}
      }
      """,
      expandedSource: """
        public final class MyModule: Module {
          @concurrent
          func load(_ object: borrowing JavaScriptObject) async {}

          public static let _jsName = "MyModule"

          @JavaScriptActor
          public func _decorateModule(object: borrowing JavaScriptObject, in runtime: JavaScriptRuntime) throws {
            object.setProperty("load") { [self] (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer) in
              guard arguments.count == 1 else {
                throw Exceptions.ArgumentsRangeMismatch((functionName: "load", received: arguments.count, required: 1, maximum: 1))
              }
              let arg0 = try JavaScriptObject.decode(arguments.unownedValue(at: 0), in: runtime)
              return {
                await self.load(arg0)
                return .undefined()
              }
            }
          }

          private func _assertTypesConformance() {
            func load(_: (some JavaScriptDecodable & ~Copyable).Type) {
            }
            load(JavaScriptObject.self)
          }
        }
        """,
      diagnostics: [
        DiagnosticSpec(
          message:
            "'object' can't be a 'JavaScriptObject' in a '.concurrent' function: '.concurrent' runs the body on the concurrent thread pool, and a JavaScript value is valid only on the JavaScript thread. Take a native type that the value decodes to, such as a @Record or [String: Any], or remove '.concurrent'.",
          // The test harness expands `@JS` after `@ExpoModule` adds `@concurrent` on its own line, so it
          // reports the parameter one line lower than the compiler and `expand` do (line 4).
          line: 5,
          column: 23,
          severity: .error
        )
      ]
    )
  }

  @Test
  func `An optional JavaScript value parameter of a .withAsync function is diagnosed on its type`() {
    assertExpansion(
      """
      @ExpoModule
      public final class MyModule: Module {
        @JS(.withAsync("readAsync"))
        func read(value: JavaScriptValue?) {}
      }
      """,
      expandedSource: """
        public final class MyModule: Module {
          func read(value: JavaScriptValue?) {}

          public static let _jsName = "MyModule"

          @JavaScriptActor
          public func _decorateModule(object: borrowing JavaScriptObject, in runtime: JavaScriptRuntime) throws {
            object.setProperty("read") { [self] (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer) -> Void in
              guard arguments.count >= 0 && arguments.count <= 1 else {
                throw Exceptions.ArgumentsRangeMismatch((functionName: "read", received: arguments.count, required: 0, maximum: 1))
              }
              switch arguments.count {
              case 0:
                self.read(value: nil)
              default:
                let arg0 = try JavaScriptValue?.decode(arguments.unownedValue(at: 0), in: runtime)
                self.read(value: arg0)
              }
            }
            object.setProperty("readAsync") { [self] (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer) in
              guard arguments.count >= 0 && arguments.count <= 1 else {
                throw Exceptions.ArgumentsRangeMismatch((functionName: "readAsync", received: arguments.count, required: 0, maximum: 1))
              }
              switch arguments.count {
              case 0:
                return {
                  await { @concurrent () async in
                    self.read(value: nil)
                  }()
                  return .undefined()
                }
              default:
                let arg0 = try JavaScriptValue?.decode(arguments.unownedValue(at: 0), in: runtime)
                return {
                  await { @concurrent () async in
                    self.read(value: arg0)
                  }()
                  return .undefined()
                }
              }
            }
          }

          private func _assertTypesConformance() {
            func read(value _: (some JavaScriptDecodable & ~Copyable).Type) {
            }
            read(value: JavaScriptValue.self)
          }
        }
        """,
      diagnostics: [
        DiagnosticSpec(
          message:
            "'value' can't be a 'JavaScriptValue' in a '.withAsync' function: the variant that '.withAsync' adds runs the function on the concurrent thread pool, and a JavaScript value is valid only on the JavaScript thread. Take a native type that the value decodes to, such as a @Record or [String: Any], or remove '.withAsync'.",
          line: 4,
          column: 20,
          severity: .error
        )
      ]
    )
  }

  @Test
  func `JavaScript value parameters of synchronous and plain async functions aren't diagnosed`() {
    assertExpansion(
      """
      @ExpoModule
      public final class MyModule: Module {
        @JS
        func update(_ object: borrowing JavaScriptObject) {}

        @JS
        func store(_ value: JavaScriptValue) async {}
      }
      """,
      expandedSource: """
        public final class MyModule: Module {
          @JavaScriptActor
          func update(_ object: borrowing JavaScriptObject) {}
          @JavaScriptActor
          func store(_ value: JavaScriptValue) async {}

          public static let _jsName = "MyModule"

          @JavaScriptActor
          public func _decorateModule(object: borrowing JavaScriptObject, in runtime: JavaScriptRuntime) throws {
            object.setProperty("update") { [self] (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer) -> Void in
              guard arguments.count == 1 else {
                throw Exceptions.ArgumentsRangeMismatch((functionName: "update", received: arguments.count, required: 1, maximum: 1))
              }
              let arg0 = try JavaScriptObject.decode(arguments.unownedValue(at: 0), in: runtime)
              self.update(arg0)
            }
            object.setProperty("store") { [self] (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer) in
              guard arguments.count == 1 else {
                throw Exceptions.ArgumentsRangeMismatch((functionName: "store", received: arguments.count, required: 1, maximum: 1))
              }
              let arg0 = try JavaScriptValue.decode(arguments.unownedValue(at: 0), in: runtime)
              return {
                await self.store(arg0)
                return .undefined()
              }
            }
          }

          private func _assertTypesConformance() {
            func update(_: (some JavaScriptDecodable & ~Copyable).Type) {
            }
            update(JavaScriptObject.self)
            func store(_: (some JavaScriptDecodable & ~Copyable).Type) {
            }
            store(JavaScriptValue.self)
          }
        }
        """
    )
  }

  @Test
  func `@JS(.withAsync) variant name that the function's own binding uses is a collision`() {
    assertExpansion(
      """
      @ExpoModule
      public final class MyModule: Module {
        @JS(.withAsync("load"))
        func load() {}
      }
      """,
      expandedSource: """
        public final class MyModule: Module {
          func load() {}

          public static let _jsName = "MyModule"

          @JavaScriptActor
          public func _decorateModule(object: borrowing JavaScriptObject, in runtime: JavaScriptRuntime) throws {
            object.setProperty("load") { [self] (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer) -> Void in
              guard arguments.count == 0 else {
                throw Exceptions.ArgumentsRangeMismatch((functionName: "load", received: arguments.count, required: 0, maximum: 0))
              }
              self.load()
            }
            object.setProperty("load") { [self] (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer) in
              guard arguments.count == 0 else {
                throw Exceptions.ArgumentsRangeMismatch((functionName: "load", received: arguments.count, required: 0, maximum: 0))
              }
              return {
                await { @concurrent () async in
                  self.load()
                }()
                return .undefined()
              }
            }
          }
        }
        """,
      diagnostics: [
        DiagnosticSpec(
          message:
            "The JavaScript name 'load' is already bound by an earlier '.withAsync' variant. A JavaScript object holds one member per name, so JavaScript could reach only one of them. Give one of them another name with .withAsync(\"...\") or @JS(\"...\").",
          line: 4,
          column: 8,
          severity: .error,
          notes: [NoteSpec(message: "'load' is first bound here", line: 3, column: 19)]
        )
      ]
    )
  }

  @Test
  func `@JS(.withAsync) variant name that another member uses is a collision on the variant's name`() {
    assertExpansion(
      """
      @ExpoModule
      public final class MyModule: Module {
        @JS
        func load() {}

        @JS(.withAsync("load"))
        func fetch() {}
      }
      """,
      expandedSource: """
        public final class MyModule: Module {
          @JavaScriptActor
          func load() {}
          func fetch() {}

          public static let _jsName = "MyModule"

          @JavaScriptActor
          public func _decorateModule(object: borrowing JavaScriptObject, in runtime: JavaScriptRuntime) throws {
            object.setProperty("load") { [self] (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer) -> Void in
              guard arguments.count == 0 else {
                throw Exceptions.ArgumentsRangeMismatch((functionName: "load", received: arguments.count, required: 0, maximum: 0))
              }
              self.load()
            }
            object.setProperty("fetch") { [self] (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer) -> Void in
              guard arguments.count == 0 else {
                throw Exceptions.ArgumentsRangeMismatch((functionName: "fetch", received: arguments.count, required: 0, maximum: 0))
              }
              self.fetch()
            }
            object.setProperty("load") { [self] (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer) in
              guard arguments.count == 0 else {
                throw Exceptions.ArgumentsRangeMismatch((functionName: "load", received: arguments.count, required: 0, maximum: 0))
              }
              return {
                await { @concurrent () async in
                  self.fetch()
                }()
                return .undefined()
              }
            }
          }
        }
        """,
      diagnostics: [
        DiagnosticSpec(
          message:
            "The JavaScript name 'load' is already bound by an earlier @JS function. A JavaScript object holds one member per name, so JavaScript could reach only one of them. Give one of them another name with @JS(\"...\") or .withAsync(\"...\").",
          line: 6,
          column: 19,
          severity: .error,
          notes: [NoteSpec(message: "'load' is first bound here", line: 4, column: 8)]
        )
      ]
    )
  }

  @Test
  func `@JS(.withAsync) listed twice binds the first variant and reports the others`() {
    assertExpansion(
      """
      @ExpoModule
      public final class MyModule: Module {
        @JS(.withAsync("loadAsync"), .withAsync("fetchAsync"))
        func load() {}
      }
      """,
      expandedSource: """
        public final class MyModule: Module {
          func load() {}

          public static let _jsName = "MyModule"

          @JavaScriptActor
          public func _decorateModule(object: borrowing JavaScriptObject, in runtime: JavaScriptRuntime) throws {
            object.setProperty("load") { [self] (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer) -> Void in
              guard arguments.count == 0 else {
                throw Exceptions.ArgumentsRangeMismatch((functionName: "load", received: arguments.count, required: 0, maximum: 0))
              }
              self.load()
            }
            object.setProperty("loadAsync") { [self] (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer) in
              guard arguments.count == 0 else {
                throw Exceptions.ArgumentsRangeMismatch((functionName: "loadAsync", received: arguments.count, required: 0, maximum: 0))
              }
              return {
                await { @concurrent () async in
                  self.load()
                }()
                return .undefined()
              }
            }
          }
        }
        """,
      diagnostics: [
        DiagnosticSpec(
          message: "'.withAsync' can be listed only once: a function gets one promise-returning variant.",
          line: 3,
          column: 32,
          severity: .error
        )
      ]
    )
  }

  @Test
  func `@JS(.concurrent) on a synchronous function is diagnosed on the attribute`() {
    assertExpansion(
      """
      @ExpoModule
      public final class MyModule: Module {
        @JS(.concurrent)
        func compute() -> Int { 42 }
      }
      """,
      expandedSource: """
        public final class MyModule: Module {
          @concurrent
          func compute() -> Int { 42 }

          public static let _jsName = "MyModule"

          @JavaScriptActor
          public func _decorateModule(object: borrowing JavaScriptObject, in runtime: JavaScriptRuntime) throws {
            object.setProperty("compute") { [self] (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer, result: borrowing JavaScriptValue.Slot, runtime: borrowing JavaScriptRuntime) in
              guard arguments.count == 0 else {
                throw Exceptions.ArgumentsRangeMismatch((functionName: "compute", received: arguments.count, required: 0, maximum: 0))
              }
              let value = self.compute()
              try Int.encode(value, into: result, in: runtime)
            }
          }
        }
        """,
      diagnostics: [
        DiagnosticSpec(
          message:
            "'.concurrent' needs an 'async' function: a synchronous @JS member runs on the JavaScript thread by definition. Mark the function 'async' to run its body off that thread.",
          line: 3,
          column: 3,
          severity: .error,
          fixIts: [FixItSpec(message: "Mark the function 'async'")]
        )
      ]
    )
  }

  @Test
  func `@JS(.concurrent) on a throwing synchronous function offers the insert-async fix-it`() {
    assertExpansion(
      """
      @ExpoModule
      public final class MyModule: Module {
        @JS(.concurrent)
        func compute() throws -> Int { 42 }
      }
      """,
      expandedSource: """
        public final class MyModule: Module {
          @concurrent
          func compute() throws -> Int { 42 }

          public static let _jsName = "MyModule"

          @JavaScriptActor
          public func _decorateModule(object: borrowing JavaScriptObject, in runtime: JavaScriptRuntime) throws {
            object.setProperty("compute") { [self] (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer, result: borrowing JavaScriptValue.Slot, runtime: borrowing JavaScriptRuntime) in
              guard arguments.count == 0 else {
                throw Exceptions.ArgumentsRangeMismatch((functionName: "compute", received: arguments.count, required: 0, maximum: 0))
              }
              let value = try self.compute()
              try Int.encode(value, into: result, in: runtime)
            }
          }
        }
        """,
      diagnostics: [
        DiagnosticSpec(
          message:
            "'.concurrent' needs an 'async' function: a synchronous @JS member runs on the JavaScript thread by definition. Mark the function 'async' to run its body off that thread.",
          line: 3,
          column: 3,
          severity: .error,
          fixIts: [FixItSpec(message: "Mark the function 'async'")]
        )
      ]
    )
  }

  // The two tests below apply the fix-it and check the resulting source. They mark `@JS` on its own
  // rather than inside an `@ExpoModule` class: `assertMacroExpansion` maps a fix-it back onto the
  // original source through the node it is anchored to, and for a member that the enclosing
  // `@ExpoModule` expansion re-emits that mapping lands at the wrong offset. The nested tests above
  // cover that the fix-it is offered; these cover what it writes.
  @Test
  func `The insert-async fix-it marks a synchronous function async`() {
    assertExpansion(
      """
      @JS(.concurrent)
      func compute() -> Int { 42 }
      """,
      expandedSource: """
        func compute() -> Int { 42 }
        """,
      diagnostics: [
        DiagnosticSpec(
          message:
            "'.concurrent' needs an 'async' function: a synchronous @JS member runs on the JavaScript thread by definition. Mark the function 'async' to run its body off that thread.",
          line: 1,
          column: 1,
          severity: .error,
          fixIts: [FixItSpec(message: "Mark the function 'async'")]
        )
      ],
      fixedSource: """
        @JS(.concurrent)
        func compute() async -> Int { 42 }
        """
    )
  }

  @Test
  func `The insert-async fix-it puts 'async' before an existing 'throws'`() {
    assertExpansion(
      """
      @JS(.concurrent)
      func compute() throws -> Int { 42 }
      """,
      expandedSource: """
        func compute() throws -> Int { 42 }
        """,
      diagnostics: [
        DiagnosticSpec(
          message:
            "'.concurrent' needs an 'async' function: a synchronous @JS member runs on the JavaScript thread by definition. Mark the function 'async' to run its body off that thread.",
          line: 1,
          column: 1,
          severity: .error,
          fixIts: [FixItSpec(message: "Mark the function 'async'")]
        )
      ],
      fixedSource: """
        @JS(.concurrent)
        func compute() async throws -> Int { 42 }
        """
    )
  }

  @Test
  func `nonisolated members are not stamped with @JavaScriptActor`() {
    assertExpansion(
      """
      @ExpoModule
      public final class MyModule: Module {
        @JS
        nonisolated func compute() -> Int { 42 }
      }
      """,
      expandedSource: """
        public final class MyModule: Module {
          nonisolated func compute() -> Int { 42 }

          public static let _jsName = "MyModule"

          @JavaScriptActor
          public func _decorateModule(object: borrowing JavaScriptObject, in runtime: JavaScriptRuntime) throws {
            object.setProperty("compute") { [self] (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer, result: borrowing JavaScriptValue.Slot, runtime: borrowing JavaScriptRuntime) in
              guard arguments.count == 0 else {
                throw Exceptions.ArgumentsRangeMismatch((functionName: "compute", received: arguments.count, required: 0, maximum: 0))
              }
              let value = self.compute()
              try Int.encode(value, into: result, in: runtime)
            }
          }
        }
        """
    )
  }

  @Test
  func `Sync @Event member is stamped with @JavaScriptActor while the async default is not`() {
    assertExpansion(
      """
      @ExpoModule
      public final class MyModule: Module {
        @Event(sync: true)
        var onTick: () -> Void

        @Event
        var onReady: () -> Void
      }
      """,
      expandedSource: """
        public final class MyModule: Module {
          @JavaScriptActor
          var onTick: () -> Void {
            get {
              { [weak self] in
                self?.emitSync(event: "tick")
              }
            }
          }

          private func _assertTypesConformance_onTick() {
            func onTick(_: (some EventEmitter).Type) {
            }
            onTick(MyModule.self)
          }
          var onReady: () -> Void {
            get {
              { [weak self] in
                self?.emit(event: "ready")
              }
            }
          }

          private func _assertTypesConformance_onReady() {
            func onReady(_: (some EventEmitter).Type) {
            }
            onReady(MyModule.self)
          }

          public static let _jsName = "MyModule"
        }
        """
    )
  }

  @Test
  func `Class without inheritance gets appContext storage, init, and an AnyModule conformance`() {
    assertExpansion(
      """
      @ExpoModule
      public final class MyModule {
      }
      """,
      expandedSource: """
        public final class MyModule {

          public static let _jsName = "MyModule"

          public weak var appContext: AppContext?

          public required init(appContext: AppContext) {
            self.appContext = appContext
          }
        }

        extension MyModule: AnyModule {
        }
        """
    )
  }

  @Test
  func `Class with another superclass gets appContext storage, init, and an AnyModule conformance`() {
    assertExpansion(
      """
      @ExpoModule
      public final class MyModule: SomeOtherBase {
      }
      """,
      expandedSource: """
        public final class MyModule: SomeOtherBase {

          public static let _jsName = "MyModule"

          public weak var appContext: AppContext?

          public required init(appContext: AppContext) {
            self.appContext = appContext
          }
        }

        extension MyModule: AnyModule {
        }
        """
    )
  }

  @Test
  func `: Module does not get redundant storage, init, or AnyModule conformance`() {
    assertExpansion(
      """
      @ExpoModule
      public final class MyModule: Module {
      }
      """,
      expandedSource: """
        public final class MyModule: Module {

          public static let _jsName = "MyModule"
        }
        """
    )
  }

  @Test
  func `: BaseModule does not get a redundant AnyModule conformance`() {
    assertExpansion(
      """
      @ExpoModule
      public final class MyModule: BaseModule {
      }
      """,
      expandedSource: """
        public final class MyModule: BaseModule {

          public static let _jsName = "MyModule"
        }
        """
    )
  }

  @Test
  func `: AnyModule gets storage and init but no redundant conformance`() {
    assertExpansion(
      """
      @ExpoModule
      public final class MyModule: AnyModule {
      }
      """,
      expandedSource: """
        public final class MyModule: AnyModule {

          public static let _jsName = "MyModule"

          public weak var appContext: AppContext?

          public required init(appContext: AppContext) {
            self.appContext = appContext
          }
        }
        """
    )
  }

  @Test
  func `User-provided appContext property is not overridden`() {
    assertExpansion(
      """
      @ExpoModule
      public final class MyModule {
        public weak var appContext: AppContext?
      }
      """,
      expandedSource: """
        public final class MyModule {
          public weak var appContext: AppContext?

          public static let _jsName = "MyModule"

          public required init(appContext: AppContext) {
            self.appContext = appContext
          }
        }

        extension MyModule: AnyModule {
        }
        """
    )
  }

  @Test
  func `User-provided init(appContext:) is not overridden`() {
    assertExpansion(
      """
      @ExpoModule
      public final class MyModule {
        public required init(appContext: AppContext) {}
      }
      """,
      expandedSource: """
        public final class MyModule {
          public required init(appContext: AppContext) {}

          public static let _jsName = "MyModule"

          public weak var appContext: AppContext?
        }

        extension MyModule: AnyModule {
        }
        """
    )
  }

  @Test
  func `init with the right type but a different label does not satisfy the requirement and is still synthesized`() {
    assertExpansion(
      """
      @ExpoModule
      public final class MyModule {
        public required init(c: AppContext) {}
      }
      """,
      expandedSource: """
        public final class MyModule {
          public required init(c: AppContext) {}

          public static let _jsName = "MyModule"

          public weak var appContext: AppContext?

          public required init(appContext: AppContext) {
            self.appContext = appContext
          }
        }

        extension MyModule: AnyModule {
        }
        """
    )
  }

  @Test
  func `definition() is stamped with @ModuleDefinitionBuilder`() {
    assertExpansion(
      """
      @ExpoModule
      public final class MyModule: Module {
        public func definition() -> ModuleDefinition {
          Name("MyModule")
        }
      }
      """,
      expandedSource: """
        public final class MyModule: Module {
          @ModuleDefinitionBuilder
          public func definition() -> ModuleDefinition {
            Name("MyModule")
          }

          public static let _jsName = "MyModule"
        }
        """
    )
  }

  @Test
  func `definition() that already has @ModuleDefinitionBuilder is not stamped twice`() {
    assertExpansion(
      """
      @ExpoModule
      public final class MyModule: Module {
        @ModuleDefinitionBuilder
        public func definition() -> ModuleDefinition {
          Name("MyModule")
        }
      }
      """,
      expandedSource: """
        public final class MyModule: Module {
          @ModuleDefinitionBuilder
          public func definition() -> ModuleDefinition {
            Name("MyModule")
          }

          public static let _jsName = "MyModule"
        }
        """
    )
  }

  // MARK: - Parameter specifiers

  @Test
  func `Ownership specifiers on @JS parameters are left off the decode and the assertion`() {
    assertExpansion(
      """
      @ExpoModule
      public final class MyModule: Module {
        @JS
        func move(point: borrowing Point, by delta: consuming Delta, tag: sending Tag) {}
      }
      """,
      expandedSource: """
        public final class MyModule: Module {
          @JavaScriptActor
          func move(point: borrowing Point, by delta: consuming Delta, tag: sending Tag) {}

          public static let _jsName = "MyModule"

          @JavaScriptActor
          public func _decorateModule(object: borrowing JavaScriptObject, in runtime: JavaScriptRuntime) throws {
            object.setProperty("move") { [self] (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer) -> Void in
              guard arguments.count == 3 else {
                throw Exceptions.ArgumentsRangeMismatch((functionName: "move", received: arguments.count, required: 3, maximum: 3))
              }
              let arg0 = try Point.decode(arguments.unownedValue(at: 0), in: runtime)
              let arg1 = try Delta.decode(arguments.unownedValue(at: 1), in: runtime)
              let arg2 = try Tag.decode(arguments.unownedValue(at: 2), in: runtime)
              self.move(point: arg0, by: arg1, tag: arg2)
            }
          }

          private func _assertTypesConformance() {
            func move(point _: (some JavaScriptDecodable & ~Copyable).Type, by _: (some JavaScriptDecodable & ~Copyable).Type, tag _: (some JavaScriptDecodable & ~Copyable).Type) {
            }
            move(point: Point.self, by: Delta.self, tag: Tag.self)
          }
        }
        """
    )
  }

  @Test
  func `Ownership specifier keeps a trailing optional parameter omittable`() {
    assertExpansion(
      """
      @ExpoModule
      public final class MyModule: Module {
        @JS
        func tag(name: String, note: borrowing String?) { }
      }
      """,
      expandedSource: """
        public final class MyModule: Module {
          @JavaScriptActor
          func tag(name: String, note: borrowing String?) { }

          public static let _jsName = "MyModule"

          @JavaScriptActor
          public func _decorateModule(object: borrowing JavaScriptObject, in runtime: JavaScriptRuntime) throws {
            object.setProperty("tag") { [self] (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer) -> Void in
              guard arguments.count >= 1 && arguments.count <= 2 else {
                throw Exceptions.ArgumentsRangeMismatch((functionName: "tag", received: arguments.count, required: 1, maximum: 2))
              }
              let arg0 = try String.decode(arguments.unownedValue(at: 0), in: runtime)
              switch arguments.count {
              case 1:
                self.tag(name: arg0, note: nil)
              default:
                let arg1 = try String?.decode(arguments.unownedValue(at: 1), in: runtime)
                self.tag(name: arg0, note: arg1)
              }
            }
          }
        }
        """
    )
  }

  @Test
  func `Ownership specifier on a free-form parameter still reroutes the decode`() {
    assertExpansion(
      """
      @ExpoModule
      public final class MyModule: Module {
        @JS
        func store(config: borrowing [String: Any]) { }
      }
      """,
      expandedSource: """
        public final class MyModule: Module {
          @JavaScriptActor
          func store(config: borrowing [String: Any]) { }

          public static let _jsName = "MyModule"

          @JavaScriptActor
          public func _decorateModule(object: borrowing JavaScriptObject, in runtime: JavaScriptRuntime) throws {
            object.setProperty("store") { [self] (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer) -> Void in
              guard arguments.count == 1 else {
                throw Exceptions.ArgumentsRangeMismatch((functionName: "store", received: arguments.count, required: 1, maximum: 1))
              }
              let arg0 = try JavaScriptValue.decodeAnyDictionary(arguments.unownedValue(at: 0), in: runtime)
              self.store(config: arg0)
            }
          }
        }
        """
    )
  }

  @Test
  func `inout and isolated @JS parameters are errors`() {
    assertExpansion(
      """
      @JS
      func a(value: inout Int) {}
      @JS
      func b(worker: isolated Worker, name: Name) {}
      """,
      expandedSource: """
        func a(value: inout Int) {}
        func b(worker: isolated Worker, name: Name) {}

        private func _assertTypesConformance_b() {
          func b(name _: (some JavaScriptDecodable & ~Copyable).Type) {
          }
          b(name: Name.self)
        }
        """,
      diagnostics: [
        DiagnosticSpec(
          message:
            "A @JS parameter can't be 'inout': its argument is a value decoded from JavaScript, which can't be written back or carry an isolation.",
          line: 2,
          column: 15,
          severity: .error
        ),
        DiagnosticSpec(
          message:
            "A @JS parameter can't be 'isolated': its argument is a value decoded from JavaScript, which can't be written back or carry an isolation.",
          line: 4,
          column: 16,
          severity: .error
        ),
      ]
    )
  }

  // MARK: - Tuple types

  @Test
  func `Unlabeled tuple argument and return value convert through the tuple methods`() {
    assertExpansion(
      """
      @ExpoModule
      public final class MyModule: Module {
        @JS
        func swap(pair: (Int, String)) -> (String, Int) { (pair.1, pair.0) }
      }
      """,
      expandedSource: """
        public final class MyModule: Module {
          @JavaScriptActor
          func swap(pair: (Int, String)) -> (String, Int) { (pair.1, pair.0) }

          public static let _jsName = "MyModule"

          @JavaScriptActor
          public func _decorateModule(object: borrowing JavaScriptObject, in runtime: JavaScriptRuntime) throws {
            object.setProperty("swap") { [self] (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer, result: borrowing JavaScriptValue.Slot, runtime: borrowing JavaScriptRuntime) in
              guard arguments.count == 1 else {
                throw Exceptions.ArgumentsRangeMismatch((functionName: "swap", received: arguments.count, required: 1, maximum: 1))
              }
              let arg0 = try JavaScriptValue.decodeTuple(arguments.unownedValue(at: 0), as: Int.self, String.self, in: runtime)
              let value = self.swap(pair: arg0)
              try JavaScriptValue.encodeTuple(value, into: result, in: runtime)
            }
          }
        }
        """
    )
  }

  @Test
  func `Labeled tuple converts through the tuple methods with labels and asserts its element types`() {
    assertExpansion(
      """
      @ExpoModule
      public final class MyModule: Module {
        @JS
        func move(_ point: Point, by offset: (x: Double, y: Double)) -> (point: Point, distance: Double) { fatalError() }
      }
      """,
      expandedSource: """
        public final class MyModule: Module {
          @JavaScriptActor
          func move(_ point: Point, by offset: (x: Double, y: Double)) -> (point: Point, distance: Double) { fatalError() }

          public static let _jsName = "MyModule"

          @JavaScriptActor
          public func _decorateModule(object: borrowing JavaScriptObject, in runtime: JavaScriptRuntime) throws {
            object.setProperty("move") { [self] (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer, result: borrowing JavaScriptValue.Slot, runtime: borrowing JavaScriptRuntime) in
              guard arguments.count == 2 else {
                throw Exceptions.ArgumentsRangeMismatch((functionName: "move", received: arguments.count, required: 2, maximum: 2))
              }
              let arg0 = try Point.decode(arguments.unownedValue(at: 0), in: runtime)
              let arg1 = try JavaScriptValue.decodeTuple(arguments.unownedValue(at: 1), labels: ["x", "y"], as: Double.self, Double.self, in: runtime)
              let value = self.move(arg0, by: arg1)
              try JavaScriptValue.encodeTuple(value as (Point, Double), labels: ["point", "distance"], into: result, in: runtime)
            }
          }

          private func _assertTypesConformance() {
            func move(_: (some JavaScriptDecodable & ~Copyable).Type, returning _: (some JavaScriptEncodable & ~Copyable).Type) {
            }
            move(Point.self, returning: Point.self)
          }
        }
        """
    )
  }

  @Test
  func `Optional tuple argument and property map undefined and null to nil`() {
    assertExpansion(
      """
      @ExpoModule
      public final class MyModule: Module {
        @JS
        var selection: (start: Int, end: Int)?

        @JS
        func select(_ range: (Int, Int)?) { }
      }
      """,
      expandedSource: """
        public final class MyModule: Module {
          @JavaScriptActor
          var selection: (start: Int, end: Int)?
          @JavaScriptActor
          func select(_ range: (Int, Int)?) { }

          public static let _jsName = "MyModule"

          @JavaScriptActor
          public func _decorateModule(object: borrowing JavaScriptObject, in runtime: JavaScriptRuntime) throws {
            object.setProperty("select") { [self] (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer) -> Void in
              guard arguments.count >= 0 && arguments.count <= 1 else {
                throw Exceptions.ArgumentsRangeMismatch((functionName: "select", received: arguments.count, required: 0, maximum: 1))
              }
              switch arguments.count {
              case 0:
                self.select(nil)
              default:
                let arg0 = try JavaScriptValue.decodeOptional(arguments.unownedValue(at: 0), in: runtime, wrapped: { value, runtime in
                    return try JavaScriptValue.decodeTuple(value, as: Int.self, Int.self, in: runtime)
                  })
                self.select(arg0)
              }
            }
            let selectionDescriptor = runtime.createObject()
            selectionDescriptor.setProperty("enumerable", value: true)
            selectionDescriptor.setProperty("get") { [self] (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer, result: borrowing JavaScriptValue.Slot, runtime: borrowing JavaScriptRuntime) in
              try JavaScriptValue.encodeOptional(self.selection, into: result, in: runtime, wrapped: { value, slot, runtime in
                  try JavaScriptValue.encodeTuple(value as (Int, Int), labels: ["start", "end"], into: slot, in: runtime)
                })
            }
            selectionDescriptor.setProperty("set") { [self] (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer, result: borrowing JavaScriptValue.Slot, runtime: borrowing JavaScriptRuntime) in
              self.selection = try JavaScriptValue.decodeOptional(arguments.unownedValue(at: 0), in: runtime, wrapped: { value, runtime in
                  return try JavaScriptValue.decodeTuple(value, labels: ["start", "end"], as: Int.self, Int.self, in: runtime)
                })
            }
            object.defineProperty("selection", descriptor: selectionDescriptor)
          }
        }
        """
    )
  }

  @Test
  func `Containers holding tuples convert through nested conversion closures`() {
    assertExpansion(
      """
      @ExpoModule
      public final class MyModule: Module {
        @JS
        func lengths(of ranges: [(name: String, range: (Int, Point))]) -> [String: (Int, Int)?] { [:] }
      }
      """,
      expandedSource: """
        public final class MyModule: Module {
          @JavaScriptActor
          func lengths(of ranges: [(name: String, range: (Int, Point))]) -> [String: (Int, Int)?] { [:] }

          public static let _jsName = "MyModule"

          @JavaScriptActor
          public func _decorateModule(object: borrowing JavaScriptObject, in runtime: JavaScriptRuntime) throws {
            object.setProperty("lengths") { [self] (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer, result: borrowing JavaScriptValue.Slot, runtime: borrowing JavaScriptRuntime) in
              guard arguments.count == 1 else {
                throw Exceptions.ArgumentsRangeMismatch((functionName: "lengths", received: arguments.count, required: 1, maximum: 1))
              }
              let arg0 = try JavaScriptValue.decodeArray(arguments.unownedValue(at: 0), in: runtime, element: { value, runtime in
                  return try JavaScriptValue.decodeTuple(value, labels: ["name", "range"], in: runtime, { value, runtime in
                      return try String.decode(value, in: runtime)
                    }, { value, runtime in
                      return try JavaScriptValue.decodeTuple(value, as: Int.self, Point.self, in: runtime)
                    })
                })
              let value = self.lengths(of: arg0)
              try JavaScriptValue.encodeDictionary(value, into: result, in: runtime, value: { value, slot, runtime in
                  try JavaScriptValue.encodeOptional(value, into: slot, in: runtime, wrapped: { value, slot, runtime in
                      try JavaScriptValue.encodeTuple(value, into: slot, in: runtime)
                    })
                })
            }
          }

          private func _assertTypesConformance() {
            func lengths(of _: (some JavaScriptDecodable & ~Copyable).Type) {
            }
            lengths(of: Point.self)
          }
        }
        """
    )
  }

  @Test
  func `Closure argument encodes a tuple parameter and decodes a tuple result`() {
    assertExpansion(
      """
      @ExpoModule
      public final class MyModule: Module {
        @JS
        func transform(with body: ((Int, Int)) throws -> (x: Int, y: Int)) { }
      }
      """,
      expandedSource: """
        public final class MyModule: Module {
          @JavaScriptActor
          func transform(with body: ((Int, Int)) throws -> (x: Int, y: Int)) { }

          public static let _jsName = "MyModule"

          @JavaScriptActor
          public func _decorateModule(object: borrowing JavaScriptObject, in runtime: JavaScriptRuntime) throws {
            object.setProperty("transform") { [self] (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer) -> Void in
              guard arguments.count == 1 else {
                throw Exceptions.ArgumentsRangeMismatch((functionName: "transform", received: arguments.count, required: 1, maximum: 1))
              }
              let arg0Callback = try JavaScriptCallback.decode(arguments.unownedValue(at: 0), in: runtime)
              let arg0: ((Int, Int)) throws -> (x: Int, y: Int) = { @Sendable p0 in
                try arg0Callback.invokeBlocking(p0, argumentCount: 1, decoding: { value, runtime in
                    return try JavaScriptValue.decodeTuple(value, labels: ["x", "y"], as: Int.self, Int.self, in: runtime)
                  }) { _values, _arguments, _runtime in
                  try _arguments.emplace(at: 0) { slot in
                    try JavaScriptValue.encodeTuple(_values, into: slot, in: _runtime)
                  }
                }
              }
              self.transform(with: arg0)
            }
          }
        }
        """
    )
  }

  @Test
  func `Async closure argument with a tuple is diagnosed`() {
    assertExpansion(
      """
      @ExpoModule
      public final class MyModule: Module {
        @JS
        func load(with body: @escaping ((Int, Int)) async -> Void) { }
      }
      """,
      expandedSource: """
        public final class MyModule: Module {
          @JavaScriptActor
          func load(with body: @escaping ((Int, Int)) async -> Void) { }

          public static let _jsName = "MyModule"

          @JavaScriptActor
          public func _decorateModule(object: borrowing JavaScriptObject, in runtime: JavaScriptRuntime) throws {
            object.setProperty("load") { [self] (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer) -> Void in
              guard arguments.count == 1 else {
                throw Exceptions.ArgumentsRangeMismatch((functionName: "load", received: arguments.count, required: 1, maximum: 1))
              }
              let arg0Callback = try JavaScriptCallback.decode(arguments.unownedValue(at: 0), in: runtime)
              let arg0: ((Int, Int)) async -> Void = { @Sendable p0 in
                do {
                  try await arg0Callback.invokeAsync(p0)
                } catch {
                  arg0Callback.reportError(error)
                }
              }
              self.load(with: arg0)
            }
          }
        }
        """,
      diagnostics: [
        DiagnosticSpec(
          message:
            "An async @JS closure argument can't take or return a tuple. Use a @Record type, or a closure that isn't async.",
          line: 5,
          column: 35,
          severity: .error
        )
      ]
    )
  }

  @Test
  func `Assertion helpers take argument labels, and only helpers with the same labels get separate scopes`() {
    assertExpansion(
      """
      @ExpoModule
      public final class MyModule: Module {
        @JS
        func load(_ point: Point) { }

        @JS("loadSize")
        func load(_ size: Size) { }

        @JS("loadAt")
        func load(at point: Point) { }

        @JS
        func save(_ record: MyRecord) { }
      }
      """,
      expandedSource: """
        public final class MyModule: Module {
          @JavaScriptActor
          func load(_ point: Point) { }
          @JavaScriptActor
          func load(_ size: Size) { }
          @JavaScriptActor
          func load(at point: Point) { }
          @JavaScriptActor
          func save(_ record: MyRecord) { }

          public static let _jsName = "MyModule"

          @JavaScriptActor
          public func _decorateModule(object: borrowing JavaScriptObject, in runtime: JavaScriptRuntime) throws {
            object.setProperty("load") { [self] (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer) -> Void in
              guard arguments.count == 1 else {
                throw Exceptions.ArgumentsRangeMismatch((functionName: "load", received: arguments.count, required: 1, maximum: 1))
              }
              let arg0 = try Point.decode(arguments.unownedValue(at: 0), in: runtime)
              self.load(arg0)
            }
            object.setProperty("loadSize") { [self] (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer) -> Void in
              guard arguments.count == 1 else {
                throw Exceptions.ArgumentsRangeMismatch((functionName: "loadSize", received: arguments.count, required: 1, maximum: 1))
              }
              let arg0 = try Size.decode(arguments.unownedValue(at: 0), in: runtime)
              self.load(arg0)
            }
            object.setProperty("loadAt") { [self] (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer) -> Void in
              guard arguments.count == 1 else {
                throw Exceptions.ArgumentsRangeMismatch((functionName: "loadAt", received: arguments.count, required: 1, maximum: 1))
              }
              let arg0 = try Point.decode(arguments.unownedValue(at: 0), in: runtime)
              self.load(at: arg0)
            }
            object.setProperty("save") { [self] (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer) -> Void in
              guard arguments.count == 1 else {
                throw Exceptions.ArgumentsRangeMismatch((functionName: "save", received: arguments.count, required: 1, maximum: 1))
              }
              let arg0 = try MyRecord.decode(arguments.unownedValue(at: 0), in: runtime)
              self.save(arg0)
            }
          }

          private func _assertTypesConformance() {
            do {
              func load(_: (some JavaScriptDecodable & ~Copyable).Type) {
              }
              load(Point.self)
            }
            do {
              func load(_: (some JavaScriptDecodable & ~Copyable).Type) {
              }
              load(Size.self)
            }
            func load(at _: (some JavaScriptDecodable & ~Copyable).Type) {
            }
            load(at: Point.self)
            func save(_: (some JavaScriptDecodable & ~Copyable).Type) {
            }
            save(MyRecord.self)
          }
        }
        """
    )
  }

  @Test
  func `Tuple type aliases in the module body resolve in @JS members`() {
    assertExpansion(
      """
      @ExpoModule
      public final class MyModule: Module {
        typealias Span = (start: Int, end: Point)
        typealias Spans = [Self.Span]
        typealias Identifier = String

        @JS
        func merge(_ spans: Spans, id: Identifier) -> Span? { nil }
      }
      """,
      expandedSource: """
        public final class MyModule: Module {
          typealias Span = (start: Int, end: Point)
          typealias Spans = [Self.Span]
          typealias Identifier = String
          @JavaScriptActor
          func merge(_ spans: Spans, id: Identifier) -> Span? { nil }

          public static let _jsName = "MyModule"

          @JavaScriptActor
          public func _decorateModule(object: borrowing JavaScriptObject, in runtime: JavaScriptRuntime) throws {
            object.setProperty("merge") { [self] (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer, result: borrowing JavaScriptValue.Slot, runtime: borrowing JavaScriptRuntime) in
              guard arguments.count == 2 else {
                throw Exceptions.ArgumentsRangeMismatch((functionName: "merge", received: arguments.count, required: 2, maximum: 2))
              }
              let arg0 = try JavaScriptValue.decodeArray(arguments.unownedValue(at: 0), in: runtime, element: { value, runtime in
                  return try JavaScriptValue.decodeTuple(value, labels: ["start", "end"], as: Int.self, Point.self, in: runtime)
                })
              let arg1 = try Identifier.decode(arguments.unownedValue(at: 1), in: runtime)
              let value = self.merge(arg0, id: arg1)
              try JavaScriptValue.encodeOptional(value, into: result, in: runtime, wrapped: { value, slot, runtime in
                  try JavaScriptValue.encodeTuple(value as (Int, Point), labels: ["start", "end"], into: slot, in: runtime)
                })
            }
          }

          private func _assertTypesConformance() {
            func merge(_: (some JavaScriptDecodable & ~Copyable).Type, id _: (some JavaScriptDecodable & ~Copyable).Type, returning _: (some JavaScriptEncodable & ~Copyable).Type) {
            }
            merge(Point.self, id: Identifier.self, returning: Point.self)
          }
        }
        """
    )
  }

  // MARK: - Free-form (Any) types

  @Test
  func `Free-form dictionary argument decodes through JavaScriptValue.decodeAnyDictionary`() {
    assertExpansion(
      """
      @ExpoModule
      public final class MyModule: Module {
        @JS
        func store(config: [String: Any]) { }
      }
      """,
      expandedSource: """
        public final class MyModule: Module {
          @JavaScriptActor
          func store(config: [String: Any]) { }

          public static let _jsName = "MyModule"

          @JavaScriptActor
          public func _decorateModule(object: borrowing JavaScriptObject, in runtime: JavaScriptRuntime) throws {
            object.setProperty("store") { [self] (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer) -> Void in
              guard arguments.count == 1 else {
                throw Exceptions.ArgumentsRangeMismatch((functionName: "store", received: arguments.count, required: 1, maximum: 1))
              }
              let arg0 = try JavaScriptValue.decodeAnyDictionary(arguments.unownedValue(at: 0), in: runtime)
              self.store(config: arg0)
            }
          }
        }
        """
    )
  }

  @Test
  func `Optional free-form argument maps undefined and null to nil around decodeAnyDictionary`() {
    assertExpansion(
      """
      @ExpoModule
      public final class MyModule: Module {
        @JS
        func keep(config: [String: Any]?) { }
      }
      """,
      expandedSource: """
        public final class MyModule: Module {
          @JavaScriptActor
          func keep(config: [String: Any]?) { }

          public static let _jsName = "MyModule"

          @JavaScriptActor
          public func _decorateModule(object: borrowing JavaScriptObject, in runtime: JavaScriptRuntime) throws {
            object.setProperty("keep") { [self] (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer) -> Void in
              guard arguments.count >= 0 && arguments.count <= 1 else {
                throw Exceptions.ArgumentsRangeMismatch((functionName: "keep", received: arguments.count, required: 0, maximum: 1))
              }
              switch arguments.count {
              case 0:
                self.keep(config: nil)
              default:
                let arg0 = try arguments.unownedValue(at: 0).isUndefined() || arguments.unownedValue(at: 0).isNull() ? nil : JavaScriptValue.decodeAnyDictionary(arguments.unownedValue(at: 0), in: runtime)
                self.keep(config: arg0)
              }
            }
          }
        }
        """
    )
  }

  @Test
  func `Nested free-form argument decodes through the generic decodeAny from a copied value`() {
    assertExpansion(
      """
      @ExpoModule
      public final class MyModule: Module {
        @JS
        func store(groups: [String: [Any]], rows: [[String: Any]]?) { }
      }
      """,
      expandedSource: """
        public final class MyModule: Module {
          @JavaScriptActor
          func store(groups: [String: [Any]], rows: [[String: Any]]?) { }

          public static let _jsName = "MyModule"

          @JavaScriptActor
          public func _decorateModule(object: borrowing JavaScriptObject, in runtime: JavaScriptRuntime) throws {
            object.setProperty("store") { [self] (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer) -> Void in
              guard arguments.count >= 1 && arguments.count <= 2 else {
                throw Exceptions.ArgumentsRangeMismatch((functionName: "store", received: arguments.count, required: 1, maximum: 2))
              }
              let arg0 = try JavaScriptValue.decodeAny(arguments.unownedValue(at: 0).copied(in: runtime), as: [String: [Any]].self, in: runtime)
              switch arguments.count {
              case 1:
                self.store(groups: arg0, rows: nil)
              default:
                let arg1 = try JavaScriptValue.decodeAny(arguments.unownedValue(at: 1).copied(in: runtime), as: [[String: Any]]?.self, in: runtime)
                self.store(groups: arg0, rows: arg1)
              }
            }
          }
        }
        """
    )
  }

  @Test
  func `Free-form array and bare Any arguments each reroute to their decodeAny entry point`() {
    assertExpansion(
      """
      @ExpoModule
      public final class MyModule: Module {
        @JS
        func inspect(list: [Any], value: Any) { }
      }
      """,
      expandedSource: """
        public final class MyModule: Module {
          @JavaScriptActor
          func inspect(list: [Any], value: Any) { }

          public static let _jsName = "MyModule"

          @JavaScriptActor
          public func _decorateModule(object: borrowing JavaScriptObject, in runtime: JavaScriptRuntime) throws {
            object.setProperty("inspect") { [self] (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer) -> Void in
              guard arguments.count == 2 else {
                throw Exceptions.ArgumentsRangeMismatch((functionName: "inspect", received: arguments.count, required: 2, maximum: 2))
              }
              let arg0 = try JavaScriptValue.decodeAnyArray(arguments.unownedValue(at: 0), in: runtime)
              let arg1 = try JavaScriptValue.decodeAny(arguments.unownedValue(at: 1), in: runtime)
              self.inspect(list: arg0, value: arg1)
            }
          }
        }
        """
    )
  }

  @Test
  func `Free-form return values encode through the matching encodeAny method`() {
    assertExpansion(
      """
      @ExpoModule
      public final class MyModule: Module {
        @JS
        func load() -> [String: Any] { [:] }
        @JS
        func list() -> [Any] { [] }
        @JS
        func raw() -> Any { 0 }
      }
      """,
      expandedSource: """
        public final class MyModule: Module {
          @JavaScriptActor
          func load() -> [String: Any] { [:] }
          @JavaScriptActor
          func list() -> [Any] { [] }
          @JavaScriptActor
          func raw() -> Any { 0 }

          public static let _jsName = "MyModule"

          @JavaScriptActor
          public func _decorateModule(object: borrowing JavaScriptObject, in runtime: JavaScriptRuntime) throws {
            object.setProperty("load") { [self] (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer, result: borrowing JavaScriptValue.Slot, runtime: borrowing JavaScriptRuntime) in
              guard arguments.count == 0 else {
                throw Exceptions.ArgumentsRangeMismatch((functionName: "load", received: arguments.count, required: 0, maximum: 0))
              }
              let value = self.load()
              result.emplace(try JavaScriptValue.encodeAnyDictionary(value, in: runtime))
            }
            object.setProperty("list") { [self] (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer, result: borrowing JavaScriptValue.Slot, runtime: borrowing JavaScriptRuntime) in
              guard arguments.count == 0 else {
                throw Exceptions.ArgumentsRangeMismatch((functionName: "list", received: arguments.count, required: 0, maximum: 0))
              }
              let value = self.list()
              result.emplace(try JavaScriptValue.encodeAnyArray(value, in: runtime))
            }
            object.setProperty("raw") { [self] (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer, result: borrowing JavaScriptValue.Slot, runtime: borrowing JavaScriptRuntime) in
              guard arguments.count == 0 else {
                throw Exceptions.ArgumentsRangeMismatch((functionName: "raw", received: arguments.count, required: 0, maximum: 0))
              }
              let value = self.raw()
              result.emplace(try JavaScriptValue.encodeAny(value, in: runtime))
            }
          }
        }
        """
    )
  }

  @Test
  func `Optional and nested free-form return values encode through the generic encodeAny`() {
    assertExpansion(
      """
      @ExpoModule
      public final class MyModule: Module {
        @JS
        func find() -> [String: Any]? { nil }
        @JS
        func groups() -> [String: [Any]] { [:] }
        @JS
        func peek() -> Any? { nil }
      }
      """,
      expandedSource: """
        public final class MyModule: Module {
          @JavaScriptActor
          func find() -> [String: Any]? { nil }
          @JavaScriptActor
          func groups() -> [String: [Any]] { [:] }
          @JavaScriptActor
          func peek() -> Any? { nil }

          public static let _jsName = "MyModule"

          @JavaScriptActor
          public func _decorateModule(object: borrowing JavaScriptObject, in runtime: JavaScriptRuntime) throws {
            object.setProperty("find") { [self] (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer, result: borrowing JavaScriptValue.Slot, runtime: borrowing JavaScriptRuntime) in
              guard arguments.count == 0 else {
                throw Exceptions.ArgumentsRangeMismatch((functionName: "find", received: arguments.count, required: 0, maximum: 0))
              }
              let value = self.find()
              result.emplace(try JavaScriptValue.encodeAny(value as Any, in: runtime))
            }
            object.setProperty("groups") { [self] (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer, result: borrowing JavaScriptValue.Slot, runtime: borrowing JavaScriptRuntime) in
              guard arguments.count == 0 else {
                throw Exceptions.ArgumentsRangeMismatch((functionName: "groups", received: arguments.count, required: 0, maximum: 0))
              }
              let value = self.groups()
              result.emplace(try JavaScriptValue.encodeAny(value as Any, in: runtime))
            }
            object.setProperty("peek") { [self] (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer, result: borrowing JavaScriptValue.Slot, runtime: borrowing JavaScriptRuntime) in
              guard arguments.count == 0 else {
                throw Exceptions.ArgumentsRangeMismatch((functionName: "peek", received: arguments.count, required: 0, maximum: 0))
              }
              let value = self.peek()
              result.emplace(try JavaScriptValue.encodeAny(value as Any, in: runtime))
            }
          }
        }
        """
    )
  }

  @Test
  func `Async free-form return value encodes on the JavaScript thread`() {
    assertExpansion(
      """
      @ExpoModule
      public final class MyModule: Module {
        @JS
        func fetch() async throws -> [String: Any] { [:] }
      }
      """,
      expandedSource: """
        public final class MyModule: Module {
          @JavaScriptActor
          func fetch() async throws -> [String: Any] { [:] }

          public static let _jsName = "MyModule"

          @JavaScriptActor
          public func _decorateModule(object: borrowing JavaScriptObject, in runtime: JavaScriptRuntime) throws {
            object.setProperty("fetch") { [self] (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer) in
              guard arguments.count == 0 else {
                throw Exceptions.ArgumentsRangeMismatch((functionName: "fetch", received: arguments.count, required: 0, maximum: 0))
              }
              return {
                let result = try await self.fetch()
                return try await runtime.execute {
                  return try JavaScriptValue.encodeAnyDictionary(result, in: runtime)
                }
              }
            }
          }
        }
        """
    )
  }

  @Test
  func `Free-form property encodes in its getter and decodes in its setter`() {
    assertExpansion(
      """
      @ExpoModule
      public final class MyModule: Module {
        @JS
        var metadata: [String: Any] = [:]
        @JS
        var groups: [String: [Any]]? = nil
      }
      """,
      expandedSource: """
        public final class MyModule: Module {
          @JavaScriptActor
          var metadata: [String: Any] = [:]
          @JavaScriptActor
          var groups: [String: [Any]]? = nil

          public static let _jsName = "MyModule"

          @JavaScriptActor
          public func _decorateModule(object: borrowing JavaScriptObject, in runtime: JavaScriptRuntime) throws {
            let metadataDescriptor = runtime.createObject()
            metadataDescriptor.setProperty("enumerable", value: true)
            metadataDescriptor.setProperty("get") { [self] (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer, result: borrowing JavaScriptValue.Slot, runtime: borrowing JavaScriptRuntime) in
              result.emplace(try JavaScriptValue.encodeAnyDictionary(self.metadata, in: runtime))
            }
            metadataDescriptor.setProperty("set") { [self] (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer, result: borrowing JavaScriptValue.Slot, runtime: borrowing JavaScriptRuntime) in
              self.metadata = try JavaScriptValue.decodeAnyDictionary(arguments.unownedValue(at: 0), in: runtime)
            }
            object.defineProperty("metadata", descriptor: metadataDescriptor)
            let groupsDescriptor = runtime.createObject()
            groupsDescriptor.setProperty("enumerable", value: true)
            groupsDescriptor.setProperty("get") { [self] (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer, result: borrowing JavaScriptValue.Slot, runtime: borrowing JavaScriptRuntime) in
              result.emplace(try JavaScriptValue.encodeAny(self.groups as Any, in: runtime))
            }
            groupsDescriptor.setProperty("set") { [self] (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer, result: borrowing JavaScriptValue.Slot, runtime: borrowing JavaScriptRuntime) in
              self.groups = try JavaScriptValue.decodeAny(arguments.unownedValue(at: 0).copied(in: runtime), as: [String: [Any]]?.self, in: runtime)
            }
            object.defineProperty("groups", descriptor: groupsDescriptor)
          }
        }
        """
    )
  }

  @Test
  func `A type holding Any in an unconvertible shape is an error and isn't asserted`() {
    assertExpansion(
      """
      @ExpoModule
      public final class MyModule: Module {
        @JS
        func keyed(map: [Int: Any]) -> Set<[String: Any]> { [] }
      }
      """,
      expandedSource: """
        public final class MyModule: Module {
          @JavaScriptActor
          func keyed(map: [Int: Any]) -> Set<[String: Any]> { [] }

          public static let _jsName = "MyModule"

          @JavaScriptActor
          public func _decorateModule(object: borrowing JavaScriptObject, in runtime: JavaScriptRuntime) throws {
            object.setProperty("keyed") { [self] (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer, result: borrowing JavaScriptValue.Slot, runtime: borrowing JavaScriptRuntime) in
              guard arguments.count == 1 else {
                throw Exceptions.ArgumentsRangeMismatch((functionName: "keyed", received: arguments.count, required: 1, maximum: 1))
              }
              let arg0 = try [Int: Any].decode(arguments.unownedValue(at: 0), in: runtime)
              let value = self.keyed(map: arg0)
              try Set<[String: Any]>.encode(value, into: result, in: runtime)
            }
          }
        }
        """,
      diagnostics: [
        DiagnosticSpec(
          message:
            "A @JS member can't use the type '[Int: Any]': a type holding 'Any' converts to and from JavaScript only when it's built from 'Any', arrays, String-keyed dictionaries and optionals. Use one of those shapes, such as '[String: Any]', or 'JavaScriptValue' to keep the JavaScript value unconverted.",
          line: 5,
          column: 19,
          severity: .error
        ),
        DiagnosticSpec(
          message:
            "A @JS member can't use the type 'Set<[String: Any]>': a type holding 'Any' converts to and from JavaScript only when it's built from 'Any', arrays, String-keyed dictionaries and optionals. Use one of those shapes, such as '[String: Any]', or 'JavaScriptValue' to keep the JavaScript value unconverted.",
          line: 5,
          column: 34,
          severity: .error
        ),
      ]
    )
  }

  @Test
  func `views: registers view classes by type`() {
    assertExpansion(
      """
      @ExpoModule(views: [CardView.self, BadgeView.self])
      public class MyModule: Module {
      }
      """,
      expandedSource: """
        public class MyModule: Module {

          public static let _jsName = "MyModule"

          public static let _viewTypes: [Any.Type] = [CardView.self, BadgeView.self]
        }
        """
    )
  }

  @Test
  func `views: combines with classes:`() {
    assertExpansion(
      """
      @ExpoModule(classes: [Cache.self], views: [CardView.self])
      public class MyModule: Module {
      }
      """,
      expandedSource: """
        public class MyModule: Module {

          public static let _jsName = "MyModule"

          public static let _classTypes: [SharedObject.Type] = [Cache.self]

          public static let _viewTypes: [Any.Type] = [CardView.self]
        }
        """
    )
  }

  @Test
  func `No views: argument emits no _viewTypes`() {
    assertExpansion(
      """
      @ExpoModule
      public class MyModule: Module {
      }
      """,
      expandedSource: """
        public class MyModule: Module {

          public static let _jsName = "MyModule"
        }
        """
    )
  }

  @Test
  func `A qualified type in views: is registered, not dropped`() {
    // The base of `Outer.CardView.self` is a member access, not a bare name. Skipping it would
    // emit no _viewTypes at all and silently never register the view.
    assertExpansion(
      """
      @ExpoModule(views: [Outer.CardView.self])
      public class MyModule: Module {
      }
      """,
      expandedSource: """
        public class MyModule: Module {

          public static let _jsName = "MyModule"

          public static let _viewTypes: [Any.Type] = [Outer.CardView.self]
        }
        """
    )
  }

  @Test
  func `An explicitly empty views: list emits no _viewTypes`() {
    assertExpansion(
      """
      @ExpoModule(views: [])
      public class MyModule: Module {
      }
      """,
      expandedSource: """
        public class MyModule: Module {

          public static let _jsName = "MyModule"
        }
        """
    )
  }

  @Test
  func `Escaped member names bind under the bare JS name and keep the backticks in Swift`() {
    assertExpansion(
      """
      @ExpoModule
      public final class MyModule: Module {
        @JS
        func `default`(`in` value: Int) -> Int { value }

        @JS
        var `class`: Int = 1

        @Event
        var `onClass`: () -> Void
      }
      """,
      expandedSource: """
        public final class MyModule: Module {
          @JavaScriptActor
          func `default`(`in` value: Int) -> Int { value }
          @JavaScriptActor
          var `class`: Int = 1
          var `onClass`: () -> Void {
            get {
              { [weak self] in
                self?.emit(event: "class")
              }
            }
          }

          private func `_assertTypesConformance_onClass`() {
            func `onClass`(_: (some EventEmitter).Type) {
            }
            `onClass`(MyModule.self)
          }

          public static let _jsName = "MyModule"

          @JavaScriptActor
          public func _decorateModule(object: borrowing JavaScriptObject, in runtime: JavaScriptRuntime) throws {
            object.setProperty("default") { [self] (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer, result: borrowing JavaScriptValue.Slot, runtime: borrowing JavaScriptRuntime) in
              guard arguments.count == 1 else {
                throw Exceptions.ArgumentsRangeMismatch((functionName: "default", received: arguments.count, required: 1, maximum: 1))
              }
              let arg0 = try Int.decode(arguments.unownedValue(at: 0), in: runtime)
              let value = self.`default`(`in`: arg0)
              try Int.encode(value, into: result, in: runtime)
            }
            let `classDescriptor` = runtime.createObject()
            `classDescriptor`.setProperty("enumerable", value: true)
            `classDescriptor`.setProperty("get") { [self] (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer, result: borrowing JavaScriptValue.Slot, runtime: borrowing JavaScriptRuntime) in
              try Int.encode(self.`class`, into: result, in: runtime)
            }
            `classDescriptor`.setProperty("set") { [self] (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer, result: borrowing JavaScriptValue.Slot, runtime: borrowing JavaScriptRuntime) in
              self.`class` = try Int.decode(arguments.unownedValue(at: 0), in: runtime)
            }
            object.defineProperty("class", descriptor: `classDescriptor`)
          }
        }
        """
    )
  }

  @Test
  func `Two functions with the same JS name are an error on the later one`() {
    assertExpansion(
      """
      @ExpoModule
      public final class MyModule: Module {
        @JS
        func greet(name: String) -> String { "Hi" }

        @JS
        func greet(times: Int) -> String { "Hi" }
      }
      """,
      expandedSource: """
        public final class MyModule: Module {
          @JavaScriptActor
          func greet(name: String) -> String { "Hi" }
          @JavaScriptActor
          func greet(times: Int) -> String { "Hi" }

          public static let _jsName = "MyModule"

          @JavaScriptActor
          public func _decorateModule(object: borrowing JavaScriptObject, in runtime: JavaScriptRuntime) throws {
            object.setProperty("greet") { [self] (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer, result: borrowing JavaScriptValue.Slot, runtime: borrowing JavaScriptRuntime) in
              guard arguments.count == 1 else {
                throw Exceptions.ArgumentsRangeMismatch((functionName: "greet", received: arguments.count, required: 1, maximum: 1))
              }
              let arg0 = try String.decode(arguments.unownedValue(at: 0), in: runtime)
              let value = self.greet(name: arg0)
              try String.encode(value, into: result, in: runtime)
            }
            object.setProperty("greet") { [self] (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer, result: borrowing JavaScriptValue.Slot, runtime: borrowing JavaScriptRuntime) in
              guard arguments.count == 1 else {
                throw Exceptions.ArgumentsRangeMismatch((functionName: "greet", received: arguments.count, required: 1, maximum: 1))
              }
              let arg0 = try Int.decode(arguments.unownedValue(at: 0), in: runtime)
              let value = self.greet(times: arg0)
              try String.encode(value, into: result, in: runtime)
            }
          }
        }
        """,
      diagnostics: [
        DiagnosticSpec(
          message:
            "The JavaScript name 'greet' is already bound by an earlier @JS function. A JavaScript object holds one member per name, so JavaScript could reach only one of them. Give one of them another name with @JS(\"...\").",
          line: 7,
          column: 8,
          severity: .error,
          notes: [NoteSpec(message: "'greet' is first bound here", line: 4, column: 8)]
        )
      ]
    )
  }

  @Test
  func `A function renamed to a property's JS name is an error`() {
    assertExpansion(
      """
      @ExpoModule
      public final class MyModule: Module {
        @JS
        var status: String { "ok" }

        @JS("status")
        func readStatus() -> String { "ok" }
      }
      """,
      expandedSource: """
        public final class MyModule: Module {
          @JavaScriptActor
          var status: String { "ok" }
          @JavaScriptActor
          func readStatus() -> String { "ok" }

          public static let _jsName = "MyModule"

          @JavaScriptActor
          public func _decorateModule(object: borrowing JavaScriptObject, in runtime: JavaScriptRuntime) throws {
            object.setProperty("status") { [self] (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer, result: borrowing JavaScriptValue.Slot, runtime: borrowing JavaScriptRuntime) in
              guard arguments.count == 0 else {
                throw Exceptions.ArgumentsRangeMismatch((functionName: "status", received: arguments.count, required: 0, maximum: 0))
              }
              let value = self.readStatus()
              try String.encode(value, into: result, in: runtime)
            }
            let statusDescriptor = runtime.createObject()
            statusDescriptor.setProperty("enumerable", value: true)
            statusDescriptor.setProperty("get") { [self] (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer, result: borrowing JavaScriptValue.Slot, runtime: borrowing JavaScriptRuntime) in
              try String.encode(self.status, into: result, in: runtime)
            }
            object.defineProperty("status", descriptor: statusDescriptor)
          }
        }
        """,
      diagnostics: [
        DiagnosticSpec(
          message:
            "The JavaScript name 'status' is already bound by an earlier @JS property. A JavaScript object holds one member per name, so JavaScript could reach only one of them. Give one of them another name with @JS(\"...\").",
          line: 7,
          column: 8,
          severity: .error,
          notes: [NoteSpec(message: "'status' is first bound here", line: 4, column: 7)]
        )
      ]
    )
  }
}
