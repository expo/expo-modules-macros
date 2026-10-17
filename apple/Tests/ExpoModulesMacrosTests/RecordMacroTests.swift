import ExpoModulesMacros
import SwiftSyntax
import SwiftSyntaxMacroExpansion
import SwiftSyntaxMacros
import SwiftSyntaxMacrosGenericTestSupport
import Testing

private let recordMacroSpecs: [String: MacroSpec] = [
  "Record": MacroSpec(type: RecordMacro.self)
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
    macroSpecs: recordMacroSpecs,
    indentationWidth: .spaces(2),
    failureHandler: recordIssue,
    fileID: fileID,
    filePath: filePath,
    line: line,
    column: column
  )
}

@Suite("@Record macro")
struct RecordMacroTests {
  @Test
  func `All stored properties become record properties with requiredness inferred from the declaration`() {
    assertExpansion(
      """
      @Record
      struct Options {
        var name: String
        var count: Int = 0
        var note: String?
      }
      """,
      expandedSource: """
        struct Options {
          var name: String
          var count: Int = 0
          var note: String?

          public init() {
            fatalError("\\(Self.self) has required properties and cannot be created with init(); construct it through the @Record-synthesized from(dictionary:) or from(object:) factories")
          }

          public init(name: String, count: Int, note: String? = nil) {
            self.name = name
            self.count = count
            self.note = note
          }

          @JavaScriptActor
          public static func from(object: borrowing JavaScriptObject, appContext: AppContext) throws -> Self {
            let runtime = try appContext.runtime
            return try object.asValue().withUnownedValue(in: runtime) { unownedValue in
              return try decode(unownedValue, in: runtime)
            }
          }

          public static func from(dictionary: [String: Any], appContext: AppContext) throws -> Self {
            let entry0 = dictionary["name"]
            guard let entry0 else {
              throw RecordPropertyRequiredException("name")
            }
            let field0 = try String.getDynamicType().cast(entry0, appContext: appContext) as! String
            let entry1 = dictionary["count"]
            let field1 = entry1 == nil ? 0 : try Int.getDynamicType().cast(entry1, appContext: appContext) as! Int
            let entry2 = dictionary["note"]
            let field2: String? = (entry2 == nil || entry2! is NSNull) ? nil : try String?.getDynamicType().cast(entry2, appContext: appContext) as! String?
            return Self(name: field0, count: field1, note: field2)
          }

          public func toDictionary(appContext: AppContext? = nil) -> [String: Any] {
            var dictionary: [String: Any] = [:]
            dictionary["name"] = self.name
            dictionary["count"] = self.count
            dictionary["note"] = self.note
            return dictionary
          }

          @JavaScriptActor
          public func toObject(appContext: AppContext) throws -> JavaScriptObject {
            return try Self.encode(self, in: appContext.runtime).asObject()
          }

          @JavaScriptActor
          public static func decode(_ value: borrowing JavaScriptUnownedValue, in runtime: borrowing JavaScriptRuntime) throws -> Self {
            let object = try value.asObject(in: runtime)
            let field0 = try object.withUnownedProperty("name") { nameJSValue in
              guard !nameJSValue.isUndefined() else {
                throw RecordPropertyRequiredException("name")
              }
              return try String.decode(nameJSValue, in: runtime)
            }
            let field1 = try object.withUnownedProperty("count") { countJSValue in
              return countJSValue.isUndefined() ? 0 : try Int.decode(countJSValue, in: runtime)
            }
            let field2 = try object.withUnownedProperty("note") { noteJSValue in
              return try String?.decode(noteJSValue, in: runtime)
            }
            return Self(name: field0, count: field1, note: field2)
          }

          @JavaScriptActor
          public static func encode(_ value: Options, in runtime: borrowing JavaScriptRuntime) throws -> JavaScriptValue {
            let object = runtime.createObject()
            object.setProperty("name", value: try String.encode(value.name, in: runtime))
            object.setProperty("count", value: try Int.encode(value.count, in: runtime))
            object.setProperty("note", value: try String?.encode(value.note, in: runtime))
            return object.asValue()
          }
        }

        extension Options: Record {
        }
        """
    )
  }

  @Test
  func `Implicitly-unwrapped optional property normalizes to optional in cast and convert expressions`() {
    assertExpansion(
      """
      @Record
      struct Options {
        var owner: MyRecord!
      }
      """,
      expandedSource: """
        struct Options {
          var owner: MyRecord!

          private func _assertTypesConformance() {
            func owner<T: AnyArgument & JavaScriptDecodable & JavaScriptEncodable>(_: T.Type) {
            }
            owner(MyRecord.self)
          }

          public init() {
          }

          public init(owner: MyRecord! = nil) {
            self.owner = owner
          }

          @JavaScriptActor
          public static func from(object: borrowing JavaScriptObject, appContext: AppContext) throws -> Self {
            let runtime = try appContext.runtime
            return try object.asValue().withUnownedValue(in: runtime) { unownedValue in
              return try decode(unownedValue, in: runtime)
            }
          }

          public static func from(dictionary: [String: Any], appContext: AppContext) throws -> Self {
            let entry0 = dictionary["owner"]
            let field0: MyRecord! = (entry0 == nil || entry0! is NSNull) ? nil : try MyRecord?.getDynamicType().cast(entry0, appContext: appContext) as! MyRecord?
            return Self(owner: field0)
          }

          public func toDictionary(appContext: AppContext? = nil) -> [String: Any] {
            var dictionary: [String: Any] = [:]
            dictionary["owner"] = self.owner
            return dictionary
          }

          @JavaScriptActor
          public func toObject(appContext: AppContext) throws -> JavaScriptObject {
            return try Self.encode(self, in: appContext.runtime).asObject()
          }

          @JavaScriptActor
          public static func decode(_ value: borrowing JavaScriptUnownedValue, in runtime: borrowing JavaScriptRuntime) throws -> Self {
            let object = try value.asObject(in: runtime)
            let field0 = try object.withUnownedProperty("owner") { ownerJSValue in
              return try MyRecord?.decode(ownerJSValue, in: runtime)
            }
            return Self(owner: field0)
          }

          @JavaScriptActor
          public static func encode(_ value: Options, in runtime: borrowing JavaScriptRuntime) throws -> JavaScriptValue {
            let object = runtime.createObject()
            object.setProperty("owner", value: try MyRecord?.encode(value.owner, in: runtime))
            return object.asValue()
          }
        }

        extension Options: Record {
        }
        """
    )
  }

  @Test
  func `Non-primitive properties are checked in a single conformance-assertion peer`() {
    assertExpansion(
      """
      @Record
      struct Options {
        var primary: MyRecord
        var tags: [String]
        var count: Int = 0
      }
      """,
      expandedSource: """
        struct Options {
          var primary: MyRecord
          var tags: [String]
          var count: Int = 0

          private func _assertTypesConformance() {
            func primary<T: AnyArgument & JavaScriptDecodable & JavaScriptEncodable>(_: T.Type) {
            }
            primary(MyRecord.self)
            func tags<T: AnyArgument & JavaScriptDecodable & JavaScriptEncodable>(_: T.Type) {
            }
            tags([String].self)
          }

          public init() {
            fatalError("\\(Self.self) has required properties and cannot be created with init(); construct it through the @Record-synthesized from(dictionary:) or from(object:) factories")
          }

          public init(primary: MyRecord, tags: [String], count: Int) {
            self.primary = primary
            self.tags = tags
            self.count = count
          }

          @JavaScriptActor
          public static func from(object: borrowing JavaScriptObject, appContext: AppContext) throws -> Self {
            let runtime = try appContext.runtime
            return try object.asValue().withUnownedValue(in: runtime) { unownedValue in
              return try decode(unownedValue, in: runtime)
            }
          }

          public static func from(dictionary: [String: Any], appContext: AppContext) throws -> Self {
            let entry0 = dictionary["primary"]
            guard let entry0 else {
              throw RecordPropertyRequiredException("primary")
            }
            let field0 = try MyRecord.getDynamicType().cast(entry0, appContext: appContext) as! MyRecord
            let entry1 = dictionary["tags"]
            guard let entry1 else {
              throw RecordPropertyRequiredException("tags")
            }
            let field1 = try [String].getDynamicType().cast(entry1, appContext: appContext) as! [String]
            let entry2 = dictionary["count"]
            let field2 = entry2 == nil ? 0 : try Int.getDynamicType().cast(entry2, appContext: appContext) as! Int
            return Self(primary: field0, tags: field1, count: field2)
          }

          public func toDictionary(appContext: AppContext? = nil) -> [String: Any] {
            var dictionary: [String: Any] = [:]
            dictionary["primary"] = self.primary
            dictionary["tags"] = self.tags
            dictionary["count"] = self.count
            return dictionary
          }

          @JavaScriptActor
          public func toObject(appContext: AppContext) throws -> JavaScriptObject {
            return try Self.encode(self, in: appContext.runtime).asObject()
          }

          @JavaScriptActor
          public static func decode(_ value: borrowing JavaScriptUnownedValue, in runtime: borrowing JavaScriptRuntime) throws -> Self {
            let object = try value.asObject(in: runtime)
            let field0 = try object.withUnownedProperty("primary") { primaryJSValue in
              guard !primaryJSValue.isUndefined() else {
                throw RecordPropertyRequiredException("primary")
              }
              return try MyRecord.decode(primaryJSValue, in: runtime)
            }
            let field1 = try object.withUnownedProperty("tags") { tagsJSValue in
              guard !tagsJSValue.isUndefined() else {
                throw RecordPropertyRequiredException("tags")
              }
              return try [String].decode(tagsJSValue, in: runtime)
            }
            let field2 = try object.withUnownedProperty("count") { countJSValue in
              return countJSValue.isUndefined() ? 0 : try Int.decode(countJSValue, in: runtime)
            }
            return Self(primary: field0, tags: field1, count: field2)
          }

          @JavaScriptActor
          public static func encode(_ value: Options, in runtime: borrowing JavaScriptRuntime) throws -> JavaScriptValue {
            let object = runtime.createObject()
            object.setProperty("primary", value: try MyRecord.encode(value.primary, in: runtime))
            object.setProperty("tags", value: try [String].encode(value.tags, in: runtime))
            object.setProperty("count", value: try Int.encode(value.count, in: runtime))
            return object.asValue()
          }
        }

        extension Options: Record {
        }
        """
    )
  }

  @Test
  func `Property types are inferred from scalar literal defaults when the annotation is omitted`() {
    assertExpansion(
      """
      @Record
      struct Options {
        var name = "foo"
        var ratio = 1.0
        var count = 0
        var flag = false
      }
      """,
      expandedSource: """
        struct Options {
          var name = "foo"
          var ratio = 1.0
          var count = 0
          var flag = false

          public init() {
          }

          public init(name: String, ratio: Double, count: Int, flag: Bool) {
            self.name = name
            self.ratio = ratio
            self.count = count
            self.flag = flag
          }

          @JavaScriptActor
          public static func from(object: borrowing JavaScriptObject, appContext: AppContext) throws -> Self {
            let runtime = try appContext.runtime
            return try object.asValue().withUnownedValue(in: runtime) { unownedValue in
              return try decode(unownedValue, in: runtime)
            }
          }

          public static func from(dictionary: [String: Any], appContext: AppContext) throws -> Self {
            let entry0 = dictionary["name"]
            let field0 = entry0 == nil ? "foo" : try String.getDynamicType().cast(entry0, appContext: appContext) as! String
            let entry1 = dictionary["ratio"]
            let field1 = entry1 == nil ? 1.0 : try Double.getDynamicType().cast(entry1, appContext: appContext) as! Double
            let entry2 = dictionary["count"]
            let field2 = entry2 == nil ? 0 : try Int.getDynamicType().cast(entry2, appContext: appContext) as! Int
            let entry3 = dictionary["flag"]
            let field3 = entry3 == nil ? false : try Bool.getDynamicType().cast(entry3, appContext: appContext) as! Bool
            return Self(name: field0, ratio: field1, count: field2, flag: field3)
          }

          public func toDictionary(appContext: AppContext? = nil) -> [String: Any] {
            var dictionary: [String: Any] = [:]
            dictionary["name"] = self.name
            dictionary["ratio"] = self.ratio
            dictionary["count"] = self.count
            dictionary["flag"] = self.flag
            return dictionary
          }

          @JavaScriptActor
          public func toObject(appContext: AppContext) throws -> JavaScriptObject {
            return try Self.encode(self, in: appContext.runtime).asObject()
          }

          @JavaScriptActor
          public static func decode(_ value: borrowing JavaScriptUnownedValue, in runtime: borrowing JavaScriptRuntime) throws -> Self {
            let object = try value.asObject(in: runtime)
            let field0 = try object.withUnownedProperty("name") { nameJSValue in
              return nameJSValue.isUndefined() ? "foo" : try String.decode(nameJSValue, in: runtime)
            }
            let field1 = try object.withUnownedProperty("ratio") { ratioJSValue in
              return ratioJSValue.isUndefined() ? 1.0 : try Double.decode(ratioJSValue, in: runtime)
            }
            let field2 = try object.withUnownedProperty("count") { countJSValue in
              return countJSValue.isUndefined() ? 0 : try Int.decode(countJSValue, in: runtime)
            }
            let field3 = try object.withUnownedProperty("flag") { flagJSValue in
              return flagJSValue.isUndefined() ? false : try Bool.decode(flagJSValue, in: runtime)
            }
            return Self(name: field0, ratio: field1, count: field2, flag: field3)
          }

          @JavaScriptActor
          public static func encode(_ value: Options, in runtime: borrowing JavaScriptRuntime) throws -> JavaScriptValue {
            let object = runtime.createObject()
            object.setProperty("name", value: try String.encode(value.name, in: runtime))
            object.setProperty("ratio", value: try Double.encode(value.ratio, in: runtime))
            object.setProperty("count", value: try Int.encode(value.count, in: runtime))
            object.setProperty("flag", value: try Bool.encode(value.flag, in: runtime))
            return object.asValue()
          }
        }

        extension Options: Record {
        }
        """
    )
  }

  @Test
  func `A non-literal default without an annotation still requires an explicit type`() {
    assertExpansion(
      """
      @Record
      struct Options {
        var items = []
      }
      """,
      expandedSource: """
        struct Options {
          var items = []
        }

        extension Options: Record {
        }
        """,
      diagnostics: [
        DiagnosticSpec(
          message: "@Record properties must declare an explicit type — 'items' has none",
          line: 1,
          column: 1
        )
      ]
    )
  }

  @Test
  func `static, private and fileprivate properties and computed properties are excluded`() {
    assertExpansion(
      """
      @Record
      struct Options {
        var name: String
        static let shared = "x"
        private var secret: Int = 0
        fileprivate var hidden: Bool = false
        var computed: Int { 1 }
      }
      """,
      expandedSource: """
        struct Options {
          var name: String
          static let shared = "x"
          private var secret: Int = 0
          fileprivate var hidden: Bool = false
          var computed: Int { 1 }

          public init() {
            fatalError("\\(Self.self) has required properties and cannot be created with init(); construct it through the @Record-synthesized from(dictionary:) or from(object:) factories")
          }

          public init(name: String) {
            self.name = name
          }

          @JavaScriptActor
          public static func from(object: borrowing JavaScriptObject, appContext: AppContext) throws -> Self {
            let runtime = try appContext.runtime
            return try object.asValue().withUnownedValue(in: runtime) { unownedValue in
              return try decode(unownedValue, in: runtime)
            }
          }

          public static func from(dictionary: [String: Any], appContext: AppContext) throws -> Self {
            let entry0 = dictionary["name"]
            guard let entry0 else {
              throw RecordPropertyRequiredException("name")
            }
            let field0 = try String.getDynamicType().cast(entry0, appContext: appContext) as! String
            return Self(name: field0)
          }

          public func toDictionary(appContext: AppContext? = nil) -> [String: Any] {
            var dictionary: [String: Any] = [:]
            dictionary["name"] = self.name
            return dictionary
          }

          @JavaScriptActor
          public func toObject(appContext: AppContext) throws -> JavaScriptObject {
            return try Self.encode(self, in: appContext.runtime).asObject()
          }

          @JavaScriptActor
          public static func decode(_ value: borrowing JavaScriptUnownedValue, in runtime: borrowing JavaScriptRuntime) throws -> Self {
            let object = try value.asObject(in: runtime)
            let field0 = try object.withUnownedProperty("name") { nameJSValue in
              guard !nameJSValue.isUndefined() else {
                throw RecordPropertyRequiredException("name")
              }
              return try String.decode(nameJSValue, in: runtime)
            }
            return Self(name: field0)
          }

          @JavaScriptActor
          public static func encode(_ value: Options, in runtime: borrowing JavaScriptRuntime) throws -> JavaScriptValue {
            let object = runtime.createObject()
            object.setProperty("name", value: try String.encode(value.name, in: runtime))
            return object.asValue()
          }
        }

        extension Options: Record {
        }
        """
    )
  }

  @Test
  func `Empty record synthesizes the full surface with no properties`() {
    assertExpansion(
      """
      @Record
      struct Empty {
      }
      """,
      expandedSource: """
        struct Empty {

          public init() {

          }

          @JavaScriptActor
          public static func from(object: borrowing JavaScriptObject, appContext: AppContext) throws -> Self {
            let runtime = try appContext.runtime
            return try object.asValue().withUnownedValue(in: runtime) { unownedValue in
              return try decode(unownedValue, in: runtime)
            }
          }

          public static func from(dictionary: [String: Any], appContext: AppContext) throws -> Self {
            return Self()
          }

          public func toDictionary(appContext: AppContext? = nil) -> [String: Any] {
            var dictionary: [String: Any] = [:]
            return dictionary
          }

          @JavaScriptActor
          public func toObject(appContext: AppContext) throws -> JavaScriptObject {
            return try Self.encode(self, in: appContext.runtime).asObject()
          }

          @JavaScriptActor
          public static func decode(_ value: borrowing JavaScriptUnownedValue, in runtime: borrowing JavaScriptRuntime) throws -> Self {
            _ = try value.asObject(in: runtime)
            return Self()
          }

          @JavaScriptActor
          public static func encode(_ value: Empty, in runtime: borrowing JavaScriptRuntime) throws -> JavaScriptValue {
            let object = runtime.createObject()
            return object.asValue()
          }
        }

        extension Empty: Record {
        }
        """
    )
  }

  @Test
  func `Struct with only defaulted properties gets an explicit init() for Record conformance`() {
    assertExpansion(
      """
      @Record
      struct Point {
        var x: Double = 0
        var y: Double = 0
      }
      """,
      expandedSource: """
        struct Point {
          var x: Double = 0
          var y: Double = 0

          public init() {
          }

          public init(x: Double, y: Double) {
            self.x = x
            self.y = y
          }

          @JavaScriptActor
          public static func from(object: borrowing JavaScriptObject, appContext: AppContext) throws -> Self {
            let runtime = try appContext.runtime
            return try object.asValue().withUnownedValue(in: runtime) { unownedValue in
              return try decode(unownedValue, in: runtime)
            }
          }

          public static func from(dictionary: [String: Any], appContext: AppContext) throws -> Self {
            let entry0 = dictionary["x"]
            let field0 = entry0 == nil ? 0 : try Double.getDynamicType().cast(entry0, appContext: appContext) as! Double
            let entry1 = dictionary["y"]
            let field1 = entry1 == nil ? 0 : try Double.getDynamicType().cast(entry1, appContext: appContext) as! Double
            return Self(x: field0, y: field1)
          }

          public func toDictionary(appContext: AppContext? = nil) -> [String: Any] {
            var dictionary: [String: Any] = [:]
            dictionary["x"] = self.x
            dictionary["y"] = self.y
            return dictionary
          }

          @JavaScriptActor
          public func toObject(appContext: AppContext) throws -> JavaScriptObject {
            return try Self.encode(self, in: appContext.runtime).asObject()
          }

          @JavaScriptActor
          public static func decode(_ value: borrowing JavaScriptUnownedValue, in runtime: borrowing JavaScriptRuntime) throws -> Self {
            let object = try value.asObject(in: runtime)
            let field0 = try object.withUnownedProperty("x") { xJSValue in
              return xJSValue.isUndefined() ? 0 : try Double.decode(xJSValue, in: runtime)
            }
            let field1 = try object.withUnownedProperty("y") { yJSValue in
              return yJSValue.isUndefined() ? 0 : try Double.decode(yJSValue, in: runtime)
            }
            return Self(x: field0, y: field1)
          }

          @JavaScriptActor
          public static func encode(_ value: Point, in runtime: borrowing JavaScriptRuntime) throws -> JavaScriptValue {
            let object = runtime.createObject()
            object.setProperty("x", value: try Double.encode(value.x, in: runtime))
            object.setProperty("y", value: try Double.encode(value.y, in: runtime))
            return object.asValue()
          }
        }

        extension Point: Record {
        }
        """
    )
  }

  @Test
  func `Subclass chains to super for the write side and inlines property defaults`() {
    assertExpansion(
      """
      @Record
      final class Child: Parent {
        var extra: String = ""
      }
      """,
      expandedSource: """
        final class Child: Parent {
          var extra: String = ""

          public init(extra: String) {
            self.extra = extra
          }

          @JavaScriptActor
          public static func from(object: borrowing JavaScriptObject, appContext: AppContext) throws -> Self {
            let runtime = try appContext.runtime
            let field0 = try object.withUnownedProperty("extra") { extraJSValue in
              return extraJSValue.isUndefined() ? "" : try String.decode(extraJSValue, in: runtime)
            }
            return Self(extra: field0)
          }

          public static func from(dictionary: [String: Any], appContext: AppContext) throws -> Self {
            let entry0 = dictionary["extra"]
            let field0 = entry0 == nil ? "" : try String.getDynamicType().cast(entry0, appContext: appContext) as! String
            return Self(extra: field0)
          }

          public override func toDictionary(appContext: AppContext? = nil) -> [String: Any] {
            var dictionary = super.toDictionary(appContext: appContext)
            dictionary["extra"] = self.extra
            return dictionary
          }

          @JavaScriptActor
          public override func toObject(appContext: AppContext) throws -> JavaScriptObject {
            let runtime = try appContext.runtime
            let object = try super.toObject(appContext: appContext)
            object.setProperty("extra", value: try String.encode(self.extra, in: runtime))
            return object
          }
        }
        """
    )
  }

  @Test
  func `Class without inheritance gets the Record conformance`() {
    assertExpansion(
      """
      @Record
      final class Options {
        var name: String
      }
      """,
      expandedSource: """
        final class Options {
          var name: String

          public init(name: String) {
            self.name = name
          }

          @JavaScriptActor
          public static func from(object: borrowing JavaScriptObject, appContext: AppContext) throws -> Self {
            let runtime = try appContext.runtime
            return try object.asValue().withUnownedValue(in: runtime) { unownedValue in
              return try decode(unownedValue, in: runtime)
            }
          }

          public static func from(dictionary: [String: Any], appContext: AppContext) throws -> Self {
            let entry0 = dictionary["name"]
            guard let entry0 else {
              throw RecordPropertyRequiredException("name")
            }
            let field0 = try String.getDynamicType().cast(entry0, appContext: appContext) as! String
            return Self(name: field0)
          }

          public func toDictionary(appContext: AppContext? = nil) -> [String: Any] {
            var dictionary: [String: Any] = [:]
            dictionary["name"] = self.name
            return dictionary
          }

          @JavaScriptActor
          public func toObject(appContext: AppContext) throws -> JavaScriptObject {
            return try Self.encode(self, in: appContext.runtime).asObject()
          }

          @JavaScriptActor
          public static func decode(_ value: borrowing JavaScriptUnownedValue, in runtime: borrowing JavaScriptRuntime) throws -> Self {
            let object = try value.asObject(in: runtime)
            let field0 = try object.withUnownedProperty("name") { nameJSValue in
              guard !nameJSValue.isUndefined() else {
                throw RecordPropertyRequiredException("name")
              }
              return try String.decode(nameJSValue, in: runtime)
            }
            return Self(name: field0)
          }

          @JavaScriptActor
          public static func encode(_ value: Options, in runtime: borrowing JavaScriptRuntime) throws -> JavaScriptValue {
            let object = runtime.createObject()
            object.setProperty("name", value: try String.encode(value.name, in: runtime))
            return object.asValue()
          }
        }

        extension Options: Record {
        }
        """
    )
  }

  @Test
  func `Type already declaring Record does not get a redundant extension`() {
    assertExpansion(
      """
      @Record
      struct Options: Record {
        var name: String
      }
      """,
      expandedSource: """
        struct Options: Record {
          var name: String

          public init() {
            fatalError("\\(Self.self) has required properties and cannot be created with init(); construct it through the @Record-synthesized from(dictionary:) or from(object:) factories")
          }

          public init(name: String) {
            self.name = name
          }

          @JavaScriptActor
          public static func from(object: borrowing JavaScriptObject, appContext: AppContext) throws -> Self {
            let runtime = try appContext.runtime
            return try object.asValue().withUnownedValue(in: runtime) { unownedValue in
              return try decode(unownedValue, in: runtime)
            }
          }

          public static func from(dictionary: [String: Any], appContext: AppContext) throws -> Self {
            let entry0 = dictionary["name"]
            guard let entry0 else {
              throw RecordPropertyRequiredException("name")
            }
            let field0 = try String.getDynamicType().cast(entry0, appContext: appContext) as! String
            return Self(name: field0)
          }

          public func toDictionary(appContext: AppContext? = nil) -> [String: Any] {
            var dictionary: [String: Any] = [:]
            dictionary["name"] = self.name
            return dictionary
          }

          @JavaScriptActor
          public func toObject(appContext: AppContext) throws -> JavaScriptObject {
            return try Self.encode(self, in: appContext.runtime).asObject()
          }

          @JavaScriptActor
          public static func decode(_ value: borrowing JavaScriptUnownedValue, in runtime: borrowing JavaScriptRuntime) throws -> Self {
            let object = try value.asObject(in: runtime)
            let field0 = try object.withUnownedProperty("name") { nameJSValue in
              guard !nameJSValue.isUndefined() else {
                throw RecordPropertyRequiredException("name")
              }
              return try String.decode(nameJSValue, in: runtime)
            }
            return Self(name: field0)
          }

          @JavaScriptActor
          public static func encode(_ value: Options, in runtime: borrowing JavaScriptRuntime) throws -> JavaScriptValue {
            let object = runtime.createObject()
            object.setProperty("name", value: try String.encode(value.name, in: runtime))
            return object.asValue()
          }
        }
        """
    )
  }

  @Test
  func `A leftover @Field attribute produces a diagnostic`() {
    assertExpansion(
      """
      @Record
      struct Options {
        var name: String
        @Field var defaultName = "foo"
      }
      """,
      expandedSource: """
        struct Options {
          var name: String
          @Field var defaultName = "foo"
        }

        extension Options: Record {
        }
        """,
      diagnostics: [
        DiagnosticSpec(
          message: "@Field is no longer used — @Record treats every stored property as a record property. Remove the @Field attribute",
          line: 1,
          column: 1
        )
      ]
    )
  }

  @Test
  func `Applying @Record to an enum produces a diagnostic`() {
    assertExpansion(
      """
      @Record
      enum NotARecord {
      }
      """,
      expandedSource: """
        enum NotARecord {
        }
        """,
      diagnostics: [
        DiagnosticSpec(
          message: "@Record can only be applied to a struct or class",
          line: 1,
          column: 1
        )
      ]
    )
  }

  @Test
  func `Author-declared init() is not duplicated`() {
    assertExpansion(
      """
      @Record
      struct Options {
        var x: Double = 0
        var y: Double = 0

        init() {
          x = 1
          y = 2
        }
      }
      """,
      expandedSource: """
        struct Options {
          var x: Double = 0
          var y: Double = 0

          init() {
            x = 1
            y = 2
          }

          public init(x: Double, y: Double) {
            self.x = x
            self.y = y
          }

          @JavaScriptActor
          public static func from(object: borrowing JavaScriptObject, appContext: AppContext) throws -> Self {
            let runtime = try appContext.runtime
            return try object.asValue().withUnownedValue(in: runtime) { unownedValue in
              return try decode(unownedValue, in: runtime)
            }
          }

          public static func from(dictionary: [String: Any], appContext: AppContext) throws -> Self {
            let entry0 = dictionary["x"]
            let field0 = entry0 == nil ? 0 : try Double.getDynamicType().cast(entry0, appContext: appContext) as! Double
            let entry1 = dictionary["y"]
            let field1 = entry1 == nil ? 0 : try Double.getDynamicType().cast(entry1, appContext: appContext) as! Double
            return Self(x: field0, y: field1)
          }

          public func toDictionary(appContext: AppContext? = nil) -> [String: Any] {
            var dictionary: [String: Any] = [:]
            dictionary["x"] = self.x
            dictionary["y"] = self.y
            return dictionary
          }

          @JavaScriptActor
          public func toObject(appContext: AppContext) throws -> JavaScriptObject {
            return try Self.encode(self, in: appContext.runtime).asObject()
          }

          @JavaScriptActor
          public static func decode(_ value: borrowing JavaScriptUnownedValue, in runtime: borrowing JavaScriptRuntime) throws -> Self {
            let object = try value.asObject(in: runtime)
            let field0 = try object.withUnownedProperty("x") { xJSValue in
              return xJSValue.isUndefined() ? 0 : try Double.decode(xJSValue, in: runtime)
            }
            let field1 = try object.withUnownedProperty("y") { yJSValue in
              return yJSValue.isUndefined() ? 0 : try Double.decode(yJSValue, in: runtime)
            }
            return Self(x: field0, y: field1)
          }

          @JavaScriptActor
          public static func encode(_ value: Options, in runtime: borrowing JavaScriptRuntime) throws -> JavaScriptValue {
            let object = runtime.createObject()
            object.setProperty("x", value: try Double.encode(value.x, in: runtime))
            object.setProperty("y", value: try Double.encode(value.y, in: runtime))
            return object.asValue()
          }
        }

        extension Options: Record {
        }
        """
    )
  }

  @Test
  func `Author-declared memberwise init is not duplicated`() {
    assertExpansion(
      """
      @Record
      struct Options {
        var x: Double = 0
        var y: Double = 0

        init(x: Double, y: Double) {
          self.x = x
          self.y = y
        }
      }
      """,
      expandedSource: """
        struct Options {
          var x: Double = 0
          var y: Double = 0

          init(x: Double, y: Double) {
            self.x = x
            self.y = y
          }

          public init() {
          }

          @JavaScriptActor
          public static func from(object: borrowing JavaScriptObject, appContext: AppContext) throws -> Self {
            let runtime = try appContext.runtime
            return try object.asValue().withUnownedValue(in: runtime) { unownedValue in
              return try decode(unownedValue, in: runtime)
            }
          }

          public static func from(dictionary: [String: Any], appContext: AppContext) throws -> Self {
            let entry0 = dictionary["x"]
            let field0 = entry0 == nil ? 0 : try Double.getDynamicType().cast(entry0, appContext: appContext) as! Double
            let entry1 = dictionary["y"]
            let field1 = entry1 == nil ? 0 : try Double.getDynamicType().cast(entry1, appContext: appContext) as! Double
            return Self(x: field0, y: field1)
          }

          public func toDictionary(appContext: AppContext? = nil) -> [String: Any] {
            var dictionary: [String: Any] = [:]
            dictionary["x"] = self.x
            dictionary["y"] = self.y
            return dictionary
          }

          @JavaScriptActor
          public func toObject(appContext: AppContext) throws -> JavaScriptObject {
            return try Self.encode(self, in: appContext.runtime).asObject()
          }

          @JavaScriptActor
          public static func decode(_ value: borrowing JavaScriptUnownedValue, in runtime: borrowing JavaScriptRuntime) throws -> Self {
            let object = try value.asObject(in: runtime)
            let field0 = try object.withUnownedProperty("x") { xJSValue in
              return xJSValue.isUndefined() ? 0 : try Double.decode(xJSValue, in: runtime)
            }
            let field1 = try object.withUnownedProperty("y") { yJSValue in
              return yJSValue.isUndefined() ? 0 : try Double.decode(yJSValue, in: runtime)
            }
            return Self(x: field0, y: field1)
          }

          @JavaScriptActor
          public static func encode(_ value: Options, in runtime: borrowing JavaScriptRuntime) throws -> JavaScriptValue {
            let object = runtime.createObject()
            object.setProperty("x", value: try Double.encode(value.x, in: runtime))
            object.setProperty("y", value: try Double.encode(value.y, in: runtime))
            return object.asValue()
          }
        }

        extension Options: Record {
        }
        """
    )
  }

  @Test
  func `Author-declared memberwise init matches an escaped property name by its bare label`() {
    assertExpansion(
      """
      @Record
      struct Options {
        var `default`: Int = 0

        init(default: Int) {
          self.default = `default`
        }
      }
      """,
      expandedSource: """
        struct Options {
          var `default`: Int = 0

          init(default: Int) {
            self.default = `default`
          }

          public init() {
          }

          @JavaScriptActor
          public static func from(object: borrowing JavaScriptObject, appContext: AppContext) throws -> Self {
            let runtime = try appContext.runtime
            return try object.asValue().withUnownedValue(in: runtime) { unownedValue in
              return try decode(unownedValue, in: runtime)
            }
          }

          public static func from(dictionary: [String: Any], appContext: AppContext) throws -> Self {
            let entry0 = dictionary["default"]
            let field0 = entry0 == nil ? 0 : try Int.getDynamicType().cast(entry0, appContext: appContext) as! Int
            return Self(`default`: field0)
          }

          public func toDictionary(appContext: AppContext? = nil) -> [String: Any] {
            var dictionary: [String: Any] = [:]
            dictionary["default"] = self.`default`
            return dictionary
          }

          @JavaScriptActor
          public func toObject(appContext: AppContext) throws -> JavaScriptObject {
            return try Self.encode(self, in: appContext.runtime).asObject()
          }

          @JavaScriptActor
          public static func decode(_ value: borrowing JavaScriptUnownedValue, in runtime: borrowing JavaScriptRuntime) throws -> Self {
            let object = try value.asObject(in: runtime)
            let field0 = try object.withUnownedProperty("default") { `defaultJSValue` in
              return `defaultJSValue`.isUndefined() ? 0 : try Int.decode(`defaultJSValue`, in: runtime)
            }
            return Self(`default`: field0)
          }

          @JavaScriptActor
          public static func encode(_ value: Options, in runtime: borrowing JavaScriptRuntime) throws -> JavaScriptValue {
            let object = runtime.createObject()
            object.setProperty("default", value: try Int.encode(value.`default`, in: runtime))
            return object.asValue()
          }
        }

        extension Options: Record {
        }
        """
    )
  }

  @Test
  func `Optional free-form dictionary property converts through the dedicated free-form methods on the JS-object paths`() {
    assertExpansion(
      """
      @Record
      struct Report {
        var name: String
        var attributes: [String: Any]?
      }
      """,
      expandedSource: """
        struct Report {
          var name: String
          var attributes: [String: Any]?

          private func _assertTypesConformance() {
            func attributes<T: AnyArgument>(_: T.Type) {
            }
            attributes([String: Any].self)
          }

          public init() {
            fatalError("\\(Self.self) has required properties and cannot be created with init(); construct it through the @Record-synthesized from(dictionary:) or from(object:) factories")
          }

          public init(name: String, attributes: [String: Any]? = nil) {
            self.name = name
            self.attributes = attributes
          }

          @JavaScriptActor
          public static func from(object: borrowing JavaScriptObject, appContext: AppContext) throws -> Self {
            let runtime = try appContext.runtime
            return try object.asValue().withUnownedValue(in: runtime) { unownedValue in
              return try decode(unownedValue, in: runtime)
            }
          }

          public static func from(dictionary: [String: Any], appContext: AppContext) throws -> Self {
            let entry0 = dictionary["name"]
            guard let entry0 else {
              throw RecordPropertyRequiredException("name")
            }
            let field0 = try String.getDynamicType().cast(entry0, appContext: appContext) as! String
            let entry1 = dictionary["attributes"]
            let field1: [String: Any]? = (entry1 == nil || entry1! is NSNull) ? nil : try [String: Any]?.getDynamicType().cast(entry1, appContext: appContext) as! [String: Any]?
            return Self(name: field0, attributes: field1)
          }

          public func toDictionary(appContext: AppContext? = nil) -> [String: Any] {
            var dictionary: [String: Any] = [:]
            dictionary["name"] = self.name
            dictionary["attributes"] = self.attributes
            return dictionary
          }

          @JavaScriptActor
          public func toObject(appContext: AppContext) throws -> JavaScriptObject {
            return try Self.encode(self, in: appContext.runtime).asObject()
          }

          @JavaScriptActor
          public static func decode(_ value: borrowing JavaScriptUnownedValue, in runtime: borrowing JavaScriptRuntime) throws -> Self {
            let object = try value.asObject(in: runtime)
            let field0 = try object.withUnownedProperty("name") { nameJSValue in
              guard !nameJSValue.isUndefined() else {
                throw RecordPropertyRequiredException("name")
              }
              return try String.decode(nameJSValue, in: runtime)
            }
            let field1 = try object.withUnownedProperty("attributes") { attributesJSValue in
              return try attributesJSValue.isUndefined() || attributesJSValue.isNull() ? nil : JavaScriptValue.decodeAnyDictionary(attributesJSValue, in: runtime)
            }
            return Self(name: field0, attributes: field1)
          }

          @JavaScriptActor
          public static func encode(_ value: Report, in runtime: borrowing JavaScriptRuntime) throws -> JavaScriptValue {
            let object = runtime.createObject()
            object.setProperty("name", value: try String.encode(value.name, in: runtime))
            object.setProperty("attributes", value: value.attributes == nil ? .null() : try JavaScriptValue.encodeAnyDictionary(value.attributes!, in: runtime))
            return object.asValue()
          }
        }

        extension Report: Record {
        }
        """
    )
  }

  @Test
  func `Array, defaulted dictionary and nested free-form properties pick the dedicated or the generic free-form methods`() {
    assertExpansion(
      """
      @Record
      struct Payload {
        var items: [Any]
        var meta: [String : Any] = [:]
        var groups: [String: [Any]]?
      }
      """,
      expandedSource: """
        struct Payload {
          var items: [Any]
          var meta: [String : Any] = [:]
          var groups: [String: [Any]]?

          private func _assertTypesConformance() {
            func groups<T: AnyArgument>(_: T.Type) {
            }
            groups([String: [Any]].self)
          }

          public init() {
            fatalError("\\(Self.self) has required properties and cannot be created with init(); construct it through the @Record-synthesized from(dictionary:) or from(object:) factories")
          }

          public init(items: [Any], meta: [String : Any], groups: [String: [Any]]? = nil) {
            self.items = items
            self.meta = meta
            self.groups = groups
          }

          @JavaScriptActor
          public static func from(object: borrowing JavaScriptObject, appContext: AppContext) throws -> Self {
            let runtime = try appContext.runtime
            return try object.asValue().withUnownedValue(in: runtime) { unownedValue in
              return try decode(unownedValue, in: runtime)
            }
          }

          public static func from(dictionary: [String: Any], appContext: AppContext) throws -> Self {
            let entry0 = dictionary["items"]
            guard let entry0 else {
              throw RecordPropertyRequiredException("items")
            }
            let field0 = try [Any].getDynamicType().cast(entry0, appContext: appContext) as! [Any]
            let entry1 = dictionary["meta"]
            let field1 = entry1 == nil ? [:] : try [String : Any].getDynamicType().cast(entry1, appContext: appContext) as! [String : Any]
            let entry2 = dictionary["groups"]
            let field2: [String: [Any]]? = (entry2 == nil || entry2! is NSNull) ? nil : try [String: [Any]]?.getDynamicType().cast(entry2, appContext: appContext) as! [String: [Any]]?
            return Self(items: field0, meta: field1, groups: field2)
          }

          public func toDictionary(appContext: AppContext? = nil) -> [String: Any] {
            var dictionary: [String: Any] = [:]
            dictionary["items"] = self.items
            dictionary["meta"] = self.meta
            dictionary["groups"] = self.groups
            return dictionary
          }

          @JavaScriptActor
          public func toObject(appContext: AppContext) throws -> JavaScriptObject {
            return try Self.encode(self, in: appContext.runtime).asObject()
          }

          @JavaScriptActor
          public static func decode(_ value: borrowing JavaScriptUnownedValue, in runtime: borrowing JavaScriptRuntime) throws -> Self {
            let object = try value.asObject(in: runtime)
            let field0 = try object.withUnownedProperty("items") { itemsJSValue in
              guard !itemsJSValue.isUndefined() else {
                throw RecordPropertyRequiredException("items")
              }
              return try JavaScriptValue.decodeAnyArray(itemsJSValue, in: runtime)
            }
            let field1 = try object.withUnownedProperty("meta") { metaJSValue in
              return metaJSValue.isUndefined() ? [:] : try JavaScriptValue.decodeAnyDictionary(metaJSValue, in: runtime)
            }
            let field2 = try object.withUnownedProperty("groups") { groupsJSValue in
              return try JavaScriptValue.decodeAny(groupsJSValue.copied(in: runtime), as: [String: [Any]]?.self, in: runtime)
            }
            return Self(items: field0, meta: field1, groups: field2)
          }

          @JavaScriptActor
          public static func encode(_ value: Payload, in runtime: borrowing JavaScriptRuntime) throws -> JavaScriptValue {
            let object = runtime.createObject()
            object.setProperty("items", value: try JavaScriptValue.encodeAnyArray(value.items, in: runtime))
            object.setProperty("meta", value: try JavaScriptValue.encodeAnyDictionary(value.meta, in: runtime))
            object.setProperty("groups", value: try JavaScriptValue.encodeAny(value.groups as Any, in: runtime))
            return object.asValue()
          }
        }

        extension Payload: Record {
        }
        """
    )
  }

  @Test
  func `Bare Any properties pass through the dictionary paths and skip the conformance assertion`() {
    assertExpansion(
      """
      @Record
      struct Payload {
        var value: Any
        var maybe: Any?
      }
      """,
      expandedSource: """
        struct Payload {
          var value: Any
          var maybe: Any?

          public init() {
            fatalError("\\(Self.self) has required properties and cannot be created with init(); construct it through the @Record-synthesized from(dictionary:) or from(object:) factories")
          }

          public init(value: Any, maybe: Any? = nil) {
            self.value = value
            self.maybe = maybe
          }

          @JavaScriptActor
          public static func from(object: borrowing JavaScriptObject, appContext: AppContext) throws -> Self {
            let runtime = try appContext.runtime
            return try object.asValue().withUnownedValue(in: runtime) { unownedValue in
              return try decode(unownedValue, in: runtime)
            }
          }

          public static func from(dictionary: [String: Any], appContext: AppContext) throws -> Self {
            let entry0 = dictionary["value"]
            guard let entry0 else {
              throw RecordPropertyRequiredException("value")
            }
            let field0 = entry0
            let entry1 = dictionary["maybe"]
            let field1: Any? = (entry1 == nil || entry1! is NSNull) ? nil : entry1
            return Self(value: field0, maybe: field1)
          }

          public func toDictionary(appContext: AppContext? = nil) -> [String: Any] {
            var dictionary: [String: Any] = [:]
            dictionary["value"] = self.value
            dictionary["maybe"] = self.maybe
            return dictionary
          }

          @JavaScriptActor
          public func toObject(appContext: AppContext) throws -> JavaScriptObject {
            return try Self.encode(self, in: appContext.runtime).asObject()
          }

          @JavaScriptActor
          public static func decode(_ value: borrowing JavaScriptUnownedValue, in runtime: borrowing JavaScriptRuntime) throws -> Self {
            let object = try value.asObject(in: runtime)
            let field0 = try object.withUnownedProperty("value") { valueJSValue in
              guard !valueJSValue.isUndefined() else {
                throw RecordPropertyRequiredException("value")
              }
              return try JavaScriptValue.decodeAny(valueJSValue, in: runtime)
            }
            let field1 = try object.withUnownedProperty("maybe") { maybeJSValue in
              return try maybeJSValue.isUndefined() || maybeJSValue.isNull() ? nil : JavaScriptValue.decodeAny(maybeJSValue, in: runtime)
            }
            return Self(value: field0, maybe: field1)
          }

          @JavaScriptActor
          public static func encode(_ value: Payload, in runtime: borrowing JavaScriptRuntime) throws -> JavaScriptValue {
            let object = runtime.createObject()
            object.setProperty("value", value: try JavaScriptValue.encodeAny(value.value, in: runtime))
            object.setProperty("maybe", value: value.maybe == nil ? .null() : try JavaScriptValue.encodeAny(value.maybe!, in: runtime))
            return object.asValue()
          }
        }

        extension Payload: Record {
        }
        """
    )
  }

  @Test(arguments: ["[Int: Any]", "Box<Any>", "[String: (Any, Int)]", "Set<[String: Any]>"])
  func `Free-form type that can't convert produces a diagnostic`(type: String) {
    assertExpansion(
      """
      @Record
      struct Payload {
        var value: \(type)
      }
      """,
      expandedSource: """
        struct Payload {
          var value: \(type)
        }

        extension Payload: Record {
        }
        """,
      diagnostics: [
        DiagnosticSpec(
          message: "@Record property 'value' can't be typed '\(type)', because a type holding Any converts to and from JavaScript only when it's built from Any, arrays, String-keyed dictionaries and optionals. Use one of those shapes, such as [String: Any], or JavaScriptValue to keep the JavaScript value unconverted",
          line: 1,
          column: 1
        )
      ]
    )
  }

  @Test
  func `Swift.Any is recognized as Any`() {
    assertExpansion(
      """
      @Record
      struct Payload {
        var value: Swift.Any
        var list: [Swift.Any]?
      }
      """,
      expandedSource: """
        struct Payload {
          var value: Swift.Any
          var list: [Swift.Any]?

          private func _assertTypesConformance() {
            func list<T: AnyArgument>(_: T.Type) {
            }
            list([Swift.Any].self)
          }

          public init() {
            fatalError("\\(Self.self) has required properties and cannot be created with init(); construct it through the @Record-synthesized from(dictionary:) or from(object:) factories")
          }

          public init(value: Swift.Any, list: [Swift.Any]? = nil) {
            self.value = value
            self.list = list
          }

          @JavaScriptActor
          public static func from(object: borrowing JavaScriptObject, appContext: AppContext) throws -> Self {
            let runtime = try appContext.runtime
            return try object.asValue().withUnownedValue(in: runtime) { unownedValue in
              return try decode(unownedValue, in: runtime)
            }
          }

          public static func from(dictionary: [String: Any], appContext: AppContext) throws -> Self {
            let entry0 = dictionary["value"]
            guard let entry0 else {
              throw RecordPropertyRequiredException("value")
            }
            let field0 = entry0
            let entry1 = dictionary["list"]
            let field1: [Swift.Any]? = (entry1 == nil || entry1! is NSNull) ? nil : try [Swift.Any]?.getDynamicType().cast(entry1, appContext: appContext) as! [Swift.Any]?
            return Self(value: field0, list: field1)
          }

          public func toDictionary(appContext: AppContext? = nil) -> [String: Any] {
            var dictionary: [String: Any] = [:]
            dictionary["value"] = self.value
            dictionary["list"] = self.list
            return dictionary
          }

          @JavaScriptActor
          public func toObject(appContext: AppContext) throws -> JavaScriptObject {
            return try Self.encode(self, in: appContext.runtime).asObject()
          }

          @JavaScriptActor
          public static func decode(_ value: borrowing JavaScriptUnownedValue, in runtime: borrowing JavaScriptRuntime) throws -> Self {
            let object = try value.asObject(in: runtime)
            let field0 = try object.withUnownedProperty("value") { valueJSValue in
              guard !valueJSValue.isUndefined() else {
                throw RecordPropertyRequiredException("value")
              }
              return try JavaScriptValue.decodeAny(valueJSValue, in: runtime)
            }
            let field1 = try object.withUnownedProperty("list") { listJSValue in
              return try listJSValue.isUndefined() || listJSValue.isNull() ? nil : JavaScriptValue.decodeAnyArray(listJSValue, in: runtime)
            }
            return Self(value: field0, list: field1)
          }

          @JavaScriptActor
          public static func encode(_ value: Payload, in runtime: borrowing JavaScriptRuntime) throws -> JavaScriptValue {
            let object = runtime.createObject()
            object.setProperty("value", value: try JavaScriptValue.encodeAny(value.value, in: runtime))
            object.setProperty("list", value: value.list == nil ? .null() : try JavaScriptValue.encodeAnyArray(value.list!, in: runtime))
            return object.asValue()
          }
        }

        extension Payload: Record {
        }
        """
    )
  }

  @Test
  func `Escaped property names read and write the bare key`() {
    assertExpansion(
      """
      @Record
      struct Options {
        var `default`: Int = 0
        var `class`: String
      }
      """,
      expandedSource: """
        struct Options {
          var `default`: Int = 0
          var `class`: String

          public init() {
            fatalError("\\(Self.self) has required properties and cannot be created with init(); construct it through the @Record-synthesized from(dictionary:) or from(object:) factories")
          }

          public init(`default`: Int, `class`: String) {
            self.`default` = `default`
            self.`class` = `class`
          }

          @JavaScriptActor
          public static func from(object: borrowing JavaScriptObject, appContext: AppContext) throws -> Self {
            let runtime = try appContext.runtime
            return try object.asValue().withUnownedValue(in: runtime) { unownedValue in
              return try decode(unownedValue, in: runtime)
            }
          }

          public static func from(dictionary: [String: Any], appContext: AppContext) throws -> Self {
            let entry0 = dictionary["default"]
            let field0 = entry0 == nil ? 0 : try Int.getDynamicType().cast(entry0, appContext: appContext) as! Int
            let entry1 = dictionary["class"]
            guard let entry1 else {
              throw RecordPropertyRequiredException("class")
            }
            let field1 = try String.getDynamicType().cast(entry1, appContext: appContext) as! String
            return Self(`default`: field0, `class`: field1)
          }

          public func toDictionary(appContext: AppContext? = nil) -> [String: Any] {
            var dictionary: [String: Any] = [:]
            dictionary["default"] = self.`default`
            dictionary["class"] = self.`class`
            return dictionary
          }

          @JavaScriptActor
          public func toObject(appContext: AppContext) throws -> JavaScriptObject {
            return try Self.encode(self, in: appContext.runtime).asObject()
          }

          @JavaScriptActor
          public static func decode(_ value: borrowing JavaScriptUnownedValue, in runtime: borrowing JavaScriptRuntime) throws -> Self {
            let object = try value.asObject(in: runtime)
            let field0 = try object.withUnownedProperty("default") { `defaultJSValue` in
              return `defaultJSValue`.isUndefined() ? 0 : try Int.decode(`defaultJSValue`, in: runtime)
            }
            let field1 = try object.withUnownedProperty("class") { `classJSValue` in
              guard !`classJSValue`.isUndefined() else {
                throw RecordPropertyRequiredException("class")
              }
              return try String.decode(`classJSValue`, in: runtime)
            }
            return Self(`default`: field0, `class`: field1)
          }

          @JavaScriptActor
          public static func encode(_ value: Options, in runtime: borrowing JavaScriptRuntime) throws -> JavaScriptValue {
            let object = runtime.createObject()
            object.setProperty("default", value: try Int.encode(value.`default`, in: runtime))
            object.setProperty("class", value: try String.encode(value.`class`, in: runtime))
            return object.asValue()
          }
        }

        extension Options: Record {
        }
        """
    )
  }

  @Test
  func `A property named object doesn't collide with the local holding the JS object`() {
    assertExpansion(
      """
      @Record
      struct Payload {
        var object: String
        var count: Int = 0
      }
      """,
      expandedSource: """
        struct Payload {
          var object: String
          var count: Int = 0

          public init() {
            fatalError("\\(Self.self) has required properties and cannot be created with init(); construct it through the @Record-synthesized from(dictionary:) or from(object:) factories")
          }

          public init(object: String, count: Int) {
            self.object = object
            self.count = count
          }

          @JavaScriptActor
          public static func from(object: borrowing JavaScriptObject, appContext: AppContext) throws -> Self {
            let runtime = try appContext.runtime
            return try object.asValue().withUnownedValue(in: runtime) { unownedValue in
              return try decode(unownedValue, in: runtime)
            }
          }

          public static func from(dictionary: [String: Any], appContext: AppContext) throws -> Self {
            let entry0 = dictionary["object"]
            guard let entry0 else {
              throw RecordPropertyRequiredException("object")
            }
            let field0 = try String.getDynamicType().cast(entry0, appContext: appContext) as! String
            let entry1 = dictionary["count"]
            let field1 = entry1 == nil ? 0 : try Int.getDynamicType().cast(entry1, appContext: appContext) as! Int
            return Self(object: field0, count: field1)
          }

          public func toDictionary(appContext: AppContext? = nil) -> [String: Any] {
            var dictionary: [String: Any] = [:]
            dictionary["object"] = self.object
            dictionary["count"] = self.count
            return dictionary
          }

          @JavaScriptActor
          public func toObject(appContext: AppContext) throws -> JavaScriptObject {
            return try Self.encode(self, in: appContext.runtime).asObject()
          }

          @JavaScriptActor
          public static func decode(_ value: borrowing JavaScriptUnownedValue, in runtime: borrowing JavaScriptRuntime) throws -> Self {
            let object = try value.asObject(in: runtime)
            let field0 = try object.withUnownedProperty("object") { objectJSValue in
              guard !objectJSValue.isUndefined() else {
                throw RecordPropertyRequiredException("object")
              }
              return try String.decode(objectJSValue, in: runtime)
            }
            let field1 = try object.withUnownedProperty("count") { countJSValue in
              return countJSValue.isUndefined() ? 0 : try Int.decode(countJSValue, in: runtime)
            }
            return Self(object: field0, count: field1)
          }

          @JavaScriptActor
          public static func encode(_ value: Payload, in runtime: borrowing JavaScriptRuntime) throws -> JavaScriptValue {
            let object = runtime.createObject()
            object.setProperty("object", value: try String.encode(value.object, in: runtime))
            object.setProperty("count", value: try Int.encode(value.count, in: runtime))
            return object.asValue()
          }
        }

        extension Payload: Record {
        }
        """
    )
  }

  @Test
  func `Properties named like the factories' parameters and temporaries don't collide with them`() {
    assertExpansion(
      """
      @Record
      struct Conflicts {
        var dictionary: String
        var appContext: String
        var runtime: String
        var name: String
        var nameValue: Int = 0
      }
      """,
      expandedSource: """
        struct Conflicts {
          var dictionary: String
          var appContext: String
          var runtime: String
          var name: String
          var nameValue: Int = 0

          public init() {
            fatalError("\\(Self.self) has required properties and cannot be created with init(); construct it through the @Record-synthesized from(dictionary:) or from(object:) factories")
          }

          public init(dictionary: String, appContext: String, runtime: String, name: String, nameValue: Int) {
            self.dictionary = dictionary
            self.appContext = appContext
            self.runtime = runtime
            self.name = name
            self.nameValue = nameValue
          }

          @JavaScriptActor
          public static func from(object: borrowing JavaScriptObject, appContext: AppContext) throws -> Self {
            let runtime = try appContext.runtime
            return try object.asValue().withUnownedValue(in: runtime) { unownedValue in
              return try decode(unownedValue, in: runtime)
            }
          }

          public static func from(dictionary: [String: Any], appContext: AppContext) throws -> Self {
            let entry0 = dictionary["dictionary"]
            guard let entry0 else {
              throw RecordPropertyRequiredException("dictionary")
            }
            let field0 = try String.getDynamicType().cast(entry0, appContext: appContext) as! String
            let entry1 = dictionary["appContext"]
            guard let entry1 else {
              throw RecordPropertyRequiredException("appContext")
            }
            let field1 = try String.getDynamicType().cast(entry1, appContext: appContext) as! String
            let entry2 = dictionary["runtime"]
            guard let entry2 else {
              throw RecordPropertyRequiredException("runtime")
            }
            let field2 = try String.getDynamicType().cast(entry2, appContext: appContext) as! String
            let entry3 = dictionary["name"]
            guard let entry3 else {
              throw RecordPropertyRequiredException("name")
            }
            let field3 = try String.getDynamicType().cast(entry3, appContext: appContext) as! String
            let entry4 = dictionary["nameValue"]
            let field4 = entry4 == nil ? 0 : try Int.getDynamicType().cast(entry4, appContext: appContext) as! Int
            return Self(dictionary: field0, appContext: field1, runtime: field2, name: field3, nameValue: field4)
          }

          public func toDictionary(appContext: AppContext? = nil) -> [String: Any] {
            var dictionary: [String: Any] = [:]
            dictionary["dictionary"] = self.dictionary
            dictionary["appContext"] = self.appContext
            dictionary["runtime"] = self.runtime
            dictionary["name"] = self.name
            dictionary["nameValue"] = self.nameValue
            return dictionary
          }

          @JavaScriptActor
          public func toObject(appContext: AppContext) throws -> JavaScriptObject {
            return try Self.encode(self, in: appContext.runtime).asObject()
          }

          @JavaScriptActor
          public static func decode(_ value: borrowing JavaScriptUnownedValue, in runtime: borrowing JavaScriptRuntime) throws -> Self {
            let object = try value.asObject(in: runtime)
            let field0 = try object.withUnownedProperty("dictionary") { dictionaryJSValue in
              guard !dictionaryJSValue.isUndefined() else {
                throw RecordPropertyRequiredException("dictionary")
              }
              return try String.decode(dictionaryJSValue, in: runtime)
            }
            let field1 = try object.withUnownedProperty("appContext") { appContextJSValue in
              guard !appContextJSValue.isUndefined() else {
                throw RecordPropertyRequiredException("appContext")
              }
              return try String.decode(appContextJSValue, in: runtime)
            }
            let field2 = try object.withUnownedProperty("runtime") { runtimeJSValue in
              guard !runtimeJSValue.isUndefined() else {
                throw RecordPropertyRequiredException("runtime")
              }
              return try String.decode(runtimeJSValue, in: runtime)
            }
            let field3 = try object.withUnownedProperty("name") { nameJSValue in
              guard !nameJSValue.isUndefined() else {
                throw RecordPropertyRequiredException("name")
              }
              return try String.decode(nameJSValue, in: runtime)
            }
            let field4 = try object.withUnownedProperty("nameValue") { nameValueJSValue in
              return nameValueJSValue.isUndefined() ? 0 : try Int.decode(nameValueJSValue, in: runtime)
            }
            return Self(dictionary: field0, appContext: field1, runtime: field2, name: field3, nameValue: field4)
          }

          @JavaScriptActor
          public static func encode(_ value: Conflicts, in runtime: borrowing JavaScriptRuntime) throws -> JavaScriptValue {
            let object = runtime.createObject()
            object.setProperty("dictionary", value: try String.encode(value.dictionary, in: runtime))
            object.setProperty("appContext", value: try String.encode(value.appContext, in: runtime))
            object.setProperty("runtime", value: try String.encode(value.runtime, in: runtime))
            object.setProperty("name", value: try String.encode(value.name, in: runtime))
            object.setProperty("nameValue", value: try Int.encode(value.nameValue, in: runtime))
            return object.asValue()
          }
        }

        extension Conflicts: Record {
        }
        """
    )
  }

  @Test
  func `A closure property produces a diagnostic on the closure type`() {
    assertExpansion(
      """
      @Record
      struct Options {
        var name: String
        var onTap: (Int) -> Void
      }
      """,
      expandedSource: """
        struct Options {
          var name: String
          var onTap: (Int) -> Void
        }

        extension Options: Record {
        }
        """,
      diagnostics: [
        DiagnosticSpec(
          message:
            "@Record property 'onTap' can't hold a closure: a record property is also encoded to JavaScript, and a native closure can't be encoded",
          line: 4,
          column: 14
        )
      ]
    )
  }

  @Test
  func `A closure nested in a property type produces a diagnostic on the closure type`() {
    assertExpansion(
      """
      @Record
      struct Options {
        var handlers: [String: ((Any) -> Void)?] = [:]
      }
      """,
      expandedSource: """
        struct Options {
          var handlers: [String: ((Any) -> Void)?] = [:]
        }

        extension Options: Record {
        }
        """,
      diagnostics: [
        DiagnosticSpec(
          message:
            "@Record property 'handlers' can't hold a closure: a record property is also encoded to JavaScript, and a native closure can't be encoded",
          line: 3,
          column: 27
        )
      ]
    )
  }
}
