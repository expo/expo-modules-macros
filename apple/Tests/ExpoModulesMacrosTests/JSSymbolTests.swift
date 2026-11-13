import ExpoModulesMacrosCore
import SwiftSyntax
import SwiftSyntaxMacroExpansion
import SwiftSyntaxMacros
import SwiftSyntaxMacrosGenericTestSupport
import Testing

private let symbolMacroSpecs: [String: MacroSpec] = [
  "JS": MacroSpec(type: JSMacro.self),
  "ExpoModule": MacroSpec(type: ExpoModuleMacro.self, conformances: ["AnyModule"]),
  "SharedObject": MacroSpec(type: SharedObjectMacro.self),
]

private func assertExpansion(
  _ original: String,
  expandedSource expected: String,
  diagnostics: [DiagnosticSpec] = [],
  fileID: StaticString = #fileID,
  filePath: StaticString = #filePath,
  line: UInt = #line,
  column: UInt = #column
) {
  assertMacroExpansion(
    original,
    expandedSource: expected,
    diagnostics: diagnostics,
    macroSpecs: symbolMacroSpecs,
    indentationWidth: .spaces(2),
    failureHandler: recordIssue,
    fileID: fileID,
    filePath: filePath,
    line: line,
    column: column
  )
}

@Suite("@JS(symbol:)")
struct JSSymbolTests {
  @Test
  func `Shared object members bind under well-known and registered symbols`() {
    assertExpansion(
      """
      @SharedObject
      public final class Cache: SharedObject {
        @JS(symbol: .iterator)
        func makeIterator() -> JavaScriptObject { fatalError() }

        @JS(symbol: .toStringTag)
        var tag: String { "Cache" }

        @JS(symbol: "app.id")
        var id: String = ""

        @JS(symbol: .hasInstance)
        static func isCache(_ value: JavaScriptValue) -> Bool { false }
      }
      """,
      expandedSource: """
        public final class Cache: SharedObject {
          @JavaScriptActor
          func makeIterator() -> JavaScriptObject { fatalError() }
          @JavaScriptActor
          var tag: String { "Cache" }
          @JavaScriptActor
          var id: String = ""
          @JavaScriptActor
          static func isCache(_ value: JavaScriptValue) -> Bool { false }

          public override class var _jsName: String {
            "Cache"
          }

          @JavaScriptActor
          public override class func _decorateSharedObject(prototype: borrowing JavaScriptObject, in runtime: JavaScriptRuntime) throws {
            try prototype.setProperty(JavaScriptSymbol.wellKnown(runtime, .iterator)) { (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer, result: borrowing JavaScriptValue.Slot, runtime: borrowing JavaScriptRuntime) in
              let _self = try SharedObject.native(from: this.asObject(in: runtime), as: Cache.self)
              guard arguments.count == 0 else {
                throw Exceptions.ArgumentsRangeMismatch((functionName: "[Symbol.iterator]", received: arguments.count, required: 0, maximum: 0))
              }
              let value = _self.makeIterator()
              try JavaScriptObject.encode(value, into: result, in: runtime)
            }
            let tagDescriptor = runtime.createObject()
            tagDescriptor.setProperty("enumerable", value: true)
            tagDescriptor.setProperty("get") { (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer, result: borrowing JavaScriptValue.Slot, runtime: borrowing JavaScriptRuntime) in
              let _self = try SharedObject.native(from: this.asObject(in: runtime), as: Cache.self)
              try String.encode(_self.tag, into: result, in: runtime)
            }
            try prototype.defineProperty(JavaScriptSymbol.wellKnown(runtime, .toStringTag), descriptor: tagDescriptor)
            let idDescriptor = runtime.createObject()
            idDescriptor.setProperty("enumerable", value: true)
            idDescriptor.setProperty("get") { (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer, result: borrowing JavaScriptValue.Slot, runtime: borrowing JavaScriptRuntime) in
              let _self = try SharedObject.native(from: this.asObject(in: runtime), as: Cache.self)
              try String.encode(_self.id, into: result, in: runtime)
            }
            idDescriptor.setProperty("set") { (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer, result: borrowing JavaScriptValue.Slot, runtime: borrowing JavaScriptRuntime) in
              let _self = try SharedObject.native(from: this.asObject(in: runtime), as: Cache.self)
              _self.id = try String.decode(arguments.unownedValue(at: 0), in: runtime)
            }
            try prototype.defineProperty(JavaScriptSymbol.for(runtime, "app.id"), descriptor: idDescriptor)
          }

          @JavaScriptActor
          public override class func _decorateSharedObject(constructor: borrowing JavaScriptObject, in runtime: JavaScriptRuntime) throws {
            try constructor.defineProperty(JavaScriptSymbol.wellKnown(runtime, .hasInstance), descriptor: .init(configurable: true, enumerable: true, writable: true))
            try constructor.setProperty(JavaScriptSymbol.wellKnown(runtime, .hasInstance)) { (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer, result: borrowing JavaScriptValue.Slot, runtime: borrowing JavaScriptRuntime) in
              guard arguments.count == 1 else {
                throw Exceptions.ArgumentsRangeMismatch((functionName: "[Symbol.hasInstance]", received: arguments.count, required: 1, maximum: 1))
              }
              let arg0 = try JavaScriptValue.decode(arguments.unownedValue(at: 0), in: runtime)
              let value = Cache.isCache(arg0)
              try Bool.encode(value, into: result, in: runtime)
            }
          }

          private func _assertTypesConformance() {
            func makeIterator(returning _: (some JavaScriptEncodable & ~Copyable).Type) {
            }
            makeIterator(returning: JavaScriptObject.self)
            func isCache(_: (some JavaScriptDecodable & ~Copyable).Type) {
            }
            isCache(JavaScriptValue.self)
          }
        }
        """
    )
  }

  @Test
  func `Module members bind under symbols, with a lazy property and an async variant`() {
    assertExpansion(
      """
      @ExpoModule
      public final class Files {
        @JS(symbol: .dispose, .withAsync("disposeAsync"))
        func dispose(force: Bool) {}

        @JS(symbol: .toStringTag)
        lazy var tag: String = "Files"
      }
      """,
      expandedSource: """
        public final class Files {
          func dispose(force: Bool) {}
          @JavaScriptActor
          lazy var tag: String = "Files"

          public static let _jsName = "Files"

          public weak var appContext: AppContext?

          public required init(appContext: AppContext) {
            self.appContext = appContext
          }

          @JavaScriptActor
          public func _decorateModule(object: borrowing JavaScriptObject, in runtime: JavaScriptRuntime) throws {
            try object.setProperty(JavaScriptSymbol.wellKnown(runtime, .dispose)) { [self] (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer) -> Void in
              guard arguments.count == 1 else {
                throw Exceptions.ArgumentsRangeMismatch((functionName: "[Symbol.dispose]", received: arguments.count, required: 1, maximum: 1))
              }
              let arg0 = try Bool.decode(arguments.unownedValue(at: 0), in: runtime)
              self.dispose(force: arg0)
            }
            object.setProperty("disposeAsync") { [self] (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer) in
              guard arguments.count == 1 else {
                throw Exceptions.ArgumentsRangeMismatch((functionName: "disposeAsync", received: arguments.count, required: 1, maximum: 1))
              }
              let arg0 = try Bool.decode(arguments.unownedValue(at: 0), in: runtime)
              return {
                await { @concurrent () async in
                  self.dispose(force: arg0)
                }()
                return .undefined()
              }
            }
            let tagDescriptor = runtime.createObject()
            tagDescriptor.setProperty("enumerable", value: true)
            tagDescriptor.setProperty("configurable", value: true)
            tagDescriptor.setProperty("get") { [self] (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer, result: borrowing JavaScriptValue.Slot, runtime: borrowing JavaScriptRuntime) in
              let value = try String.encode(self.tag, in: runtime)
              if this.isObject() {
                try this.getObject(in: runtime).defineProperty(JavaScriptSymbol.wellKnown(runtime, .toStringTag), value: value, options: [.enumerable])
              }
              result.emplace(value)
            }
            try object.defineProperty(JavaScriptSymbol.wellKnown(runtime, .toStringTag), descriptor: tagDescriptor)
          }
        }

        extension Files: AnyModule {
        }
        """
    )
  }

  @Test
  func `A subclass redefines the symbol of each function before it binds the function`() {
    assertExpansion(
      """
      @SharedObject
      public class Image: Base {
        @JS(symbol: .toPrimitive)
        func primitive(hint: String) -> String { "" }
      }
      """,
      expandedSource: """
        public class Image: Base {
          @JavaScriptActor
          func primitive(hint: String) -> String { "" }

          public override class var _jsName: String {
            "Image"
          }

          @JavaScriptActor
          public override class func _decorateSharedObject(prototype: borrowing JavaScriptObject, in runtime: JavaScriptRuntime) throws {
            try super._decorateSharedObject(prototype: prototype, in: runtime)
            try prototype.defineProperty(JavaScriptSymbol.wellKnown(runtime, .toPrimitive), descriptor: .init(configurable: true, enumerable: true, writable: true))
            try prototype.setProperty(JavaScriptSymbol.wellKnown(runtime, .toPrimitive)) { (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer, result: borrowing JavaScriptValue.Slot, runtime: borrowing JavaScriptRuntime) in
              let _self = try SharedObject.native(from: this.asObject(in: runtime), as: Image.self)
              guard arguments.count == 1 else {
                throw Exceptions.ArgumentsRangeMismatch((functionName: "[Symbol.toPrimitive]", received: arguments.count, required: 1, maximum: 1))
              }
              let arg0 = try String.decode(arguments.unownedValue(at: 0), in: runtime)
              let value = _self.primitive(hint: arg0)
              try String.encode(value, into: result, in: runtime)
            }
          }
        }
        """
    )
  }

  @Test
  func `A symbol and a string name with the same text don't collide`() {
    assertExpansion(
      """
      @SharedObject
      public final class List: SharedObject {
        @JS(symbol: .iterator)
        func makeIterator() -> Int { 0 }

        @JS
        func iterator() -> Int { 0 }
      }
      """,
      expandedSource: """
        public final class List: SharedObject {
          @JavaScriptActor
          func makeIterator() -> Int { 0 }
          @JavaScriptActor
          func iterator() -> Int { 0 }

          public override class var _jsName: String {
            "List"
          }

          @JavaScriptActor
          public override class func _decorateSharedObject(prototype: borrowing JavaScriptObject, in runtime: JavaScriptRuntime) throws {
            try prototype.setProperty(JavaScriptSymbol.wellKnown(runtime, .iterator)) { (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer, result: borrowing JavaScriptValue.Slot, runtime: borrowing JavaScriptRuntime) in
              let _self = try SharedObject.native(from: this.asObject(in: runtime), as: List.self)
              guard arguments.count == 0 else {
                throw Exceptions.ArgumentsRangeMismatch((functionName: "[Symbol.iterator]", received: arguments.count, required: 0, maximum: 0))
              }
              let value = _self.makeIterator()
              try Int.encode(value, into: result, in: runtime)
            }
            prototype.setProperty("iterator") { (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer, result: borrowing JavaScriptValue.Slot, runtime: borrowing JavaScriptRuntime) in
              let _self = try SharedObject.native(from: this.asObject(in: runtime), as: List.self)
              guard arguments.count == 0 else {
                throw Exceptions.ArgumentsRangeMismatch((functionName: "iterator", received: arguments.count, required: 0, maximum: 0))
              }
              let value = _self.iterator()
              try Int.encode(value, into: result, in: runtime)
            }
          }
        }
        """
    )
  }

  @Test
  func `Two members under the same symbol collide`() {
    assertExpansion(
      """
      @SharedObject
      public final class List: SharedObject {
        @JS(symbol: "app.id")
        var id: String = ""

        @JS(symbol: "app.id")
        func identifier() -> String { "" }
      }
      """,
      expandedSource: """
        public final class List: SharedObject {
          @JavaScriptActor
          var id: String = ""
          @JavaScriptActor
          func identifier() -> String { "" }

          public override class var _jsName: String {
            "List"
          }

          @JavaScriptActor
          public override class func _decorateSharedObject(prototype: borrowing JavaScriptObject, in runtime: JavaScriptRuntime) throws {
            try prototype.setProperty(JavaScriptSymbol.for(runtime, "app.id")) { (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer, result: borrowing JavaScriptValue.Slot, runtime: borrowing JavaScriptRuntime) in
              let _self = try SharedObject.native(from: this.asObject(in: runtime), as: List.self)
              guard arguments.count == 0 else {
                throw Exceptions.ArgumentsRangeMismatch((functionName: "[app.id]", received: arguments.count, required: 0, maximum: 0))
              }
              let value = _self.identifier()
              try String.encode(value, into: result, in: runtime)
            }
            let idDescriptor = runtime.createObject()
            idDescriptor.setProperty("enumerable", value: true)
            idDescriptor.setProperty("get") { (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer, result: borrowing JavaScriptValue.Slot, runtime: borrowing JavaScriptRuntime) in
              let _self = try SharedObject.native(from: this.asObject(in: runtime), as: List.self)
              try String.encode(_self.id, into: result, in: runtime)
            }
            idDescriptor.setProperty("set") { (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer, result: borrowing JavaScriptValue.Slot, runtime: borrowing JavaScriptRuntime) in
              let _self = try SharedObject.native(from: this.asObject(in: runtime), as: List.self)
              _self.id = try String.decode(arguments.unownedValue(at: 0), in: runtime)
            }
            try prototype.defineProperty(JavaScriptSymbol.for(runtime, "app.id"), descriptor: idDescriptor)
          }
        }
        """,
      diagnostics: [
        DiagnosticSpec(
          message:
            "The JavaScript symbol 'Symbol.for(\"app.id\")' is already bound by an earlier @JS property. A JavaScript object holds one member per symbol, so JavaScript could reach only one of them. Give one of them another symbol with @JS(symbol: ...).",
          line: 7,
          column: 8,
          severity: .error,
          notes: [NoteSpec(message: "'Symbol.for(\"app.id\")' is first bound here", line: 4, column: 7)]
        )
      ]
    )
  }

  @Test
  func `A symbol on an initializer is an error`() {
    assertExpansion(
      """
      @SharedObject
      public final class List: SharedObject {
        @JS(symbol: .iterator)
        init() {}
      }
      """,
      expandedSource: """
        public final class List: SharedObject {
          @JavaScriptActor
          init() {}

          public override class var _jsName: String {
            "List"
          }

          @JavaScriptActor
          public override class func _constructSharedObject(this: borrowing JavaScriptValue, arguments: borrowing JavaScriptValuesBuffer, in runtime: JavaScriptRuntime) throws -> SharedObject? {
            guard arguments.count == 0 else {
              throw Exceptions.ArgumentsRangeMismatch((functionName: "List", received: arguments.count, required: 0, maximum: 0))
            }
            return List()
          }
        }
        """,
      diagnostics: [
        DiagnosticSpec(
          message:
            "'symbol:' applies only to a @JS function or property: JavaScript constructs a shared object with 'new', so an initializer isn't bound under a key.",
          line: 3,
          column: 7,
          severity: .error
        )
      ]
    )
  }

  @Test
  func `A symbol that isn't a literal is an error`() {
    assertExpansion(
      """
      @SharedObject
      public final class List: SharedObject {
        @JS(symbol: "app.\\(name)")
        func id() -> Int { 0 }

        @JS(symbol: key)
        func other() -> Int { 0 }

        @JS(symbol: Keys.iterator)
        func constant() -> Int { 0 }
      }
      """,
      expandedSource: """
        public final class List: SharedObject {
          @JavaScriptActor
          func id() -> Int { 0 }
          @JavaScriptActor
          func other() -> Int { 0 }
          @JavaScriptActor
          func constant() -> Int { 0 }

          public override class var _jsName: String {
            "List"
          }

          @JavaScriptActor
          public override class func _decorateSharedObject(prototype: borrowing JavaScriptObject, in runtime: JavaScriptRuntime) throws {
            prototype.setProperty("id") { (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer, result: borrowing JavaScriptValue.Slot, runtime: borrowing JavaScriptRuntime) in
              let _self = try SharedObject.native(from: this.asObject(in: runtime), as: List.self)
              guard arguments.count == 0 else {
                throw Exceptions.ArgumentsRangeMismatch((functionName: "id", received: arguments.count, required: 0, maximum: 0))
              }
              let value = _self.id()
              try Int.encode(value, into: result, in: runtime)
            }
            prototype.setProperty("other") { (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer, result: borrowing JavaScriptValue.Slot, runtime: borrowing JavaScriptRuntime) in
              let _self = try SharedObject.native(from: this.asObject(in: runtime), as: List.self)
              guard arguments.count == 0 else {
                throw Exceptions.ArgumentsRangeMismatch((functionName: "other", received: arguments.count, required: 0, maximum: 0))
              }
              let value = _self.other()
              try Int.encode(value, into: result, in: runtime)
            }
            prototype.setProperty("constant") { (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer, result: borrowing JavaScriptValue.Slot, runtime: borrowing JavaScriptRuntime) in
              let _self = try SharedObject.native(from: this.asObject(in: runtime), as: List.self)
              guard arguments.count == 0 else {
                throw Exceptions.ArgumentsRangeMismatch((functionName: "constant", received: arguments.count, required: 0, maximum: 0))
              }
              let value = _self.constant()
              try Int.encode(value, into: result, in: runtime)
            }
          }
        }
        """,
      diagnostics: [
        DiagnosticSpec(
          message:
            "'symbol:' takes a well-known symbol, such as '.iterator', or the registry key of 'Symbol.for' as a string literal, such as \"app.id\". The macro reads the argument from the source, so it can't be a variable, a constant or an interpolated string.",
          line: 3,
          column: 15,
          severity: .error
        ),
        DiagnosticSpec(
          message:
            "'symbol:' takes a well-known symbol, such as '.iterator', or the registry key of 'Symbol.for' as a string literal, such as \"app.id\". The macro reads the argument from the source, so it can't be a variable, a constant or an interpolated string.",
          line: 6,
          column: 15,
          severity: .error
        ),
        DiagnosticSpec(
          message:
            "'symbol:' takes a well-known symbol, such as '.iterator', or the registry key of 'Symbol.for' as a string literal, such as \"app.id\". The macro reads the argument from the source, so it can't be a variable, a constant or an interpolated string.",
          line: 9,
          column: 15,
          severity: .error
        ),
      ]
    )
  }

  @Test
  func `A registered symbol is the value of the literal, escaped again in the generated code`() {
    assertExpansion(
      #"""
      @SharedObject
      public final class List: SharedObject {
        @JS(symbol: #"app."id""#)
        func id() -> Int { 0 }
      }
      """#,
      expandedSource: #"""
        public final class List: SharedObject {
          @JavaScriptActor
          func id() -> Int { 0 }

          public override class var _jsName: String {
            "List"
          }

          @JavaScriptActor
          public override class func _decorateSharedObject(prototype: borrowing JavaScriptObject, in runtime: JavaScriptRuntime) throws {
            try prototype.setProperty(JavaScriptSymbol.for(runtime, "app.\"id\"")) { (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer, result: borrowing JavaScriptValue.Slot, runtime: borrowing JavaScriptRuntime) in
              let _self = try SharedObject.native(from: this.asObject(in: runtime), as: List.self)
              guard arguments.count == 0 else {
                throw Exceptions.ArgumentsRangeMismatch((functionName: "[app.\"id\"]", received: arguments.count, required: 0, maximum: 0))
              }
              let value = _self.id()
              try Int.encode(value, into: result, in: runtime)
            }
          }
        }
        """#
    )
  }

  @Test
  func `Two literals with the same value name the same registered symbol`() {
    assertExpansion(
      #"""
      @SharedObject
      public final class List: SharedObject {
        @JS(symbol: "app.id")
        func id() -> Int { 0 }

        @JS(symbol: "app.\u{69}d")
        func other() -> Int { 0 }
      }
      """#,
      expandedSource: #"""
        public final class List: SharedObject {
          @JavaScriptActor
          func id() -> Int { 0 }
          @JavaScriptActor
          func other() -> Int { 0 }

          public override class var _jsName: String {
            "List"
          }

          @JavaScriptActor
          public override class func _decorateSharedObject(prototype: borrowing JavaScriptObject, in runtime: JavaScriptRuntime) throws {
            try prototype.setProperty(JavaScriptSymbol.for(runtime, "app.id")) { (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer, result: borrowing JavaScriptValue.Slot, runtime: borrowing JavaScriptRuntime) in
              let _self = try SharedObject.native(from: this.asObject(in: runtime), as: List.self)
              guard arguments.count == 0 else {
                throw Exceptions.ArgumentsRangeMismatch((functionName: "[app.id]", received: arguments.count, required: 0, maximum: 0))
              }
              let value = _self.id()
              try Int.encode(value, into: result, in: runtime)
            }
            try prototype.setProperty(JavaScriptSymbol.for(runtime, "app.id")) { (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer, result: borrowing JavaScriptValue.Slot, runtime: borrowing JavaScriptRuntime) in
              let _self = try SharedObject.native(from: this.asObject(in: runtime), as: List.self)
              guard arguments.count == 0 else {
                throw Exceptions.ArgumentsRangeMismatch((functionName: "[app.id]", received: arguments.count, required: 0, maximum: 0))
              }
              let value = _self.other()
              try Int.encode(value, into: result, in: runtime)
            }
          }
        }
        """#,
      diagnostics: [
        DiagnosticSpec(
          message:
            "The JavaScript symbol 'Symbol.for(\"app.id\")' is already bound by an earlier @JS function. A JavaScript object holds one member per symbol, so JavaScript could reach only one of them. Give one of them another symbol with @JS(symbol: ...).",
          line: 7,
          column: 8,
          severity: .error,
          notes: [NoteSpec(message: "'Symbol.for(\"app.id\")' is first bound here", line: 4, column: 8)]
        )
      ]
    )
  }
}
