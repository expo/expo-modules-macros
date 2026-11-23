import ExpoModulesMacrosCore
import SwiftSyntax
import SwiftSyntaxMacroExpansion
import SwiftSyntaxMacros
import SwiftSyntaxMacrosGenericTestSupport
import Testing

/// The conformances that the compiler passes for a root class, which conforms to none of them yet.
private let rootConformances: [TypeSyntax] = [
  "AnyJavaScriptClass", "JavaScriptDecodable", "Sendable",
]

/// The macros of the tests, with `@JSClass` getting `conformances`. The compiler passes only the
/// conformances that the class doesn't have yet, so a test of a subclass passes fewer.
private func macroSpecs(jsClassConformances conformances: [TypeSyntax]) -> [String: MacroSpec] {
  return [
    "JS": MacroSpec(type: JSMacro.self),
    "JSClass": MacroSpec(type: JSClassMacro.self, conformances: conformances),
    "SharedObject": MacroSpec(type: SharedObjectMacro.self),
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
              throw Exceptions.ArgumentsRangeMismatch((functionName: "Shape", received: arguments.count, required: 1, maximum: 1))
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
    // The compiler passes no conformance: the superclass has them all.
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
      conformances: []
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
      conformances: []
    )
  }

  @Test
  func `A class that names AnyJavaScriptClass is a root and gets only the conformances it doesn't name`() {
    // The compiler leaves out `AnyJavaScriptClass`, which the clause names.
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
      conformances: ["JavaScriptDecodable"]
    )
  }

  @Test
  func `On a shared object, warns with a fix-it that uses @SharedObject and keeps the name`() {
    // `SharedObject` has the root conformances, but isn't `Sendable`.
    assertExpansion(
      """
      @JSClass("Store")
      public final class Storage: SharedObject {
      }
      """,
      expandedSource: """
        public final class Storage: SharedObject {

          public override class var _jsName: String {
            "Store"
          }

          public override class var _jsClassType: (any AnyJavaScriptClass.Type)? {
            Storage.self
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
        }

        extension Storage: @unchecked Sendable {
        }
        """,
      conformances: ["Sendable"],
      diagnostics: [
        DiagnosticSpec(
          message: "This class inherits from a shared object, so use @SharedObject instead of @JSClass",
          line: 1,
          column: 1,
          severity: .warning,
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
      conformances: [],
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
  func `Reports a second @JS initializer with the name of the macro`() {
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
          line: 1,
          column: 1
        )
      ]
    )
  }
}
