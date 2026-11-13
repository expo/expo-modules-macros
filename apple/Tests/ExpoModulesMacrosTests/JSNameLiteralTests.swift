import ExpoModulesMacrosCore
import SwiftSyntax
import SwiftSyntaxMacroExpansion
import SwiftSyntaxMacros
import SwiftSyntaxMacrosGenericTestSupport
import Testing

private let nameLiteralMacroSpecs: [String: MacroSpec] = [
  "JS": MacroSpec(type: JSMacro.self),
  "ExpoModule": MacroSpec(type: ExpoModuleMacro.self, conformances: ["AnyModule"]),
  "SharedObject": MacroSpec(type: SharedObjectMacro.self),
  "Event": MacroSpec(type: EventMacro.self),
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
    macroSpecs: nameLiteralMacroSpecs,
    indentationWidth: .spaces(2),
    failureHandler: recordIssue,
    fileID: fileID,
    filePath: filePath,
    line: line,
    column: column
  )
}

@Suite("JavaScript names written as string literals")
struct JSNameLiteralTests {
  @Test
  func `Raw string names are escaped in the generated code`() {
    assertExpansion(
      ##"""
      @ExpoModule(#"My"Module"#)
      public final class Files {
        @JS(#"read"File"#, .withAsync(#"read"FileAsync"#))
        func read() -> Int { 0 }

        @Event(#"on"Change"#)
        var onChange: () -> Void
      }
      """##,
      expandedSource: ##"""
        public final class Files {
          func read() -> Int { 0 }
          var onChange: () -> Void {
            get {
              { [weak self] in
                self?.emit(event: "on\"Change")
              }
            }
          }

          private func _assertTypesConformance_onChange() {
            func onChange(_: (some EventEmitter).Type) {
            }
            onChange(Files.self)
          }

          public static let _jsName = "My\"Module"

          public weak var appContext: AppContext?

          public required init(appContext: AppContext) {
            self.appContext = appContext
          }

          @JavaScriptActor
          public func _decorateModule(object: borrowing JavaScriptObject, in runtime: JavaScriptRuntime) throws {
            object.setProperty("read\"File") { [self] (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer, result: borrowing JavaScriptValue.Slot, runtime: borrowing JavaScriptRuntime) in
              guard arguments.count == 0 else {
                throw Exceptions.ArgumentsRangeMismatch((functionName: "read\"File", received: arguments.count, required: 0, maximum: 0))
              }
              let value = self.read()
              try Int.encode(value, into: result, in: runtime)
            }
            object.setProperty("read\"FileAsync") { [self] (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer) in
              guard arguments.count == 0 else {
                throw Exceptions.ArgumentsRangeMismatch((functionName: "read\"FileAsync", received: arguments.count, required: 0, maximum: 0))
              }
              return {
                let result = await { @concurrent () async -> Int in
                  self.read()
                }()
                return try await runtime.execute {
                  return try Int.encode(result, in: runtime)
                }
              }
            }
          }
        }

        extension Files: AnyModule {
        }
        """##
    )
  }

  @Test
  func `A shared object name with an escape sequence is the value of the literal`() {
    assertExpansion(
      #"""
      @SharedObject("Ca\u{63}he")
      public final class Cache: SharedObject {
      }
      """#,
      expandedSource: ##"""
        public final class Cache: SharedObject {

          public override class var _jsName: String {
            "Cache"
          }
        }
        """##
    )
  }

  @Test
  func `Two literals with the same value name the same member`() {
    assertExpansion(
      #"""
      @ExpoModule
      public final class Files {
        @JS("read")
        func read() -> Int { 0 }

        @JS("r\u{65}ad")
        func other() -> Int { 0 }
      }
      """#,
      expandedSource: ##"""
        public final class Files {
          @JavaScriptActor
          func read() -> Int { 0 }
          @JavaScriptActor
          func other() -> Int { 0 }

          public static let _jsName = "Files"

          public weak var appContext: AppContext?

          public required init(appContext: AppContext) {
            self.appContext = appContext
          }

          @JavaScriptActor
          public func _decorateModule(object: borrowing JavaScriptObject, in runtime: JavaScriptRuntime) throws {
            object.setProperty("read") { [self] (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer, result: borrowing JavaScriptValue.Slot, runtime: borrowing JavaScriptRuntime) in
              guard arguments.count == 0 else {
                throw Exceptions.ArgumentsRangeMismatch((functionName: "read", received: arguments.count, required: 0, maximum: 0))
              }
              let value = self.read()
              try Int.encode(value, into: result, in: runtime)
            }
            object.setProperty("read") { [self] (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer, result: borrowing JavaScriptValue.Slot, runtime: borrowing JavaScriptRuntime) in
              guard arguments.count == 0 else {
                throw Exceptions.ArgumentsRangeMismatch((functionName: "read", received: arguments.count, required: 0, maximum: 0))
              }
              let value = self.other()
              try Int.encode(value, into: result, in: runtime)
            }
          }
        }

        extension Files: AnyModule {
        }
        """##,
      diagnostics: [
        DiagnosticSpec(
          message:
            "The JavaScript name 'read' is already bound by an earlier @JS function. A JavaScript object holds one member per name, so JavaScript could reach only one of them. Give one of them another name with @JS(\"...\").",
          line: 7,
          column: 8,
          severity: .error,
          notes: [NoteSpec(message: "'read' is first bound here", line: 4, column: 8)]
        )
      ]
    )
  }
}
