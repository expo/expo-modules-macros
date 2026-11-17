import ExpoModulesMacrosCore
import SwiftSyntax
import SwiftSyntaxMacroExpansion
import SwiftSyntaxMacros
import SwiftSyntaxMacrosGenericTestSupport
import Testing

private let expoViewMacroSpecs: [String: MacroSpec] = [
  "ExpoView": MacroSpec(type: ExpoViewMacro.self, conformances: ["AnyNativeUIKitView", "AnyNativeSwiftUIView"])
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

        extension CardView: AnyNativeUIKitView {
        }
        """
    )
  }

  @Test
  func `didUpdateProps with another parameter type produces a warning with a fix-it`() {
    assertExpansion(
      """
      @ExpoView<CardProps>
      class CardView: ExpoNativeView {
        func didUpdateProps(_ diff: OtherProps.Diff) {}
      }
      """,
      expandedSource: """
        class CardView: ExpoNativeView {
          func didUpdateProps(_ diff: OtherProps.Diff) {}

          public typealias Props = CardProps
        }

        extension CardView: AnyNativeUIKitView {
        }
        """,
      diagnostics: [
        DiagnosticSpec(
          message:
            "'didUpdateProps' never runs, because it doesn't match the method that core calls: 'func didUpdateProps(_ diff: CardProps.Diff)', which isn't 'async', doesn't throw and returns nothing. Change the method to match it",
          line: 3,
          column: 8,
          severity: .warning,
          fixIts: [FixItSpec(message: "Change the parameter to '_ diff: CardProps.Diff'")]
        )
      ],
      applyFixIts: ["Change the parameter to '_ diff: CardProps.Diff'"],
      fixedSource: """
        @ExpoView<CardProps>
        class CardView: ExpoNativeView {
          func didUpdateProps(_ diff: CardProps.Diff) {}
        }
        """
    )
  }

  @Test
  func `didUpdateProps with a parameter label produces a warning with a fix-it`() {
    assertExpansion(
      """
      @ExpoView<CardProps>
      class CardView: ExpoNativeView {
        func didUpdateProps(diff: CardProps.Diff) {}
      }
      """,
      expandedSource: """
        class CardView: ExpoNativeView {
          func didUpdateProps(diff: CardProps.Diff) {}

          public typealias Props = CardProps
        }

        extension CardView: AnyNativeUIKitView {
        }
        """,
      diagnostics: [
        DiagnosticSpec(
          message:
            "'didUpdateProps' never runs, because it doesn't match the method that core calls: 'func didUpdateProps(_ diff: CardProps.Diff)', which isn't 'async', doesn't throw and returns nothing. Change the method to match it",
          line: 3,
          column: 8,
          severity: .warning,
          fixIts: [FixItSpec(message: "Change the parameter to '_ diff: CardProps.Diff'")]
        )
      ],
      applyFixIts: ["Change the parameter to '_ diff: CardProps.Diff'"],
      fixedSource: """
        @ExpoView<CardProps>
        class CardView: ExpoNativeView {
          func didUpdateProps(_ diff: CardProps.Diff) {}
        }
        """
    )
  }

  @Test
  func `An async, throwing or returning didUpdateProps produces a warning without a fix-it`() {
    assertExpansion(
      """
      @ExpoView<CardProps>
      class AsyncCardView: ExpoNativeView {
        func didUpdateProps(_ diff: CardProps.Diff) async {}
      }

      @ExpoView<CardProps>
      class ThrowingCardView: ExpoNativeView {
        func didUpdateProps(_ diff: CardProps.Diff) throws {}
      }

      @ExpoView<CardProps>
      class ReturningCardView: ExpoNativeView {
        func didUpdateProps(_ diff: CardProps.Diff) -> Bool { true }
      }
      """,
      expandedSource: """
        class AsyncCardView: ExpoNativeView {
          func didUpdateProps(_ diff: CardProps.Diff) async {}

          public typealias Props = CardProps
        }
        class ThrowingCardView: ExpoNativeView {
          func didUpdateProps(_ diff: CardProps.Diff) throws {}

          public typealias Props = CardProps
        }
        class ReturningCardView: ExpoNativeView {
          func didUpdateProps(_ diff: CardProps.Diff) -> Bool { true }

          public typealias Props = CardProps
        }

        extension AsyncCardView: AnyNativeUIKitView {
        }

        extension ThrowingCardView: AnyNativeUIKitView {
        }

        extension ReturningCardView: AnyNativeUIKitView {
        }
        """,
      diagnostics: [
        DiagnosticSpec(
          message:
            "'didUpdateProps' never runs, because it doesn't match the method that core calls: 'func didUpdateProps(_ diff: CardProps.Diff)', which isn't 'async', doesn't throw and returns nothing. Change the method to match it",
          line: 3,
          column: 8,
          severity: .warning
        ),
        DiagnosticSpec(
          message:
            "'didUpdateProps' never runs, because it doesn't match the method that core calls: 'func didUpdateProps(_ diff: CardProps.Diff)', which isn't 'async', doesn't throw and returns nothing. Change the method to match it",
          line: 8,
          column: 8,
          severity: .warning
        ),
        DiagnosticSpec(
          message:
            "'didUpdateProps' never runs, because it doesn't match the method that core calls: 'func didUpdateProps(_ diff: CardProps.Diff)', which isn't 'async', doesn't throw and returns nothing. Change the method to match it",
          line: 13,
          column: 8,
          severity: .warning
        ),
      ]
    )
  }

  @Test
  func `didUpdateProps that returns Void gets no warning`() {
    assertExpansion(
      """
      @ExpoView<CardProps>
      class CardView: ExpoNativeView {
        func didUpdateProps(_ diff: CardProps.Diff) -> Void {}
      }
      """,
      expandedSource: """
        class CardView: ExpoNativeView {
          func didUpdateProps(_ diff: CardProps.Diff) -> Void {}

          public typealias Props = CardProps
        }

        extension CardView: AnyNativeUIKitView {
        }
        """
    )
  }

  @Test
  func `didUpdateProps that takes the generic diff or Props.Diff gets no warning`() {
    assertExpansion(
      """
      @ExpoView<CardProps>
      class CardView: ExpoNativeView {
        func didUpdateProps(_ diff: PropsDiff<CardProps>) {}
      }

      @ExpoView<CardProps>
      class OtherCardView: ExpoNativeView {
        func didUpdateProps(_ diff: Props.Diff) {}
      }
      """,
      expandedSource: """
        class CardView: ExpoNativeView {
          func didUpdateProps(_ diff: PropsDiff<CardProps>) {}

          public typealias Props = CardProps
        }
        class OtherCardView: ExpoNativeView {
          func didUpdateProps(_ diff: Props.Diff) {}

          public typealias Props = CardProps
        }

        extension CardView: AnyNativeUIKitView {
        }

        extension OtherCardView: AnyNativeUIKitView {
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

        extension CardView: AnyNativeUIKitView {
        }
        """
    )
  }

  @Test
  func `A name argument becomes the _jsName static`() {
    assertExpansion(
      """
      @ExpoView<CardProps>("FancyCard")
      final class CardView: ExpoNativeView {
      }
      """,
      expandedSource: """
        final class CardView: ExpoNativeView {

          public typealias Props = CardProps

          public nonisolated static let _jsName = "FancyCard"
        }

        extension CardView: AnyNativeUIKitView {
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

        extension CardView: AnyNativeUIKitView {
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

        extension CardView: AnyNativeUIKitView {
        }
        """
    )
  }

  @Test
  func `A class that already conforms to AnyNativeUIKitView gets no second conformance`() {
    assertExpansion(
      """
      @ExpoView<CardProps>
      class CardView: ExpoNativeView, AnyNativeUIKitView {
      }
      """,
      expandedSource: """
        class CardView: ExpoNativeView, AnyNativeUIKitView {

          public typealias Props = CardProps
        }
        """
    )
  }

  @Test
  func `Applying @ExpoView to an enum produces a diagnostic`() {
    assertExpansion(
      """
      @ExpoView<CardProps>
      enum CardView {
      }
      """,
      expandedSource: """
        enum CardView {
        }
        """,
      diagnostics: [
        DiagnosticSpec(
          message: "@ExpoView can only be applied to a class or a struct",
          line: 1,
          column: 1
        )
      ]
    )
  }

  @Test
  func `A SwiftUI view struct gets the props, the children and the initializer`() {
    assertExpansion(
      """
      @ExpoView<SliderProps>
      struct SliderView: View {
        @State private var isEditing = false

        var body: some View {
          Text(props.title)
        }
      }
      """,
      expandedSource: """
        struct SliderView: View {
          @State private var isEditing = false

          var body: some View {
            Text(props.title)
          }

          public typealias Props = SliderProps

          public let props: Props

          public let children: ExpoSwiftUI.Children

          public init(props: Props, children: ExpoSwiftUI.Children) {
            self.props = props
            self.children = children
          }
        }

        extension SliderView: AnyNativeSwiftUIView {
        }
        """
    )
  }

  @Test
  func `A name argument on a struct becomes the _jsName static`() {
    assertExpansion(
      """
      @ExpoView<SliderProps>("Slider")
      struct SliderView: SwiftUI.View {
        var body: some View {
          EmptyView()
        }
      }
      """,
      expandedSource: """
        struct SliderView: SwiftUI.View {
          var body: some View {
            EmptyView()
          }

          public typealias Props = SliderProps

          public let props: Props

          public let children: ExpoSwiftUI.Children

          public init(props: Props, children: ExpoSwiftUI.Children) {
            self.props = props
            self.children = children
          }

          public nonisolated static let _jsName = "Slider"
        }

        extension SliderView: AnyNativeSwiftUIView {
        }
        """
    )
  }

  @Test
  func `A struct that already conforms to AnyNativeSwiftUIView gets no second conformance`() {
    assertExpansion(
      """
      @ExpoView<SliderProps>
      struct SliderView: View, AnyNativeSwiftUIView {
      }
      """,
      expandedSource: """
        struct SliderView: View, AnyNativeSwiftUIView {

          public typealias Props = SliderProps

          public let props: Props

          public let children: ExpoSwiftUI.Children

          public init(props: Props, children: ExpoSwiftUI.Children) {
            self.props = props
            self.children = children
          }
        }
        """
    )
  }

  @Test
  func `A struct without an inheritance clause produces a diagnostic`() {
    assertExpansion(
      """
      @ExpoView<SliderProps>
      struct SliderView {
      }
      """,
      expandedSource: """
        struct SliderView {
        }
        """,
      diagnostics: [
        DiagnosticSpec(
          message: "@ExpoView struct must be a SwiftUI view. Add `: View` to the struct declaration",
          line: 2,
          column: 8,
          fixIts: [FixItSpec(message: "Conform to 'View'")]
        )
      ],
      applyFixIts: ["Conform to 'View'"],
      fixedSource: """
        @ExpoView<SliderProps>
        struct SliderView: View {
        }
        """
    )
  }

  @Test
  func `A struct that conforms to other protocols only produces a diagnostic`() {
    assertExpansion(
      """
      @ExpoView<SliderProps>
      struct SliderView: Equatable {
      }
      """,
      expandedSource: """
        struct SliderView: Equatable {
        }
        """,
      diagnostics: [
        DiagnosticSpec(
          message: "@ExpoView struct must be a SwiftUI view. Add `: View` to the struct declaration",
          line: 2,
          column: 8,
          fixIts: [FixItSpec(message: "Conform to 'View'")]
        )
      ],
      applyFixIts: ["Conform to 'View'"],
      fixedSource: """
        @ExpoView<SliderProps>
        struct SliderView: Equatable, View {
        }
        """
    )
  }

  @Test
  func `A struct that declares props produces a diagnostic`() {
    assertExpansion(
      """
      @ExpoView<SliderProps>
      struct SliderView: View {
        let props: SliderProps
      }
      """,
      expandedSource: """
        struct SliderView: View {
          let props: SliderProps
        }
        """,
      diagnostics: [
        DiagnosticSpec(
          message:
            "@ExpoView synthesizes `props` for a SwiftUI view, but this struct already declares it. Remove or rename it",
          line: 1,
          column: 1
        )
      ]
    )
  }

  @Test
  func `A struct that declares the initializer produces a diagnostic`() {
    assertExpansion(
      """
      @ExpoView<SliderProps>
      struct SliderView: View {
        init(props: SliderProps, children: ExpoSwiftUI.Children) {}
      }
      """,
      expandedSource: """
        struct SliderView: View {
          init(props: SliderProps, children: ExpoSwiftUI.Children) {}
        }
        """,
      diagnostics: [
        DiagnosticSpec(
          message:
            "@ExpoView synthesizes `init(props:children:)` for a SwiftUI view, but this struct already declares it. Remove or rename it",
          line: 1,
          column: 1
        )
      ]
    )
  }

  @Test
  func `A generic view struct produces a diagnostic`() {
    assertExpansion(
      """
      @ExpoView<SliderProps>
      struct SliderView<Label: View>: View {
      }
      """,
      expandedSource: """
        struct SliderView<Label: View>: View {
        }
        """,
      diagnostics: [
        DiagnosticSpec(
          message:
            "@ExpoView does not support generic structs: a view registered with @ExpoModule(views:) must be concrete",
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
          message: "@ExpoView class must inherit from ExpoNativeView. Add `: ExpoNativeView` to the class declaration",
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
          message: "@ExpoView class must inherit from ExpoNativeView. Add `: ExpoNativeView` to the class declaration",
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
            "@ExpoView does not support generic classes: a view registered with @ExpoModule(views:) must be concrete",
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
          message: "@ExpoView class must inherit from ExpoNativeView. Add `: ExpoNativeView` to the class declaration",
          line: 2,
          column: 7
        )
      ]
    )
  }
}
