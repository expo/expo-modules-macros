import ExpoModulesMacrosCore
import SwiftSyntax
import SwiftSyntaxMacroExpansion
import SwiftSyntaxMacros
import SwiftSyntaxMacrosGenericTestSupport
import Testing

/// The conformances of the macro declarations in `expo-modules-core`. The other test files leave
/// them out, so that their expansions don't repeat the conformances.
private let macroSpecs: [String: MacroSpec] = [
  "ExpoModule": MacroSpec(type: ExpoModuleMacro.self, conformances: ["AnyModule", "Sendable"]),
  "SharedObject": MacroSpec(type: SharedObjectMacro.self, conformances: ["AnySharedObject", "Sendable"]),
]

private func assertExpansion(
  _ original: String,
  expandedSource expected: String,
  fileID: StaticString = #fileID,
  filePath: StaticString = #filePath,
  line: UInt = #line,
  column: UInt = #column
) {
  assertMacroExpansion(
    original,
    expandedSource: expected,
    macroSpecs: macroSpecs,
    indentationWidth: .spaces(2),
    failureHandler: recordIssue,
    fileID: fileID,
    filePath: filePath,
    line: line,
    column: column
  )
}

@Suite("@unchecked Sendable conformance")
struct SendableConformanceTests {
  @Test
  func `@ExpoModule adds @unchecked Sendable to a module`() {
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

        extension MyModule: @unchecked Sendable {
        }
        """
    )
  }

  @Test
  func `@ExpoModule adds AnyModule before @unchecked Sendable to a class without a module superclass`() {
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

        extension MyModule: @unchecked Sendable {
        }
        """
    )
  }

  @Test
  func `@ExpoModule adds nothing to a module that declares @unchecked Sendable`() {
    assertExpansion(
      """
      @ExpoModule
      public final class MyModule: Module, @unchecked Sendable {
      }
      """,
      expandedSource: """
        public final class MyModule: Module, @unchecked Sendable {

          public static let _jsName = "MyModule"
        }
        """
    )
  }

  @Test
  func `@SharedObject adds @unchecked Sendable to a shared object`() {
    assertExpansion(
      """
      @SharedObject
      public final class Cache: SharedObject {
      }
      """,
      expandedSource: """
        public final class Cache: SharedObject {

          public override class var _jsName: String {
            "Cache"
          }

          public override class var _jsClassType: (any AnyJavaScriptClass.Type)? {
            Cache.self
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

        extension Cache: @unchecked Sendable {
        }
        """
    )
  }

  @Test
  func `@SharedObject adds nothing to a shared object that declares Sendable`() {
    assertExpansion(
      """
      @SharedObject
      public final class Cache: SharedObject, Sendable {
      }
      """,
      expandedSource: """
        public final class Cache: SharedObject, Sendable {

          public override class var _jsName: String {
            "Cache"
          }

          public override class var _jsClassType: (any AnyJavaScriptClass.Type)? {
            Cache.self
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
        """
    )
  }

  @Test
  func
    `@SharedObject adds AnySharedObject before @unchecked Sendable to a class whose clause names no shared object base`()
  {
    // The compiler passes `AnySharedObject` only when the class doesn't conform. `expand` passes it
    // for every class, so it reports the conformance for an indirect subclass like this one too.
    assertExpansion(
      """
      @SharedObject
      public final class Thumbnail: ImageRef {
      }
      """,
      expandedSource: """
        public final class Thumbnail: ImageRef {

          public override class var _jsName: String {
            "Thumbnail"
          }

          public override class var _jsClassType: (any AnyJavaScriptClass.Type)? {
            Thumbnail.self
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

        extension Thumbnail: nonisolated AnySharedObject {
        }

        extension Thumbnail: @unchecked Sendable {
        }
        """
    )
  }

  @Test
  func `@SharedObject adds no AnySharedObject to a SharedRef subclass`() {
    assertExpansion(
      """
      @SharedObject
      public final class ImageRef: SharedRef<UIImage> {
      }
      """,
      expandedSource: """
        public final class ImageRef: SharedRef<UIImage> {

          public override class var _jsName: String {
            "ImageRef"
          }

          public override class var _jsClassType: (any AnyJavaScriptClass.Type)? {
            ImageRef.self
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

        extension ImageRef: @unchecked Sendable {
        }
        """
    )
  }

  @Test
  func `@SharedObject adds no AnySharedObject to a class that declares it`() {
    assertExpansion(
      """
      @SharedObject
      public final class Cache: Storage, AnySharedObject {
      }
      """,
      expandedSource: """
        public final class Cache: Storage, AnySharedObject {

          public override class var _jsName: String {
            "Cache"
          }

          public override class var _jsClassType: (any AnyJavaScriptClass.Type)? {
            Cache.self
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

        extension Cache: @unchecked Sendable {
        }
        """
    )
  }

  @Test
  func `@SharedObject adds no AnySharedObject to a class that declares it as nonisolated`() {
    assertExpansion(
      """
      @SharedObject
      public final class Cache: Storage, nonisolated AnySharedObject {
      }
      """,
      expandedSource: """
        public final class Cache: Storage, nonisolated AnySharedObject {

          public override class var _jsName: String {
            "Cache"
          }

          public override class var _jsClassType: (any AnyJavaScriptClass.Type)? {
            Cache.self
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

        extension Cache: @unchecked Sendable {
        }
        """
    )
  }
}
