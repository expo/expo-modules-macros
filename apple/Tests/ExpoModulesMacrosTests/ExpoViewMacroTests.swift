import ExpoModulesMacrosCore
import SwiftSyntax
import SwiftSyntaxMacroExpansion
import SwiftSyntaxMacros
import SwiftSyntaxMacrosGenericTestSupport
import Testing

private let expoViewMacroSpecs: [String: MacroSpec] = [
  "ExpoView": MacroSpec(type: ExpoViewMacro.self, conformances: ["AnyNativeView"])
]

private func assertExpansion(
  _ original: String,
  expandedSource expected: String,
  diagnostics: [DiagnosticSpec] = [],
  applyFixIts: [String]? = nil,
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
    macroSpecs: expoViewMacroSpecs,
    applyFixIts: applyFixIts,
    fixedSource: fixedSource,
    indentationWidth: .spaces(2),
    failureHandler: recordIssue,
    fileID: fileID,
    filePath: filePath,
    line: line,
    column: column
  )
}

@Suite("@ExpoView macro")
struct ExpoViewMacroTests {
  @Test
  func `The generic argument becomes the Props typealias`() {
    assertExpansion(
      """
      @ExpoView<CardProps>
      class CardView: ExpoNativeView {
        func didUpdateProps(_ diff: CardProps.Diff) {
          backgroundColor = props.color
        }
      }
      """,
      expandedSource: """
        class CardView: ExpoNativeView {
          func didUpdateProps(_ diff: CardProps.Diff) {
            backgroundColor = props.color
          }

          public typealias Props = CardProps
        }

        extension CardView: AnyNativeView {
        }
        """
    )
  }

  @Test
  func `A final class is supported`() {
    assertExpansion(
      """
      @ExpoView<CardProps>
      final class CardView: ExpoNativeView {
      }
      """,
      expandedSource: """
        final class CardView: ExpoNativeView {

          public typealias Props = CardProps
        }

        extension CardView: AnyNativeView {
        }
        """
    )
  }

  @Test
  func `A qualified props type is carried through verbatim`() {
    assertExpansion(
      """
      @ExpoView<MyModule.CardProps>
      class CardView: ExpoNativeView {
      }
      """,
      expandedSource: """
        class CardView: ExpoNativeView {

          public typealias Props = MyModule.CardProps
        }

        extension CardView: AnyNativeView {
        }
        """
    )
  }

  @Test
  func `A view inheriting from ExpoNativeView and a protocol is accepted`() {
    assertExpansion(
      """
      @ExpoView<CardProps>
      class CardView: ExpoNativeView, Identifiable {
      }
      """,
      expandedSource: """
        class CardView: ExpoNativeView, Identifiable {

          public typealias Props = CardProps
        }

        extension CardView: AnyNativeView {
        }
        """
    )
  }

  @Test
  func `A class that already conforms to AnyNativeView gets no second conformance`() {
    assertExpansion(
      """
      @ExpoView<CardProps>
      class CardView: ExpoNativeView, AnyNativeView {
      }
      """,
      expandedSource: """
        class CardView: ExpoNativeView, AnyNativeView {

          public typealias Props = CardProps
        }
        """
    )
  }

  @Test
  func `Applying @ExpoView to a struct produces a diagnostic`() {
    assertExpansion(
      """
      @ExpoView<CardProps>
      struct CardView {
      }
      """,
      expandedSource: """
        struct CardView {
        }
        """,
      diagnostics: [
        DiagnosticSpec(
          message: "@ExpoView can only be applied to a class",
          line: 1,
          column: 1
        )
      ]
    )
  }

  @Test
  func `A class not inheriting from ExpoNativeView produces a diagnostic`() {
    assertExpansion(
      """
      @ExpoView<CardProps>
      class CardView: UIView {
      }
      """,
      expandedSource: """
        class CardView: UIView {
        }
        """,
      diagnostics: [
        // No fix-it: replacing a superclass the author chose isn't an edit the macro can make.
        DiagnosticSpec(
          message: "@ExpoView class must inherit from ExpoNativeView. Add `: ExpoNativeView` to the class declaration.",
          line: 2,
          column: 7
        )
      ]
    )
  }

  @Test
  func `A class with no inheritance clause produces a diagnostic`() {
    assertExpansion(
      """
      @ExpoView<CardProps>
      class CardView {
      }
      """,
      expandedSource: """
        class CardView {
        }
        """,
      diagnostics: [
        DiagnosticSpec(
          message: "@ExpoView class must inherit from ExpoNativeView. Add `: ExpoNativeView` to the class declaration.",
          line: 2,
          column: 7,
          fixIts: [FixItSpec(message: "Inherit from 'ExpoNativeView'")]
        )
      ],
      applyFixIts: ["Inherit from 'ExpoNativeView'"],
      fixedSource: """
        @ExpoView<CardProps>
        class CardView: ExpoNativeView {
        }
        """
    )
  }

  @Test
  func `A bare attribute with no generic argument produces a diagnostic`() {
    // Core declares the macro generic, so this spelling normally fails type-checking before
    // expansion ("generic parameter 'Props' could not be inferred"). The macro still reports it,
    // so the message names the attribute if the declaration ever diverges.
    assertExpansion(
      """
      @ExpoView
      class CardView: ExpoNativeView {
      }
      """,
      expandedSource: """
        class CardView: ExpoNativeView {
        }
        """,
      diagnostics: [
        DiagnosticSpec(
          message: "@ExpoView requires its props type as a generic argument, as in `@ExpoView<MyViewProps>`",
          line: 1,
          column: 1
        )
      ]
    )
  }

  @Test
  func `A generic view class produces a diagnostic`() {
    // It would expand fine but could never be registered: `[CardView.self]` on a generic type
    // fails with "generic parameter 'T' could not be inferred".
    assertExpansion(
      """
      @ExpoView<CardProps>
      class CardView<T>: ExpoNativeView {
      }
      """,
      expandedSource: """
        class CardView<T>: ExpoNativeView {
        }
        """,
      diagnostics: [
        DiagnosticSpec(
          message:
            "@ExpoView does not support generic classes — a view registered with @ExpoModule(views:) must be concrete",
          line: 1,
          column: 1
        )
      ]
    )
  }

  @Test
  func `An existing Props typealias produces a diagnostic`() {
    assertExpansion(
      """
      @ExpoView<CardProps>
      class CardView: ExpoNativeView {
        typealias Props = Something
      }
      """,
      expandedSource: """
        class CardView: ExpoNativeView {
          typealias Props = Something
        }
        """,
      diagnostics: [
        DiagnosticSpec(
          message:
            "@ExpoView synthesizes a `Props` typealias, but this class already declares a typealias named 'Props'. Rename it",
          line: 1,
          column: 1
        )
      ]
    )
  }

  @Test
  func `A nested type named Props produces a diagnostic`() {
    assertExpansion(
      """
      @ExpoView<CardProps>
      class CardView: ExpoNativeView {
        struct Props {
        }
      }
      """,
      expandedSource: """
        class CardView: ExpoNativeView {
          struct Props {
          }
        }
        """,
      diagnostics: [
        DiagnosticSpec(
          message:
            "@ExpoView synthesizes a `Props` typealias, but this class already declares a struct named 'Props'. Rename it",
          line: 1,
          column: 1
        )
      ]
    )
  }

  @Test
  func `A class inheriting indirectly is rejected`() {
    // A syntactic macro can't resolve `BaseCardView` to see that it is an ExpoNativeView, so the check
    // matches the class's own inheritance clause only. `@SharedObject` behaves the same way.
    assertExpansion(
      """
      @ExpoView<CardProps>
      class CardView: BaseCardView {
      }
      """,
      expandedSource: """
        class CardView: BaseCardView {
        }
        """,
      diagnostics: [
        DiagnosticSpec(
          message: "@ExpoView class must inherit from ExpoNativeView. Add `: ExpoNativeView` to the class declaration.",
          line: 2,
          column: 7
        )
      ]
    )
  }
}
