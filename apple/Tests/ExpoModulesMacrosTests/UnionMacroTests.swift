import ExpoModulesMacrosCore
import SwiftSyntax
import SwiftSyntaxMacroExpansion
import SwiftSyntaxMacros
import SwiftSyntaxMacrosGenericTestSupport
import Testing

private let unionMacroSpecs: [String: MacroSpec] = [
  "Union": MacroSpec(type: UnionMacro.self, conformances: ["JavaScriptDecodable", "JavaScriptEncodable"])
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
    macroSpecs: unionMacroSpecs,
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

@Suite("@Union macro")
struct UnionMacroTests {
  @Test
  func `Cases decode in declaration order and encode through their payload type`() {
    assertExpansion(
      """
      @Union
      enum Source {
        case text(String)
        case options(SourceOptions)
      }
      """,
      expandedSource: """
        enum Source {
          case text(String)
          case options(SourceOptions)

          private func _assertTypesConformance() {
            func options(_: (some JavaScriptDecodable & JavaScriptEncodable).Type) {
            }
            options(SourceOptions.self)
          }

          nonisolated public static var decodableKinds: JavaScriptValueKinds {
            return [String.decodableKinds, SourceOptions.decodableKinds]
          }

          @JavaScriptActor
          public static func decode(_ value: borrowing JavaScriptUnownedValue, in runtime: borrowing JavaScriptRuntime) throws -> Self {
            let kind = JavaScriptValueKinds(of: value)
            if String.decodableKinds.contains(kind), let payload = try? String.decode(value, in: runtime) {
              return .text(payload)
            }
            if SourceOptions.decodableKinds.contains(kind), let payload = try? SourceOptions.decode(value, in: runtime) {
              return .options(payload)
            }
            throw Exceptions.UnionCaseMismatch((unionName: "Source", received: value.copied(in: runtime).kind.rawValue, expected: ["String", "SourceOptions"]))
          }

          @JavaScriptActor
          public static func encode(_ value: Self, in runtime: borrowing JavaScriptRuntime) throws -> JavaScriptValue {
            switch value {
            case .text(let payload):
              return try String.encode(payload, in: runtime)
            case .options(let payload):
              return try SourceOptions.encode(payload, in: runtime)
            }
          }

          @JavaScriptActor
          public static func encode(
            _ value: Self,
            into slot: borrowing JavaScriptValue.Slot,
            in runtime: borrowing JavaScriptRuntime
          ) throws {
            switch value {
            case .text(let payload):
              try String.encode(payload, into: slot, in: runtime)
            case .options(let payload):
              try SourceOptions.encode(payload, into: slot, in: runtime)
            }
          }

          nonisolated public func `as`(_ type: String.Type) throws -> String {
            if case .text(let payload) = self {
              return payload
            }
            throw Exceptions.UnionCaseMismatch((unionName: "Source", received: _payloadTypeName, expected: ["String"]))
          }

          nonisolated public func `as`(_ type: SourceOptions.Type) throws -> SourceOptions {
            if case .options(let payload) = self {
              return payload
            }
            throw Exceptions.UnionCaseMismatch((unionName: "Source", received: _payloadTypeName, expected: ["SourceOptions"]))
          }

          nonisolated private var _payloadTypeName: String {
            switch self {
            case .text:
              return "String"
            case .options:
              return "SourceOptions"
            }
          }
        }

        extension Source: nonisolated JavaScriptDecodable, nonisolated JavaScriptEncodable {
        }
        """
    )
  }

  @Test
  func `Primitive-only payloads emit no conformance assertion`() {
    assertExpansion(
      """
      @Union
      enum Size {
        case named(String)
        case points(Double)
      }
      """,
      expandedSource: """
        enum Size {
          case named(String)
          case points(Double)

          nonisolated public static var decodableKinds: JavaScriptValueKinds {
            return [String.decodableKinds, Double.decodableKinds]
          }

          @JavaScriptActor
          public static func decode(_ value: borrowing JavaScriptUnownedValue, in runtime: borrowing JavaScriptRuntime) throws -> Self {
            let kind = JavaScriptValueKinds(of: value)
            if String.decodableKinds.contains(kind), let payload = try? String.decode(value, in: runtime) {
              return .named(payload)
            }
            if Double.decodableKinds.contains(kind), let payload = try? Double.decode(value, in: runtime) {
              return .points(payload)
            }
            throw Exceptions.UnionCaseMismatch((unionName: "Size", received: value.copied(in: runtime).kind.rawValue, expected: ["String", "Double"]))
          }

          @JavaScriptActor
          public static func encode(_ value: Self, in runtime: borrowing JavaScriptRuntime) throws -> JavaScriptValue {
            switch value {
            case .named(let payload):
              return try String.encode(payload, in: runtime)
            case .points(let payload):
              return try Double.encode(payload, in: runtime)
            }
          }

          @JavaScriptActor
          public static func encode(
            _ value: Self,
            into slot: borrowing JavaScriptValue.Slot,
            in runtime: borrowing JavaScriptRuntime
          ) throws {
            switch value {
            case .named(let payload):
              try String.encode(payload, into: slot, in: runtime)
            case .points(let payload):
              try Double.encode(payload, into: slot, in: runtime)
            }
          }

          nonisolated public func `as`(_ type: String.Type) throws -> String {
            if case .named(let payload) = self {
              return payload
            }
            throw Exceptions.UnionCaseMismatch((unionName: "Size", received: _payloadTypeName, expected: ["String"]))
          }

          nonisolated public func `as`(_ type: Double.Type) throws -> Double {
            if case .points(let payload) = self {
              return payload
            }
            throw Exceptions.UnionCaseMismatch((unionName: "Size", received: _payloadTypeName, expected: ["Double"]))
          }

          nonisolated private var _payloadTypeName: String {
            switch self {
            case .named:
              return "String"
            case .points:
              return "Double"
            }
          }
        }

        extension Size: nonisolated JavaScriptDecodable, nonisolated JavaScriptEncodable {
        }
        """
    )
  }

  @Test
  func `Payloads of nested arrays and sets of primitives emit no conformance assertion`() {
    assertExpansion(
      """
      @Union
      enum Selection {
        case grid([[Int]])
        case tags(Set<String>)
      }
      """,
      expandedSource: """
        enum Selection {
          case grid([[Int]])
          case tags(Set<String>)

          nonisolated public static var decodableKinds: JavaScriptValueKinds {
            return [[[Int]].decodableKinds, Set<String>.decodableKinds]
          }

          @JavaScriptActor
          public static func decode(_ value: borrowing JavaScriptUnownedValue, in runtime: borrowing JavaScriptRuntime) throws -> Self {
            let kind = JavaScriptValueKinds(of: value)
            if [[Int]].decodableKinds.contains(kind), let payload = try? [[Int]].decode(value, in: runtime) {
              return .grid(payload)
            }
            if Set<String>.decodableKinds.contains(kind), let payload = try? Set<String>.decode(value, in: runtime) {
              return .tags(payload)
            }
            throw Exceptions.UnionCaseMismatch((unionName: "Selection", received: value.copied(in: runtime).kind.rawValue, expected: ["[[Int]]", "Set<String>"]))
          }

          @JavaScriptActor
          public static func encode(_ value: Self, in runtime: borrowing JavaScriptRuntime) throws -> JavaScriptValue {
            switch value {
            case .grid(let payload):
              return try [[Int]].encode(payload, in: runtime)
            case .tags(let payload):
              return try Set<String>.encode(payload, in: runtime)
            }
          }

          @JavaScriptActor
          public static func encode(
            _ value: Self,
            into slot: borrowing JavaScriptValue.Slot,
            in runtime: borrowing JavaScriptRuntime
          ) throws {
            switch value {
            case .grid(let payload):
              try [[Int]].encode(payload, into: slot, in: runtime)
            case .tags(let payload):
              try Set<String>.encode(payload, into: slot, in: runtime)
            }
          }

          nonisolated public func `as`(_ type: [[Int]].Type) throws -> [[Int]] {
            if case .grid(let payload) = self {
              return payload
            }
            throw Exceptions.UnionCaseMismatch((unionName: "Selection", received: _payloadTypeName, expected: ["[[Int]]"]))
          }

          nonisolated public func `as`(_ type: Set<String>.Type) throws -> Set<String> {
            if case .tags(let payload) = self {
              return payload
            }
            throw Exceptions.UnionCaseMismatch((unionName: "Selection", received: _payloadTypeName, expected: ["Set<String>"]))
          }

          nonisolated private var _payloadTypeName: String {
            switch self {
            case .grid:
              return "[[Int]]"
            case .tags:
              return "Set<String>"
            }
          }
        }

        extension Selection: nonisolated JavaScriptDecodable, nonisolated JavaScriptEncodable {
        }
        """
    )
  }

  @Test
  func `Composed payload types are decoded, encoded, and asserted verbatim`() {
    assertExpansion(
      """
      @Union
      enum Input {
        case single(Point)
        case many([Point])
        case keyed([String: Point])
        case maybe(Int?)
      }
      """,
      expandedSource: """
        enum Input {
          case single(Point)
          case many([Point])
          case keyed([String: Point])
          case maybe(Int?)

          private func _assertTypesConformance() {
            func single(_: (some JavaScriptDecodable & JavaScriptEncodable).Type) {
            }
            single(Point.self)
            func many(_: (some JavaScriptDecodable & JavaScriptEncodable).Type) {
            }
            many([Point].self)
            func keyed(_: (some JavaScriptDecodable & JavaScriptEncodable).Type) {
            }
            keyed([String: Point].self)
          }

          nonisolated public static var decodableKinds: JavaScriptValueKinds {
            return [Point.decodableKinds, [Point].decodableKinds, [String: Point].decodableKinds, Int?.decodableKinds]
          }

          @JavaScriptActor
          public static func decode(_ value: borrowing JavaScriptUnownedValue, in runtime: borrowing JavaScriptRuntime) throws -> Self {
            let kind = JavaScriptValueKinds(of: value)
            if Point.decodableKinds.contains(kind), let payload = try? Point.decode(value, in: runtime) {
              return .single(payload)
            }
            if [Point].decodableKinds.contains(kind), let payload = try? [Point].decode(value, in: runtime) {
              return .many(payload)
            }
            if [String: Point].decodableKinds.contains(kind), let payload = try? [String: Point].decode(value, in: runtime) {
              return .keyed(payload)
            }
            if Int?.decodableKinds.contains(kind), let payload = try? Int?.decode(value, in: runtime) {
              return .maybe(payload)
            }
            throw Exceptions.UnionCaseMismatch((unionName: "Input", received: value.copied(in: runtime).kind.rawValue, expected: ["Point", "[Point]", "[String: Point]", "Int?"]))
          }

          @JavaScriptActor
          public static func encode(_ value: Self, in runtime: borrowing JavaScriptRuntime) throws -> JavaScriptValue {
            switch value {
            case .single(let payload):
              return try Point.encode(payload, in: runtime)
            case .many(let payload):
              return try [Point].encode(payload, in: runtime)
            case .keyed(let payload):
              return try [String: Point].encode(payload, in: runtime)
            case .maybe(let payload):
              return try Int?.encode(payload, in: runtime)
            }
          }

          @JavaScriptActor
          public static func encode(
            _ value: Self,
            into slot: borrowing JavaScriptValue.Slot,
            in runtime: borrowing JavaScriptRuntime
          ) throws {
            switch value {
            case .single(let payload):
              try Point.encode(payload, into: slot, in: runtime)
            case .many(let payload):
              try [Point].encode(payload, into: slot, in: runtime)
            case .keyed(let payload):
              try [String: Point].encode(payload, into: slot, in: runtime)
            case .maybe(let payload):
              try Int?.encode(payload, into: slot, in: runtime)
            }
          }

          nonisolated public func `as`(_ type: Point.Type) throws -> Point {
            if case .single(let payload) = self {
              return payload
            }
            throw Exceptions.UnionCaseMismatch((unionName: "Input", received: _payloadTypeName, expected: ["Point"]))
          }

          nonisolated public func `as`(_ type: [Point].Type) throws -> [Point] {
            if case .many(let payload) = self {
              return payload
            }
            throw Exceptions.UnionCaseMismatch((unionName: "Input", received: _payloadTypeName, expected: ["[Point]"]))
          }

          nonisolated public func `as`(_ type: [String: Point].Type) throws -> [String: Point] {
            if case .keyed(let payload) = self {
              return payload
            }
            throw Exceptions.UnionCaseMismatch((unionName: "Input", received: _payloadTypeName, expected: ["[String: Point]"]))
          }

          nonisolated public func `as`(_ type: Int?.Type) throws -> Int? {
            if case .maybe(let payload) = self {
              return payload
            }
            throw Exceptions.UnionCaseMismatch((unionName: "Input", received: _payloadTypeName, expected: ["Int?"]))
          }

          nonisolated private var _payloadTypeName: String {
            switch self {
            case .single:
              return "Point"
            case .many:
              return "[Point]"
            case .keyed:
              return "[String: Point]"
            case .maybe:
              return "Int?"
            }
          }
        }

        extension Input: nonisolated JavaScriptDecodable, nonisolated JavaScriptEncodable {
        }
        """
    )
  }

  @Test
  func `A labeled associated value is constructed with its label`() {
    assertExpansion(
      """
      @Union
      enum Reference {
        case id(value: Int)
        case name(_ value: String)
      }
      """,
      expandedSource: """
        enum Reference {
          case id(value: Int)
          case name(_ value: String)

          nonisolated public static var decodableKinds: JavaScriptValueKinds {
            return [Int.decodableKinds, String.decodableKinds]
          }

          @JavaScriptActor
          public static func decode(_ value: borrowing JavaScriptUnownedValue, in runtime: borrowing JavaScriptRuntime) throws -> Self {
            let kind = JavaScriptValueKinds(of: value)
            if Int.decodableKinds.contains(kind), let payload = try? Int.decode(value, in: runtime) {
              return .id(value: payload)
            }
            if String.decodableKinds.contains(kind), let payload = try? String.decode(value, in: runtime) {
              return .name(payload)
            }
            throw Exceptions.UnionCaseMismatch((unionName: "Reference", received: value.copied(in: runtime).kind.rawValue, expected: ["Int", "String"]))
          }

          @JavaScriptActor
          public static func encode(_ value: Self, in runtime: borrowing JavaScriptRuntime) throws -> JavaScriptValue {
            switch value {
            case .id(let payload):
              return try Int.encode(payload, in: runtime)
            case .name(let payload):
              return try String.encode(payload, in: runtime)
            }
          }

          @JavaScriptActor
          public static func encode(
            _ value: Self,
            into slot: borrowing JavaScriptValue.Slot,
            in runtime: borrowing JavaScriptRuntime
          ) throws {
            switch value {
            case .id(let payload):
              try Int.encode(payload, into: slot, in: runtime)
            case .name(let payload):
              try String.encode(payload, into: slot, in: runtime)
            }
          }

          nonisolated public func `as`(_ type: Int.Type) throws -> Int {
            if case .id(let payload) = self {
              return payload
            }
            throw Exceptions.UnionCaseMismatch((unionName: "Reference", received: _payloadTypeName, expected: ["Int"]))
          }

          nonisolated public func `as`(_ type: String.Type) throws -> String {
            if case .name(let payload) = self {
              return payload
            }
            throw Exceptions.UnionCaseMismatch((unionName: "Reference", received: _payloadTypeName, expected: ["String"]))
          }

          nonisolated private var _payloadTypeName: String {
            switch self {
            case .id:
              return "Int"
            case .name:
              return "String"
            }
          }
        }

        extension Reference: nonisolated JavaScriptDecodable, nonisolated JavaScriptEncodable {
        }
        """
    )
  }

  @Test
  func `Several elements in one case declaration are separate alternatives`() {
    assertExpansion(
      """
      @Union
      enum Scalar {
        case flag(Bool), count(Int)
      }
      """,
      expandedSource: """
        enum Scalar {
          case flag(Bool), count(Int)

          nonisolated public static var decodableKinds: JavaScriptValueKinds {
            return [Bool.decodableKinds, Int.decodableKinds]
          }

          @JavaScriptActor
          public static func decode(_ value: borrowing JavaScriptUnownedValue, in runtime: borrowing JavaScriptRuntime) throws -> Self {
            let kind = JavaScriptValueKinds(of: value)
            if Bool.decodableKinds.contains(kind), let payload = try? Bool.decode(value, in: runtime) {
              return .flag(payload)
            }
            if Int.decodableKinds.contains(kind), let payload = try? Int.decode(value, in: runtime) {
              return .count(payload)
            }
            throw Exceptions.UnionCaseMismatch((unionName: "Scalar", received: value.copied(in: runtime).kind.rawValue, expected: ["Bool", "Int"]))
          }

          @JavaScriptActor
          public static func encode(_ value: Self, in runtime: borrowing JavaScriptRuntime) throws -> JavaScriptValue {
            switch value {
            case .flag(let payload):
              return try Bool.encode(payload, in: runtime)
            case .count(let payload):
              return try Int.encode(payload, in: runtime)
            }
          }

          @JavaScriptActor
          public static func encode(
            _ value: Self,
            into slot: borrowing JavaScriptValue.Slot,
            in runtime: borrowing JavaScriptRuntime
          ) throws {
            switch value {
            case .flag(let payload):
              try Bool.encode(payload, into: slot, in: runtime)
            case .count(let payload):
              try Int.encode(payload, into: slot, in: runtime)
            }
          }

          nonisolated public func `as`(_ type: Bool.Type) throws -> Bool {
            if case .flag(let payload) = self {
              return payload
            }
            throw Exceptions.UnionCaseMismatch((unionName: "Scalar", received: _payloadTypeName, expected: ["Bool"]))
          }

          nonisolated public func `as`(_ type: Int.Type) throws -> Int {
            if case .count(let payload) = self {
              return payload
            }
            throw Exceptions.UnionCaseMismatch((unionName: "Scalar", received: _payloadTypeName, expected: ["Int"]))
          }

          nonisolated private var _payloadTypeName: String {
            switch self {
            case .flag:
              return "Bool"
            case .count:
              return "Int"
            }
          }
        }

        extension Scalar: nonisolated JavaScriptDecodable, nonisolated JavaScriptEncodable {
        }
        """
    )
  }

  @Test
  func `Implicitly-unwrapped optional payload normalizes to optional in expressions`() {
    assertExpansion(
      """
      @Union
      enum Slot {
        case record(MyRecord!)
      }
      """,
      expandedSource: """
        enum Slot {
          case record(MyRecord!)

          private func _assertTypesConformance() {
            func record(_: (some JavaScriptDecodable & JavaScriptEncodable).Type) {
            }
            record(MyRecord.self)
          }

          nonisolated public static var decodableKinds: JavaScriptValueKinds {
            return MyRecord?.decodableKinds
          }

          @JavaScriptActor
          public static func decode(_ value: borrowing JavaScriptUnownedValue, in runtime: borrowing JavaScriptRuntime) throws -> Self {
            let kind = JavaScriptValueKinds(of: value)
            if MyRecord?.decodableKinds.contains(kind), let payload = try? MyRecord?.decode(value, in: runtime) {
              return .record(payload)
            }
            throw Exceptions.UnionCaseMismatch((unionName: "Slot", received: value.copied(in: runtime).kind.rawValue, expected: ["MyRecord!"]))
          }

          @JavaScriptActor
          public static func encode(_ value: Self, in runtime: borrowing JavaScriptRuntime) throws -> JavaScriptValue {
            switch value {
            case .record(let payload):
              return try MyRecord?.encode(payload, in: runtime)
            }
          }

          @JavaScriptActor
          public static func encode(
            _ value: Self,
            into slot: borrowing JavaScriptValue.Slot,
            in runtime: borrowing JavaScriptRuntime
          ) throws {
            switch value {
            case .record(let payload):
              try MyRecord?.encode(payload, into: slot, in: runtime)
            }
          }

          nonisolated public func `as`(_ type: MyRecord?.Type) throws -> MyRecord? {
            if case .record(let payload) = self {
              return payload
            }
            throw Exceptions.UnionCaseMismatch((unionName: "Slot", received: _payloadTypeName, expected: ["MyRecord!"]))
          }

          nonisolated private var _payloadTypeName: String {
            switch self {
            case .record:
              return "MyRecord!"
            }
          }
        }

        extension Slot: nonisolated JavaScriptDecodable, nonisolated JavaScriptEncodable {
        }
        """
    )
  }

  @Test
  func `Non-case members are ignored`() {
    assertExpansion(
      """
      @Union
      enum Source {
        case text(String)

        static let fallback = Source.text("")

        var isText: Bool {
          if case .text = self { return true }
          return false
        }
      }
      """,
      expandedSource: """
        enum Source {
          case text(String)

          static let fallback = Source.text("")

          var isText: Bool {
            if case .text = self { return true }
            return false
          }

          nonisolated public static var decodableKinds: JavaScriptValueKinds {
            return String.decodableKinds
          }

          @JavaScriptActor
          public static func decode(_ value: borrowing JavaScriptUnownedValue, in runtime: borrowing JavaScriptRuntime) throws -> Self {
            let kind = JavaScriptValueKinds(of: value)
            if String.decodableKinds.contains(kind), let payload = try? String.decode(value, in: runtime) {
              return .text(payload)
            }
            throw Exceptions.UnionCaseMismatch((unionName: "Source", received: value.copied(in: runtime).kind.rawValue, expected: ["String"]))
          }

          @JavaScriptActor
          public static func encode(_ value: Self, in runtime: borrowing JavaScriptRuntime) throws -> JavaScriptValue {
            switch value {
            case .text(let payload):
              return try String.encode(payload, in: runtime)
            }
          }

          @JavaScriptActor
          public static func encode(
            _ value: Self,
            into slot: borrowing JavaScriptValue.Slot,
            in runtime: borrowing JavaScriptRuntime
          ) throws {
            switch value {
            case .text(let payload):
              try String.encode(payload, into: slot, in: runtime)
            }
          }

          nonisolated public func `as`(_ type: String.Type) throws -> String {
            if case .text(let payload) = self {
              return payload
            }
            throw Exceptions.UnionCaseMismatch((unionName: "Source", received: _payloadTypeName, expected: ["String"]))
          }

          nonisolated private var _payloadTypeName: String {
            switch self {
            case .text:
              return "String"
            }
          }
        }

        extension Source: nonisolated JavaScriptDecodable, nonisolated JavaScriptEncodable {
        }
        """
    )
  }

  @Test
  func `Conformances already declared are not repeated`() {
    assertExpansion(
      """
      @Union
      enum Source: JavaScriptDecodable, Sendable {
        case text(String)
      }
      """,
      expandedSource: """
        enum Source: JavaScriptDecodable, Sendable {
          case text(String)

          nonisolated public static var decodableKinds: JavaScriptValueKinds {
            return String.decodableKinds
          }

          @JavaScriptActor
          public static func decode(_ value: borrowing JavaScriptUnownedValue, in runtime: borrowing JavaScriptRuntime) throws -> Self {
            let kind = JavaScriptValueKinds(of: value)
            if String.decodableKinds.contains(kind), let payload = try? String.decode(value, in: runtime) {
              return .text(payload)
            }
            throw Exceptions.UnionCaseMismatch((unionName: "Source", received: value.copied(in: runtime).kind.rawValue, expected: ["String"]))
          }

          @JavaScriptActor
          public static func encode(_ value: Self, in runtime: borrowing JavaScriptRuntime) throws -> JavaScriptValue {
            switch value {
            case .text(let payload):
              return try String.encode(payload, in: runtime)
            }
          }

          @JavaScriptActor
          public static func encode(
            _ value: Self,
            into slot: borrowing JavaScriptValue.Slot,
            in runtime: borrowing JavaScriptRuntime
          ) throws {
            switch value {
            case .text(let payload):
              try String.encode(payload, into: slot, in: runtime)
            }
          }

          nonisolated public func `as`(_ type: String.Type) throws -> String {
            if case .text(let payload) = self {
              return payload
            }
            throw Exceptions.UnionCaseMismatch((unionName: "Source", received: _payloadTypeName, expected: ["String"]))
          }

          nonisolated private var _payloadTypeName: String {
            switch self {
            case .text:
              return "String"
            }
          }
        }

        extension Source: nonisolated JavaScriptEncodable {
        }
        """
    )
  }

  @Test
  func `Both conformances already declared emit no extension`() {
    assertExpansion(
      """
      @Union
      enum Source: JavaScriptDecodable, JavaScriptEncodable {
        case text(String)
      }
      """,
      expandedSource: """
        enum Source: JavaScriptDecodable, JavaScriptEncodable {
          case text(String)

          nonisolated public static var decodableKinds: JavaScriptValueKinds {
            return String.decodableKinds
          }

          @JavaScriptActor
          public static func decode(_ value: borrowing JavaScriptUnownedValue, in runtime: borrowing JavaScriptRuntime) throws -> Self {
            let kind = JavaScriptValueKinds(of: value)
            if String.decodableKinds.contains(kind), let payload = try? String.decode(value, in: runtime) {
              return .text(payload)
            }
            throw Exceptions.UnionCaseMismatch((unionName: "Source", received: value.copied(in: runtime).kind.rawValue, expected: ["String"]))
          }

          @JavaScriptActor
          public static func encode(_ value: Self, in runtime: borrowing JavaScriptRuntime) throws -> JavaScriptValue {
            switch value {
            case .text(let payload):
              return try String.encode(payload, in: runtime)
            }
          }

          @JavaScriptActor
          public static func encode(
            _ value: Self,
            into slot: borrowing JavaScriptValue.Slot,
            in runtime: borrowing JavaScriptRuntime
          ) throws {
            switch value {
            case .text(let payload):
              try String.encode(payload, into: slot, in: runtime)
            }
          }

          nonisolated public func `as`(_ type: String.Type) throws -> String {
            if case .text(let payload) = self {
              return payload
            }
            throw Exceptions.UnionCaseMismatch((unionName: "Source", received: _payloadTypeName, expected: ["String"]))
          }

          nonisolated private var _payloadTypeName: String {
            switch self {
            case .text:
              return "String"
            }
          }
        }
        """
    )
  }

  @Test
  func `Applying @Union to a struct produces a diagnostic`() {
    assertExpansion(
      """
      @Union
      struct NotAUnion {
        var value: String
      }
      """,
      expandedSource: """
        struct NotAUnion {
          var value: String
        }
        """,
      diagnostics: [
        DiagnosticSpec(
          message: "@Union can only be applied to an enum",
          line: 1,
          column: 1
        )
      ]
    )
  }

  @Test
  func `Applying @Union to a generic enum produces a diagnostic`() {
    assertExpansion(
      """
      @Union
      enum Wrapper<T> {
        case value(T)
      }
      """,
      expandedSource: """
        enum Wrapper<T> {
          case value(T)
        }
        """,
      diagnostics: [
        DiagnosticSpec(
          message:
            "@Union cannot be applied to a generic enum: each case's payload type must be concrete so the macro can select its converter.",
          line: 2,
          column: 13
        )
      ]
    )
  }

  @Test
  func `An enum without cases produces a diagnostic`() {
    assertExpansion(
      """
      @Union
      enum Empty {
      }
      """,
      expandedSource: """
        enum Empty {
        }
        """,
      diagnostics: [
        DiagnosticSpec(
          message: "@Union requires at least one case carrying an associated value",
          line: 1,
          column: 1
        )
      ]
    )
  }

  @Test
  func `A case without an associated value produces a diagnostic on the case`() {
    assertExpansion(
      """
      @Union
      enum Source {
        case text(String)
        case none
      }
      """,
      expandedSource: """
        enum Source {
          case text(String)
          case none
        }
        """,
      diagnostics: [
        DiagnosticSpec(
          message:
            "@Union case 'none' must carry exactly one associated value: the type this alternative decodes from. A payload-less enum is not a union; make it a raw-value enum conforming to 'Enumerable' instead.",
          line: 4,
          column: 8
        )
      ]
    )
  }

  @Test
  func `A case with several associated values produces a diagnostic on the case`() {
    assertExpansion(
      """
      @Union
      enum Source {
        case pair(String, Int)
      }
      """,
      expandedSource: """
        enum Source {
          case pair(String, Int)
        }
        """,
      diagnostics: [
        DiagnosticSpec(
          message:
            "@Union case 'pair' must carry exactly one associated value, but has 2. Group them in a @Record type and use it as the single payload.",
          line: 3,
          column: 8
        )
      ]
    )
  }

  @Test
  func `A case repeating an earlier payload type produces a diagnostic on the later case`() {
    assertExpansion(
      """
      @Union
      enum Source {
        case text(String)
        case keyed([String : Int])
        case name(String)
        case dictionary([String: Int])
      }
      """,
      expandedSource: """
        enum Source {
          case text(String)
          case keyed([String : Int])
          case name(String)
          case dictionary([String: Int])
        }
        """,
      diagnostics: [
        DiagnosticSpec(
          message:
            "@Union case 'name' repeats the payload type 'String' of case 'text' and can never be decoded: alternatives are tried in declaration order and the first match wins.",
          line: 5,
          column: 8
        ),
        DiagnosticSpec(
          message:
            "@Union case 'dictionary' repeats the payload type '[String: Int]' of case 'keyed' and can never be decoded: alternatives are tried in declaration order and the first match wins.",
          line: 6,
          column: 8
        ),
      ]
    )
  }

  @Test
  func `A qualified conformance in the inheritance clause is recognized`() {
    assertExpansion(
      """
      @Union
      enum Source: ExpoModulesJSI.JavaScriptEncodable {
        case text(String)
      }
      """,
      expandedSource: """
        enum Source: ExpoModulesJSI.JavaScriptEncodable {
          case text(String)

          nonisolated public static var decodableKinds: JavaScriptValueKinds {
            return String.decodableKinds
          }

          @JavaScriptActor
          public static func decode(_ value: borrowing JavaScriptUnownedValue, in runtime: borrowing JavaScriptRuntime) throws -> Self {
            let kind = JavaScriptValueKinds(of: value)
            if String.decodableKinds.contains(kind), let payload = try? String.decode(value, in: runtime) {
              return .text(payload)
            }
            throw Exceptions.UnionCaseMismatch((unionName: "Source", received: value.copied(in: runtime).kind.rawValue, expected: ["String"]))
          }

          @JavaScriptActor
          public static func encode(_ value: Self, in runtime: borrowing JavaScriptRuntime) throws -> JavaScriptValue {
            switch value {
            case .text(let payload):
              return try String.encode(payload, in: runtime)
            }
          }

          @JavaScriptActor
          public static func encode(
            _ value: Self,
            into slot: borrowing JavaScriptValue.Slot,
            in runtime: borrowing JavaScriptRuntime
          ) throws {
            switch value {
            case .text(let payload):
              try String.encode(payload, into: slot, in: runtime)
            }
          }

          nonisolated public func `as`(_ type: String.Type) throws -> String {
            if case .text(let payload) = self {
              return payload
            }
            throw Exceptions.UnionCaseMismatch((unionName: "Source", received: _payloadTypeName, expected: ["String"]))
          }

          nonisolated private var _payloadTypeName: String {
            switch self {
            case .text:
              return "String"
            }
          }
        }

        extension Source: nonisolated JavaScriptDecodable {
        }
        """
    )
  }

  @Test
  func `A default value on an associated value produces a diagnostic with a fix-it removing it`() {
    assertExpansion(
      """
      @Union
      enum Source {
        case text(String = "")
        case count(Int)
      }
      """,
      expandedSource: """
        enum Source {
          case text(String = "")
          case count(Int)
        }
        """,
      diagnostics: [
        DiagnosticSpec(
          message:
            "@Union case 'text' cannot give its associated value a default: the payload is always decoded from the JavaScript value, so the default would never apply. Remove '= \"\"'.",
          line: 3,
          column: 20,
          fixIts: [FixItSpec(message: "Remove the default value")]
        )
      ],
      fixedSource: """
        @Union
        enum Source {
          case text(String)
          case count(Int)
        }
        """
    )
  }

  @Test
  func `An indirect enum nested in another type extends the qualified type`() {
    assertExpansion(
      """
      struct Outer {
        @Union
        indirect enum Node {
          case leaf(Int)
          case children([Node])
        }
      }
      """,
      expandedSource: """
        struct Outer {
          indirect enum Node {
            case leaf(Int)
            case children([Node])

            private func _assertTypesConformance() {
              func children(_: (some JavaScriptDecodable & JavaScriptEncodable).Type) {
              }
              children([Node].self)
            }

            nonisolated public static var decodableKinds: JavaScriptValueKinds {
              return [Int.decodableKinds, [Node].decodableKinds]
            }

            @JavaScriptActor
            public static func decode(_ value: borrowing JavaScriptUnownedValue, in runtime: borrowing JavaScriptRuntime) throws -> Self {
              let kind = JavaScriptValueKinds(of: value)
              if Int.decodableKinds.contains(kind), let payload = try? Int.decode(value, in: runtime) {
                return .leaf(payload)
              }
              if [Node].decodableKinds.contains(kind), let payload = try? [Node].decode(value, in: runtime) {
                return .children(payload)
              }
              throw Exceptions.UnionCaseMismatch((unionName: "Node", received: value.copied(in: runtime).kind.rawValue, expected: ["Int", "[Node]"]))
            }

            @JavaScriptActor
            public static func encode(_ value: Self, in runtime: borrowing JavaScriptRuntime) throws -> JavaScriptValue {
              switch value {
              case .leaf(let payload):
                return try Int.encode(payload, in: runtime)
              case .children(let payload):
                return try [Node].encode(payload, in: runtime)
              }
            }

            @JavaScriptActor
            public static func encode(
              _ value: Self,
              into slot: borrowing JavaScriptValue.Slot,
              in runtime: borrowing JavaScriptRuntime
            ) throws {
              switch value {
              case .leaf(let payload):
                try Int.encode(payload, into: slot, in: runtime)
              case .children(let payload):
                try [Node].encode(payload, into: slot, in: runtime)
              }
            }

            nonisolated public func `as`(_ type: Int.Type) throws -> Int {
              if case .leaf(let payload) = self {
                return payload
              }
              throw Exceptions.UnionCaseMismatch((unionName: "Node", received: _payloadTypeName, expected: ["Int"]))
            }

            nonisolated public func `as`(_ type: [Node].Type) throws -> [Node] {
              if case .children(let payload) = self {
                return payload
              }
              throw Exceptions.UnionCaseMismatch((unionName: "Node", received: _payloadTypeName, expected: ["[Node]"]))
            }

            nonisolated private var _payloadTypeName: String {
              switch self {
              case .leaf:
                return "Int"
              case .children:
                return "[Node]"
              }
            }
          }
        }

        extension Outer.Node: nonisolated JavaScriptDecodable, nonisolated JavaScriptEncodable {
        }
        """
    )
  }

  @Test
  func `Diagnostics of different kinds are all reported together`() {
    assertExpansion(
      """
      @Union
      enum Source {
        case text(String)
        case none
        case pair(Int, Int)
        case again(String)
      }
      """,
      expandedSource: """
        enum Source {
          case text(String)
          case none
          case pair(Int, Int)
          case again(String)
        }
        """,
      diagnostics: [
        DiagnosticSpec(
          message:
            "@Union case 'none' must carry exactly one associated value: the type this alternative decodes from. A payload-less enum is not a union; make it a raw-value enum conforming to 'Enumerable' instead.",
          line: 4,
          column: 8
        ),
        DiagnosticSpec(
          message:
            "@Union case 'pair' must carry exactly one associated value, but has 2. Group them in a @Record type and use it as the single payload.",
          line: 5,
          column: 8
        ),
        DiagnosticSpec(
          message:
            "@Union case 'again' repeats the payload type 'String' of case 'text' and can never be decoded: alternatives are tried in declaration order and the first match wins.",
          line: 6,
          column: 8
        ),
      ]
    )
  }

  @Test
  func `A closure payload produces a diagnostic on the closure type`() {
    assertExpansion(
      """
      @Union
      enum Source {
        case text(String)
        case callback((Int) -> Void)
        case callbacks([() -> Void])
      }
      """,
      expandedSource: """
        enum Source {
          case text(String)
          case callback((Int) -> Void)
          case callbacks([() -> Void])
        }
        """,
      diagnostics: [
        DiagnosticSpec(
          message:
            "@Union case 'callback' can't carry a closure: the payload is also encoded to JavaScript, and a native closure can't be encoded.",
          line: 4,
          column: 17
        ),
        DiagnosticSpec(
          message:
            "@Union case 'callbacks' can't carry a closure: the payload is also encoded to JavaScript, and a native closure can't be encoded.",
          line: 5,
          column: 19
        ),
      ]
    )
  }

  @Test
  func `Tuple payload converts through the tuple methods`() {
    assertExpansion(
      """
      @Union
      enum Coordinate {
        case pair((Double, Double))
        case label(String)
      }
      """,
      expandedSource: """
        enum Coordinate {
          case pair((Double, Double))
          case label(String)

          nonisolated public static var decodableKinds: JavaScriptValueKinds {
            return [JavaScriptValueKinds.object, String.decodableKinds]
          }

          @JavaScriptActor
          public static func decode(_ value: borrowing JavaScriptUnownedValue, in runtime: borrowing JavaScriptRuntime) throws -> Self {
            let kind = JavaScriptValueKinds(of: value)
            if JavaScriptValueKinds.object.contains(kind), let payload = try? JavaScriptValue.decodeTuple(value, as: Double.self, Double.self, in: runtime) {
              return .pair(payload)
            }
            if String.decodableKinds.contains(kind), let payload = try? String.decode(value, in: runtime) {
              return .label(payload)
            }
            throw Exceptions.UnionCaseMismatch((unionName: "Coordinate", received: value.copied(in: runtime).kind.rawValue, expected: ["(Double, Double)", "String"]))
          }

          @JavaScriptActor
          public static func encode(_ value: Self, in runtime: borrowing JavaScriptRuntime) throws -> JavaScriptValue {
            switch value {
            case .pair(let payload):
              return try JavaScriptValue.encoding(in: runtime) { slot in
                try JavaScriptValue.encodeTuple(payload, into: slot, in: runtime)
              }
            case .label(let payload):
              return try String.encode(payload, in: runtime)
            }
          }

          @JavaScriptActor
          public static func encode(
            _ value: Self,
            into slot: borrowing JavaScriptValue.Slot,
            in runtime: borrowing JavaScriptRuntime
          ) throws {
            switch value {
            case .pair(let payload):
              try JavaScriptValue.encodeTuple(payload, into: slot, in: runtime)
            case .label(let payload):
              try String.encode(payload, into: slot, in: runtime)
            }
          }

          nonisolated public func `as`(_ type: (Double, Double).Type) throws -> (Double, Double) {
            if case .pair(let payload) = self {
              return payload
            }
            throw Exceptions.UnionCaseMismatch((unionName: "Coordinate", received: _payloadTypeName, expected: ["(Double, Double)"]))
          }

          nonisolated public func `as`(_ type: String.Type) throws -> String {
            if case .label(let payload) = self {
              return payload
            }
            throw Exceptions.UnionCaseMismatch((unionName: "Coordinate", received: _payloadTypeName, expected: ["String"]))
          }

          nonisolated private var _payloadTypeName: String {
            switch self {
            case .pair:
              return "(Double, Double)"
            case .label:
              return "String"
            }
          }
        }

        extension Coordinate: nonisolated JavaScriptDecodable, nonisolated JavaScriptEncodable {
        }
        """
    )
  }
}
