import ExpoModulesMacros
import SwiftSyntax
import SwiftSyntaxMacroExpansion
import SwiftSyntaxMacros
import SwiftSyntaxMacrosGenericTestSupport
import Testing

private let sharedObjectMacroSpecs: [String: MacroSpec] = [
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
    macroSpecs: sharedObjectMacroSpecs,
    indentationWidth: .spaces(2),
    failureHandler: recordIssue,
    fileID: fileID,
    filePath: filePath,
    line: line,
    column: column
  )
}

@Suite("@SharedObject macro")
struct SharedObjectMacroTests {
  @Test
  func `Empty class emits only _jsName`() {
    assertExpansion(
      """
      @SharedObject
      final class Cache: SharedObject {
      }
      """,
      expandedSource: """
        final class Cache: SharedObject {

          public override class var _jsName: String {
            "Cache"
          }
        }
        """
    )
  }

  @Test
  func `Custom JS name overrides the class name`() {
    assertExpansion(
      """
      @SharedObject("MyCache")
      final class Cache: SharedObject {
      }
      """,
      expandedSource: """
        final class Cache: SharedObject {

          public override class var _jsName: String {
            "MyCache"
          }
        }
        """
    )
  }

  @Test
  func `SharedRef subclass binds its @JS members and takes SharedRef arguments`() {
    assertExpansion(
      """
      @SharedObject
      final class ImageRef: SharedRef<UIImage> {
        @JS
        init(image: SharedRef<UIImage>) {
          super.init(image.ref)
        }

        @JS
        func merge(_ other: SharedRef<UIImage>) -> SharedRef<UIImage> { self }
      }
      """,
      expandedSource: """
        final class ImageRef: SharedRef<UIImage> {
          @JavaScriptActor
          init(image: SharedRef<UIImage>) {
            super.init(image.ref)
          }
          @JavaScriptActor
          func merge(_ other: SharedRef<UIImage>) -> SharedRef<UIImage> { self }

          public override class var _jsName: String {
            "ImageRef"
          }

          @JavaScriptActor
          public override class func _decorateSharedObject(prototype: borrowing JavaScriptObject, in runtime: JavaScriptRuntime) throws {
            prototype.setProperty("merge") { (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer, result: borrowing JavaScriptValue.Slot, runtime: borrowing JavaScriptRuntime) in
              let _self = try SharedObject.native(from: this.asObject(in: runtime), as: ImageRef.self)
              guard arguments.count == 1 else {
                throw Exceptions.ArgumentsRangeMismatch((functionName: "merge", received: arguments.count, required: 1, maximum: 1))
              }
              let arg0 = try SharedRef<UIImage>.decode(arguments.unownedValue(at: 0), in: runtime)
              let value = _self.merge(arg0)
              try SharedRef<UIImage>.encode(value, into: result, in: runtime)
            }
          }

          @JavaScriptActor
          public override class func _constructSharedObject(this: borrowing JavaScriptValue, arguments: borrowing JavaScriptValuesBuffer, in runtime: JavaScriptRuntime) throws -> SharedObject? {
            guard arguments.count == 1 else {
              throw Exceptions.ArgumentsRangeMismatch((functionName: "ImageRef", received: arguments.count, required: 1, maximum: 1))
            }
            let arg0 = try SharedRef<UIImage>.decode(arguments.unownedValue(at: 0), in: runtime)
            return ImageRef(image: arg0)
          }

          private func _assertTypesConformance() {
            func `init`(image _: (some JavaScriptDecodable & ~Copyable).Type) {
            }
            `init`(image: SharedRef<UIImage>.self)
            func merge(_: (some JavaScriptDecodable & ~Copyable).Type, returning _: (some JavaScriptEncodable & ~Copyable).Type) {
            }
            merge(SharedRef<UIImage>.self, returning: SharedRef<UIImage>.self)
          }
        }
        """
    )
  }

  @Test
  func `Indirect subclass expands without a diagnostic`() {
    // The macro can't see that `ImageRef` is a `SharedObject` subclass, so it leaves the superclass
    // to the compiler.
    assertExpansion(
      """
      @SharedObject
      final class Thumbnail: ImageRef {
      }
      """,
      expandedSource: """
        final class Thumbnail: ImageRef {

          public override class var _jsName: String {
            "Thumbnail"
          }
        }
        """
    )
  }

  @Test
  func `Non-final class guards its constructor and makes its properties configurable`() {
    assertExpansion(
      """
      @SharedObject
      class ImageRef: SharedObject {
        @JS
        init(path: String) {}

        @JS
        var size: Int { 1 }
      }
      """,
      expandedSource: """
        class ImageRef: SharedObject {
          @JavaScriptActor
          init(path: String) {}
          @JavaScriptActor
          var size: Int { 1 }

          public override class var _jsName: String {
            "ImageRef"
          }

          @JavaScriptActor
          public override class func _decorateSharedObject(prototype: borrowing JavaScriptObject, in runtime: JavaScriptRuntime) throws {
            let sizeDescriptor = runtime.createObject()
            sizeDescriptor.setProperty("enumerable", value: true)
            sizeDescriptor.setProperty("configurable", value: true)
            sizeDescriptor.setProperty("get") { (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer, result: borrowing JavaScriptValue.Slot, runtime: borrowing JavaScriptRuntime) in
              let _self = try SharedObject.native(from: this.asObject(in: runtime), as: ImageRef.self)
              try Int.encode(_self.size, into: result, in: runtime)
            }
            prototype.defineProperty("size", descriptor: sizeDescriptor)
          }

          @JavaScriptActor
          public override class func _constructSharedObject(this: borrowing JavaScriptValue, arguments: borrowing JavaScriptValuesBuffer, in runtime: JavaScriptRuntime) throws -> SharedObject? {
            guard self == ImageRef.self else {
              return nil
            }
            guard arguments.count == 1 else {
              throw Exceptions.ArgumentsRangeMismatch((functionName: "ImageRef", received: arguments.count, required: 1, maximum: 1))
            }
            let arg0 = try String.decode(arguments.unownedValue(at: 0), in: runtime)
            return ImageRef(path: arg0)
          }
        }
        """
    )
  }

  @Test
  func `Subclass of another shared object class binds the inherited members first`() {
    assertExpansion(
      """
      @SharedObject
      final class Thumbnail: ImageRef {
        @JS
        var size: Int { 64 }

        @JS
        static func clearCache() {}
      }
      """,
      expandedSource: """
        final class Thumbnail: ImageRef {
          @JavaScriptActor
          var size: Int { 64 }
          @JavaScriptActor
          static func clearCache() {}

          public override class var _jsName: String {
            "Thumbnail"
          }

          @JavaScriptActor
          public override class func _decorateSharedObject(prototype: borrowing JavaScriptObject, in runtime: JavaScriptRuntime) throws {
            try super._decorateSharedObject(prototype: prototype, in: runtime)
            let sizeDescriptor = runtime.createObject()
            sizeDescriptor.setProperty("enumerable", value: true)
            sizeDescriptor.setProperty("get") { (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer, result: borrowing JavaScriptValue.Slot, runtime: borrowing JavaScriptRuntime) in
              let _self = try SharedObject.native(from: this.asObject(in: runtime), as: Thumbnail.self)
              try Int.encode(_self.size, into: result, in: runtime)
            }
            prototype.defineProperty("size", descriptor: sizeDescriptor)
          }

          @JavaScriptActor
          public override class func _decorateSharedObject(constructor: borrowing JavaScriptObject, in runtime: JavaScriptRuntime) throws {
            try super._decorateSharedObject(constructor: constructor, in: runtime)
            constructor.defineProperty("clearCache", descriptor: .init(configurable: true, enumerable: true, writable: true))
            constructor.setProperty("clearCache") { (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer) -> Void in
              guard arguments.count == 0 else {
                throw Exceptions.ArgumentsRangeMismatch((functionName: "clearCache", received: arguments.count, required: 0, maximum: 0))
              }
              Thumbnail.clearCache()
            }
          }
        }
        """
    )
  }

  @Test
  func `Sync method binds via _decorateSharedObject(prototype:), unwrapping the receiver from this`() {
    assertExpansion(
      """
      @SharedObject
      final class Cache: SharedObject {
        @JS
        func get(_ key: String) -> String? { nil }
      }
      """,
      expandedSource: """
        final class Cache: SharedObject {
          @JavaScriptActor
          func get(_ key: String) -> String? { nil }

          public override class var _jsName: String {
            "Cache"
          }

          @JavaScriptActor
          public override class func _decorateSharedObject(prototype: borrowing JavaScriptObject, in runtime: JavaScriptRuntime) throws {
            prototype.setProperty("get") { (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer, result: borrowing JavaScriptValue.Slot, runtime: borrowing JavaScriptRuntime) in
              let _self = try SharedObject.native(from: this.asObject(in: runtime), as: Cache.self)
              guard arguments.count == 1 else {
                throw Exceptions.ArgumentsRangeMismatch((functionName: "get", received: arguments.count, required: 1, maximum: 1))
              }
              let arg0 = try String.decode(arguments.unownedValue(at: 0), in: runtime)
              let value = _self.get(arg0)
              try String?.encode(value, into: result, in: runtime)
            }
          }
        }
        """
    )
  }

  @Test
  func `Async method binds through the async setProperty overload`() {
    assertExpansion(
      """
      @SharedObject
      final class Cache: SharedObject {
        @JS("loadAsync")
        func load() async throws {}
      }
      """,
      expandedSource: """
        final class Cache: SharedObject {
          @JavaScriptActor
          func load() async throws {}

          public override class var _jsName: String {
            "Cache"
          }

          @JavaScriptActor
          public override class func _decorateSharedObject(prototype: borrowing JavaScriptObject, in runtime: JavaScriptRuntime) throws {
            prototype.setProperty("loadAsync") { (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer) in
              let _self = try SharedObject.native(from: this.asObject(in: runtime), as: Cache.self)
              guard arguments.count == 0 else {
                throw Exceptions.ArgumentsRangeMismatch((functionName: "loadAsync", received: arguments.count, required: 0, maximum: 0))
              }
              return {
                try await _self.load()
                return .undefined()
              }
            }
          }
        }
        """
    )
  }

  @Test
  func `A non-primitive property routes through the dynamic converter and unwraps the receiver`() {
    assertExpansion(
      """
      @SharedObject
      final class Cache: SharedObject {
        @JS
        var owner: SomeType!
      }
      """,
      expandedSource: """
        final class Cache: SharedObject {
          @JavaScriptActor
          var owner: SomeType!

          public override class var _jsName: String {
            "Cache"
          }

          @JavaScriptActor
          public override class func _decorateSharedObject(prototype: borrowing JavaScriptObject, in runtime: JavaScriptRuntime) throws {
            let ownerDescriptor = runtime.createObject()
            ownerDescriptor.setProperty("enumerable", value: true)
            ownerDescriptor.setProperty("get") { (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer, result: borrowing JavaScriptValue.Slot, runtime: borrowing JavaScriptRuntime) in
              let _self = try SharedObject.native(from: this.asObject(in: runtime), as: Cache.self)
              try SomeType?.encode(_self.owner, into: result, in: runtime)
            }
            ownerDescriptor.setProperty("set") { (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer, result: borrowing JavaScriptValue.Slot, runtime: borrowing JavaScriptRuntime) in
              let _self = try SharedObject.native(from: this.asObject(in: runtime), as: Cache.self)
              _self.owner = try SomeType?.decode(arguments.unownedValue(at: 0), in: runtime)
            }
            prototype.defineProperty("owner", descriptor: ownerDescriptor)
          }

          private func _assertTypesConformance() {
            func owner(_: (some JavaScriptDecodable & ~Copyable).Type, _: (some JavaScriptEncodable & ~Copyable).Type) {
            }
            owner(SomeType.self, SomeType.self)
          }
        }
        """
    )
  }

  @Test
  func `A primitive computed property binds a get-only accessor, unwrapping the receiver`() {
    assertExpansion(
      """
      @SharedObject
      final class Cache: SharedObject {
        @JS
        var size: Int { 42 }
      }
      """,
      expandedSource: """
        final class Cache: SharedObject {
          @JavaScriptActor
          var size: Int { 42 }

          public override class var _jsName: String {
            "Cache"
          }

          @JavaScriptActor
          public override class func _decorateSharedObject(prototype: borrowing JavaScriptObject, in runtime: JavaScriptRuntime) throws {
            let sizeDescriptor = runtime.createObject()
            sizeDescriptor.setProperty("enumerable", value: true)
            sizeDescriptor.setProperty("get") { (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer, result: borrowing JavaScriptValue.Slot, runtime: borrowing JavaScriptRuntime) in
              let _self = try SharedObject.native(from: this.asObject(in: runtime), as: Cache.self)
              try Int.encode(_self.size, into: result, in: runtime)
            }
            prototype.defineProperty("size", descriptor: sizeDescriptor)
          }
        }
        """
    )
  }

  @Test
  func `@JS init binds a _constructSharedObject that builds the instance from JS arguments`() {
    assertExpansion(
      """
      @SharedObject
      final class Cache: SharedObject {
        @JS
        init(name: String) {}
      }
      """,
      expandedSource: """
        final class Cache: SharedObject {
          @JavaScriptActor
          init(name: String) {}

          public override class var _jsName: String {
            "Cache"
          }

          @JavaScriptActor
          public override class func _constructSharedObject(this: borrowing JavaScriptValue, arguments: borrowing JavaScriptValuesBuffer, in runtime: JavaScriptRuntime) throws -> SharedObject? {
            guard arguments.count == 1 else {
              throw Exceptions.ArgumentsRangeMismatch((functionName: "Cache", received: arguments.count, required: 1, maximum: 1))
            }
            let arg0 = try String.decode(arguments.unownedValue(at: 0), in: runtime)
            return Cache(name: arg0)
          }
        }
        """
    )
  }

  @Test
  func `@JS init with an ownership specifier decodes the bare type`() {
    assertExpansion(
      """
      @SharedObject
      final class Cache: SharedObject {
        @JS
        init(origin: borrowing Point) {}
      }
      """,
      expandedSource: """
        final class Cache: SharedObject {
          @JavaScriptActor
          init(origin: borrowing Point) {}

          public override class var _jsName: String {
            "Cache"
          }

          @JavaScriptActor
          public override class func _constructSharedObject(this: borrowing JavaScriptValue, arguments: borrowing JavaScriptValuesBuffer, in runtime: JavaScriptRuntime) throws -> SharedObject? {
            guard arguments.count == 1 else {
              throw Exceptions.ArgumentsRangeMismatch((functionName: "Cache", received: arguments.count, required: 1, maximum: 1))
            }
            let arg0 = try Point.decode(arguments.unownedValue(at: 0), in: runtime)
            return Cache(origin: arg0)
          }

          private func _assertTypesConformance() {
            func `init`(origin _: (some JavaScriptDecodable & ~Copyable).Type) {
            }
            `init`(origin: Point.self)
          }
        }
        """
    )
  }

  @Test
  func `@JS init with a free-form argument decodes through decodeAnyDictionary`() {
    assertExpansion(
      """
      @SharedObject
      final class Cache: SharedObject {
        @JS
        init(config: [String: Any]) {}
      }
      """,
      expandedSource: """
        final class Cache: SharedObject {
          @JavaScriptActor
          init(config: [String: Any]) {}

          public override class var _jsName: String {
            "Cache"
          }

          @JavaScriptActor
          public override class func _constructSharedObject(this: borrowing JavaScriptValue, arguments: borrowing JavaScriptValuesBuffer, in runtime: JavaScriptRuntime) throws -> SharedObject? {
            guard arguments.count == 1 else {
              throw Exceptions.ArgumentsRangeMismatch((functionName: "Cache", received: arguments.count, required: 1, maximum: 1))
            }
            let arg0 = try JavaScriptValue.decodeAnyDictionary(arguments.unownedValue(at: 0), in: runtime)
            return Cache(config: arg0)
          }
        }
        """
    )
  }

  @Test
  func `Mixed members: init constructs, method and property decorate`() {
    assertExpansion(
      """
      @SharedObject
      final class Cache: SharedObject {
        @JS
        init(name: String) {}

        @JS
        func get(_ key: String) -> String? { nil }

        @JS
        var size: Int { 42 }
      }
      """,
      expandedSource: """
        final class Cache: SharedObject {
          @JavaScriptActor
          init(name: String) {}
          @JavaScriptActor
          func get(_ key: String) -> String? { nil }
          @JavaScriptActor
          var size: Int { 42 }

          public override class var _jsName: String {
            "Cache"
          }

          @JavaScriptActor
          public override class func _decorateSharedObject(prototype: borrowing JavaScriptObject, in runtime: JavaScriptRuntime) throws {
            prototype.setProperty("get") { (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer, result: borrowing JavaScriptValue.Slot, runtime: borrowing JavaScriptRuntime) in
              let _self = try SharedObject.native(from: this.asObject(in: runtime), as: Cache.self)
              guard arguments.count == 1 else {
                throw Exceptions.ArgumentsRangeMismatch((functionName: "get", received: arguments.count, required: 1, maximum: 1))
              }
              let arg0 = try String.decode(arguments.unownedValue(at: 0), in: runtime)
              let value = _self.get(arg0)
              try String?.encode(value, into: result, in: runtime)
            }
            let sizeDescriptor = runtime.createObject()
            sizeDescriptor.setProperty("enumerable", value: true)
            sizeDescriptor.setProperty("get") { (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer, result: borrowing JavaScriptValue.Slot, runtime: borrowing JavaScriptRuntime) in
              let _self = try SharedObject.native(from: this.asObject(in: runtime), as: Cache.self)
              try Int.encode(_self.size, into: result, in: runtime)
            }
            prototype.defineProperty("size", descriptor: sizeDescriptor)
          }

          @JavaScriptActor
          public override class func _constructSharedObject(this: borrowing JavaScriptValue, arguments: borrowing JavaScriptValuesBuffer, in runtime: JavaScriptRuntime) throws -> SharedObject? {
            guard arguments.count == 1 else {
              throw Exceptions.ArgumentsRangeMismatch((functionName: "Cache", received: arguments.count, required: 1, maximum: 1))
            }
            let arg0 = try String.decode(arguments.unownedValue(at: 0), in: runtime)
            return Cache(name: arg0)
          }
        }
        """
    )
  }

  @Test
  func `Static method binds via _decorateSharedObject(constructor:), calling the type and ignoring this`() {
    assertExpansion(
      """
      @SharedObject
      final class Cache: SharedObject {
        @JS
        static func open(_ path: String) -> Cache { Cache() }
      }
      """,
      expandedSource: """
        final class Cache: SharedObject {
          @JavaScriptActor
          static func open(_ path: String) -> Cache { Cache() }

          public override class var _jsName: String {
            "Cache"
          }

          @JavaScriptActor
          public override class func _decorateSharedObject(constructor: borrowing JavaScriptObject, in runtime: JavaScriptRuntime) throws {
            constructor.setProperty("open") { (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer, result: borrowing JavaScriptValue.Slot, runtime: borrowing JavaScriptRuntime) in
              guard arguments.count == 1 else {
                throw Exceptions.ArgumentsRangeMismatch((functionName: "open", received: arguments.count, required: 1, maximum: 1))
              }
              let arg0 = try String.decode(arguments.unownedValue(at: 0), in: runtime)
              let value = Cache.open(arg0)
              try Cache.encode(value, into: result, in: runtime)
            }
          }

          private func _assertTypesConformance() {
            func open(returning _: (some JavaScriptEncodable & ~Copyable).Type) {
            }
            open(returning: Cache.self)
          }
        }
        """
    )
  }

  @Test
  func `Static async method decodes synchronously and returns the async body`() {
    assertExpansion(
      """
      @SharedObject
      final class Cache: SharedObject {
        @JS
        static func warmUp(_ path: String) async throws {}
      }
      """,
      expandedSource: """
        final class Cache: SharedObject {
          @JavaScriptActor
          static func warmUp(_ path: String) async throws {}

          public override class var _jsName: String {
            "Cache"
          }

          @JavaScriptActor
          public override class func _decorateSharedObject(constructor: borrowing JavaScriptObject, in runtime: JavaScriptRuntime) throws {
            constructor.setProperty("warmUp") { (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer) in
              guard arguments.count == 1 else {
                throw Exceptions.ArgumentsRangeMismatch((functionName: "warmUp", received: arguments.count, required: 1, maximum: 1))
              }
              let arg0 = try String.decode(arguments.unownedValue(at: 0), in: runtime)
              return {
                try await Cache.warmUp(arg0)
                return .undefined()
              }
            }
          }
        }
        """
    )
  }

  @Test
  func `Static property binds a getter and setter onto the constructor, calling the type`() {
    assertExpansion(
      """
      @SharedObject
      final class Cache: SharedObject {
        @JS
        static var shared: Int = 0
      }
      """,
      expandedSource: """
        final class Cache: SharedObject {
          @JavaScriptActor
          static var shared: Int = 0

          public override class var _jsName: String {
            "Cache"
          }

          @JavaScriptActor
          public override class func _decorateSharedObject(constructor: borrowing JavaScriptObject, in runtime: JavaScriptRuntime) throws {
            let sharedDescriptor = runtime.createObject()
            sharedDescriptor.setProperty("enumerable", value: true)
            sharedDescriptor.setProperty("get") { (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer, result: borrowing JavaScriptValue.Slot, runtime: borrowing JavaScriptRuntime) in
              try Int.encode(Cache.shared, into: result, in: runtime)
            }
            sharedDescriptor.setProperty("set") { (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer, result: borrowing JavaScriptValue.Slot, runtime: borrowing JavaScriptRuntime) in
              Cache.shared = try Int.decode(arguments.unownedValue(at: 0), in: runtime)
            }
            constructor.defineProperty("shared", descriptor: sharedDescriptor)
          }
        }
        """
    )
  }

  @Test
  func `Static and instance members of the same name decorate different objects`() {
    assertExpansion(
      """
      @SharedObject
      final class Cache: SharedObject {
        @JS
        func get(_ key: String) -> String? { nil }

        @JS
        static func get(_ key: String) -> String? { nil }
      }
      """,
      expandedSource: """
        final class Cache: SharedObject {
          @JavaScriptActor
          func get(_ key: String) -> String? { nil }
          @JavaScriptActor
          static func get(_ key: String) -> String? { nil }

          public override class var _jsName: String {
            "Cache"
          }

          @JavaScriptActor
          public override class func _decorateSharedObject(prototype: borrowing JavaScriptObject, in runtime: JavaScriptRuntime) throws {
            prototype.setProperty("get") { (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer, result: borrowing JavaScriptValue.Slot, runtime: borrowing JavaScriptRuntime) in
              let _self = try SharedObject.native(from: this.asObject(in: runtime), as: Cache.self)
              guard arguments.count == 1 else {
                throw Exceptions.ArgumentsRangeMismatch((functionName: "get", received: arguments.count, required: 1, maximum: 1))
              }
              let arg0 = try String.decode(arguments.unownedValue(at: 0), in: runtime)
              let value = _self.get(arg0)
              try String?.encode(value, into: result, in: runtime)
            }
          }

          @JavaScriptActor
          public override class func _decorateSharedObject(constructor: borrowing JavaScriptObject, in runtime: JavaScriptRuntime) throws {
            constructor.setProperty("get") { (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer, result: borrowing JavaScriptValue.Slot, runtime: borrowing JavaScriptRuntime) in
              guard arguments.count == 1 else {
                throw Exceptions.ArgumentsRangeMismatch((functionName: "get", received: arguments.count, required: 1, maximum: 1))
              }
              let arg0 = try String.decode(arguments.unownedValue(at: 0), in: runtime)
              let value = Cache.get(arg0)
              try String?.encode(value, into: result, in: runtime)
            }
          }
        }
        """
    )
  }

  @Test
  func `Instance members with the same JS name are an error, a static one is not`() {
    assertExpansion(
      """
      @SharedObject
      final class Cache: SharedObject {
        @JS
        var size: Int { 0 }

        @JS("size")
        var count: Int { 0 }

        @JS
        static var size: Int { 0 }
      }
      """,
      expandedSource: """
        final class Cache: SharedObject {
          @JavaScriptActor
          var size: Int { 0 }
          @JavaScriptActor
          var count: Int { 0 }
          @JavaScriptActor
          static var size: Int { 0 }

          public override class var _jsName: String {
            "Cache"
          }

          @JavaScriptActor
          public override class func _decorateSharedObject(prototype: borrowing JavaScriptObject, in runtime: JavaScriptRuntime) throws {
            let sizeDescriptor = runtime.createObject()
            sizeDescriptor.setProperty("enumerable", value: true)
            sizeDescriptor.setProperty("get") { (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer, result: borrowing JavaScriptValue.Slot, runtime: borrowing JavaScriptRuntime) in
              let _self = try SharedObject.native(from: this.asObject(in: runtime), as: Cache.self)
              try Int.encode(_self.size, into: result, in: runtime)
            }
            prototype.defineProperty("size", descriptor: sizeDescriptor)
            let countDescriptor = runtime.createObject()
            countDescriptor.setProperty("enumerable", value: true)
            countDescriptor.setProperty("get") { (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer, result: borrowing JavaScriptValue.Slot, runtime: borrowing JavaScriptRuntime) in
              let _self = try SharedObject.native(from: this.asObject(in: runtime), as: Cache.self)
              try Int.encode(_self.count, into: result, in: runtime)
            }
            prototype.defineProperty("size", descriptor: countDescriptor)
          }

          @JavaScriptActor
          public override class func _decorateSharedObject(constructor: borrowing JavaScriptObject, in runtime: JavaScriptRuntime) throws {
            let sizeDescriptor = runtime.createObject()
            sizeDescriptor.setProperty("enumerable", value: true)
            sizeDescriptor.setProperty("get") { (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer, result: borrowing JavaScriptValue.Slot, runtime: borrowing JavaScriptRuntime) in
              try Int.encode(Cache.size, into: result, in: runtime)
            }
            constructor.defineProperty("size", descriptor: sizeDescriptor)
          }
        }
        """,
      diagnostics: [
        DiagnosticSpec(
          message:
            "The JavaScript name 'size' is already bound by an earlier @JS property. A JavaScript object holds one member per name, so JavaScript could reach only one of them. Give one of them another name with @JS(\"...\").",
          line: 7,
          column: 7,
          severity: .error,
          notes: [NoteSpec(message: "'size' is first bound here", line: 4, column: 7)]
        )
      ]
    )
  }

  @Test
  func `Trailing defaulted parameter branches the call through the unwrapped receiver`() {
    assertExpansion(
      """
      @SharedObject
      final class Cache: SharedObject {
        @JS
        func resize(width: Int, height: Int = 100) -> Bool { true }
      }
      """,
      expandedSource: """
        final class Cache: SharedObject {
          @JavaScriptActor
          func resize(width: Int, height: Int = 100) -> Bool { true }

          public override class var _jsName: String {
            "Cache"
          }

          @JavaScriptActor
          public override class func _decorateSharedObject(prototype: borrowing JavaScriptObject, in runtime: JavaScriptRuntime) throws {
            prototype.setProperty("resize") { (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer, result: borrowing JavaScriptValue.Slot, runtime: borrowing JavaScriptRuntime) in
              let _self = try SharedObject.native(from: this.asObject(in: runtime), as: Cache.self)
              guard arguments.count >= 1 && arguments.count <= 2 else {
                throw Exceptions.ArgumentsRangeMismatch((functionName: "resize", received: arguments.count, required: 1, maximum: 2))
              }
              let arg0 = try Int.decode(arguments.unownedValue(at: 0), in: runtime)
              let value: Bool
              switch arguments.count {
              case 1:
                value = _self.resize(width: arg0)
              default:
                let arg1 = try Int.decode(arguments.unownedValue(at: 1), in: runtime)
                value = _self.resize(width: arg0, height: arg1)
              }
              try Bool.encode(value, into: result, in: runtime)
            }
          }
        }
        """
    )
  }

  @Test
  func `Settable stored property binds a getter and setter through the unwrapped receiver`() {
    assertExpansion(
      """
      @SharedObject
      final class Cache: SharedObject {
        @JS
        var name: String = ""
      }
      """,
      expandedSource: """
        final class Cache: SharedObject {
          @JavaScriptActor
          var name: String = ""

          public override class var _jsName: String {
            "Cache"
          }

          @JavaScriptActor
          public override class func _decorateSharedObject(prototype: borrowing JavaScriptObject, in runtime: JavaScriptRuntime) throws {
            let nameDescriptor = runtime.createObject()
            nameDescriptor.setProperty("enumerable", value: true)
            nameDescriptor.setProperty("get") { (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer, result: borrowing JavaScriptValue.Slot, runtime: borrowing JavaScriptRuntime) in
              let _self = try SharedObject.native(from: this.asObject(in: runtime), as: Cache.self)
              try String.encode(_self.name, into: result, in: runtime)
            }
            nameDescriptor.setProperty("set") { (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer, result: borrowing JavaScriptValue.Slot, runtime: borrowing JavaScriptRuntime) in
              let _self = try SharedObject.native(from: this.asObject(in: runtime), as: Cache.self)
              _self.name = try String.decode(arguments.unownedValue(at: 0), in: runtime)
            }
            prototype.defineProperty("name", descriptor: nameDescriptor)
          }
        }
        """
    )
  }

  @Test
  func `Lazy property caches the value on the instance, not on the prototype`() {
    assertExpansion(
      """
      @SharedObject
      final class Cache: SharedObject {
        @JS
        lazy var size: Int = computeSize()
      }
      """,
      expandedSource: """
        final class Cache: SharedObject {
          @JavaScriptActor
          lazy var size: Int = computeSize()

          public override class var _jsName: String {
            "Cache"
          }

          @JavaScriptActor
          public override class func _decorateSharedObject(prototype: borrowing JavaScriptObject, in runtime: JavaScriptRuntime) throws {
            let sizeDescriptor = runtime.createObject()
            sizeDescriptor.setProperty("enumerable", value: true)
            sizeDescriptor.setProperty("configurable", value: true)
            sizeDescriptor.setProperty("get") { (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer, result: borrowing JavaScriptValue.Slot, runtime: borrowing JavaScriptRuntime) in
              let _self = try SharedObject.native(from: this.asObject(in: runtime), as: Cache.self)
              let value = try Int.encode(_self.size, in: runtime)
              this.getObject(in: runtime).defineProperty("size", value: value, options: [.enumerable])
              result.emplace(value)
            }
            prototype.defineProperty("size", descriptor: sizeDescriptor)
          }
        }
        """
    )
  }

  @Test
  func `No-argument void method calls through and returns undefined`() {
    assertExpansion(
      """
      @SharedObject
      final class Cache: SharedObject {
        @JS
        func clear() {}
      }
      """,
      expandedSource: """
        final class Cache: SharedObject {
          @JavaScriptActor
          func clear() {}

          public override class var _jsName: String {
            "Cache"
          }

          @JavaScriptActor
          public override class func _decorateSharedObject(prototype: borrowing JavaScriptObject, in runtime: JavaScriptRuntime) throws {
            prototype.setProperty("clear") { (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer) -> Void in
              let _self = try SharedObject.native(from: this.asObject(in: runtime), as: Cache.self)
              guard arguments.count == 0 else {
                throw Exceptions.ArgumentsRangeMismatch((functionName: "clear", received: arguments.count, required: 0, maximum: 0))
              }
              _self.clear()
            }
          }
        }
        """
    )
  }

  @Test
  func `No-argument init constructs without an arity guard body`() {
    assertExpansion(
      """
      @SharedObject
      final class Cache: SharedObject {
        @JS
        init() {}
      }
      """,
      expandedSource: """
        final class Cache: SharedObject {
          @JavaScriptActor
          init() {}

          public override class var _jsName: String {
            "Cache"
          }

          @JavaScriptActor
          public override class func _constructSharedObject(this: borrowing JavaScriptValue, arguments: borrowing JavaScriptValuesBuffer, in runtime: JavaScriptRuntime) throws -> SharedObject? {
            guard arguments.count == 0 else {
              throw Exceptions.ArgumentsRangeMismatch((functionName: "Cache", received: arguments.count, required: 0, maximum: 0))
            }
            return Cache()
          }
        }
        """
    )
  }

  @Test
  func `Non-primitive constructor argument gets a conformance assertion and decodes through its type`() {
    assertExpansion(
      """
      @SharedObject
      final class Cache: SharedObject {
        @JS
        init(config: MyRecord) {}
      }
      """,
      expandedSource: """
        final class Cache: SharedObject {
          @JavaScriptActor
          init(config: MyRecord) {}

          public override class var _jsName: String {
            "Cache"
          }

          @JavaScriptActor
          public override class func _constructSharedObject(this: borrowing JavaScriptValue, arguments: borrowing JavaScriptValuesBuffer, in runtime: JavaScriptRuntime) throws -> SharedObject? {
            guard arguments.count == 1 else {
              throw Exceptions.ArgumentsRangeMismatch((functionName: "Cache", received: arguments.count, required: 1, maximum: 1))
            }
            let arg0 = try MyRecord.decode(arguments.unownedValue(at: 0), in: runtime)
            return Cache(config: arg0)
          }

          private func _assertTypesConformance() {
            func `init`(config _: (some JavaScriptDecodable & ~Copyable).Type) {
            }
            `init`(config: MyRecord.self)
          }
        }
        """
    )
  }

  @Test
  func `Implicitly-unwrapped constructor argument normalizes to optional in the cast expression`() {
    assertExpansion(
      """
      @SharedObject
      final class Cache: SharedObject {
        @JS
        init(config: MyRecord!) {}
      }
      """,
      expandedSource: """
        final class Cache: SharedObject {
          @JavaScriptActor
          init(config: MyRecord!) {}

          public override class var _jsName: String {
            "Cache"
          }

          @JavaScriptActor
          public override class func _constructSharedObject(this: borrowing JavaScriptValue, arguments: borrowing JavaScriptValuesBuffer, in runtime: JavaScriptRuntime) throws -> SharedObject? {
            guard arguments.count == 1 else {
              throw Exceptions.ArgumentsRangeMismatch((functionName: "Cache", received: arguments.count, required: 1, maximum: 1))
            }
            let arg0 = try MyRecord?.decode(arguments.unownedValue(at: 0), in: runtime)
            return Cache(config: arg0)
          }

          private func _assertTypesConformance() {
            func `init`(config _: (some JavaScriptDecodable & ~Copyable).Type) {
            }
            `init`(config: MyRecord.self)
          }
        }
        """
    )
  }

  @Test
  func `Implicitly-unwrapped method argument and return normalize to optional through the receiver`() {
    assertExpansion(
      """
      @SharedObject
      final class Cache: SharedObject {
        @JS
        func resolve(_ input: MyRecord!) -> MyRecord! { input }
      }
      """,
      expandedSource: """
        final class Cache: SharedObject {
          @JavaScriptActor
          func resolve(_ input: MyRecord!) -> MyRecord! { input }

          public override class var _jsName: String {
            "Cache"
          }

          @JavaScriptActor
          public override class func _decorateSharedObject(prototype: borrowing JavaScriptObject, in runtime: JavaScriptRuntime) throws {
            prototype.setProperty("resolve") { (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer, result: borrowing JavaScriptValue.Slot, runtime: borrowing JavaScriptRuntime) in
              let _self = try SharedObject.native(from: this.asObject(in: runtime), as: Cache.self)
              guard arguments.count >= 0 && arguments.count <= 1 else {
                throw Exceptions.ArgumentsRangeMismatch((functionName: "resolve", received: arguments.count, required: 0, maximum: 1))
              }
              let value: MyRecord?
              switch arguments.count {
              case 0:
                value = _self.resolve(nil)
              default:
                let arg0 = try MyRecord?.decode(arguments.unownedValue(at: 0), in: runtime)
                value = _self.resolve(arg0)
              }
              try MyRecord?.encode(value, into: result, in: runtime)
            }
          }

          private func _assertTypesConformance() {
            func resolve(_: (some JavaScriptDecodable & ~Copyable).Type, returning _: (some JavaScriptEncodable & ~Copyable).Type) {
            }
            resolve(MyRecord.self, returning: MyRecord.self)
          }
        }
        """
    )
  }

  @Test
  func `Escaped class name registers the bare JS class name`() {
    assertExpansion(
      """
      @SharedObject
      final class `Type`: SharedObject {
        @JS
        func `default`() {}
      }
      """,
      expandedSource: """
        final class `Type`: SharedObject {
          @JavaScriptActor
          func `default`() {}

          public override class var _jsName: String {
            "Type"
          }

          @JavaScriptActor
          public override class func _decorateSharedObject(prototype: borrowing JavaScriptObject, in runtime: JavaScriptRuntime) throws {
            prototype.setProperty("default") { (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer) -> Void in
              let _self = try SharedObject.native(from: this.asObject(in: runtime), as: `Type`.self)
              guard arguments.count == 0 else {
                throw Exceptions.ArgumentsRangeMismatch((functionName: "default", received: arguments.count, required: 0, maximum: 0))
              }
              _self.`default`()
            }
          }
        }
        """
    )
  }

  @Test
  func `Tuple type aliases in the shared object body resolve in @JS members`() {
    assertExpansion(
      """
      @SharedObject
      final class Canvas: SharedObject {
        typealias Size = (width: Double, height: Double)

        @JS
        var size: Size = (0, 0)
      }
      """,
      expandedSource: """
        final class Canvas: SharedObject {
          typealias Size = (width: Double, height: Double)
          @JavaScriptActor
          var size: Size = (0, 0)

          public override class var _jsName: String {
            "Canvas"
          }

          @JavaScriptActor
          public override class func _decorateSharedObject(prototype: borrowing JavaScriptObject, in runtime: JavaScriptRuntime) throws {
            let sizeDescriptor = runtime.createObject()
            sizeDescriptor.setProperty("enumerable", value: true)
            sizeDescriptor.setProperty("get") { (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer, result: borrowing JavaScriptValue.Slot, runtime: borrowing JavaScriptRuntime) in
              let _self = try SharedObject.native(from: this.asObject(in: runtime), as: Canvas.self)
              try JavaScriptValue.encodeTuple(_self.size as (Double, Double), labels: ["width", "height"], into: result, in: runtime)
            }
            sizeDescriptor.setProperty("set") { (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer, result: borrowing JavaScriptValue.Slot, runtime: borrowing JavaScriptRuntime) in
              let _self = try SharedObject.native(from: this.asObject(in: runtime), as: Canvas.self)
              _self.size = try JavaScriptValue.decodeTuple(arguments.unownedValue(at: 0), labels: ["width", "height"], as: Double.self, Double.self, in: runtime)
            }
            prototype.defineProperty("size", descriptor: sizeDescriptor)
          }
        }
        """
    )
  }
}

@Suite("@ExpoModule classes: argument")
struct ExpoModuleClassesTests {
  @Test
  func `classes: list emits _classTypes`() {
    assertExpansion(
      """
      @ExpoModule(classes: [Cache.self, UserSession.self])
      final class MyModule: Module {
      }
      """,
      expandedSource: """
        final class MyModule: Module {

          public static let _jsName = "MyModule"

          public static let _classTypes: [SharedObject.Type] = [Cache.self, UserSession.self]
        }
        """
    )
  }

  @Test
  func `@JS(.concurrent) swaps the @JavaScriptActor stamp for @concurrent`() {
    assertExpansion(
      """
      @SharedObject
      final class Cache: SharedObject {
        @JS(.concurrent)
        func fetch() async -> Int { 1 }
      }
      """,
      expandedSource: """
        final class Cache: SharedObject {
          @concurrent
          func fetch() async -> Int { 1 }

          public override class var _jsName: String {
            "Cache"
          }

          @JavaScriptActor
          public override class func _decorateSharedObject(prototype: borrowing JavaScriptObject, in runtime: JavaScriptRuntime) throws {
            prototype.setProperty("fetch") { (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer) in
              let _self = try SharedObject.native(from: this.asObject(in: runtime), as: Cache.self)
              guard arguments.count == 0 else {
                throw Exceptions.ArgumentsRangeMismatch((functionName: "fetch", received: arguments.count, required: 0, maximum: 0))
              }
              return {
                let result = await _self.fetch()
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
  func `@JS(.withAsync) variants call an instance method on the unwrapped receiver and a static one on the type`() {
    assertExpansion(
      """
      @SharedObject
      final class Document: SharedObject {
        @JS("readSync", .withAsync("read"))
        func read(_ count: Int) throws -> String { "" }

        @JS(.withAsync("existsAsync"))
        static func exists(_ path: String) -> Bool { true }
      }
      """,
      expandedSource: """
        final class Document: SharedObject {
          func read(_ count: Int) throws -> String { "" }
          static func exists(_ path: String) -> Bool { true }

          public override class var _jsName: String {
            "Document"
          }

          @JavaScriptActor
          public override class func _decorateSharedObject(prototype: borrowing JavaScriptObject, in runtime: JavaScriptRuntime) throws {
            prototype.setProperty("readSync") { (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer, result: borrowing JavaScriptValue.Slot, runtime: borrowing JavaScriptRuntime) in
              let _self = try SharedObject.native(from: this.asObject(in: runtime), as: Document.self)
              guard arguments.count == 1 else {
                throw Exceptions.ArgumentsRangeMismatch((functionName: "readSync", received: arguments.count, required: 1, maximum: 1))
              }
              let arg0 = try Int.decode(arguments.unownedValue(at: 0), in: runtime)
              let value = try _self.read(arg0)
              try String.encode(value, into: result, in: runtime)
            }
            prototype.setProperty("read") { (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer) in
              let _self = try SharedObject.native(from: this.asObject(in: runtime), as: Document.self)
              guard arguments.count == 1 else {
                throw Exceptions.ArgumentsRangeMismatch((functionName: "read", received: arguments.count, required: 1, maximum: 1))
              }
              let arg0 = try Int.decode(arguments.unownedValue(at: 0), in: runtime)
              return {
                let result = try await { @concurrent () async throws -> String in
                  try _self.read(arg0)
                }()
                return try await runtime.execute {
                  return try String.encode(result, in: runtime)
                }
              }
            }
          }

          @JavaScriptActor
          public override class func _decorateSharedObject(constructor: borrowing JavaScriptObject, in runtime: JavaScriptRuntime) throws {
            constructor.setProperty("exists") { (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer, result: borrowing JavaScriptValue.Slot, runtime: borrowing JavaScriptRuntime) in
              guard arguments.count == 1 else {
                throw Exceptions.ArgumentsRangeMismatch((functionName: "exists", received: arguments.count, required: 1, maximum: 1))
              }
              let arg0 = try String.decode(arguments.unownedValue(at: 0), in: runtime)
              let value = Document.exists(arg0)
              try Bool.encode(value, into: result, in: runtime)
            }
            constructor.setProperty("existsAsync") { (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer) in
              guard arguments.count == 1 else {
                throw Exceptions.ArgumentsRangeMismatch((functionName: "existsAsync", received: arguments.count, required: 1, maximum: 1))
              }
              let arg0 = try String.decode(arguments.unownedValue(at: 0), in: runtime)
              return {
                let result = await { @concurrent () async -> Bool in
                  Document.exists(arg0)
                }()
                return try await runtime.execute {
                  return try Bool.encode(result, in: runtime)
                }
              }
            }
          }
        }
        """
    )
  }

  @Test
  func `classes: combines with custom module name and exposed members`() {
    assertExpansion(
      """
      @ExpoModule("CustomName", classes: [Cache.self])
      final class MyModule: Module {
        @JS
        func ping() -> String { "pong" }
      }
      """,
      expandedSource: """
        final class MyModule: Module {
          @JavaScriptActor
          func ping() -> String { "pong" }

          public static let _jsName = "CustomName"

          public static let _classTypes: [SharedObject.Type] = [Cache.self]

          @JavaScriptActor
          public func _decorateModule(object: borrowing JavaScriptObject, in runtime: JavaScriptRuntime) throws {
            object.setProperty("ping") { [self] (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer, result: borrowing JavaScriptValue.Slot, runtime: borrowing JavaScriptRuntime) in
              guard arguments.count == 0 else {
                throw Exceptions.ArgumentsRangeMismatch((functionName: "ping", received: arguments.count, required: 0, maximum: 0))
              }
              let value = self.ping()
              try String.encode(value, into: result, in: runtime)
            }
          }
        }
        """
    )
  }
}
