import ExpoModulesMacrosCore
import SwiftSyntax
import SwiftSyntaxMacroExpansion
import SwiftSyntaxMacros
import SwiftSyntaxMacrosGenericTestSupport
import Testing

/// The conformances of the macro declarations in `expo-modules-core`. The other test files leave
/// `Sendable` out, so that their expansions don't repeat the conformance.
private let macroSpecs: [String: MacroSpec] = [
  "ExpoModule": MacroSpec(type: ExpoModuleMacro.self, conformances: ["AnyModule", "Sendable"]),
  "SharedObject": MacroSpec(type: SharedObjectMacro.self, conformances: ["Sendable"]),
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
        }
        """
    )
  }
}
