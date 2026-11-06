import ExpoModulesMacrosCore
import SwiftSyntax
import SwiftSyntaxMacroExpansion
import SwiftSyntaxMacros
import SwiftSyntaxMacrosGenericTestSupport
import Testing

private let viewPropsMacroSpecs: [String: MacroSpec] = [
  "ViewProps": MacroSpec(type: ViewPropsMacro.self, conformances: ["AnyViewProps"])
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
    macroSpecs: viewPropsMacroSpecs,
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

@Suite("@ViewProps macro")
struct ViewPropsMacroTests {
  @Test
  func `Value props get a case and a bit; events get a name`() {
    assertExpansion(
      """
      @ViewProps
      struct CardProps {
        var color: UIColor = .red
        var radius: CGFloat = 0
        var onTap: (TapEvent) -> Void
      }
      """,
      expandedSource: """
        struct CardProps {
          var color: UIColor = .red
          var radius: CGFloat = 0
          var onTap: (TapEvent) -> Void

          nonisolated public enum PropName: String, CaseIterable {
            case color
            case radius
          }

          nonisolated public struct PropSet: OptionSet, Sendable {
            public let rawValue: UInt64

            public init(rawValue: UInt64) {
              self.rawValue = rawValue
            }

            public static let color = PropSet(rawValue: 1 << 0)
            public static let radius = PropSet(rawValue: 1 << 1)
          }

          nonisolated public static let _eventNames: [String] = ["onTap"]

          public typealias Diff = PropsDiff<Self>

          nonisolated public init() {
            self.onTap = { _ in
            }
          }

          @JavaScriptActor
          static func _resetViewProp(_ _name: PropName, in _props: inout Self) {
            switch _name {
            case .color:
              _props.color = .red
            case .radius:
              _props.radius = 0
            }
          }
        }

        extension CardProps: nonisolated AnyViewProps {
          nonisolated public static let allProps = PropSet(rawValue: 0b11)

          /// `@inlinable` so core's raw-key fold can inline the lookup across the module boundary:
          /// it runs once per changed key per props batch.
          @inlinable
          nonisolated public static func propSet(for name: PropName) -> PropSet {
            switch name {
            case .color:
              return .color
            case .radius:
              return .radius
            }
          }

          @JavaScriptActor
          public mutating func _decode(_ name: PropName, from value: borrowing JavaScriptUnownedValue, in runtime: borrowing JavaScriptRuntime) throws {
            if value.isNull() || value.isUndefined() {
              Self._resetViewProp(name, in: &self)
              return
            }
            switch name {
            case .color:
              self.color = try Self._decodeViewProp(value, in: runtime)
            case .radius:
              self.radius = try Self._decodeViewProp(value, in: runtime)
            }
          }
        }
        """
    )
  }

  @Test
  func `Bits follow declaration order`() {
    assertExpansion(
      """
      @ViewProps
      struct Props {
        var a: Int = 0
        var b: Int = 0
        var c: Int = 0
      }
      """,
      expandedSource: """
        struct Props {
          var a: Int = 0
          var b: Int = 0
          var c: Int = 0

          nonisolated public enum PropName: String, CaseIterable {
            case a
            case b
            case c
          }

          nonisolated public struct PropSet: OptionSet, Sendable {
            public let rawValue: UInt64

            public init(rawValue: UInt64) {
              self.rawValue = rawValue
            }

            public static let a = PropSet(rawValue: 1 << 0)
            public static let b = PropSet(rawValue: 1 << 1)
            public static let c = PropSet(rawValue: 1 << 2)
          }

          nonisolated public static let _eventNames: [String] = []

          public typealias Diff = PropsDiff<Self>

          @JavaScriptActor
          static func _resetViewProp(_ _name: PropName, in _props: inout Self) {
            switch _name {
            case .a:
              _props.a = 0
            case .b:
              _props.b = 0
            case .c:
              _props.c = 0
            }
          }
        }

        extension Props: nonisolated AnyViewProps {
          nonisolated public static let allProps = PropSet(rawValue: 0b111)

          /// `@inlinable` so core's raw-key fold can inline the lookup across the module boundary:
          /// it runs once per changed key per props batch.
          @inlinable
          nonisolated public static func propSet(for name: PropName) -> PropSet {
            switch name {
            case .a:
              return .a
            case .b:
              return .b
            case .c:
              return .c
            }
          }

          @JavaScriptActor
          public mutating func _decode(_ name: PropName, from value: borrowing JavaScriptUnownedValue, in runtime: borrowing JavaScriptRuntime) throws {
            if value.isNull() || value.isUndefined() {
              Self._resetViewProp(name, in: &self)
              return
            }
            switch name {
            case .a:
              self.a = try Self._decodeViewProp(value, in: runtime)
            case .b:
              self.b = try Self._decodeViewProp(value, in: runtime)
            case .c:
              self.c = try Self._decodeViewProp(value, in: runtime)
            }
          }
        }
        """
    )
  }

  @Test
  func `Event names are emitted verbatim, keeping the on prefix`() {
    assertExpansion(
      """
      @ViewProps
      struct Props {
        var onTap: () -> Void
        var onClose: (CloseEvent) -> Void
      }
      """,
      expandedSource: """
        struct Props {
          var onTap: () -> Void
          var onClose: (CloseEvent) -> Void

          nonisolated public enum PropName: RawRepresentable, CaseIterable {
            public init?(rawValue: String) {
              return nil
            }

            public var rawValue: String {
              switch self {
              }
            }
          }

          nonisolated public struct PropSet: OptionSet, Sendable {
            public let rawValue: UInt64

            public init(rawValue: UInt64) {
              self.rawValue = rawValue
            }
          }

          nonisolated public static let _eventNames: [String] = ["onTap", "onClose"]

          public typealias Diff = PropsDiff<Self>

          nonisolated public init() {
            self.onTap = {
            }
            self.onClose = { _ in
            }
          }
        }

        extension Props: nonisolated AnyViewProps {
          nonisolated public static let allProps = PropSet(rawValue: 0)

          /// `@inlinable` so core's raw-key fold can inline the lookup across the module boundary:
          /// it runs once per changed key per props batch.
          @inlinable
          nonisolated public static func propSet(for name: PropName) -> PropSet {
            return []
          }

          @JavaScriptActor
          public mutating func _decode(_ name: PropName, from value: borrowing JavaScriptUnownedValue, in runtime: borrowing JavaScriptRuntime) throws {
          }
        }
        """
    )
  }

  @Test
  func `A Sendable function property is still an event`() {
    assertExpansion(
      """
      @ViewProps
      struct Props {
        var onTap: @Sendable (TapEvent) -> Void
      }
      """,
      expandedSource: """
        struct Props {
          var onTap: @Sendable (TapEvent) -> Void

          nonisolated public enum PropName: RawRepresentable, CaseIterable {
            public init?(rawValue: String) {
              return nil
            }

            public var rawValue: String {
              switch self {
              }
            }
          }

          nonisolated public struct PropSet: OptionSet, Sendable {
            public let rawValue: UInt64

            public init(rawValue: UInt64) {
              self.rawValue = rawValue
            }
          }

          nonisolated public static let _eventNames: [String] = ["onTap"]

          public typealias Diff = PropsDiff<Self>

          nonisolated public init() {
            self.onTap = { _ in
            }
          }
        }

        extension Props: nonisolated AnyViewProps {
          nonisolated public static let allProps = PropSet(rawValue: 0)

          /// `@inlinable` so core's raw-key fold can inline the lookup across the module boundary:
          /// it runs once per changed key per props batch.
          @inlinable
          nonisolated public static func propSet(for name: PropName) -> PropSet {
            return []
          }

          @JavaScriptActor
          public mutating func _decode(_ name: PropName, from value: borrowing JavaScriptUnownedValue, in runtime: borrowing JavaScriptRuntime) throws {
          }
        }
        """
    )
  }

  @Test
  func `Static, private and computed properties are ignored`() {
    assertExpansion(
      """
      @ViewProps
      struct Props {
        var color: UIColor = .red
        static var shared: Int = 0
        private var hidden: Int = 0
        lazy var deferred: Int = 0
        var derived: Int {
          return 1
        }
      }
      """,
      expandedSource: """
        struct Props {
          var color: UIColor = .red
          static var shared: Int = 0
          private var hidden: Int = 0
          lazy var deferred: Int = 0
          var derived: Int {
            return 1
          }

          nonisolated public enum PropName: String, CaseIterable {
            case color
          }

          nonisolated public struct PropSet: OptionSet, Sendable {
            public let rawValue: UInt64

            public init(rawValue: UInt64) {
              self.rawValue = rawValue
            }

            public static let color = PropSet(rawValue: 1 << 0)
          }

          nonisolated public static let _eventNames: [String] = []

          public typealias Diff = PropsDiff<Self>

          @JavaScriptActor
          static func _resetViewProp(_ _name: PropName, in _props: inout Self) {
            switch _name {
            case .color:
              _props.color = .red
            }
          }
        }

        extension Props: nonisolated AnyViewProps {
          nonisolated public static let allProps = PropSet(rawValue: 0b1)

          /// `@inlinable` so core's raw-key fold can inline the lookup across the module boundary:
          /// it runs once per changed key per props batch.
          @inlinable
          nonisolated public static func propSet(for name: PropName) -> PropSet {
            switch name {
            case .color:
              return .color
            }
          }

          @JavaScriptActor
          public mutating func _decode(_ name: PropName, from value: borrowing JavaScriptUnownedValue, in runtime: borrowing JavaScriptRuntime) throws {
            if value.isNull() || value.isUndefined() {
              Self._resetViewProp(name, in: &self)
              return
            }
            switch name {
            case .color:
              self.color = try Self._decodeViewProp(value, in: runtime)
            }
          }
        }
        """
    )
  }

  @Test
  func `An optional value prop is a normal prop`() {
    assertExpansion(
      """
      @ViewProps
      struct Props {
        var radius: CGFloat?
      }
      """,
      expandedSource: """
        struct Props {
          var radius: CGFloat?

          nonisolated public enum PropName: String, CaseIterable {
            case radius
          }

          nonisolated public struct PropSet: OptionSet, Sendable {
            public let rawValue: UInt64

            public init(rawValue: UInt64) {
              self.rawValue = rawValue
            }

            public static let radius = PropSet(rawValue: 1 << 0)
          }

          nonisolated public static let _eventNames: [String] = []

          public typealias Diff = PropsDiff<Self>

          @JavaScriptActor
          static func _resetViewProp(_ _name: PropName, in _props: inout Self) {
            switch _name {
            case .radius:
              _props.radius = nil
            }
          }
        }

        extension Props: nonisolated AnyViewProps {
          nonisolated public static let allProps = PropSet(rawValue: 0b1)

          /// `@inlinable` so core's raw-key fold can inline the lookup across the module boundary:
          /// it runs once per changed key per props batch.
          @inlinable
          nonisolated public static func propSet(for name: PropName) -> PropSet {
            switch name {
            case .radius:
              return .radius
            }
          }

          @JavaScriptActor
          public mutating func _decode(_ name: PropName, from value: borrowing JavaScriptUnownedValue, in runtime: borrowing JavaScriptRuntime) throws {
            if value.isNull() || value.isUndefined() {
              Self._resetViewProp(name, in: &self)
              return
            }
            switch name {
            case .radius:
              self.radius = try Self._decodeViewProp(value, in: runtime)
            }
          }
        }
        """
    )
  }

  @Test
  func `A conformance already declared is not repeated`() {
    assertExpansion(
      """
      @ViewProps
      struct Props: AnyViewProps {
        var color: UIColor = .red
      }
      """,
      expandedSource: """
        struct Props: AnyViewProps {
          var color: UIColor = .red

          nonisolated public enum PropName: String, CaseIterable {
            case color
          }

          nonisolated public struct PropSet: OptionSet, Sendable {
            public let rawValue: UInt64

            public init(rawValue: UInt64) {
              self.rawValue = rawValue
            }

            public static let color = PropSet(rawValue: 1 << 0)
          }

          nonisolated public static let _eventNames: [String] = []

          public typealias Diff = PropsDiff<Self>

          @JavaScriptActor
          static func _resetViewProp(_ _name: PropName, in _props: inout Self) {
            switch _name {
            case .color:
              _props.color = .red
            }
          }
        }

        extension Props {
          nonisolated public static let allProps = PropSet(rawValue: 0b1)

          /// `@inlinable` so core's raw-key fold can inline the lookup across the module boundary:
          /// it runs once per changed key per props batch.
          @inlinable
          nonisolated public static func propSet(for name: PropName) -> PropSet {
            switch name {
            case .color:
              return .color
            }
          }

          @JavaScriptActor
          public mutating func _decode(_ name: PropName, from value: borrowing JavaScriptUnownedValue, in runtime: borrowing JavaScriptRuntime) throws {
            if value.isNull() || value.isUndefined() {
              Self._resetViewProp(name, in: &self)
              return
            }
            switch name {
            case .color:
              self.color = try Self._decodeViewProp(value, in: runtime)
            }
          }
        }
        """
    )
  }

  @Test
  func `A conformance already declared as nonisolated is not repeated`() {
    // A module with a default isolation needs `nonisolated` on a conformance that the author declares.
    assertExpansion(
      """
      @ViewProps
      struct Props: nonisolated AnyViewProps {
        var color: UIColor = .red
      }
      """,
      expandedSource: """
        struct Props: nonisolated AnyViewProps {
          var color: UIColor = .red

          nonisolated public enum PropName: String, CaseIterable {
            case color
          }

          nonisolated public struct PropSet: OptionSet, Sendable {
            public let rawValue: UInt64

            public init(rawValue: UInt64) {
              self.rawValue = rawValue
            }

            public static let color = PropSet(rawValue: 1 << 0)
          }

          nonisolated public static let _eventNames: [String] = []

          public typealias Diff = PropsDiff<Self>

          @JavaScriptActor
          static func _resetViewProp(_ _name: PropName, in _props: inout Self) {
            switch _name {
            case .color:
              _props.color = .red
            }
          }
        }

        extension Props {
          nonisolated public static let allProps = PropSet(rawValue: 0b1)

          /// `@inlinable` so core's raw-key fold can inline the lookup across the module boundary:
          /// it runs once per changed key per props batch.
          @inlinable
          nonisolated public static func propSet(for name: PropName) -> PropSet {
            switch name {
            case .color:
              return .color
            }
          }

          @JavaScriptActor
          public mutating func _decode(_ name: PropName, from value: borrowing JavaScriptUnownedValue, in runtime: borrowing JavaScriptRuntime) throws {
            if value.isNull() || value.isUndefined() {
              Self._resetViewProp(name, in: &self)
              return
            }
            switch name {
            case .color:
              self.color = try Self._decodeViewProp(value, in: runtime)
            }
          }
        }
        """
    )
  }

  @Test
  func `Applying @ViewProps to a class produces a diagnostic`() {
    assertExpansion(
      """
      @ViewProps
      class Props {
        var color: UIColor = .red
      }
      """,
      expandedSource: """
        class Props {
          var color: UIColor = .red
        }
        """,
      diagnostics: [
        DiagnosticSpec(
          message:
            "@ViewProps can only be applied to a struct — the class form (for SwiftUI views) is not supported yet",
          line: 1,
          column: 1
        )
      ]
    )
  }

  @Test
  func `An optional event prop produces a diagnostic`() {
    assertExpansion(
      """
      @ViewProps
      struct Props {
        var onTap: ((TapEvent) -> Void)?
      }
      """,
      expandedSource: """
        struct Props {
          var onTap: ((TapEvent) -> Void)?
        }
        """,
      diagnostics: [
        DiagnosticSpec(
          message:
            "Event props cannot be optional — 'onTap' is registered once at view creation, so its presence can't vary. Drop the '?'",
          line: 3,
          column: 14,
          fixIts: [FixItSpec(message: "Make 'onTap' non-optional")]
        )
      ]
    )
  }

  @Test
  func `A leftover @Field attribute produces a diagnostic`() {
    assertExpansion(
      """
      @ViewProps
      struct Props {
        @Field
        var color: UIColor = .red
      }
      """,
      expandedSource: """
        struct Props {
          @Field
          var color: UIColor = .red
        }
        """,
      diagnostics: [
        DiagnosticSpec(
          message:
            "@Field is no longer used: @ViewProps treats every stored property as a prop. Remove the @Field attribute",
          line: 3,
          column: 3,
          fixIts: [FixItSpec(message: "Remove the '@Field' attribute")]
        )
      ]
    )
  }

  @Test
  func `A property with no determinable type produces a diagnostic`() {
    assertExpansion(
      """
      @ViewProps
      struct Props {
        var items = makeItems()
      }
      """,
      expandedSource: """
        struct Props {
          var items = makeItems()
        }
        """,
      diagnostics: [
        DiagnosticSpec(
          message: "@ViewProps props must declare an explicit type — 'items' has none",
          line: 1,
          column: 1
        )
      ]
    )
  }

  @Test
  func `More than 64 value props produces a diagnostic`() {
    // The changed-props mask is a single UInt64, so the 65th value prop has no bit.
    assertExpansion(
      """
      @ViewProps
      struct Props {
        var p0: Int = 0
        var p1: Int = 0
        var p2: Int = 0
        var p3: Int = 0
        var p4: Int = 0
        var p5: Int = 0
        var p6: Int = 0
        var p7: Int = 0
        var p8: Int = 0
        var p9: Int = 0
        var p10: Int = 0
        var p11: Int = 0
        var p12: Int = 0
        var p13: Int = 0
        var p14: Int = 0
        var p15: Int = 0
        var p16: Int = 0
        var p17: Int = 0
        var p18: Int = 0
        var p19: Int = 0
        var p20: Int = 0
        var p21: Int = 0
        var p22: Int = 0
        var p23: Int = 0
        var p24: Int = 0
        var p25: Int = 0
        var p26: Int = 0
        var p27: Int = 0
        var p28: Int = 0
        var p29: Int = 0
        var p30: Int = 0
        var p31: Int = 0
        var p32: Int = 0
        var p33: Int = 0
        var p34: Int = 0
        var p35: Int = 0
        var p36: Int = 0
        var p37: Int = 0
        var p38: Int = 0
        var p39: Int = 0
        var p40: Int = 0
        var p41: Int = 0
        var p42: Int = 0
        var p43: Int = 0
        var p44: Int = 0
        var p45: Int = 0
        var p46: Int = 0
        var p47: Int = 0
        var p48: Int = 0
        var p49: Int = 0
        var p50: Int = 0
        var p51: Int = 0
        var p52: Int = 0
        var p53: Int = 0
        var p54: Int = 0
        var p55: Int = 0
        var p56: Int = 0
        var p57: Int = 0
        var p58: Int = 0
        var p59: Int = 0
        var p60: Int = 0
        var p61: Int = 0
        var p62: Int = 0
        var p63: Int = 0
        var p64: Int = 0
      }
      """,
      expandedSource: """
        struct Props {
          var p0: Int = 0
          var p1: Int = 0
          var p2: Int = 0
          var p3: Int = 0
          var p4: Int = 0
          var p5: Int = 0
          var p6: Int = 0
          var p7: Int = 0
          var p8: Int = 0
          var p9: Int = 0
          var p10: Int = 0
          var p11: Int = 0
          var p12: Int = 0
          var p13: Int = 0
          var p14: Int = 0
          var p15: Int = 0
          var p16: Int = 0
          var p17: Int = 0
          var p18: Int = 0
          var p19: Int = 0
          var p20: Int = 0
          var p21: Int = 0
          var p22: Int = 0
          var p23: Int = 0
          var p24: Int = 0
          var p25: Int = 0
          var p26: Int = 0
          var p27: Int = 0
          var p28: Int = 0
          var p29: Int = 0
          var p30: Int = 0
          var p31: Int = 0
          var p32: Int = 0
          var p33: Int = 0
          var p34: Int = 0
          var p35: Int = 0
          var p36: Int = 0
          var p37: Int = 0
          var p38: Int = 0
          var p39: Int = 0
          var p40: Int = 0
          var p41: Int = 0
          var p42: Int = 0
          var p43: Int = 0
          var p44: Int = 0
          var p45: Int = 0
          var p46: Int = 0
          var p47: Int = 0
          var p48: Int = 0
          var p49: Int = 0
          var p50: Int = 0
          var p51: Int = 0
          var p52: Int = 0
          var p53: Int = 0
          var p54: Int = 0
          var p55: Int = 0
          var p56: Int = 0
          var p57: Int = 0
          var p58: Int = 0
          var p59: Int = 0
          var p60: Int = 0
          var p61: Int = 0
          var p62: Int = 0
          var p63: Int = 0
          var p64: Int = 0
        }
        """,
      diagnostics: [
        DiagnosticSpec(
          message:
            "@ViewProps supports at most 64 value props (the changed-props mask is a UInt64), but this type declares 65; 'p64' is the first over the limit. Event props don't count toward it",
          line: 1,
          column: 1
        )
      ]
    )
  }

  @Test
  func `Exactly 64 value props fills the mask without a diagnostic`() {
    // The boundary case: 64 props occupy bits 0...63 of the UInt64 mask exactly.
    assertExpansion(
      """
      @ViewProps
      struct Props {
        var p0: Int = 0
        var p1: Int = 0
        var p2: Int = 0
        var p3: Int = 0
        var p4: Int = 0
        var p5: Int = 0
        var p6: Int = 0
        var p7: Int = 0
        var p8: Int = 0
        var p9: Int = 0
        var p10: Int = 0
        var p11: Int = 0
        var p12: Int = 0
        var p13: Int = 0
        var p14: Int = 0
        var p15: Int = 0
        var p16: Int = 0
        var p17: Int = 0
        var p18: Int = 0
        var p19: Int = 0
        var p20: Int = 0
        var p21: Int = 0
        var p22: Int = 0
        var p23: Int = 0
        var p24: Int = 0
        var p25: Int = 0
        var p26: Int = 0
        var p27: Int = 0
        var p28: Int = 0
        var p29: Int = 0
        var p30: Int = 0
        var p31: Int = 0
        var p32: Int = 0
        var p33: Int = 0
        var p34: Int = 0
        var p35: Int = 0
        var p36: Int = 0
        var p37: Int = 0
        var p38: Int = 0
        var p39: Int = 0
        var p40: Int = 0
        var p41: Int = 0
        var p42: Int = 0
        var p43: Int = 0
        var p44: Int = 0
        var p45: Int = 0
        var p46: Int = 0
        var p47: Int = 0
        var p48: Int = 0
        var p49: Int = 0
        var p50: Int = 0
        var p51: Int = 0
        var p52: Int = 0
        var p53: Int = 0
        var p54: Int = 0
        var p55: Int = 0
        var p56: Int = 0
        var p57: Int = 0
        var p58: Int = 0
        var p59: Int = 0
        var p60: Int = 0
        var p61: Int = 0
        var p62: Int = 0
        var p63: Int = 0
      }
      """,
      expandedSource: """
        struct Props {
          var p0: Int = 0
          var p1: Int = 0
          var p2: Int = 0
          var p3: Int = 0
          var p4: Int = 0
          var p5: Int = 0
          var p6: Int = 0
          var p7: Int = 0
          var p8: Int = 0
          var p9: Int = 0
          var p10: Int = 0
          var p11: Int = 0
          var p12: Int = 0
          var p13: Int = 0
          var p14: Int = 0
          var p15: Int = 0
          var p16: Int = 0
          var p17: Int = 0
          var p18: Int = 0
          var p19: Int = 0
          var p20: Int = 0
          var p21: Int = 0
          var p22: Int = 0
          var p23: Int = 0
          var p24: Int = 0
          var p25: Int = 0
          var p26: Int = 0
          var p27: Int = 0
          var p28: Int = 0
          var p29: Int = 0
          var p30: Int = 0
          var p31: Int = 0
          var p32: Int = 0
          var p33: Int = 0
          var p34: Int = 0
          var p35: Int = 0
          var p36: Int = 0
          var p37: Int = 0
          var p38: Int = 0
          var p39: Int = 0
          var p40: Int = 0
          var p41: Int = 0
          var p42: Int = 0
          var p43: Int = 0
          var p44: Int = 0
          var p45: Int = 0
          var p46: Int = 0
          var p47: Int = 0
          var p48: Int = 0
          var p49: Int = 0
          var p50: Int = 0
          var p51: Int = 0
          var p52: Int = 0
          var p53: Int = 0
          var p54: Int = 0
          var p55: Int = 0
          var p56: Int = 0
          var p57: Int = 0
          var p58: Int = 0
          var p59: Int = 0
          var p60: Int = 0
          var p61: Int = 0
          var p62: Int = 0
          var p63: Int = 0

          nonisolated public enum PropName: String, CaseIterable {
            case p0
            case p1
            case p2
            case p3
            case p4
            case p5
            case p6
            case p7
            case p8
            case p9
            case p10
            case p11
            case p12
            case p13
            case p14
            case p15
            case p16
            case p17
            case p18
            case p19
            case p20
            case p21
            case p22
            case p23
            case p24
            case p25
            case p26
            case p27
            case p28
            case p29
            case p30
            case p31
            case p32
            case p33
            case p34
            case p35
            case p36
            case p37
            case p38
            case p39
            case p40
            case p41
            case p42
            case p43
            case p44
            case p45
            case p46
            case p47
            case p48
            case p49
            case p50
            case p51
            case p52
            case p53
            case p54
            case p55
            case p56
            case p57
            case p58
            case p59
            case p60
            case p61
            case p62
            case p63
          }

          nonisolated public struct PropSet: OptionSet, Sendable {
            public let rawValue: UInt64

            public init(rawValue: UInt64) {
              self.rawValue = rawValue
            }

            public static let p0 = PropSet(rawValue: 1 << 0)
            public static let p1 = PropSet(rawValue: 1 << 1)
            public static let p2 = PropSet(rawValue: 1 << 2)
            public static let p3 = PropSet(rawValue: 1 << 3)
            public static let p4 = PropSet(rawValue: 1 << 4)
            public static let p5 = PropSet(rawValue: 1 << 5)
            public static let p6 = PropSet(rawValue: 1 << 6)
            public static let p7 = PropSet(rawValue: 1 << 7)
            public static let p8 = PropSet(rawValue: 1 << 8)
            public static let p9 = PropSet(rawValue: 1 << 9)
            public static let p10 = PropSet(rawValue: 1 << 10)
            public static let p11 = PropSet(rawValue: 1 << 11)
            public static let p12 = PropSet(rawValue: 1 << 12)
            public static let p13 = PropSet(rawValue: 1 << 13)
            public static let p14 = PropSet(rawValue: 1 << 14)
            public static let p15 = PropSet(rawValue: 1 << 15)
            public static let p16 = PropSet(rawValue: 1 << 16)
            public static let p17 = PropSet(rawValue: 1 << 17)
            public static let p18 = PropSet(rawValue: 1 << 18)
            public static let p19 = PropSet(rawValue: 1 << 19)
            public static let p20 = PropSet(rawValue: 1 << 20)
            public static let p21 = PropSet(rawValue: 1 << 21)
            public static let p22 = PropSet(rawValue: 1 << 22)
            public static let p23 = PropSet(rawValue: 1 << 23)
            public static let p24 = PropSet(rawValue: 1 << 24)
            public static let p25 = PropSet(rawValue: 1 << 25)
            public static let p26 = PropSet(rawValue: 1 << 26)
            public static let p27 = PropSet(rawValue: 1 << 27)
            public static let p28 = PropSet(rawValue: 1 << 28)
            public static let p29 = PropSet(rawValue: 1 << 29)
            public static let p30 = PropSet(rawValue: 1 << 30)
            public static let p31 = PropSet(rawValue: 1 << 31)
            public static let p32 = PropSet(rawValue: 1 << 32)
            public static let p33 = PropSet(rawValue: 1 << 33)
            public static let p34 = PropSet(rawValue: 1 << 34)
            public static let p35 = PropSet(rawValue: 1 << 35)
            public static let p36 = PropSet(rawValue: 1 << 36)
            public static let p37 = PropSet(rawValue: 1 << 37)
            public static let p38 = PropSet(rawValue: 1 << 38)
            public static let p39 = PropSet(rawValue: 1 << 39)
            public static let p40 = PropSet(rawValue: 1 << 40)
            public static let p41 = PropSet(rawValue: 1 << 41)
            public static let p42 = PropSet(rawValue: 1 << 42)
            public static let p43 = PropSet(rawValue: 1 << 43)
            public static let p44 = PropSet(rawValue: 1 << 44)
            public static let p45 = PropSet(rawValue: 1 << 45)
            public static let p46 = PropSet(rawValue: 1 << 46)
            public static let p47 = PropSet(rawValue: 1 << 47)
            public static let p48 = PropSet(rawValue: 1 << 48)
            public static let p49 = PropSet(rawValue: 1 << 49)
            public static let p50 = PropSet(rawValue: 1 << 50)
            public static let p51 = PropSet(rawValue: 1 << 51)
            public static let p52 = PropSet(rawValue: 1 << 52)
            public static let p53 = PropSet(rawValue: 1 << 53)
            public static let p54 = PropSet(rawValue: 1 << 54)
            public static let p55 = PropSet(rawValue: 1 << 55)
            public static let p56 = PropSet(rawValue: 1 << 56)
            public static let p57 = PropSet(rawValue: 1 << 57)
            public static let p58 = PropSet(rawValue: 1 << 58)
            public static let p59 = PropSet(rawValue: 1 << 59)
            public static let p60 = PropSet(rawValue: 1 << 60)
            public static let p61 = PropSet(rawValue: 1 << 61)
            public static let p62 = PropSet(rawValue: 1 << 62)
            public static let p63 = PropSet(rawValue: 1 << 63)
          }

          nonisolated public static let _eventNames: [String] = []

          public typealias Diff = PropsDiff<Self>

          @JavaScriptActor
          static func _resetViewProp(_ _name: PropName, in _props: inout Self) {
            switch _name {
            case .p0:
              _props.p0 = 0
            case .p1:
              _props.p1 = 0
            case .p2:
              _props.p2 = 0
            case .p3:
              _props.p3 = 0
            case .p4:
              _props.p4 = 0
            case .p5:
              _props.p5 = 0
            case .p6:
              _props.p6 = 0
            case .p7:
              _props.p7 = 0
            case .p8:
              _props.p8 = 0
            case .p9:
              _props.p9 = 0
            case .p10:
              _props.p10 = 0
            case .p11:
              _props.p11 = 0
            case .p12:
              _props.p12 = 0
            case .p13:
              _props.p13 = 0
            case .p14:
              _props.p14 = 0
            case .p15:
              _props.p15 = 0
            case .p16:
              _props.p16 = 0
            case .p17:
              _props.p17 = 0
            case .p18:
              _props.p18 = 0
            case .p19:
              _props.p19 = 0
            case .p20:
              _props.p20 = 0
            case .p21:
              _props.p21 = 0
            case .p22:
              _props.p22 = 0
            case .p23:
              _props.p23 = 0
            case .p24:
              _props.p24 = 0
            case .p25:
              _props.p25 = 0
            case .p26:
              _props.p26 = 0
            case .p27:
              _props.p27 = 0
            case .p28:
              _props.p28 = 0
            case .p29:
              _props.p29 = 0
            case .p30:
              _props.p30 = 0
            case .p31:
              _props.p31 = 0
            case .p32:
              _props.p32 = 0
            case .p33:
              _props.p33 = 0
            case .p34:
              _props.p34 = 0
            case .p35:
              _props.p35 = 0
            case .p36:
              _props.p36 = 0
            case .p37:
              _props.p37 = 0
            case .p38:
              _props.p38 = 0
            case .p39:
              _props.p39 = 0
            case .p40:
              _props.p40 = 0
            case .p41:
              _props.p41 = 0
            case .p42:
              _props.p42 = 0
            case .p43:
              _props.p43 = 0
            case .p44:
              _props.p44 = 0
            case .p45:
              _props.p45 = 0
            case .p46:
              _props.p46 = 0
            case .p47:
              _props.p47 = 0
            case .p48:
              _props.p48 = 0
            case .p49:
              _props.p49 = 0
            case .p50:
              _props.p50 = 0
            case .p51:
              _props.p51 = 0
            case .p52:
              _props.p52 = 0
            case .p53:
              _props.p53 = 0
            case .p54:
              _props.p54 = 0
            case .p55:
              _props.p55 = 0
            case .p56:
              _props.p56 = 0
            case .p57:
              _props.p57 = 0
            case .p58:
              _props.p58 = 0
            case .p59:
              _props.p59 = 0
            case .p60:
              _props.p60 = 0
            case .p61:
              _props.p61 = 0
            case .p62:
              _props.p62 = 0
            case .p63:
              _props.p63 = 0
            }
          }
        }

        extension Props: nonisolated AnyViewProps {
          nonisolated public static let allProps = PropSet(rawValue: 0b1111111111111111111111111111111111111111111111111111111111111111)

          /// `@inlinable` so core's raw-key fold can inline the lookup across the module boundary:
          /// it runs once per changed key per props batch.
          @inlinable
          nonisolated public static func propSet(for name: PropName) -> PropSet {
            switch name {
            case .p0:
              return .p0
            case .p1:
              return .p1
            case .p2:
              return .p2
            case .p3:
              return .p3
            case .p4:
              return .p4
            case .p5:
              return .p5
            case .p6:
              return .p6
            case .p7:
              return .p7
            case .p8:
              return .p8
            case .p9:
              return .p9
            case .p10:
              return .p10
            case .p11:
              return .p11
            case .p12:
              return .p12
            case .p13:
              return .p13
            case .p14:
              return .p14
            case .p15:
              return .p15
            case .p16:
              return .p16
            case .p17:
              return .p17
            case .p18:
              return .p18
            case .p19:
              return .p19
            case .p20:
              return .p20
            case .p21:
              return .p21
            case .p22:
              return .p22
            case .p23:
              return .p23
            case .p24:
              return .p24
            case .p25:
              return .p25
            case .p26:
              return .p26
            case .p27:
              return .p27
            case .p28:
              return .p28
            case .p29:
              return .p29
            case .p30:
              return .p30
            case .p31:
              return .p31
            case .p32:
              return .p32
            case .p33:
              return .p33
            case .p34:
              return .p34
            case .p35:
              return .p35
            case .p36:
              return .p36
            case .p37:
              return .p37
            case .p38:
              return .p38
            case .p39:
              return .p39
            case .p40:
              return .p40
            case .p41:
              return .p41
            case .p42:
              return .p42
            case .p43:
              return .p43
            case .p44:
              return .p44
            case .p45:
              return .p45
            case .p46:
              return .p46
            case .p47:
              return .p47
            case .p48:
              return .p48
            case .p49:
              return .p49
            case .p50:
              return .p50
            case .p51:
              return .p51
            case .p52:
              return .p52
            case .p53:
              return .p53
            case .p54:
              return .p54
            case .p55:
              return .p55
            case .p56:
              return .p56
            case .p57:
              return .p57
            case .p58:
              return .p58
            case .p59:
              return .p59
            case .p60:
              return .p60
            case .p61:
              return .p61
            case .p62:
              return .p62
            case .p63:
              return .p63
            }
          }

          @JavaScriptActor
          public mutating func _decode(_ name: PropName, from value: borrowing JavaScriptUnownedValue, in runtime: borrowing JavaScriptRuntime) throws {
            if value.isNull() || value.isUndefined() {
              Self._resetViewProp(name, in: &self)
              return
            }
            switch name {
            case .p0:
              self.p0 = try Self._decodeViewProp(value, in: runtime)
            case .p1:
              self.p1 = try Self._decodeViewProp(value, in: runtime)
            case .p2:
              self.p2 = try Self._decodeViewProp(value, in: runtime)
            case .p3:
              self.p3 = try Self._decodeViewProp(value, in: runtime)
            case .p4:
              self.p4 = try Self._decodeViewProp(value, in: runtime)
            case .p5:
              self.p5 = try Self._decodeViewProp(value, in: runtime)
            case .p6:
              self.p6 = try Self._decodeViewProp(value, in: runtime)
            case .p7:
              self.p7 = try Self._decodeViewProp(value, in: runtime)
            case .p8:
              self.p8 = try Self._decodeViewProp(value, in: runtime)
            case .p9:
              self.p9 = try Self._decodeViewProp(value, in: runtime)
            case .p10:
              self.p10 = try Self._decodeViewProp(value, in: runtime)
            case .p11:
              self.p11 = try Self._decodeViewProp(value, in: runtime)
            case .p12:
              self.p12 = try Self._decodeViewProp(value, in: runtime)
            case .p13:
              self.p13 = try Self._decodeViewProp(value, in: runtime)
            case .p14:
              self.p14 = try Self._decodeViewProp(value, in: runtime)
            case .p15:
              self.p15 = try Self._decodeViewProp(value, in: runtime)
            case .p16:
              self.p16 = try Self._decodeViewProp(value, in: runtime)
            case .p17:
              self.p17 = try Self._decodeViewProp(value, in: runtime)
            case .p18:
              self.p18 = try Self._decodeViewProp(value, in: runtime)
            case .p19:
              self.p19 = try Self._decodeViewProp(value, in: runtime)
            case .p20:
              self.p20 = try Self._decodeViewProp(value, in: runtime)
            case .p21:
              self.p21 = try Self._decodeViewProp(value, in: runtime)
            case .p22:
              self.p22 = try Self._decodeViewProp(value, in: runtime)
            case .p23:
              self.p23 = try Self._decodeViewProp(value, in: runtime)
            case .p24:
              self.p24 = try Self._decodeViewProp(value, in: runtime)
            case .p25:
              self.p25 = try Self._decodeViewProp(value, in: runtime)
            case .p26:
              self.p26 = try Self._decodeViewProp(value, in: runtime)
            case .p27:
              self.p27 = try Self._decodeViewProp(value, in: runtime)
            case .p28:
              self.p28 = try Self._decodeViewProp(value, in: runtime)
            case .p29:
              self.p29 = try Self._decodeViewProp(value, in: runtime)
            case .p30:
              self.p30 = try Self._decodeViewProp(value, in: runtime)
            case .p31:
              self.p31 = try Self._decodeViewProp(value, in: runtime)
            case .p32:
              self.p32 = try Self._decodeViewProp(value, in: runtime)
            case .p33:
              self.p33 = try Self._decodeViewProp(value, in: runtime)
            case .p34:
              self.p34 = try Self._decodeViewProp(value, in: runtime)
            case .p35:
              self.p35 = try Self._decodeViewProp(value, in: runtime)
            case .p36:
              self.p36 = try Self._decodeViewProp(value, in: runtime)
            case .p37:
              self.p37 = try Self._decodeViewProp(value, in: runtime)
            case .p38:
              self.p38 = try Self._decodeViewProp(value, in: runtime)
            case .p39:
              self.p39 = try Self._decodeViewProp(value, in: runtime)
            case .p40:
              self.p40 = try Self._decodeViewProp(value, in: runtime)
            case .p41:
              self.p41 = try Self._decodeViewProp(value, in: runtime)
            case .p42:
              self.p42 = try Self._decodeViewProp(value, in: runtime)
            case .p43:
              self.p43 = try Self._decodeViewProp(value, in: runtime)
            case .p44:
              self.p44 = try Self._decodeViewProp(value, in: runtime)
            case .p45:
              self.p45 = try Self._decodeViewProp(value, in: runtime)
            case .p46:
              self.p46 = try Self._decodeViewProp(value, in: runtime)
            case .p47:
              self.p47 = try Self._decodeViewProp(value, in: runtime)
            case .p48:
              self.p48 = try Self._decodeViewProp(value, in: runtime)
            case .p49:
              self.p49 = try Self._decodeViewProp(value, in: runtime)
            case .p50:
              self.p50 = try Self._decodeViewProp(value, in: runtime)
            case .p51:
              self.p51 = try Self._decodeViewProp(value, in: runtime)
            case .p52:
              self.p52 = try Self._decodeViewProp(value, in: runtime)
            case .p53:
              self.p53 = try Self._decodeViewProp(value, in: runtime)
            case .p54:
              self.p54 = try Self._decodeViewProp(value, in: runtime)
            case .p55:
              self.p55 = try Self._decodeViewProp(value, in: runtime)
            case .p56:
              self.p56 = try Self._decodeViewProp(value, in: runtime)
            case .p57:
              self.p57 = try Self._decodeViewProp(value, in: runtime)
            case .p58:
              self.p58 = try Self._decodeViewProp(value, in: runtime)
            case .p59:
              self.p59 = try Self._decodeViewProp(value, in: runtime)
            case .p60:
              self.p60 = try Self._decodeViewProp(value, in: runtime)
            case .p61:
              self.p61 = try Self._decodeViewProp(value, in: runtime)
            case .p62:
              self.p62 = try Self._decodeViewProp(value, in: runtime)
            case .p63:
              self.p63 = try Self._decodeViewProp(value, in: runtime)
            }
          }
        }
        """
    )
  }

  @Test
  func `A stored property with observers is still a prop`() {
    assertExpansion(
      """
      @ViewProps
      struct Props {
        var color: UIColor = .red {
          didSet {
            print(color)
          }
        }
      }
      """,
      expandedSource: """
        struct Props {
          var color: UIColor = .red {
            didSet {
              print(color)
            }
          }

          nonisolated public enum PropName: String, CaseIterable {
            case color
          }

          nonisolated public struct PropSet: OptionSet, Sendable {
            public let rawValue: UInt64

            public init(rawValue: UInt64) {
              self.rawValue = rawValue
            }

            public static let color = PropSet(rawValue: 1 << 0)
          }

          nonisolated public static let _eventNames: [String] = []

          public typealias Diff = PropsDiff<Self>

          @JavaScriptActor
          static func _resetViewProp(_ _name: PropName, in _props: inout Self) {
            switch _name {
            case .color:
              _props.color = .red
            }
          }
        }

        extension Props: nonisolated AnyViewProps {
          nonisolated public static let allProps = PropSet(rawValue: 0b1)

          /// `@inlinable` so core's raw-key fold can inline the lookup across the module boundary:
          /// it runs once per changed key per props batch.
          @inlinable
          nonisolated public static func propSet(for name: PropName) -> PropSet {
            switch name {
            case .color:
              return .color
            }
          }

          @JavaScriptActor
          public mutating func _decode(_ name: PropName, from value: borrowing JavaScriptUnownedValue, in runtime: borrowing JavaScriptRuntime) throws {
            if value.isNull() || value.isUndefined() {
              Self._resetViewProp(name, in: &self)
              return
            }
            switch name {
            case .color:
              self.color = try Self._decodeViewProp(value, in: runtime)
            }
          }
        }
        """
    )
  }

  @Test
  func `Several bindings in one declaration are separate props`() {
    assertExpansion(
      """
      @ViewProps
      struct Props {
        var a: Int = 0, b: Int = 0
      }
      """,
      expandedSource: """
        struct Props {
          var a: Int = 0, b: Int = 0

          nonisolated public enum PropName: String, CaseIterable {
            case a
            case b
          }

          nonisolated public struct PropSet: OptionSet, Sendable {
            public let rawValue: UInt64

            public init(rawValue: UInt64) {
              self.rawValue = rawValue
            }

            public static let a = PropSet(rawValue: 1 << 0)
            public static let b = PropSet(rawValue: 1 << 1)
          }

          nonisolated public static let _eventNames: [String] = []

          public typealias Diff = PropsDiff<Self>

          @JavaScriptActor
          static func _resetViewProp(_ _name: PropName, in _props: inout Self) {
            switch _name {
            case .a:
              _props.a = 0
            case .b:
              _props.b = 0
            }
          }
        }

        extension Props: nonisolated AnyViewProps {
          nonisolated public static let allProps = PropSet(rawValue: 0b11)

          /// `@inlinable` so core's raw-key fold can inline the lookup across the module boundary:
          /// it runs once per changed key per props batch.
          @inlinable
          nonisolated public static func propSet(for name: PropName) -> PropSet {
            switch name {
            case .a:
              return .a
            case .b:
              return .b
            }
          }

          @JavaScriptActor
          public mutating func _decode(_ name: PropName, from value: borrowing JavaScriptUnownedValue, in runtime: borrowing JavaScriptRuntime) throws {
            if value.isNull() || value.isUndefined() {
              Self._resetViewProp(name, in: &self)
              return
            }
            switch name {
            case .a:
              self.a = try Self._decodeViewProp(value, in: runtime)
            case .b:
              self.b = try Self._decodeViewProp(value, in: runtime)
            }
          }
        }
        """
    )
  }

  @Test
  func `An escaped name drops its backticks in the wire key`() {
    assertExpansion(
      """
      @ViewProps
      struct Props {
        var `default`: Int = 0
      }
      """,
      expandedSource: """
        struct Props {
          var `default`: Int = 0

          nonisolated public enum PropName: String, CaseIterable {
            case `default` = "default"
          }

          nonisolated public struct PropSet: OptionSet, Sendable {
            public let rawValue: UInt64

            public init(rawValue: UInt64) {
              self.rawValue = rawValue
            }

            public static let `default` = PropSet(rawValue: 1 << 0)
          }

          nonisolated public static let _eventNames: [String] = []

          public typealias Diff = PropsDiff<Self>

          @JavaScriptActor
          static func _resetViewProp(_ _name: PropName, in _props: inout Self) {
            switch _name {
            case .`default`:
              _props.`default` = 0
            }
          }
        }

        extension Props: nonisolated AnyViewProps {
          nonisolated public static let allProps = PropSet(rawValue: 0b1)

          /// `@inlinable` so core's raw-key fold can inline the lookup across the module boundary:
          /// it runs once per changed key per props batch.
          @inlinable
          nonisolated public static func propSet(for name: PropName) -> PropSet {
            switch name {
            case .`default`:
              return .`default`
            }
          }

          @JavaScriptActor
          public mutating func _decode(_ name: PropName, from value: borrowing JavaScriptUnownedValue, in runtime: borrowing JavaScriptRuntime) throws {
            if value.isNull() || value.isUndefined() {
              Self._resetViewProp(name, in: &self)
              return
            }
            switch name {
            case .`default`:
              self.`default` = try Self._decodeViewProp(value, in: runtime)
            }
          }
        }
        """
    )
  }

  @Test
  func `Optional spelled generically is still a rejected event`() {
    assertExpansion(
      """
      @ViewProps
      struct Props {
        var onTap: Optional<() -> Void>
      }
      """,
      expandedSource: """
        struct Props {
          var onTap: Optional<() -> Void>
        }
        """,
      diagnostics: [
        DiagnosticSpec(
          message:
            "Event props cannot be optional — 'onTap' is registered once at view creation, so its presence can't vary. Drop the '?'",
          line: 3,
          column: 14,
          fixIts: [FixItSpec(message: "Make 'onTap' non-optional")]
        )
      ]
    )
  }

  @Test
  func `A prop named rawValue produces a diagnostic`() {
    // It would emit a PropSet static member shadowing the option set's own storage.
    assertExpansion(
      """
      @ViewProps
      struct Props {
        var rawValue: Int = 0
      }
      """,
      expandedSource: """
        struct Props {
          var rawValue: Int = 0
        }
        """,
      diagnostics: [
        DiagnosticSpec(
          message:
            "'rawValue' can't be used as a prop name — it collides with the synthesized PropSet's storage. Rename the property",
          line: 1,
          column: 1
        )
      ]
    )
  }

  @Test
  func `A tuple-destructuring property produces a diagnostic`() {
    assertExpansion(
      """
      @ViewProps
      struct Props {
        var (a, b) = (1, 2)
      }
      """,
      expandedSource: """
        struct Props {
          var (a, b) = (1, 2)
        }
        """,
      diagnostics: [
        DiagnosticSpec(
          message: "@ViewProps does not support tuple-destructuring properties — declare each prop separately",
          line: 1,
          column: 1
        )
      ]
    )
  }

  @Test
  func `A generic props struct produces a diagnostic`() {
    assertExpansion(
      """
      @ViewProps
      struct Props<T> {
        var value: T
      }
      """,
      expandedSource: """
        struct Props<T> {
          var value: T
        }
        """,
      diagnostics: [
        DiagnosticSpec(
          message: "@ViewProps does not support generic types — a view's props type must be concrete",
          line: 1,
          column: 1
        )
      ]
    )
  }

  @Test
  func `The @Field diagnostic offers a removal fix-it`() {
    assertExpansion(
      """
      @ViewProps
      struct Props {
        @Field
        var color: UIColor = .red
      }
      """,
      expandedSource: """
        struct Props {
          @Field
          var color: UIColor = .red
        }
        """,
      diagnostics: [
        DiagnosticSpec(
          message:
            "@Field is no longer used: @ViewProps treats every stored property as a prop. Remove the @Field attribute",
          line: 3,
          column: 3,
          fixIts: [FixItSpec(message: "Remove the '@Field' attribute")]
        )
      ],
      applyFixIts: ["Remove the '@Field' attribute"],
      fixedSource: """
        @ViewProps
        struct Props {
          var color: UIColor = .red
        }
        """
    )
  }

  @Test
  func `The @Field removal fix-it keeps the line break of an attribute on the line of the property`() {
    assertExpansion(
      """
      @ViewProps
      struct Props {
        var title: String = ""
        @Field var color: UIColor = .red
      }
      """,
      expandedSource: """
        struct Props {
          var title: String = ""
          @Field var color: UIColor = .red
        }
        """,
      diagnostics: [
        DiagnosticSpec(
          message:
            "@Field is no longer used: @ViewProps treats every stored property as a prop. Remove the @Field attribute",
          line: 4,
          column: 3,
          fixIts: [FixItSpec(message: "Remove the '@Field' attribute")]
        )
      ],
      applyFixIts: ["Remove the '@Field' attribute"],
      fixedSource: """
        @ViewProps
        struct Props {
          var title: String = ""
          var color: UIColor = .red
        }
        """
    )
  }

  @Test
  func `The @Field removal fix-it keeps the comments around the attribute`() {
    assertExpansion(
      """
      @ViewProps
      struct Props {
        /// The color.
        @Field
        // Red by default.
        var color: UIColor = .red
      }
      """,
      expandedSource: """
        struct Props {
          /// The color.
          @Field
          // Red by default.
          var color: UIColor = .red
        }
        """,
      diagnostics: [
        DiagnosticSpec(
          message:
            "@Field is no longer used: @ViewProps treats every stored property as a prop. Remove the @Field attribute",
          line: 4,
          column: 3,
          fixIts: [FixItSpec(message: "Remove the '@Field' attribute")]
        )
      ],
      applyFixIts: ["Remove the '@Field' attribute"],
      fixedSource: """
        @ViewProps
        struct Props {
          /// The color.
          // Red by default.
          var color: UIColor = .red
        }
        """
    )
  }

  @Test
  func `The @Field removal fix-it keeps a block comment after an attribute on the line of the property`() {
    assertExpansion(
      """
      @ViewProps
      struct Props {
        @Field /* red */ var color: UIColor = .red
      }
      """,
      expandedSource: """
        struct Props {
          @Field /* red */ var color: UIColor = .red
        }
        """,
      diagnostics: [
        DiagnosticSpec(
          message:
            "@Field is no longer used: @ViewProps treats every stored property as a prop. Remove the @Field attribute",
          line: 3,
          column: 3,
          fixIts: [FixItSpec(message: "Remove the '@Field' attribute")]
        )
      ],
      applyFixIts: ["Remove the '@Field' attribute"],
      fixedSource: """
        @ViewProps
        struct Props {
          /* red */ var color: UIColor = .red
        }
        """
    )
  }

  @Test
  func `The @Field removal fix-it keeps a line comment after the attribute`() {
    assertExpansion(
      """
      @ViewProps
      struct Props {
        @Field // red
        var color: UIColor = .red
      }
      """,
      expandedSource: """
        struct Props {
          @Field // red
          var color: UIColor = .red
        }
        """,
      diagnostics: [
        DiagnosticSpec(
          message:
            "@Field is no longer used: @ViewProps treats every stored property as a prop. Remove the @Field attribute",
          line: 3,
          column: 3,
          fixIts: [FixItSpec(message: "Remove the '@Field' attribute")]
        )
      ],
      applyFixIts: ["Remove the '@Field' attribute"],
      fixedSource: """
        @ViewProps
        struct Props {
          // red
          var color: UIColor = .red
        }
        """
    )
  }

  @Test
  func `The @Field removal fix-it keeps the attributes before it`() {
    assertExpansion(
      """
      @ViewProps
      struct Props {
        @MainActor @Field var color: UIColor = .red
      }
      """,
      expandedSource: """
        struct Props {
          @MainActor @Field var color: UIColor = .red
        }
        """,
      diagnostics: [
        DiagnosticSpec(
          message:
            "@Field is no longer used: @ViewProps treats every stored property as a prop. Remove the @Field attribute",
          line: 3,
          column: 14,
          fixIts: [FixItSpec(message: "Remove the '@Field' attribute")]
        )
      ],
      applyFixIts: ["Remove the '@Field' attribute"],
      fixedSource: """
        @ViewProps
        struct Props {
          @MainActor var color: UIColor = .red
        }
        """
    )
  }

  @Test
  func `A @Field attribute with arguments gets no removal fix-it`() {
    assertExpansion(
      """
      @ViewProps
      struct Props {
        @Field(.keyed("borderColor")) var color: UIColor = .red
      }
      """,
      expandedSource: """
        struct Props {
          @Field(.keyed("borderColor")) var color: UIColor = .red
        }
        """,
      diagnostics: [
        DiagnosticSpec(
          message:
            "@Field is no longer used: @ViewProps treats every stored property as a prop, named after the property. Remove the @Field attribute, and rename the property if its arguments set another prop name",
          line: 3,
          column: 3
        )
      ]
    )
  }

  @Test
  func `A @Field attribute with empty parentheses gets the removal fix-it`() {
    assertExpansion(
      """
      @ViewProps
      struct Props {
        @Field() var color: UIColor = .red
      }
      """,
      expandedSource: """
        struct Props {
          @Field() var color: UIColor = .red
        }
        """,
      diagnostics: [
        DiagnosticSpec(
          message:
            "@Field is no longer used: @ViewProps treats every stored property as a prop. Remove the @Field attribute",
          line: 3,
          column: 3,
          fixIts: [FixItSpec(message: "Remove the '@Field' attribute")]
        )
      ],
      applyFixIts: ["Remove the '@Field' attribute"],
      fixedSource: """
        @ViewProps
        struct Props {
          var color: UIColor = .red
        }
        """
    )
  }

  @Test
  func `Reports every @Field attribute, also after one without a fix-it`() {
    assertExpansion(
      """
      @ViewProps
      struct Props {
        @Field(.keyed("borderColor")) var color: UIColor = .red
        @Field var radius: Double = 0
      }
      """,
      expandedSource: """
        struct Props {
          @Field(.keyed("borderColor")) var color: UIColor = .red
          @Field var radius: Double = 0
        }
        """,
      diagnostics: [
        DiagnosticSpec(
          message:
            "@Field is no longer used: @ViewProps treats every stored property as a prop, named after the property. Remove the @Field attribute, and rename the property if its arguments set another prop name",
          line: 3,
          column: 3
        ),
        DiagnosticSpec(
          message:
            "@Field is no longer used: @ViewProps treats every stored property as a prop. Remove the @Field attribute",
          line: 4,
          column: 3,
          fixIts: [FixItSpec(message: "Remove the '@Field' attribute")]
        ),
      ],
      applyFixIts: ["Remove the '@Field' attribute"],
      fixedSource: """
        @ViewProps
        struct Props {
          @Field(.keyed("borderColor")) var color: UIColor = .red
          var radius: Double = 0
        }
        """
    )
  }

  @Test
  func `The optional-event diagnostic offers an unwrapping fix-it`() {
    assertExpansion(
      """
      @ViewProps
      struct Props {
        var onTap: ((TapEvent) -> Void)?
      }
      """,
      expandedSource: """
        struct Props {
          var onTap: ((TapEvent) -> Void)?
        }
        """,
      diagnostics: [
        DiagnosticSpec(
          message:
            "Event props cannot be optional — 'onTap' is registered once at view creation, so its presence can't vary. Drop the '?'",
          line: 3,
          column: 14,
          fixIts: [FixItSpec(message: "Make 'onTap' non-optional")]
        )
      ],
      applyFixIts: ["Make 'onTap' non-optional"],
      fixedSource: """
        @ViewProps
        struct Props {
          var onTap: (TapEvent) -> Void
        }
        """
    )
  }

  @Test
  func `Decodes each value prop and resets a removed one to its default`() {
    // `value` is also the name of a `_decode` parameter, so the generated code reaches the prop
    // through `self.`.
    assertExpansion(
      """
      @ViewProps
      struct Props {
        var title = ""
        var radius: CGFloat = 4
        var value: Int?
        var tint: UIColor?
        var onTap: (TapEvent) -> Void
      }
      """,
      expandedSource: """
        struct Props {
          var title = ""
          var radius: CGFloat = 4
          var value: Int?
          var tint: UIColor?
          var onTap: (TapEvent) -> Void

          nonisolated public enum PropName: String, CaseIterable {
            case title
            case radius
            case value
            case tint
          }

          nonisolated public struct PropSet: OptionSet, Sendable {
            public let rawValue: UInt64

            public init(rawValue: UInt64) {
              self.rawValue = rawValue
            }

            public static let title = PropSet(rawValue: 1 << 0)
            public static let radius = PropSet(rawValue: 1 << 1)
            public static let value = PropSet(rawValue: 1 << 2)
            public static let tint = PropSet(rawValue: 1 << 3)
          }

          nonisolated public static let _eventNames: [String] = ["onTap"]

          public typealias Diff = PropsDiff<Self>

          nonisolated public init() {
            self.onTap = { _ in
            }
          }

          @JavaScriptActor
          static func _resetViewProp(_ _name: PropName, in _props: inout Self) {
            switch _name {
            case .title:
              _props.title = ""
            case .radius:
              _props.radius = 4
            case .value:
              _props.value = nil
            case .tint:
              _props.tint = nil
            }
          }
        }

        extension Props: nonisolated AnyViewProps {
          nonisolated public static let allProps = PropSet(rawValue: 0b1111)

          /// `@inlinable` so core's raw-key fold can inline the lookup across the module boundary:
          /// it runs once per changed key per props batch.
          @inlinable
          nonisolated public static func propSet(for name: PropName) -> PropSet {
            switch name {
            case .title:
              return .title
            case .radius:
              return .radius
            case .value:
              return .value
            case .tint:
              return .tint
            }
          }

          @JavaScriptActor
          public mutating func _decode(_ name: PropName, from value: borrowing JavaScriptUnownedValue, in runtime: borrowing JavaScriptRuntime) throws {
            if value.isNull() || value.isUndefined() {
              Self._resetViewProp(name, in: &self)
              return
            }
            switch name {
            case .title:
              self.title = try Self._decodeViewProp(value, in: runtime)
            case .radius:
              self.radius = try Self._decodeViewProp(value, in: runtime)
            case .value:
              self.value = try Self._decodeViewProp(value, in: runtime)
            case .tint:
              self.tint = try Self._decodeViewProp(value, in: runtime)
            }
          }
        }
        """
    )
  }

  @Test
  func `A removed prop gets its initial value as written`() {
    // The initial values are copied without their trailing comments into a static function of the
    // struct body, where `base` resolves as it does in the property initializer.
    assertExpansion(
      """
      @ViewProps
      struct Props {
        static let base = 2
        var count: Int = base  // two
        var labels: [String: String] = [
          "start": "Start",
          "end": "End",
        ]
        var level: Int = 1 {
          didSet { print(level) }
        }
      }
      """,
      expandedSource: """
        struct Props {
          static let base = 2
          var count: Int = base  // two
          var labels: [String: String] = [
            "start": "Start",
            "end": "End",
          ]
          var level: Int = 1 {
            didSet { print(level) }
          }

          nonisolated public enum PropName: String, CaseIterable {
            case count
            case labels
            case level
          }

          nonisolated public struct PropSet: OptionSet, Sendable {
            public let rawValue: UInt64

            public init(rawValue: UInt64) {
              self.rawValue = rawValue
            }

            public static let count = PropSet(rawValue: 1 << 0)
            public static let labels = PropSet(rawValue: 1 << 1)
            public static let level = PropSet(rawValue: 1 << 2)
          }

          nonisolated public static let _eventNames: [String] = []

          public typealias Diff = PropsDiff<Self>

          @JavaScriptActor
          static func _resetViewProp(_ _name: PropName, in _props: inout Self) {
            switch _name {
            case .count:
              _props.count = base
            case .labels:
              _props.labels = [
              "start": "Start",
              "end": "End",
            ]
            case .level:
              _props.level = 1
            }
          }
        }

        extension Props: nonisolated AnyViewProps {
          nonisolated public static let allProps = PropSet(rawValue: 0b111)

          /// `@inlinable` so core's raw-key fold can inline the lookup across the module boundary:
          /// it runs once per changed key per props batch.
          @inlinable
          nonisolated public static func propSet(for name: PropName) -> PropSet {
            switch name {
            case .count:
              return .count
            case .labels:
              return .labels
            case .level:
              return .level
            }
          }

          @JavaScriptActor
          public mutating func _decode(_ name: PropName, from value: borrowing JavaScriptUnownedValue, in runtime: borrowing JavaScriptRuntime) throws {
            if value.isNull() || value.isUndefined() {
              Self._resetViewProp(name, in: &self)
              return
            }
            switch name {
            case .count:
              self.count = try Self._decodeViewProp(value, in: runtime)
            case .labels:
              self.labels = try Self._decodeViewProp(value, in: runtime)
            case .level:
              self.level = try Self._decodeViewProp(value, in: runtime)
            }
          }
        }
        """
    )
  }

  @Test
  func `An initial value with a # expression is reset from a new instance`() {
    // `#function` and `#line` would give the location of `_resetViewProp`, also inside a string.
    assertExpansion(
      """
      @ViewProps
      struct Props {
        var source: String = #function
        var label: String = "line \\(#line)"
        var count: Int = 1
      }
      """,
      expandedSource: """
        struct Props {
          var source: String = #function
          var label: String = "line \\(#line)"
          var count: Int = 1

          nonisolated public enum PropName: String, CaseIterable {
            case source
            case label
            case count
          }

          nonisolated public struct PropSet: OptionSet, Sendable {
            public let rawValue: UInt64

            public init(rawValue: UInt64) {
              self.rawValue = rawValue
            }

            public static let source = PropSet(rawValue: 1 << 0)
            public static let label = PropSet(rawValue: 1 << 1)
            public static let count = PropSet(rawValue: 1 << 2)
          }

          nonisolated public static let _eventNames: [String] = []

          public typealias Diff = PropsDiff<Self>

          @JavaScriptActor
          static func _resetViewProp(_ _name: PropName, in _props: inout Self) {
            switch _name {
            case .source:
              _props.source = Self().source
            case .label:
              _props.label = Self().label
            case .count:
              _props.count = 1
            }
          }
        }

        extension Props: nonisolated AnyViewProps {
          nonisolated public static let allProps = PropSet(rawValue: 0b111)

          /// `@inlinable` so core's raw-key fold can inline the lookup across the module boundary:
          /// it runs once per changed key per props batch.
          @inlinable
          nonisolated public static func propSet(for name: PropName) -> PropSet {
            switch name {
            case .source:
              return .source
            case .label:
              return .label
            case .count:
              return .count
            }
          }

          @JavaScriptActor
          public mutating func _decode(_ name: PropName, from value: borrowing JavaScriptUnownedValue, in runtime: borrowing JavaScriptRuntime) throws {
            if value.isNull() || value.isUndefined() {
              Self._resetViewProp(name, in: &self)
              return
            }
            switch name {
            case .source:
              self.source = try Self._decodeViewProp(value, in: runtime)
            case .label:
              self.label = try Self._decodeViewProp(value, in: runtime)
            case .count:
              self.count = try Self._decodeViewProp(value, in: runtime)
            }
          }
        }
        """
    )
  }

  @Test
  func `The reset parameters don't hide a name that an initial value uses`() {
    assertExpansion(
      """
      @ViewProps
      struct Props {
        static let _name = "Untitled"
        static let _props = 2
        var title: String = _name
        var count: Int = _props
      }
      """,
      expandedSource: """
        struct Props {
          static let _name = "Untitled"
          static let _props = 2
          var title: String = _name
          var count: Int = _props

          nonisolated public enum PropName: String, CaseIterable {
            case title
            case count
          }

          nonisolated public struct PropSet: OptionSet, Sendable {
            public let rawValue: UInt64

            public init(rawValue: UInt64) {
              self.rawValue = rawValue
            }

            public static let title = PropSet(rawValue: 1 << 0)
            public static let count = PropSet(rawValue: 1 << 1)
          }

          nonisolated public static let _eventNames: [String] = []

          public typealias Diff = PropsDiff<Self>

          @JavaScriptActor
          static func _resetViewProp(_ _name1: PropName, in _props1: inout Self) {
            switch _name1 {
            case .title:
              _props1.title = _name
            case .count:
              _props1.count = _props
            }
          }
        }

        extension Props: nonisolated AnyViewProps {
          nonisolated public static let allProps = PropSet(rawValue: 0b11)

          /// `@inlinable` so core's raw-key fold can inline the lookup across the module boundary:
          /// it runs once per changed key per props batch.
          @inlinable
          nonisolated public static func propSet(for name: PropName) -> PropSet {
            switch name {
            case .title:
              return .title
            case .count:
              return .count
            }
          }

          @JavaScriptActor
          public mutating func _decode(_ name: PropName, from value: borrowing JavaScriptUnownedValue, in runtime: borrowing JavaScriptRuntime) throws {
            if value.isNull() || value.isUndefined() {
              Self._resetViewProp(name, in: &self)
              return
            }
            switch name {
            case .title:
              self.title = try Self._decodeViewProp(value, in: runtime)
            case .count:
              self.count = try Self._decodeViewProp(value, in: runtime)
            }
          }
        }
        """
    )
  }

  @Test
  func `A prop with an attribute is reset from a new instance`() {
    // A property wrapper can change the initial value in `init(wrappedValue:)`, so only `Self()` gives
    // the prop's default.
    assertExpansion(
      """
      @ViewProps
      struct Props {
        @Clamped var level: Int = 15
      }
      """,
      expandedSource: """
        struct Props {
          @Clamped var level: Int = 15

          nonisolated public enum PropName: String, CaseIterable {
            case level
          }

          nonisolated public struct PropSet: OptionSet, Sendable {
            public let rawValue: UInt64

            public init(rawValue: UInt64) {
              self.rawValue = rawValue
            }

            public static let level = PropSet(rawValue: 1 << 0)
          }

          nonisolated public static let _eventNames: [String] = []

          public typealias Diff = PropsDiff<Self>

          @JavaScriptActor
          static func _resetViewProp(_ _name: PropName, in _props: inout Self) {
            switch _name {
            case .level:
              _props.level = Self().level
            }
          }
        }

        extension Props: nonisolated AnyViewProps {
          nonisolated public static let allProps = PropSet(rawValue: 0b1)

          /// `@inlinable` so core's raw-key fold can inline the lookup across the module boundary:
          /// it runs once per changed key per props batch.
          @inlinable
          nonisolated public static func propSet(for name: PropName) -> PropSet {
            switch name {
            case .level:
              return .level
            }
          }

          @JavaScriptActor
          public mutating func _decode(_ name: PropName, from value: borrowing JavaScriptUnownedValue, in runtime: borrowing JavaScriptRuntime) throws {
            if value.isNull() || value.isUndefined() {
              Self._resetViewProp(name, in: &self)
              return
            }
            switch name {
            case .level:
              self.level = try Self._decodeViewProp(value, in: runtime)
            }
          }
        }
        """
    )
  }

  @Test
  func `A value prop without a default produces a diagnostic`() {
    assertExpansion(
      """
      @ViewProps
      struct Props {
        var color: UIColor = .red
        var radius: CGFloat
        var onTap: (TapEvent) -> Void
      }
      """,
      expandedSource: """
        struct Props {
          var color: UIColor = .red
          var radius: CGFloat
          var onTap: (TapEvent) -> Void
        }
        """,
      diagnostics: [
        DiagnosticSpec(
          message:
            "View prop 'radius' needs an initial value, which is its default when React removes the prop. Give it one, or make its type optional with '?', which defaults to nil",
          line: 4,
          column: 7
        )
      ]
    )
  }

  @Test
  func `Reports every value prop without a default, including one written as Optional<T>`() {
    assertExpansion(
      """
      @ViewProps
      struct Props {
        var radius: CGFloat
        var `default`: Int, opacity: Double = 1
        var tint: Optional<UIColor>
      }
      """,
      expandedSource: """
        struct Props {
          var radius: CGFloat
          var `default`: Int, opacity: Double = 1
          var tint: Optional<UIColor>
        }
        """,
      diagnostics: [
        DiagnosticSpec(
          message:
            "View prop 'radius' needs an initial value, which is its default when React removes the prop. Give it one, or make its type optional with '?', which defaults to nil",
          line: 3,
          column: 7
        ),
        DiagnosticSpec(
          message:
            "View prop 'default' needs an initial value, which is its default when React removes the prop. Give it one, or make its type optional with '?', which defaults to nil",
          line: 4,
          column: 7
        ),
        DiagnosticSpec(
          message:
            "View prop 'tint' needs an initial value, which is its default when React removes the prop. A type written as 'Optional<UIColor>' gets no implicit nil, so write it as 'UIColor?'",
          line: 5,
          column: 7,
          fixIts: [FixItSpec(message: "Write the type as 'UIColor?'")]
        ),
      ],
      applyFixIts: ["Write the type as 'UIColor?'"],
      fixedSource: """
        @ViewProps
        struct Props {
          var radius: CGFloat
          var `default`: Int, opacity: Double = 1
          var tint: UIColor?
        }
        """
    )
  }

  @Test
  func `A let value prop produces a diagnostic with a fix-it`() {
    assertExpansion(
      """
      @ViewProps
      struct Props {
        let color: UIColor = .red
      }
      """,
      expandedSource: """
        struct Props {
          let color: UIColor = .red
        }
        """,
      diagnostics: [
        DiagnosticSpec(
          message:
            "View prop 'color' can't be a 'let' constant, because it's assigned whenever React sets or removes the prop. Declare it with 'var'",
          line: 3,
          column: 3,
          fixIts: [FixItSpec(message: "Replace 'let' with 'var'")]
        )
      ],
      applyFixIts: ["Replace 'let' with 'var'"],
      fixedSource: """
        @ViewProps
        struct Props {
          var color: UIColor = .red
        }
        """
    )
  }

  @Test
  func `A let value prop without a default produces both diagnostics`() {
    assertExpansion(
      """
      @ViewProps
      struct Props {
        let radius: CGFloat
      }
      """,
      expandedSource: """
        struct Props {
          let radius: CGFloat
        }
        """,
      diagnostics: [
        DiagnosticSpec(
          message:
            "View prop 'radius' can't be a 'let' constant, because it's assigned whenever React sets or removes the prop. Declare it with 'var'",
          line: 3,
          column: 3,
          fixIts: [FixItSpec(message: "Replace 'let' with 'var'")]
        ),
        DiagnosticSpec(
          message:
            "View prop 'radius' needs an initial value, which is its default when React removes the prop. Give it one, or make its type optional with '?', which defaults to nil",
          line: 3,
          column: 7
        ),
      ]
    )
  }

  @Test
  func `A let declaring several value props gets one diagnostic`() {
    assertExpansion(
      """
      @ViewProps
      struct Props {
        let width: Double = 0, height: Double = 0
      }
      """,
      expandedSource: """
        struct Props {
          let width: Double = 0, height: Double = 0
        }
        """,
      diagnostics: [
        DiagnosticSpec(
          message:
            "View props 'width' and 'height' can't be 'let' constants, because they're assigned whenever React sets or removes the props. Declare them with 'var'",
          line: 3,
          column: 3,
          fixIts: [FixItSpec(message: "Replace 'let' with 'var'")]
        )
      ]
    )
  }

  @Test
  func `Generates init() that gives events without an initial value an empty closure`() {
    assertExpansion(
      """
      @ViewProps
      struct Props {
        var onTap: () -> Void
        var onMove: @Sendable (Double, Double) throws -> ()
        var `default`: (Int) async -> Swift.Void
        var onClose: (CloseEvent) -> Void = { _ in }
      }
      """,
      expandedSource: """
        struct Props {
          var onTap: () -> Void
          var onMove: @Sendable (Double, Double) throws -> ()
          var `default`: (Int) async -> Swift.Void
          var onClose: (CloseEvent) -> Void = { _ in }

          nonisolated public enum PropName: RawRepresentable, CaseIterable {
            public init?(rawValue: String) {
              return nil
            }

            public var rawValue: String {
              switch self {
              }
            }
          }

          nonisolated public struct PropSet: OptionSet, Sendable {
            public let rawValue: UInt64

            public init(rawValue: UInt64) {
              self.rawValue = rawValue
            }
          }

          nonisolated public static let _eventNames: [String] = ["onTap", "onMove", "default", "onClose"]

          public typealias Diff = PropsDiff<Self>

          nonisolated public init() {
            self.onTap = {
            }
            self.onMove = { _, _ in
            }
            self.`default` = { _ in
            }
          }
        }

        extension Props: nonisolated AnyViewProps {
          nonisolated public static let allProps = PropSet(rawValue: 0)

          /// `@inlinable` so core's raw-key fold can inline the lookup across the module boundary:
          /// it runs once per changed key per props batch.
          @inlinable
          nonisolated public static func propSet(for name: PropName) -> PropSet {
            return []
          }

          @JavaScriptActor
          public mutating func _decode(_ name: PropName, from value: borrowing JavaScriptUnownedValue, in runtime: borrowing JavaScriptRuntime) throws {
          }
        }
        """
    )
  }

  @Test
  func `No init() is generated when every event has an initial value`() {
    assertExpansion(
      """
      @ViewProps
      struct Props {
        var onTap: () -> Void = {}
        var onClose: (CloseEvent) -> Void = { _ in }
      }
      """,
      expandedSource: """
        struct Props {
          var onTap: () -> Void = {}
          var onClose: (CloseEvent) -> Void = { _ in }

          nonisolated public enum PropName: RawRepresentable, CaseIterable {
            public init?(rawValue: String) {
              return nil
            }

            public var rawValue: String {
              switch self {
              }
            }
          }

          nonisolated public struct PropSet: OptionSet, Sendable {
            public let rawValue: UInt64

            public init(rawValue: UInt64) {
              self.rawValue = rawValue
            }
          }

          nonisolated public static let _eventNames: [String] = ["onTap", "onClose"]

          public typealias Diff = PropsDiff<Self>
        }

        extension Props: nonisolated AnyViewProps {
          nonisolated public static let allProps = PropSet(rawValue: 0)

          /// `@inlinable` so core's raw-key fold can inline the lookup across the module boundary:
          /// it runs once per changed key per props batch.
          @inlinable
          nonisolated public static func propSet(for name: PropName) -> PropSet {
            return []
          }

          @JavaScriptActor
          public mutating func _decode(_ name: PropName, from value: borrowing JavaScriptUnownedValue, in runtime: borrowing JavaScriptRuntime) throws {
          }
        }
        """
    )
  }

  @Test
  func `No init() is generated when the type declares its own`() {
    assertExpansion(
      """
      @ViewProps
      struct Props {
        var onTap: (TapEvent) -> Void

        init() {
          onTap = { event in print(event) }
        }
      }
      """,
      expandedSource: """
        struct Props {
          var onTap: (TapEvent) -> Void

          init() {
            onTap = { event in print(event) }
          }

          nonisolated public enum PropName: RawRepresentable, CaseIterable {
            public init?(rawValue: String) {
              return nil
            }

            public var rawValue: String {
              switch self {
              }
            }
          }

          nonisolated public struct PropSet: OptionSet, Sendable {
            public let rawValue: UInt64

            public init(rawValue: UInt64) {
              self.rawValue = rawValue
            }
          }

          nonisolated public static let _eventNames: [String] = ["onTap"]

          public typealias Diff = PropsDiff<Self>
        }

        extension Props: nonisolated AnyViewProps {
          nonisolated public static let allProps = PropSet(rawValue: 0)

          /// `@inlinable` so core's raw-key fold can inline the lookup across the module boundary:
          /// it runs once per changed key per props batch.
          @inlinable
          nonisolated public static func propSet(for name: PropName) -> PropSet {
            return []
          }

          @JavaScriptActor
          public mutating func _decode(_ name: PropName, from value: borrowing JavaScriptUnownedValue, in runtime: borrowing JavaScriptRuntime) throws {
          }
        }
        """
    )
  }

  @Test
  func `An event that returns a value produces a diagnostic`() {
    assertExpansion(
      """
      @ViewProps
      struct Props {
        var onTap: (TapEvent) -> Bool
      }
      """,
      expandedSource: """
        struct Props {
          var onTap: (TapEvent) -> Bool
        }
        """,
      diagnostics: [
        DiagnosticSpec(
          message:
            "Event prop 'onTap' must return Void, because an event is sent to JavaScript, which can't return a value. Change the return type 'Bool' to 'Void'",
          line: 3,
          column: 28,
          fixIts: [FixItSpec(message: "Change the return type to 'Void'")]
        )
      ],
      applyFixIts: ["Change the return type to 'Void'"],
      fixedSource: """
        @ViewProps
        struct Props {
          var onTap: (TapEvent) -> Void
        }
        """
    )
  }

  @Test
  func `An implicitly unwrapped value prop needs no initial value`() {
    assertExpansion(
      """
      @ViewProps
      struct Props {
        var radius: CGFloat!
      }
      """,
      expandedSource: """
        struct Props {
          var radius: CGFloat!

          nonisolated public enum PropName: String, CaseIterable {
            case radius
          }

          nonisolated public struct PropSet: OptionSet, Sendable {
            public let rawValue: UInt64

            public init(rawValue: UInt64) {
              self.rawValue = rawValue
            }

            public static let radius = PropSet(rawValue: 1 << 0)
          }

          nonisolated public static let _eventNames: [String] = []

          public typealias Diff = PropsDiff<Self>

          @JavaScriptActor
          static func _resetViewProp(_ _name: PropName, in _props: inout Self) {
            switch _name {
            case .radius:
              _props.radius = nil
            }
          }
        }

        extension Props: nonisolated AnyViewProps {
          nonisolated public static let allProps = PropSet(rawValue: 0b1)

          /// `@inlinable` so core's raw-key fold can inline the lookup across the module boundary:
          /// it runs once per changed key per props batch.
          @inlinable
          nonisolated public static func propSet(for name: PropName) -> PropSet {
            switch name {
            case .radius:
              return .radius
            }
          }

          @JavaScriptActor
          public mutating func _decode(_ name: PropName, from value: borrowing JavaScriptUnownedValue, in runtime: borrowing JavaScriptRuntime) throws {
            if value.isNull() || value.isUndefined() {
              Self._resetViewProp(name, in: &self)
              return
            }
            switch name {
            case .radius:
              self.radius = try Self._decodeViewProp(value, in: runtime)
            }
          }
        }
        """
    )
  }

  @Test
  func `A computed prop with a setter needs no initial value`() {
    assertExpansion(
      """
      @ViewProps
      struct Props {
        var storage: Int = 0
        var size: Int {
          get { storage }
          set { storage = newValue }
        }
      }
      """,
      expandedSource: """
        struct Props {
          var storage: Int = 0
          var size: Int {
            get { storage }
            set { storage = newValue }
          }

          nonisolated public enum PropName: String, CaseIterable {
            case storage
            case size
          }

          nonisolated public struct PropSet: OptionSet, Sendable {
            public let rawValue: UInt64

            public init(rawValue: UInt64) {
              self.rawValue = rawValue
            }

            public static let storage = PropSet(rawValue: 1 << 0)
            public static let size = PropSet(rawValue: 1 << 1)
          }

          nonisolated public static let _eventNames: [String] = []

          public typealias Diff = PropsDiff<Self>

          @JavaScriptActor
          static func _resetViewProp(_ _name: PropName, in _props: inout Self) {
            switch _name {
            case .storage:
              _props.storage = 0
            case .size:
              _props.size = Self().size
            }
          }
        }

        extension Props: nonisolated AnyViewProps {
          nonisolated public static let allProps = PropSet(rawValue: 0b11)

          /// `@inlinable` so core's raw-key fold can inline the lookup across the module boundary:
          /// it runs once per changed key per props batch.
          @inlinable
          nonisolated public static func propSet(for name: PropName) -> PropSet {
            switch name {
            case .storage:
              return .storage
            case .size:
              return .size
            }
          }

          @JavaScriptActor
          public mutating func _decode(_ name: PropName, from value: borrowing JavaScriptUnownedValue, in runtime: borrowing JavaScriptRuntime) throws {
            if value.isNull() || value.isUndefined() {
              Self._resetViewProp(name, in: &self)
              return
            }
            switch name {
            case .storage:
              self.storage = try Self._decodeViewProp(value, in: runtime)
            case .size:
              self.size = try Self._decodeViewProp(value, in: runtime)
            }
          }
        }
        """
    )
  }

  @Test
  func `A public props struct gets a public init()`() {
    // Swift's own `init()` is internal, which a public type's conformance can't use.
    assertExpansion(
      """
      @ViewProps
      public struct Props {
        var color: UIColor = .red
      }
      """,
      expandedSource: """
        public struct Props {
          var color: UIColor = .red

          nonisolated public enum PropName: String, CaseIterable {
            case color
          }

          nonisolated public struct PropSet: OptionSet, Sendable {
            public let rawValue: UInt64

            public init(rawValue: UInt64) {
              self.rawValue = rawValue
            }

            public static let color = PropSet(rawValue: 1 << 0)
          }

          nonisolated public static let _eventNames: [String] = []

          public typealias Diff = PropsDiff<Self>

          nonisolated public init() {
          }

          @JavaScriptActor
          static func _resetViewProp(_ _name: PropName, in _props: inout Self) {
            switch _name {
            case .color:
              _props.color = .red
            }
          }
        }

        extension Props: nonisolated AnyViewProps {
          nonisolated public static let allProps = PropSet(rawValue: 0b1)

          /// `@inlinable` so core's raw-key fold can inline the lookup across the module boundary:
          /// it runs once per changed key per props batch.
          @inlinable
          nonisolated public static func propSet(for name: PropName) -> PropSet {
            switch name {
            case .color:
              return .color
            }
          }

          @JavaScriptActor
          public mutating func _decode(_ name: PropName, from value: borrowing JavaScriptUnownedValue, in runtime: borrowing JavaScriptRuntime) throws {
            if value.isNull() || value.isUndefined() {
              Self._resetViewProp(name, in: &self)
              return
            }
            switch name {
            case .color:
              self.color = try Self._decodeViewProp(value, in: runtime)
            }
          }
        }
        """
    )
  }

  @Test
  func `A props struct with another initializer gets init()`() {
    assertExpansion(
      """
      @ViewProps
      struct Props {
        var color: UIColor = .red

        init(color: UIColor) {
          self.color = color
        }
      }
      """,
      expandedSource: """
        struct Props {
          var color: UIColor = .red

          init(color: UIColor) {
            self.color = color
          }

          nonisolated public enum PropName: String, CaseIterable {
            case color
          }

          nonisolated public struct PropSet: OptionSet, Sendable {
            public let rawValue: UInt64

            public init(rawValue: UInt64) {
              self.rawValue = rawValue
            }

            public static let color = PropSet(rawValue: 1 << 0)
          }

          nonisolated public static let _eventNames: [String] = []

          public typealias Diff = PropsDiff<Self>

          nonisolated public init() {
          }

          @JavaScriptActor
          static func _resetViewProp(_ _name: PropName, in _props: inout Self) {
            switch _name {
            case .color:
              _props.color = .red
            }
          }
        }

        extension Props: nonisolated AnyViewProps {
          nonisolated public static let allProps = PropSet(rawValue: 0b1)

          /// `@inlinable` so core's raw-key fold can inline the lookup across the module boundary:
          /// it runs once per changed key per props batch.
          @inlinable
          nonisolated public static func propSet(for name: PropName) -> PropSet {
            switch name {
            case .color:
              return .color
            }
          }

          @JavaScriptActor
          public mutating func _decode(_ name: PropName, from value: borrowing JavaScriptUnownedValue, in runtime: borrowing JavaScriptRuntime) throws {
            if value.isNull() || value.isUndefined() {
              Self._resetViewProp(name, in: &self)
              return
            }
            switch name {
            case .color:
              self.color = try Self._decodeViewProp(value, in: runtime)
            }
          }
        }
        """
    )
  }

  @Test
  func `The author's init() sets the defaults`() {
    assertExpansion(
      """
      @ViewProps
      struct Props {
        var color: UIColor
        var onTap: (TapEvent) -> Void
        private var cache: [String: Int]

        init() {
          color = .blue
          onTap = { _ in }
          cache = [:]
        }
      }
      """,
      expandedSource: """
        struct Props {
          var color: UIColor
          var onTap: (TapEvent) -> Void
          private var cache: [String: Int]

          init() {
            color = .blue
            onTap = { _ in }
            cache = [:]
          }

          nonisolated public enum PropName: String, CaseIterable {
            case color
          }

          nonisolated public struct PropSet: OptionSet, Sendable {
            public let rawValue: UInt64

            public init(rawValue: UInt64) {
              self.rawValue = rawValue
            }

            public static let color = PropSet(rawValue: 1 << 0)
          }

          nonisolated public static let _eventNames: [String] = ["onTap"]

          public typealias Diff = PropsDiff<Self>

          @JavaScriptActor
          static func _resetViewProp(_ _name: PropName, in _props: inout Self) {
            switch _name {
            case .color:
              _props.color = Self().color
            }
          }
        }

        extension Props: nonisolated AnyViewProps {
          nonisolated public static let allProps = PropSet(rawValue: 0b1)

          /// `@inlinable` so core's raw-key fold can inline the lookup across the module boundary:
          /// it runs once per changed key per props batch.
          @inlinable
          nonisolated public static func propSet(for name: PropName) -> PropSet {
            switch name {
            case .color:
              return .color
            }
          }

          @JavaScriptActor
          public mutating func _decode(_ name: PropName, from value: borrowing JavaScriptUnownedValue, in runtime: borrowing JavaScriptRuntime) throws {
            if value.isNull() || value.isUndefined() {
              Self._resetViewProp(name, in: &self)
              return
            }
            switch name {
            case .color:
              self.color = try Self._decodeViewProp(value, in: runtime)
            }
          }
        }
        """
    )
  }

  @Test
  func `A private stored property without an initial value produces a diagnostic`() {
    assertExpansion(
      """
      @ViewProps
      struct Props {
        var color: UIColor = .red
        private var cache: [String: Int]
        fileprivate var count: Int
        private var note: String?
        private static var shared: Int
      }
      """,
      expandedSource: """
        struct Props {
          var color: UIColor = .red
          private var cache: [String: Int]
          fileprivate var count: Int
          private var note: String?
          private static var shared: Int
        }
        """,
      diagnostics: [
        DiagnosticSpec(
          message:
            "@ViewProps leaves out the private property 'cache', so 'init()' doesn't set it. Give it an initial value, or remove 'private' to make it a prop",
          line: 4,
          column: 15
        ),
        DiagnosticSpec(
          message:
            "@ViewProps leaves out the fileprivate property 'count', so 'init()' doesn't set it. Give it an initial value, or remove 'fileprivate' to make it a prop",
          line: 5,
          column: 19
        ),
      ]
    )
  }

  @Test
  func `A throwing init() produces a diagnostic with a fix-it`() {
    assertExpansion(
      """
      @ViewProps
      struct Props {
        var color: UIColor = .red

        init() throws {
          color = .blue
        }
      }
      """,
      expandedSource: """
        struct Props {
          var color: UIColor = .red

          init() throws {
            color = .blue
          }
        }
        """,
      diagnostics: [
        DiagnosticSpec(
          message:
            "@ViewProps needs a non-throwing 'init()', because core creates the props with 'Self()'. Remove 'throws'",
          line: 5,
          column: 10,
          fixIts: [FixItSpec(message: "Remove 'throws'")]
        )
      ],
      applyFixIts: ["Remove 'throws'"],
      fixedSource: """
        @ViewProps
        struct Props {
          var color: UIColor = .red

          init() {
            color = .blue
          }
        }
        """
    )
  }

  @Test
  func `A typed throws clause of init() is removed as a whole`() {
    assertExpansion(
      """
      @ViewProps
      struct Props {
        var color: UIColor = .red

        init() throws(PropsError) {
          color = .blue
        }
      }
      """,
      expandedSource: """
        struct Props {
          var color: UIColor = .red

          init() throws(PropsError) {
            color = .blue
          }
        }
        """,
      diagnostics: [
        DiagnosticSpec(
          message:
            "@ViewProps needs a non-throwing 'init()', because core creates the props with 'Self()'. Remove 'throws(PropsError)'",
          line: 5,
          column: 10,
          fixIts: [FixItSpec(message: "Remove 'throws(PropsError)'")]
        )
      ],
      applyFixIts: ["Remove 'throws(PropsError)'"],
      fixedSource: """
        @ViewProps
        struct Props {
          var color: UIColor = .red

          init() {
            color = .blue
          }
        }
        """
    )
  }

  @Test
  func `A failable init() produces a diagnostic with a fix-it`() {
    assertExpansion(
      """
      @ViewProps
      struct Props {
        var color: UIColor = .red

        init?() {
          color = .blue
        }
      }
      """,
      expandedSource: """
        struct Props {
          var color: UIColor = .red

          init?() {
            color = .blue
          }
        }
        """,
      diagnostics: [
        DiagnosticSpec(
          message:
            "@ViewProps needs a non-failable 'init()', because core creates the props with 'Self()'. Remove '?'",
          line: 5,
          column: 7,
          fixIts: [FixItSpec(message: "Remove '?'")]
        )
      ],
      applyFixIts: ["Remove '?'"],
      fixedSource: """
        @ViewProps
        struct Props {
          var color: UIColor = .red

          init() {
            color = .blue
          }
        }
        """
    )
  }

  @Test
  func `An implicitly unwrapped failable init() produces a diagnostic with a fix-it`() {
    assertExpansion(
      """
      @ViewProps
      struct Props {
        var color: UIColor = .red

        init!() {
          color = .blue
        }
      }
      """,
      expandedSource: """
        struct Props {
          var color: UIColor = .red

          init!() {
            color = .blue
          }
        }
        """,
      diagnostics: [
        DiagnosticSpec(
          message:
            "@ViewProps needs a non-failable 'init()', because core creates the props with 'Self()'. Remove '!'",
          line: 5,
          column: 7,
          fixIts: [FixItSpec(message: "Remove '!'")]
        )
      ],
      applyFixIts: ["Remove '!'"],
      fixedSource: """
        @ViewProps
        struct Props {
          var color: UIColor = .red

          init() {
            color = .blue
          }
        }
        """
    )
  }

  @Test
  func `An async throwing init() gets one diagnostic for each effect`() {
    assertExpansion(
      """
      @ViewProps
      struct Props {
        var color: UIColor = .red

        init() async throws {
          color = .blue
        }
      }
      """,
      expandedSource: """
        struct Props {
          var color: UIColor = .red

          init() async throws {
            color = .blue
          }
        }
        """,
      diagnostics: [
        DiagnosticSpec(
          message:
            "@ViewProps needs a synchronous 'init()', because core creates the props with 'Self()'. Remove 'async'",
          line: 5,
          column: 10,
          fixIts: [FixItSpec(message: "Remove 'async'")]
        ),
        DiagnosticSpec(
          message:
            "@ViewProps needs a non-throwing 'init()', because core creates the props with 'Self()'. Remove 'throws'",
          line: 5,
          column: 16,
          fixIts: [FixItSpec(message: "Remove 'throws'")]
        ),
      ],
      applyFixIts: ["Remove 'async'", "Remove 'throws'"],
      fixedSource: """
        @ViewProps
        struct Props {
          var color: UIColor = .red

          init() {
            color = .blue
          }
        }
        """
    )
  }

  @Test
  func `Removing async from init() leaves the throws clause well formatted`() {
    assertExpansion(
      """
      @ViewProps
      struct Props {
        var color: UIColor = .red

        init() async throws {
          color = .blue
        }
      }
      """,
      expandedSource: """
        struct Props {
          var color: UIColor = .red

          init() async throws {
            color = .blue
          }
        }
        """,
      diagnostics: [
        DiagnosticSpec(
          message:
            "@ViewProps needs a synchronous 'init()', because core creates the props with 'Self()'. Remove 'async'",
          line: 5,
          column: 10,
          fixIts: [FixItSpec(message: "Remove 'async'")]
        ),
        DiagnosticSpec(
          message:
            "@ViewProps needs a non-throwing 'init()', because core creates the props with 'Self()'. Remove 'throws'",
          line: 5,
          column: 16,
          fixIts: [FixItSpec(message: "Remove 'throws'")]
        ),
      ],
      applyFixIts: ["Remove 'async'"],
      fixedSource: """
        @ViewProps
        struct Props {
          var color: UIColor = .red

          init() throws {
            color = .blue
          }
        }
        """
    )
  }

  @Test
  func `A failable async init() gets one diagnostic for each problem`() {
    assertExpansion(
      """
      @ViewProps
      struct Props {
        var color: UIColor = .red

        init?() async {
          color = .blue
        }
      }
      """,
      expandedSource: """
        struct Props {
          var color: UIColor = .red

          init?() async {
            color = .blue
          }
        }
        """,
      diagnostics: [
        DiagnosticSpec(
          message:
            "@ViewProps needs a non-failable 'init()', because core creates the props with 'Self()'. Remove '?'",
          line: 5,
          column: 7,
          fixIts: [FixItSpec(message: "Remove '?'")]
        ),
        DiagnosticSpec(
          message:
            "@ViewProps needs a synchronous 'init()', because core creates the props with 'Self()'. Remove 'async'",
          line: 5,
          column: 11,
          fixIts: [FixItSpec(message: "Remove 'async'")]
        ),
      ],
      applyFixIts: ["Remove '?'", "Remove 'async'"],
      fixedSource: """
        @ViewProps
        struct Props {
          var color: UIColor = .red

          init() {
            color = .blue
          }
        }
        """
    )
  }

  @Test
  func `An optional event is reported together with the other diagnostics`() {
    assertExpansion(
      """
      @ViewProps
      struct Props {
        var onTap: ((TapEvent) -> Void)?
        var radius: CGFloat
      }
      """,
      expandedSource: """
        struct Props {
          var onTap: ((TapEvent) -> Void)?
          var radius: CGFloat
        }
        """,
      diagnostics: [
        DiagnosticSpec(
          message:
            "Event props cannot be optional — 'onTap' is registered once at view creation, so its presence can't vary. Drop the '?'",
          line: 3,
          column: 14,
          fixIts: [FixItSpec(message: "Make 'onTap' non-optional")]
        ),
        DiagnosticSpec(
          message:
            "View prop 'radius' needs an initial value, which is its default when React removes the prop. Give it one, or make its type optional with '?', which defaults to nil",
          line: 4,
          column: 7
        ),
      ]
    )
  }

  @Test
  func `The Optional<T> fix-it keeps the parentheses around an existential`() {
    assertExpansion(
      """
      @ViewProps
      struct Props {
        var shape: Optional<any Shape>
      }
      """,
      expandedSource: """
        struct Props {
          var shape: Optional<any Shape>
        }
        """,
      diagnostics: [
        DiagnosticSpec(
          message:
            "View prop 'shape' needs an initial value, which is its default when React removes the prop. A type written as 'Optional<any Shape>' gets no implicit nil, so write it as '(any Shape)?'",
          line: 3,
          column: 7,
          fixIts: [FixItSpec(message: "Write the type as '(any Shape)?'")]
        )
      ],
      applyFixIts: ["Write the type as '(any Shape)?'"],
      fixedSource: """
        @ViewProps
        struct Props {
          var shape: (any Shape)?
        }
        """
    )
  }

  @Test
  func `An event that returns Void in parentheses is accepted`() {
    assertExpansion(
      """
      @ViewProps
      struct Props {
        var onTap: () -> (Void)
        var onClose: () -> (())
        var onMove: (Int) -> ((Void))
      }
      """,
      expandedSource: """
        struct Props {
          var onTap: () -> (Void)
          var onClose: () -> (())
          var onMove: (Int) -> ((Void))

          nonisolated public enum PropName: RawRepresentable, CaseIterable {
            public init?(rawValue: String) {
              return nil
            }

            public var rawValue: String {
              switch self {
              }
            }
          }

          nonisolated public struct PropSet: OptionSet, Sendable {
            public let rawValue: UInt64

            public init(rawValue: UInt64) {
              self.rawValue = rawValue
            }
          }

          nonisolated public static let _eventNames: [String] = ["onTap", "onClose", "onMove"]

          public typealias Diff = PropsDiff<Self>

          nonisolated public init() {
            self.onTap = {
            }
            self.onClose = {
            }
            self.onMove = { _ in
            }
          }
        }

        extension Props: nonisolated AnyViewProps {
          nonisolated public static let allProps = PropSet(rawValue: 0)

          /// `@inlinable` so core's raw-key fold can inline the lookup across the module boundary:
          /// it runs once per changed key per props batch.
          @inlinable
          nonisolated public static func propSet(for name: PropName) -> PropSet {
            return []
          }

          @JavaScriptActor
          public mutating func _decode(_ name: PropName, from value: borrowing JavaScriptUnownedValue, in runtime: borrowing JavaScriptRuntime) throws {
          }
        }
        """
    )
  }

  @Test
  func `An event that returns a value in parentheses gets a fix-it for the whole return type`() {
    assertExpansion(
      """
      @ViewProps
      struct Props {
        var onTap: () -> (Bool)
      }
      """,
      expandedSource: """
        struct Props {
          var onTap: () -> (Bool)
        }
        """,
      diagnostics: [
        DiagnosticSpec(
          message:
            "Event prop 'onTap' must return Void, because an event is sent to JavaScript, which can't return a value. Change the return type '(Bool)' to 'Void'",
          line: 3,
          column: 20,
          fixIts: [FixItSpec(message: "Change the return type to 'Void'")]
        )
      ],
      applyFixIts: ["Change the return type to 'Void'"],
      fixedSource: """
        @ViewProps
        struct Props {
          var onTap: () -> Void
        }
        """
    )
  }

  @Test
  func `A computed prop with a mutating getter is reset from a mutable default`() {
    // A mutating getter can't be read from a `let` constant.
    assertExpansion(
      """
      @ViewProps
      struct Props {
        var storage: Int = 0
        var size: Int {
          mutating get { storage }
          set { storage = newValue }
        }
      }
      """,
      expandedSource: """
        struct Props {
          var storage: Int = 0
          var size: Int {
            mutating get { storage }
            set { storage = newValue }
          }

          nonisolated public enum PropName: String, CaseIterable {
            case storage
            case size
          }

          nonisolated public struct PropSet: OptionSet, Sendable {
            public let rawValue: UInt64

            public init(rawValue: UInt64) {
              self.rawValue = rawValue
            }

            public static let storage = PropSet(rawValue: 1 << 0)
            public static let size = PropSet(rawValue: 1 << 1)
          }

          nonisolated public static let _eventNames: [String] = []

          public typealias Diff = PropsDiff<Self>

          @JavaScriptActor
          static func _resetViewProp(_ _name: PropName, in _props: inout Self) {
            switch _name {
            case .storage:
              _props.storage = 0
            case .size:
              var _defaults = Self()
              _props.size = _defaults.size
            }
          }
        }

        extension Props: nonisolated AnyViewProps {
          nonisolated public static let allProps = PropSet(rawValue: 0b11)

          /// `@inlinable` so core's raw-key fold can inline the lookup across the module boundary:
          /// it runs once per changed key per props batch.
          @inlinable
          nonisolated public static func propSet(for name: PropName) -> PropSet {
            switch name {
            case .storage:
              return .storage
            case .size:
              return .size
            }
          }

          @JavaScriptActor
          public mutating func _decode(_ name: PropName, from value: borrowing JavaScriptUnownedValue, in runtime: borrowing JavaScriptRuntime) throws {
            if value.isNull() || value.isUndefined() {
              Self._resetViewProp(name, in: &self)
              return
            }
            switch name {
            case .storage:
              self.storage = try Self._decodeViewProp(value, in: runtime)
            case .size:
              self.size = try Self._decodeViewProp(value, in: runtime)
            }
          }
        }
        """
    )
  }

  @Test
  func `A package props struct gets a public init()`() {
    // Swift's own `init()` is internal, which a package type's conformance can't use.
    assertExpansion(
      """
      @ViewProps
      package struct Props {
        var color: UIColor = .red
      }
      """,
      expandedSource: """
        package struct Props {
          var color: UIColor = .red

          nonisolated public enum PropName: String, CaseIterable {
            case color
          }

          nonisolated public struct PropSet: OptionSet, Sendable {
            public let rawValue: UInt64

            public init(rawValue: UInt64) {
              self.rawValue = rawValue
            }

            public static let color = PropSet(rawValue: 1 << 0)
          }

          nonisolated public static let _eventNames: [String] = []

          public typealias Diff = PropsDiff<Self>

          nonisolated public init() {
          }

          @JavaScriptActor
          static func _resetViewProp(_ _name: PropName, in _props: inout Self) {
            switch _name {
            case .color:
              _props.color = .red
            }
          }
        }

        extension Props: nonisolated AnyViewProps {
          nonisolated public static let allProps = PropSet(rawValue: 0b1)

          /// `@inlinable` so core's raw-key fold can inline the lookup across the module boundary:
          /// it runs once per changed key per props batch.
          @inlinable
          nonisolated public static func propSet(for name: PropName) -> PropSet {
            switch name {
            case .color:
              return .color
            }
          }

          @JavaScriptActor
          public mutating func _decode(_ name: PropName, from value: borrowing JavaScriptUnownedValue, in runtime: borrowing JavaScriptRuntime) throws {
            if value.isNull() || value.isUndefined() {
              Self._resetViewProp(name, in: &self)
              return
            }
            switch name {
            case .color:
              self.color = try Self._decodeViewProp(value, in: runtime)
            }
          }
        }
        """
    )
  }

  @Test
  func `A props struct in a public extension gets a public init()`() {
    // The extension makes the struct public, so Swift's internal `init()` is not enough.
    assertExpansion(
      """
      public extension Outer {
        @ViewProps
        struct Props {
          var color: UIColor = .red
        }
      }
      """,
      expandedSource: """
        public extension Outer {
          struct Props {
            var color: UIColor = .red

            nonisolated public enum PropName: String, CaseIterable {
              case color
            }

            nonisolated public struct PropSet: OptionSet, Sendable {
              public let rawValue: UInt64

              public init(rawValue: UInt64) {
                self.rawValue = rawValue
              }

              public static let color = PropSet(rawValue: 1 << 0)
            }

            nonisolated public static let _eventNames: [String] = []

            public typealias Diff = PropsDiff<Self>

            nonisolated public init() {
            }

            @JavaScriptActor
            static func _resetViewProp(_ _name: PropName, in _props: inout Self) {
              switch _name {
              case .color:
                _props.color = .red
              }
            }
          }
        }

        extension Outer.Props: nonisolated AnyViewProps {
          nonisolated public static let allProps = PropSet(rawValue: 0b1)

          /// `@inlinable` so core's raw-key fold can inline the lookup across the module boundary:
          /// it runs once per changed key per props batch.
          @inlinable
          nonisolated public static func propSet(for name: PropName) -> PropSet {
            switch name {
            case .color:
              return .color
            }
          }

          @JavaScriptActor
          public mutating func _decode(_ name: PropName, from value: borrowing JavaScriptUnownedValue, in runtime: borrowing JavaScriptRuntime) throws {
            if value.isNull() || value.isUndefined() {
              Self._resetViewProp(name, in: &self)
              return
            }
            switch name {
            case .color:
              self.color = try Self._decodeViewProp(value, in: runtime)
            }
          }
        }
        """
    )
  }

  @Test
  func `A props struct in a package extension gets a public init()`() {
    // The extension makes the struct package, so Swift's internal `init()` is not enough.
    assertExpansion(
      """
      package extension Outer {
        @ViewProps
        struct Props {
          var color: UIColor = .red
        }
      }
      """,
      expandedSource: """
        package extension Outer {
          struct Props {
            var color: UIColor = .red

            nonisolated public enum PropName: String, CaseIterable {
              case color
            }

            nonisolated public struct PropSet: OptionSet, Sendable {
              public let rawValue: UInt64

              public init(rawValue: UInt64) {
                self.rawValue = rawValue
              }

              public static let color = PropSet(rawValue: 1 << 0)
            }

            nonisolated public static let _eventNames: [String] = []

            public typealias Diff = PropsDiff<Self>

            nonisolated public init() {
            }

            @JavaScriptActor
            static func _resetViewProp(_ _name: PropName, in _props: inout Self) {
              switch _name {
              case .color:
                _props.color = .red
              }
            }
          }
        }

        extension Outer.Props: nonisolated AnyViewProps {
          nonisolated public static let allProps = PropSet(rawValue: 0b1)

          /// `@inlinable` so core's raw-key fold can inline the lookup across the module boundary:
          /// it runs once per changed key per props batch.
          @inlinable
          nonisolated public static func propSet(for name: PropName) -> PropSet {
            switch name {
            case .color:
              return .color
            }
          }

          @JavaScriptActor
          public mutating func _decode(_ name: PropName, from value: borrowing JavaScriptUnownedValue, in runtime: borrowing JavaScriptRuntime) throws {
            if value.isNull() || value.isUndefined() {
              Self._resetViewProp(name, in: &self)
              return
            }
            switch name {
            case .color:
              self.color = try Self._decodeViewProp(value, in: runtime)
            }
          }
        }
        """
    )
  }

  @Test
  func `An internal props struct in a public extension keeps Swift's init()`() {
    // The modifier on the struct overrides the default access of the extension.
    assertExpansion(
      """
      public extension Outer {
        @ViewProps
        internal struct Props {
          var color: UIColor = .red
        }
      }
      """,
      expandedSource: """
        public extension Outer {
          internal struct Props {
            var color: UIColor = .red

            nonisolated public enum PropName: String, CaseIterable {
              case color
            }

            nonisolated public struct PropSet: OptionSet, Sendable {
              public let rawValue: UInt64

              public init(rawValue: UInt64) {
                self.rawValue = rawValue
              }

              public static let color = PropSet(rawValue: 1 << 0)
            }

            nonisolated public static let _eventNames: [String] = []

            public typealias Diff = PropsDiff<Self>

            @JavaScriptActor
            static func _resetViewProp(_ _name: PropName, in _props: inout Self) {
              switch _name {
              case .color:
                _props.color = .red
              }
            }
          }
        }

        extension Outer.Props: nonisolated AnyViewProps {
          nonisolated public static let allProps = PropSet(rawValue: 0b1)

          /// `@inlinable` so core's raw-key fold can inline the lookup across the module boundary:
          /// it runs once per changed key per props batch.
          @inlinable
          nonisolated public static func propSet(for name: PropName) -> PropSet {
            switch name {
            case .color:
              return .color
            }
          }

          @JavaScriptActor
          public mutating func _decode(_ name: PropName, from value: borrowing JavaScriptUnownedValue, in runtime: borrowing JavaScriptRuntime) throws {
            if value.isNull() || value.isUndefined() {
              Self._resetViewProp(name, in: &self)
              return
            }
            switch name {
            case .color:
              self.color = try Self._decodeViewProp(value, in: runtime)
            }
          }
        }
        """
    )
  }

  @Test
  func `A prop named _decodeViewProp does not shadow the decode helper`() {
    // The helper is reached through `Self.`, so the property does not hide it.
    assertExpansion(
      """
      @ViewProps
      struct Props {
        var _decodeViewProp: Int = 0
      }
      """,
      expandedSource: """
        struct Props {
          var _decodeViewProp: Int = 0

          nonisolated public enum PropName: String, CaseIterable {
            case _decodeViewProp
          }

          nonisolated public struct PropSet: OptionSet, Sendable {
            public let rawValue: UInt64

            public init(rawValue: UInt64) {
              self.rawValue = rawValue
            }

            public static let _decodeViewProp = PropSet(rawValue: 1 << 0)
          }

          nonisolated public static let _eventNames: [String] = []

          public typealias Diff = PropsDiff<Self>

          @JavaScriptActor
          static func _resetViewProp(_ _name: PropName, in _props: inout Self) {
            switch _name {
            case ._decodeViewProp:
              _props._decodeViewProp = 0
            }
          }
        }

        extension Props: nonisolated AnyViewProps {
          nonisolated public static let allProps = PropSet(rawValue: 0b1)

          /// `@inlinable` so core's raw-key fold can inline the lookup across the module boundary:
          /// it runs once per changed key per props batch.
          @inlinable
          nonisolated public static func propSet(for name: PropName) -> PropSet {
            switch name {
            case ._decodeViewProp:
              return ._decodeViewProp
            }
          }

          @JavaScriptActor
          public mutating func _decode(_ name: PropName, from value: borrowing JavaScriptUnownedValue, in runtime: borrowing JavaScriptRuntime) throws {
            if value.isNull() || value.isUndefined() {
              Self._resetViewProp(name, in: &self)
              return
            }
            switch name {
            case ._decodeViewProp:
              self._decodeViewProp = try Self._decodeViewProp(value, in: runtime)
            }
          }
        }
        """
    )
  }

  @Test
  func `An async init() next to a usable init() is accepted`() {
    // Swift allows both, and `Self()` in the synchronous `_decode` calls `init()`.
    assertExpansion(
      """
      @ViewProps
      struct Props {
        var color: UIColor = .red

        init() {
        }

        init() async {
        }
      }
      """,
      expandedSource: """
        struct Props {
          var color: UIColor = .red

          init() {
          }

          init() async {
          }

          nonisolated public enum PropName: String, CaseIterable {
            case color
          }

          nonisolated public struct PropSet: OptionSet, Sendable {
            public let rawValue: UInt64

            public init(rawValue: UInt64) {
              self.rawValue = rawValue
            }

            public static let color = PropSet(rawValue: 1 << 0)
          }

          nonisolated public static let _eventNames: [String] = []

          public typealias Diff = PropsDiff<Self>

          @JavaScriptActor
          static func _resetViewProp(_ _name: PropName, in _props: inout Self) {
            switch _name {
            case .color:
              _props.color = Self().color
            }
          }
        }

        extension Props: nonisolated AnyViewProps {
          nonisolated public static let allProps = PropSet(rawValue: 0b1)

          /// `@inlinable` so core's raw-key fold can inline the lookup across the module boundary:
          /// it runs once per changed key per props batch.
          @inlinable
          nonisolated public static func propSet(for name: PropName) -> PropSet {
            switch name {
            case .color:
              return .color
            }
          }

          @JavaScriptActor
          public mutating func _decode(_ name: PropName, from value: borrowing JavaScriptUnownedValue, in runtime: borrowing JavaScriptRuntime) throws {
            if value.isNull() || value.isUndefined() {
              Self._resetViewProp(name, in: &self)
              return
            }
            switch name {
            case .color:
              self.color = try Self._decodeViewProp(value, in: runtime)
            }
          }
        }
        """
    )
  }

  @Test
  func `An optional type in parentheses needs no initial value`() {
    // `(Int?)` is `Int?`, which Swift gives an implicit nil, also for a private property.
    assertExpansion(
      """
      @ViewProps
      struct Props {
        var value: (Int?)
        private var cache: ((Int)?)
      }
      """,
      expandedSource: """
        struct Props {
          var value: (Int?)
          private var cache: ((Int)?)

          nonisolated public enum PropName: String, CaseIterable {
            case value
          }

          nonisolated public struct PropSet: OptionSet, Sendable {
            public let rawValue: UInt64

            public init(rawValue: UInt64) {
              self.rawValue = rawValue
            }

            public static let value = PropSet(rawValue: 1 << 0)
          }

          nonisolated public static let _eventNames: [String] = []

          public typealias Diff = PropsDiff<Self>

          @JavaScriptActor
          static func _resetViewProp(_ _name: PropName, in _props: inout Self) {
            switch _name {
            case .value:
              _props.value = nil
            }
          }
        }

        extension Props: nonisolated AnyViewProps {
          nonisolated public static let allProps = PropSet(rawValue: 0b1)

          /// `@inlinable` so core's raw-key fold can inline the lookup across the module boundary:
          /// it runs once per changed key per props batch.
          @inlinable
          nonisolated public static func propSet(for name: PropName) -> PropSet {
            switch name {
            case .value:
              return .value
            }
          }

          @JavaScriptActor
          public mutating func _decode(_ name: PropName, from value: borrowing JavaScriptUnownedValue, in runtime: borrowing JavaScriptRuntime) throws {
            if value.isNull() || value.isUndefined() {
              Self._resetViewProp(name, in: &self)
              return
            }
            switch name {
            case .value:
              self.value = try Self._decodeViewProp(value, in: runtime)
            }
          }
        }
        """
    )
  }

  @Test
  func `Conditional init() declarations are not duplicated`() {
    assertExpansion(
      """
      @ViewProps
      public struct Props {
        var color: Int = 0

        #if os(iOS)
        public init() {
          color = 1
        }
        #else
        public init() {
          color = 2
        }
        #endif
      }
      """,
      expandedSource: """
        public struct Props {
          var color: Int = 0

          #if os(iOS)
          public init() {
            color = 1
          }
          #else
          public init() {
            color = 2
          }
          #endif

          nonisolated public enum PropName: String, CaseIterable {
            case color
          }

          nonisolated public struct PropSet: OptionSet, Sendable {
            public let rawValue: UInt64

            public init(rawValue: UInt64) {
              self.rawValue = rawValue
            }

            public static let color = PropSet(rawValue: 1 << 0)
          }

          nonisolated public static let _eventNames: [String] = []

          public typealias Diff = PropsDiff<Self>

          @JavaScriptActor
          static func _resetViewProp(_ _name: PropName, in _props: inout Self) {
            switch _name {
            case .color:
              _props.color = Self().color
            }
          }
        }

        extension Props: nonisolated AnyViewProps {
          nonisolated public static let allProps = PropSet(rawValue: 0b1)

          /// `@inlinable` so core's raw-key fold can inline the lookup across the module boundary:
          /// it runs once per changed key per props batch.
          @inlinable
          nonisolated public static func propSet(for name: PropName) -> PropSet {
            switch name {
            case .color:
              return .color
            }
          }

          @JavaScriptActor
          public mutating func _decode(_ name: PropName, from value: borrowing JavaScriptUnownedValue, in runtime: borrowing JavaScriptRuntime) throws {
            if value.isNull() || value.isUndefined() {
              Self._resetViewProp(name, in: &self)
              return
            }
            switch name {
            case .color:
              self.color = try Self._decodeViewProp(value, in: runtime)
            }
          }
        }
        """
    )
  }

  @Test
  func `Shared trailing optional annotations count as private property defaults`() {
    assertExpansion(
      """
      @ViewProps
      struct Props {
        private var first, second: Int?
        fileprivate var third, fourth: String?
      }
      """,
      expandedSource: """
        struct Props {
          private var first, second: Int?
          fileprivate var third, fourth: String?

          nonisolated public enum PropName: RawRepresentable, CaseIterable {
            public init?(rawValue: String) {
              return nil
            }

            public var rawValue: String {
              switch self {
              }
            }
          }

          nonisolated public struct PropSet: OptionSet, Sendable {
            public let rawValue: UInt64

            public init(rawValue: UInt64) {
              self.rawValue = rawValue
            }
          }

          nonisolated public static let _eventNames: [String] = []

          public typealias Diff = PropsDiff<Self>
        }

        extension Props: nonisolated AnyViewProps {
          nonisolated public static let allProps = PropSet(rawValue: 0)

          /// `@inlinable` so core's raw-key fold can inline the lookup across the module boundary:
          /// it runs once per changed key per props batch.
          @inlinable
          nonisolated public static func propSet(for name: PropName) -> PropSet {
            return []
          }

          @JavaScriptActor
          public mutating func _decode(_ name: PropName, from value: borrowing JavaScriptUnownedValue, in runtime: borrowing JavaScriptRuntime) throws {
          }
        }
        """
    )
  }
}
