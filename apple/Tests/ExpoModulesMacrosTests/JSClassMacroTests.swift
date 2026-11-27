import ExpoModulesMacrosCore
import SwiftSyntax
import SwiftSyntaxMacroExpansion
import SwiftSyntaxMacros
import SwiftSyntaxMacrosGenericTestSupport
import Testing

/// The conformances that the compiler passes for a root class, which conforms to none of them yet.
private let rootConformances: [TypeSyntax] = [
  "AnyJavaScriptClass", "AnySharedObject", "JavaScriptDecodable", "Sendable",
]

/// The conformances that the compiler passes for a subclass of a `@JSClass` class, which isn't a shared
/// object.
private let subclassConformances: [TypeSyntax] = ["AnySharedObject"]

/// The macros of the tests, with `@JSClass` getting `conformances`. The compiler passes only the
/// conformances that the class doesn't have yet, so a test of a subclass passes fewer.
private func macroSpecs(jsClassConformances conformances: [TypeSyntax]) -> [String: MacroSpec] {
  return [
    "JS": MacroSpec(type: JSMacro.self),
    "JSClass": MacroSpec(type: JSClassMacro.self, conformances: conformances),
    "SharedObject": MacroSpec(type: SharedObjectMacro.self),
    "Event": MacroSpec(type: EventMacro.self),
  ]
}

private func assertExpansion(
  _ original: String,
  expandedSource expected: String,
  conformances: [TypeSyntax] = rootConformances,
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
    macroSpecs: macroSpecs(jsClassConformances: conformances),
    fixedSource: fixedSource,
    indentationWidth: .spaces(2),
    failureHandler: recordIssue,
    fileID: fileID,
    filePath: filePath,
    line: line,
    column: column
  )
}

@Suite("@JSClass macro")
struct JSClassMacroTests {
  @Test
  func `A root class implements the hooks, returns nil from the constructor and gets the root conformances`() {
    assertExpansion(
      """
      @JSClass
      public final class Point {
      }
      """,
      expandedSource: """
        public final class Point {

          nonisolated public class var _jsName: String {
            "Point"
          }

          nonisolated public class var _jsClassType: (any AnyJavaScriptClass.Type)? {
            Point.self
          }

          nonisolated public class var _jsSuperclassType: (any AnyJavaScriptClass.Type)? {
            nil
          }

          @JavaScriptActor
          public class func _decorateClass(prototype: borrowing JavaScriptObject, in runtime: JavaScriptRuntime) throws {
          }

          @JavaScriptActor
          public class func _decorateClass(constructor: borrowing JavaScriptObject, in runtime: JavaScriptRuntime) throws {
          }

          @JavaScriptActor
          public class func _constructInstance(this: borrowing JavaScriptValue, arguments: borrowing JavaScriptValuesBuffer, in runtime: JavaScriptRuntime) throws -> (any AnyJavaScriptClass)? {
            return nil
          }
        }

        extension Point: nonisolated AnyJavaScriptClass, nonisolated JavaScriptDecodable {
        }

        extension Point: @unchecked Sendable {
        }
        """
    )
  }

  @Test
  func `An open root has open hooks, binds its members through _native(from:) and guards its constructor`() {
    assertExpansion(
      """
      @JSClass("Shape2D")
      open class Shape {
        @JS
        init(name: String) {}

        @JS
        func area() -> Double { 0 }

        @JS
        static func unit() -> Double { 1 }
      }
      """,
      expandedSource: """
        open class Shape {
          @JavaScriptActor
          init(name: String) {}
          @JavaScriptActor
          func area() -> Double { 0 }
          @JavaScriptActor
          static func unit() -> Double { 1 }

          nonisolated open class var _jsName: String {
            "Shape2D"
          }

          nonisolated open class var _jsClassType: (any AnyJavaScriptClass.Type)? {
            Shape.self
          }

          nonisolated open class var _jsSuperclassType: (any AnyJavaScriptClass.Type)? {
            nil
          }

          @JavaScriptActor
          open class func _decorateClass(prototype: borrowing JavaScriptObject, in runtime: JavaScriptRuntime) throws {
            prototype.setProperty("area") { (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer, result: borrowing JavaScriptValue.Slot, runtime: borrowing JavaScriptRuntime) in
              let _self = try Shape._native(from: this.asObject(in: runtime))
              guard arguments.count == 0 else {
                throw Exceptions.ArgumentsRangeMismatch((functionName: "area", received: arguments.count, required: 0, maximum: 0))
              }
              let value = _self.area()
              try Double.encode(value, into: result, in: runtime)
            }
          }

          @JavaScriptActor
          open class func _decorateClass(constructor: borrowing JavaScriptObject, in runtime: JavaScriptRuntime) throws {
            constructor.setProperty("unit") { (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer, result: borrowing JavaScriptValue.Slot, runtime: borrowing JavaScriptRuntime) in
              guard arguments.count == 0 else {
                throw Exceptions.ArgumentsRangeMismatch((functionName: "unit", received: arguments.count, required: 0, maximum: 0))
              }
              let value = Shape.unit()
              try Double.encode(value, into: result, in: runtime)
            }
          }

          @JavaScriptActor
          open class func _constructInstance(this: borrowing JavaScriptValue, arguments: borrowing JavaScriptValuesBuffer, in runtime: JavaScriptRuntime) throws -> (any AnyJavaScriptClass)? {
            guard self == Shape.self else {
              return nil
            }
            guard arguments.count == 1 else {
              throw Exceptions.ArgumentsRangeMismatch((functionName: "Shape2D", received: arguments.count, required: 1, maximum: 1))
            }
            let arg0 = try String.decode(arguments.unownedValue(at: 0), in: runtime)
            return Shape(name: arg0)
          }
        }

        extension Shape: nonisolated AnyJavaScriptClass, nonisolated JavaScriptDecodable {
        }

        extension Shape: @unchecked Sendable {
        }
        """
    )
  }

  @Test
  func `A subclass overrides the hooks, defines its functions first and has no constructor without a @JS init`() {
    // The compiler passes only `AnySharedObject`: the superclass has the other conformances.
    assertExpansion(
      """
      @JSClass
      public final class Circle: Shape {
        @JS
        func area() -> Double { 3 }
      }
      """,
      expandedSource: """
        public final class Circle: Shape {
          @JavaScriptActor
          func area() -> Double { 3 }

          public override class var _jsName: String {
            "Circle"
          }

          public override class var _jsClassType: (any AnyJavaScriptClass.Type)? {
            Circle.self
          }

          public override class var _jsSuperclassType: (any AnyJavaScriptClass.Type)? {
            super._jsClassType
          }

          @JavaScriptActor
          public override class func _decorateClass(prototype: borrowing JavaScriptObject, in runtime: JavaScriptRuntime) throws {
            prototype.defineProperty("area", descriptor: .init(configurable: true, enumerable: true, writable: true))
            prototype.setProperty("area") { (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer, result: borrowing JavaScriptValue.Slot, runtime: borrowing JavaScriptRuntime) in
              let _self = try Circle._native(from: this.asObject(in: runtime))
              guard arguments.count == 0 else {
                throw Exceptions.ArgumentsRangeMismatch((functionName: "area", received: arguments.count, required: 0, maximum: 0))
              }
              let value = _self.area()
              try Double.encode(value, into: result, in: runtime)
            }
          }

          @JavaScriptActor
          public override class func _decorateClass(constructor: borrowing JavaScriptObject, in runtime: JavaScriptRuntime) throws {
          }
        }
        """,
      conformances: subclassConformances,
      diagnostics: [
        // The class is `final`, and the constructor of `Shape` doesn't construct a subclass.
        DiagnosticSpec(
          message:
            "'Circle' has instance @JS members but no @JS initializer, and JavaScript gets an instance of this class only from its constructor. Add a @JS init, or make the members static",
          line: 2,
          column: 20,
          severity: .warning
        )
      ]
    )
  }

  @Test
  func `A subclass with a @JS init overrides the constructor of its root`() {
    assertExpansion(
      """
      @JSClass
      public final class Square: Shape {
        @JS
        init(side: Double) {}
      }
      """,
      expandedSource: """
        public final class Square: Shape {
          @JavaScriptActor
          init(side: Double) {}

          public override class var _jsName: String {
            "Square"
          }

          public override class var _jsClassType: (any AnyJavaScriptClass.Type)? {
            Square.self
          }

          public override class var _jsSuperclassType: (any AnyJavaScriptClass.Type)? {
            super._jsClassType
          }

          @JavaScriptActor
          public override class func _decorateClass(prototype: borrowing JavaScriptObject, in runtime: JavaScriptRuntime) throws {
          }

          @JavaScriptActor
          public override class func _decorateClass(constructor: borrowing JavaScriptObject, in runtime: JavaScriptRuntime) throws {
          }

          @JavaScriptActor
          public override class func _constructInstance(this: borrowing JavaScriptValue, arguments: borrowing JavaScriptValuesBuffer, in runtime: JavaScriptRuntime) throws -> (any AnyJavaScriptClass)? {
            guard arguments.count == 1 else {
              throw Exceptions.ArgumentsRangeMismatch((functionName: "Square", received: arguments.count, required: 1, maximum: 1))
            }
            let arg0 = try Double.decode(arguments.unownedValue(at: 0), in: runtime)
            return Square(side: arg0)
          }
        }
        """,
      conformances: subclassConformances
    )
  }

  @Test
  func `A class that names AnyJavaScriptClass is a root and gets only the conformances it doesn't name`() {
    // The compiler leaves out `AnyJavaScriptClass`, which the clause names, and `Sendable`.
    assertExpansion(
      """
      @JSClass
      public final class Point: AnyJavaScriptClass, @unchecked Sendable {
      }
      """,
      expandedSource: """
        public final class Point: AnyJavaScriptClass, @unchecked Sendable {

          nonisolated public class var _jsName: String {
            "Point"
          }

          nonisolated public class var _jsClassType: (any AnyJavaScriptClass.Type)? {
            Point.self
          }

          nonisolated public class var _jsSuperclassType: (any AnyJavaScriptClass.Type)? {
            nil
          }

          @JavaScriptActor
          public class func _decorateClass(prototype: borrowing JavaScriptObject, in runtime: JavaScriptRuntime) throws {
          }

          @JavaScriptActor
          public class func _decorateClass(constructor: borrowing JavaScriptObject, in runtime: JavaScriptRuntime) throws {
          }

          @JavaScriptActor
          public class func _constructInstance(this: borrowing JavaScriptValue, arguments: borrowing JavaScriptValuesBuffer, in runtime: JavaScriptRuntime) throws -> (any AnyJavaScriptClass)? {
            return nil
          }
        }

        extension Point: nonisolated JavaScriptDecodable {
        }
        """,
      conformances: ["AnySharedObject", "JavaScriptDecodable"]
    )
  }

  @Test
  func `On a SharedObject subclass, reports an error with a fix-it that uses @SharedObject and keeps the name`() {
    // `SharedObject` has the root conformances and `AnySharedObject`, but isn't `Sendable`.
    assertExpansion(
      """
      @JSClass("Store")
      public final class Storage: SharedObject {
      }
      """,
      expandedSource: """
        public final class Storage: SharedObject {
        }
        """,
      conformances: ["Sendable"],
      diagnostics: [
        DiagnosticSpec(
          message:
            "A @JSClass class can't be a shared object, and this class inherits from one. Use @SharedObject instead of @JSClass",
          line: 1,
          column: 1,
          fixIts: [FixItSpec(message: "Use '@SharedObject'")]
        )
      ],
      fixedSource: """
        @SharedObject("Store")
        public final class Storage: SharedObject {
        }
        """
    )
  }

  @Test
  func `Reports a class below a shared object, which the compiler tells by leaving out AnySharedObject`() {
    // `Store` has `@SharedObject`, so the class has every conformance already. Its clause doesn't name
    // a shared object base.
    assertExpansion(
      """
      @JSClass
      public final class Cache: Store {
      }
      """,
      expandedSource: """
        public final class Cache: Store {
        }
        """,
      conformances: [],
      diagnostics: [
        DiagnosticSpec(
          message:
            "A @JSClass class can't be a shared object, and this class inherits from one. Use @SharedObject instead of @JSClass",
          line: 1,
          column: 1,
          fixIts: [FixItSpec(message: "Use '@SharedObject'")]
        )
      ],
      fixedSource: """
        @SharedObject
        public final class Cache: Store {
        }
        """
    )
  }

  @Test
  func `With @SharedObject on the same class, adds nothing and @SharedObject reports the class`() {
    assertExpansion(
      """
      @JSClass
      @SharedObject
      public final class Cache: SharedObject {
      }
      """,
      expandedSource: """
        public final class Cache: SharedObject {
        }
        """,
      conformances: ["Sendable"],
      diagnostics: [
        DiagnosticSpec(
          message:
            "A @SharedObject class can't also have @JSClass: @SharedObject gives the class its JavaScript class. Remove @JSClass",
          line: 1,
          column: 1,
          fixIts: [FixItSpec(message: "Remove '@JSClass'")]
        )
      ],
      fixedSource: """
        @SharedObject
        public final class Cache: SharedObject {
        }
        """
    )
  }

  @Test
  func `Warns about a class that isn't public, with a fix-it that makes it public`() {
    assertExpansion(
      """
      @JSClass
      final class Point: AnyJavaScriptClass, @unchecked Sendable {
      }
      """,
      expandedSource: """
        final class Point: AnyJavaScriptClass, @unchecked Sendable {

          nonisolated public class var _jsName: String {
            "Point"
          }

          nonisolated public class var _jsClassType: (any AnyJavaScriptClass.Type)? {
            Point.self
          }

          nonisolated public class var _jsSuperclassType: (any AnyJavaScriptClass.Type)? {
            nil
          }

          @JavaScriptActor
          public class func _decorateClass(prototype: borrowing JavaScriptObject, in runtime: JavaScriptRuntime) throws {
          }

          @JavaScriptActor
          public class func _decorateClass(constructor: borrowing JavaScriptObject, in runtime: JavaScriptRuntime) throws {
          }

          @JavaScriptActor
          public class func _constructInstance(this: borrowing JavaScriptValue, arguments: borrowing JavaScriptValuesBuffer, in runtime: JavaScriptRuntime) throws -> (any AnyJavaScriptClass)? {
            return nil
          }
        }
        """,
      conformances: subclassConformances,
      diagnostics: [
        DiagnosticSpec(
          message:
            "@JSClass class 'Point' should be public or open, so that the modules provider that autolinking generates in the app target can export it",
          line: 2,
          column: 7,
          severity: .warning,
          fixIts: [FixItSpec(message: "Make the class 'public'")]
        )
      ],
      fixedSource: """
        @JSClass
        public final class Point: AnyJavaScriptClass, @unchecked Sendable {
        }
        """
    )
  }

  @Test
  func `Reports a declaration that isn't a class`() {
    assertExpansion(
      """
      @JSClass
      public struct Point {
      }
      """,
      expandedSource: """
        public struct Point {
        }
        """,
      diagnostics: [
        DiagnosticSpec(message: "@JSClass can only be applied to a class", line: 1, column: 1)
      ]
    )
  }

  @Test
  func `Reports a second @JS initializer on it, and binds the first without a guard in a final class`() {
    assertExpansion(
      """
      @JSClass
      public final class Point {
        @JS
        init() {}

        @JS
        init(x: Double) {}
      }
      """,
      expandedSource: """
        public final class Point {
          @JavaScriptActor
          init() {}
          @JavaScriptActor
          init(x: Double) {}

          nonisolated public class var _jsName: String {
            "Point"
          }

          nonisolated public class var _jsClassType: (any AnyJavaScriptClass.Type)? {
            Point.self
          }

          nonisolated public class var _jsSuperclassType: (any AnyJavaScriptClass.Type)? {
            nil
          }

          @JavaScriptActor
          public class func _decorateClass(prototype: borrowing JavaScriptObject, in runtime: JavaScriptRuntime) throws {
          }

          @JavaScriptActor
          public class func _decorateClass(constructor: borrowing JavaScriptObject, in runtime: JavaScriptRuntime) throws {
          }

          @JavaScriptActor
          public class func _constructInstance(this: borrowing JavaScriptValue, arguments: borrowing JavaScriptValuesBuffer, in runtime: JavaScriptRuntime) throws -> (any AnyJavaScriptClass)? {
            guard arguments.count == 0 else {
              throw Exceptions.ArgumentsRangeMismatch((functionName: "Point", received: arguments.count, required: 0, maximum: 0))
            }
            return Point()
          }
        }

        extension Point: nonisolated AnyJavaScriptClass, nonisolated JavaScriptDecodable {
        }

        extension Point: @unchecked Sendable {
        }
        """,
      diagnostics: [
        DiagnosticSpec(
          message:
            "@JSClass classes can have at most one @JS initializer: JavaScript classes have a single constructor",
          line: 6,
          column: 3
        )
      ]
    )
  }

  @Test
  func `A throwing @JS init with trailing optional and defaulted parameters emits try and arity dispatch`() {
    assertExpansion(
      """
      @JSClass
      public final class `Class` {
        @JS
        init(name: String, tag: String?, limit: Int = 10) throws {}
      }
      """,
      expandedSource: """
        public final class `Class` {
          @JavaScriptActor
          init(name: String, tag: String?, limit: Int = 10) throws {}

          nonisolated public class var _jsName: String {
            "Class"
          }

          nonisolated public class var _jsClassType: (any AnyJavaScriptClass.Type)? {
            `Class`.self
          }

          nonisolated public class var _jsSuperclassType: (any AnyJavaScriptClass.Type)? {
            nil
          }

          @JavaScriptActor
          public class func _decorateClass(prototype: borrowing JavaScriptObject, in runtime: JavaScriptRuntime) throws {
          }

          @JavaScriptActor
          public class func _decorateClass(constructor: borrowing JavaScriptObject, in runtime: JavaScriptRuntime) throws {
          }

          @JavaScriptActor
          public class func _constructInstance(this: borrowing JavaScriptValue, arguments: borrowing JavaScriptValuesBuffer, in runtime: JavaScriptRuntime) throws -> (any AnyJavaScriptClass)? {
            guard arguments.count >= 1 && arguments.count <= 3 else {
              throw Exceptions.ArgumentsRangeMismatch((functionName: "Class", received: arguments.count, required: 1, maximum: 3))
            }
            let arg0 = try String.decode(arguments.unownedValue(at: 0), in: runtime)
            switch arguments.count {
            case 1:
              return try `Class`(name: arg0, tag: nil)
            case 2:
              let arg1 = try String?.decode(arguments.unownedValue(at: 1), in: runtime)
              return try `Class`(name: arg0, tag: arg1)
            default:
              let arg1 = try String?.decode(arguments.unownedValue(at: 1), in: runtime)
              let arg2 = try Int.decode(arguments.unownedValue(at: 2), in: runtime)
              return try `Class`(name: arg0, tag: arg1, limit: arg2)
            }
          }
        }

        extension `Class`: nonisolated AnyJavaScriptClass, nonisolated JavaScriptDecodable {
        }

        extension `Class`: @unchecked Sendable {
        }
        """
    )
  }

  @Test
  func `Reports a failable @JS init and leaves it unbound without a missing-initializer warning`() {
    assertExpansion(
      """
      @JSClass
      public final class Token {
        @JS
        init?(raw: String) {}

        @JS
        func read() -> String { "" }
      }
      """,
      expandedSource: """
        public final class Token {
          @JavaScriptActor
          init?(raw: String) {}
          @JavaScriptActor
          func read() -> String { "" }

          nonisolated public class var _jsName: String {
            "Token"
          }

          nonisolated public class var _jsClassType: (any AnyJavaScriptClass.Type)? {
            Token.self
          }

          nonisolated public class var _jsSuperclassType: (any AnyJavaScriptClass.Type)? {
            nil
          }

          @JavaScriptActor
          public class func _decorateClass(prototype: borrowing JavaScriptObject, in runtime: JavaScriptRuntime) throws {
            prototype.setProperty("read") { (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer, result: borrowing JavaScriptValue.Slot, runtime: borrowing JavaScriptRuntime) in
              let _self = try Token._native(from: this.asObject(in: runtime))
              guard arguments.count == 0 else {
                throw Exceptions.ArgumentsRangeMismatch((functionName: "read", received: arguments.count, required: 0, maximum: 0))
              }
              let value = _self.read()
              try String.encode(value, into: result, in: runtime)
            }
          }

          @JavaScriptActor
          public class func _decorateClass(constructor: borrowing JavaScriptObject, in runtime: JavaScriptRuntime) throws {
          }

          @JavaScriptActor
          public class func _constructInstance(this: borrowing JavaScriptValue, arguments: borrowing JavaScriptValuesBuffer, in runtime: JavaScriptRuntime) throws -> (any AnyJavaScriptClass)? {
            return nil
          }
        }

        extension Token: nonisolated AnyJavaScriptClass, nonisolated JavaScriptDecodable {
        }

        extension Token: @unchecked Sendable {
        }
        """,
      diagnostics: [
        DiagnosticSpec(
          message:
            "A @JS initializer can't be failable: throw an error from a throwing initializer instead, since returning 'nil' can't be distinguished from a class without a JavaScript constructor",
          line: 5,
          column: 7
        )
      ]
    )
  }

  @Test
  func `An unlabeled defaulted parameter before an unlabeled optional stays required to avoid positional mismatch`() {
    assertExpansion(
      """
      @JSClass
      public final class Range {
        @JS
        init(_ start: Int = 0, _ label: String?) {}
      }
      """,
      expandedSource: """
        public final class Range {
          @JavaScriptActor
          init(_ start: Int = 0, _ label: String?) {}

          nonisolated public class var _jsName: String {
            "Range"
          }

          nonisolated public class var _jsClassType: (any AnyJavaScriptClass.Type)? {
            Range.self
          }

          nonisolated public class var _jsSuperclassType: (any AnyJavaScriptClass.Type)? {
            nil
          }

          @JavaScriptActor
          public class func _decorateClass(prototype: borrowing JavaScriptObject, in runtime: JavaScriptRuntime) throws {
          }

          @JavaScriptActor
          public class func _decorateClass(constructor: borrowing JavaScriptObject, in runtime: JavaScriptRuntime) throws {
          }

          @JavaScriptActor
          public class func _constructInstance(this: borrowing JavaScriptValue, arguments: borrowing JavaScriptValuesBuffer, in runtime: JavaScriptRuntime) throws -> (any AnyJavaScriptClass)? {
            guard arguments.count >= 1 && arguments.count <= 2 else {
              throw Exceptions.ArgumentsRangeMismatch((functionName: "Range", received: arguments.count, required: 1, maximum: 2))
            }
            let arg0 = try Int.decode(arguments.unownedValue(at: 0), in: runtime)
            switch arguments.count {
            case 1:
              return Range(arg0, nil)
            default:
              let arg1 = try String?.decode(arguments.unownedValue(at: 1), in: runtime)
              return Range(arg0, arg1)
            }
          }
        }

        extension Range: nonisolated AnyJavaScriptClass, nonisolated JavaScriptDecodable {
        }

        extension Range: @unchecked Sendable {
        }
        """
    )
  }

  @Test
  func `Reports an async @JS init and leaves it unbound`() {
    assertExpansion(
      """
      @JSClass
      public final class Client {
        @JS
        init(url: String) async {}
      }
      """,
      expandedSource: """
        public final class Client {
          @JavaScriptActor
          init(url: String) async {}

          nonisolated public class var _jsName: String {
            "Client"
          }

          nonisolated public class var _jsClassType: (any AnyJavaScriptClass.Type)? {
            Client.self
          }

          nonisolated public class var _jsSuperclassType: (any AnyJavaScriptClass.Type)? {
            nil
          }

          @JavaScriptActor
          public class func _decorateClass(prototype: borrowing JavaScriptObject, in runtime: JavaScriptRuntime) throws {
          }

          @JavaScriptActor
          public class func _decorateClass(constructor: borrowing JavaScriptObject, in runtime: JavaScriptRuntime) throws {
          }

          @JavaScriptActor
          public class func _constructInstance(this: borrowing JavaScriptValue, arguments: borrowing JavaScriptValuesBuffer, in runtime: JavaScriptRuntime) throws -> (any AnyJavaScriptClass)? {
            return nil
          }
        }

        extension Client: nonisolated AnyJavaScriptClass, nonisolated JavaScriptDecodable {
        }

        extension Client: @unchecked Sendable {
        }
        """,
      diagnostics: [
        DiagnosticSpec(
          message:
            "A @JS initializer can't be 'async': JavaScript constructors run synchronously. Expose a static async @JS factory function instead",
          line: 5,
          column: 21
        )
      ]
    )
  }

  @Test
  func `Warns about a final class with instance @JS members but no @JS init`() {
    assertExpansion(
      """
      @JSClass
      public final class Timer {
        @JS
        func start() {}
      }
      """,
      expandedSource: """
        public final class Timer {
          @JavaScriptActor
          func start() {}

          nonisolated public class var _jsName: String {
            "Timer"
          }

          nonisolated public class var _jsClassType: (any AnyJavaScriptClass.Type)? {
            Timer.self
          }

          nonisolated public class var _jsSuperclassType: (any AnyJavaScriptClass.Type)? {
            nil
          }

          @JavaScriptActor
          public class func _decorateClass(prototype: borrowing JavaScriptObject, in runtime: JavaScriptRuntime) throws {
            prototype.setProperty("start") { (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer, result: borrowing JavaScriptValue.Slot, runtime: borrowing JavaScriptRuntime) in
              let _self = try Timer._native(from: this.asObject(in: runtime))
              guard arguments.count == 0 else {
                throw Exceptions.ArgumentsRangeMismatch((functionName: "start", received: arguments.count, required: 0, maximum: 0))
              }
              _self.start()
            }
          }

          @JavaScriptActor
          public class func _decorateClass(constructor: borrowing JavaScriptObject, in runtime: JavaScriptRuntime) throws {
          }

          @JavaScriptActor
          public class func _constructInstance(this: borrowing JavaScriptValue, arguments: borrowing JavaScriptValuesBuffer, in runtime: JavaScriptRuntime) throws -> (any AnyJavaScriptClass)? {
            return nil
          }
        }

        extension Timer: nonisolated AnyJavaScriptClass, nonisolated JavaScriptDecodable {
        }

        extension Timer: @unchecked Sendable {
        }
        """,
      diagnostics: [
        DiagnosticSpec(
          message:
            "'Timer' has instance @JS members but no @JS initializer, and JavaScript gets an instance of this class only from its constructor. Add a @JS init, or make the members static",
          line: 2,
          column: 20,
          severity: .warning
        )
      ]
    )
  }

  @Test
  func `An @Event member asserts that the class is an EventEmitter, which a plain class isn't`() {
    // The assertion fails to compile in a `@JSClass` class, so the build reports the event on its own
    // declaration.
    assertExpansion(
      """
      @JSClass
      public final class Clock {
        @JS
        init() {}

        @Event
        var onTick: () -> Void
      }
      """,
      expandedSource: """
        public final class Clock {
          @JavaScriptActor
          init() {}
          var onTick: () -> Void {
            get {
              { [weak self] in
                self?.emit(event: "tick")
              }
            }
          }

          private func _assertTypesConformance_onTick() {
            func onTick(_: (some EventEmitter).Type) {
            }
            onTick(Clock.self)
          }

          nonisolated public class var _jsName: String {
            "Clock"
          }

          nonisolated public class var _jsClassType: (any AnyJavaScriptClass.Type)? {
            Clock.self
          }

          nonisolated public class var _jsSuperclassType: (any AnyJavaScriptClass.Type)? {
            nil
          }

          @JavaScriptActor
          public class func _decorateClass(prototype: borrowing JavaScriptObject, in runtime: JavaScriptRuntime) throws {
          }

          @JavaScriptActor
          public class func _decorateClass(constructor: borrowing JavaScriptObject, in runtime: JavaScriptRuntime) throws {
          }

          @JavaScriptActor
          public class func _constructInstance(this: borrowing JavaScriptValue, arguments: borrowing JavaScriptValuesBuffer, in runtime: JavaScriptRuntime) throws -> (any AnyJavaScriptClass)? {
            guard arguments.count == 0 else {
              throw Exceptions.ArgumentsRangeMismatch((functionName: "Clock", received: arguments.count, required: 0, maximum: 0))
            }
            return Clock()
          }
        }

        extension Clock: nonisolated AnyJavaScriptClass, nonisolated JavaScriptDecodable {
        }

        extension Clock: @unchecked Sendable {
        }
        """
    )
  }
}
