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
    macroSpecs: recordMacroSpecs,
    fixedSource: fixedSource,
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

          private final class _PropNames {
            static let _key = JavaScriptRuntime.Cache.Key<_PropNames>()

            let _name0: JavaScriptPropNameID
            let _name1: JavaScriptPropNameID
            let _name2: JavaScriptPropNameID

            init(_ runtime: borrowing JavaScriptRuntime) {
              self._name0 = JavaScriptPropNameID(runtime, string: "name")
              self._name1 = JavaScriptPropNameID(runtime, string: "count")
              self._name2 = JavaScriptPropNameID(runtime, string: "note")
            }
          }

          @JavaScriptActor
          public static func decode(_ value: borrowing JavaScriptUnownedValue, in runtime: borrowing JavaScriptRuntime) throws -> Self {
            let object = try value.asObject(in: runtime)
            let _propNames = runtime.cached(_PropNames._key) {
              return _PropNames(runtime)
            }
            let field0 = try object.withUnownedProperty(_propNames._name0) { nameJSValue in
              guard !nameJSValue.isUndefined() else {
                throw RecordPropertyRequiredException("name")
              }
              return try String.decode(nameJSValue, in: runtime)
            }
            let field1 = try object.withUnownedProperty(_propNames._name1) { countJSValue in
              return countJSValue.isUndefined() ? 0 : try Int.decode(countJSValue, in: runtime)
            }
            let field2 = try object.withUnownedProperty(_propNames._name2) { noteJSValue in
              return try String?.decode(noteJSValue, in: runtime)
            }
            return Self(name: field0, count: field1, note: field2)
          }

          @JavaScriptActor
          public static func encode(_ value: Options, in runtime: borrowing JavaScriptRuntime) throws -> JavaScriptValue {
            let object = runtime.createObject()
            let _propNames = runtime.cached(_PropNames._key) {
              return _PropNames(runtime)
            }
            try object.setProperty(_propNames._name0, encoding: value.name, in: runtime)
            try object.setProperty(_propNames._name1, encoding: value.count, in: runtime)
            try object.setProperty(_propNames._name2, encoding: value.note, in: runtime)
            return object.takeValue()
          }

          @JavaScriptActor
          public static func encode(
            _ value: Options,
            into slot: borrowing JavaScriptValue.Slot,
            in runtime: borrowing JavaScriptRuntime
          ) throws {
            let object = runtime.createObject()
            let _propNames = runtime.cached(_PropNames._key) {
              return _PropNames(runtime)
            }
            try object.setProperty(_propNames._name0, encoding: value.name, in: runtime)
            try object.setProperty(_propNames._name1, encoding: value.count, in: runtime)
            try object.setProperty(_propNames._name2, encoding: value.note, in: runtime)
            slot.emplace(object)
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
            func owner(_: (some JavaScriptDecodable & JavaScriptEncodable).Type) {
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

          private final class _PropNames {
            static let _key = JavaScriptRuntime.Cache.Key<_PropNames>()

            let _name0: JavaScriptPropNameID

            init(_ runtime: borrowing JavaScriptRuntime) {
              self._name0 = JavaScriptPropNameID(runtime, string: "owner")
            }
          }

          @JavaScriptActor
          public static func decode(_ value: borrowing JavaScriptUnownedValue, in runtime: borrowing JavaScriptRuntime) throws -> Self {
            let object = try value.asObject(in: runtime)
            let _propNames = runtime.cached(_PropNames._key) {
              return _PropNames(runtime)
            }
            let field0 = try object.withUnownedProperty(_propNames._name0) { ownerJSValue in
              return try MyRecord?.decode(ownerJSValue, in: runtime)
            }
            return Self(owner: field0)
          }

          @JavaScriptActor
          public static func encode(_ value: Options, in runtime: borrowing JavaScriptRuntime) throws -> JavaScriptValue {
            let object = runtime.createObject()
            let _propNames = runtime.cached(_PropNames._key) {
              return _PropNames(runtime)
            }
            try object.setProperty(_propNames._name0, encoding: value.owner, in: runtime)
            return object.takeValue()
          }

          @JavaScriptActor
          public static func encode(
            _ value: Options,
            into slot: borrowing JavaScriptValue.Slot,
            in runtime: borrowing JavaScriptRuntime
          ) throws {
            let object = runtime.createObject()
            let _propNames = runtime.cached(_PropNames._key) {
              return _PropNames(runtime)
            }
            try object.setProperty(_propNames._name0, encoding: value.owner, in: runtime)
            slot.emplace(object)
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
        var tags: [Tag]
        var count: Int = 0
      }
      """,
      expandedSource: """
        struct Options {
          var primary: MyRecord
          var tags: [Tag]
          var count: Int = 0

          private func _assertTypesConformance() {
            func primary(_: (some JavaScriptDecodable & JavaScriptEncodable).Type) {
            }
            primary(MyRecord.self)
            func tags(_: (some JavaScriptDecodable & JavaScriptEncodable).Type) {
            }
            tags([Tag].self)
          }

          public init() {
            fatalError("\\(Self.self) has required properties and cannot be created with init(); construct it through the @Record-synthesized from(dictionary:) or from(object:) factories")
          }

          public init(primary: MyRecord, tags: [Tag], count: Int) {
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
            let field1 = try [Tag].getDynamicType().cast(entry1, appContext: appContext) as! [Tag]
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

          private final class _PropNames {
            static let _key = JavaScriptRuntime.Cache.Key<_PropNames>()

            let _name0: JavaScriptPropNameID
            let _name1: JavaScriptPropNameID
            let _name2: JavaScriptPropNameID

            init(_ runtime: borrowing JavaScriptRuntime) {
              self._name0 = JavaScriptPropNameID(runtime, string: "primary")
              self._name1 = JavaScriptPropNameID(runtime, string: "tags")
              self._name2 = JavaScriptPropNameID(runtime, string: "count")
            }
          }

          @JavaScriptActor
          public static func decode(_ value: borrowing JavaScriptUnownedValue, in runtime: borrowing JavaScriptRuntime) throws -> Self {
            let object = try value.asObject(in: runtime)
            let _propNames = runtime.cached(_PropNames._key) {
              return _PropNames(runtime)
            }
            let field0 = try object.withUnownedProperty(_propNames._name0) { primaryJSValue in
              guard !primaryJSValue.isUndefined() else {
                throw RecordPropertyRequiredException("primary")
              }
              return try MyRecord.decode(primaryJSValue, in: runtime)
            }
            let field1 = try object.withUnownedProperty(_propNames._name1) { tagsJSValue in
              guard !tagsJSValue.isUndefined() else {
                throw RecordPropertyRequiredException("tags")
              }
              return try [Tag].decode(tagsJSValue, in: runtime)
            }
            let field2 = try object.withUnownedProperty(_propNames._name2) { countJSValue in
              return countJSValue.isUndefined() ? 0 : try Int.decode(countJSValue, in: runtime)
            }
            return Self(primary: field0, tags: field1, count: field2)
          }

          @JavaScriptActor
          public static func encode(_ value: Options, in runtime: borrowing JavaScriptRuntime) throws -> JavaScriptValue {
            let object = runtime.createObject()
            let _propNames = runtime.cached(_PropNames._key) {
              return _PropNames(runtime)
            }
            try object.setProperty(_propNames._name0, encoding: value.primary, in: runtime)
            try object.setProperty(_propNames._name1, encoding: value.tags, in: runtime)
            try object.setProperty(_propNames._name2, encoding: value.count, in: runtime)
            return object.takeValue()
          }

          @JavaScriptActor
          public static func encode(
            _ value: Options,
            into slot: borrowing JavaScriptValue.Slot,
            in runtime: borrowing JavaScriptRuntime
          ) throws {
            let object = runtime.createObject()
            let _propNames = runtime.cached(_PropNames._key) {
              return _PropNames(runtime)
            }
            try object.setProperty(_propNames._name0, encoding: value.primary, in: runtime)
            try object.setProperty(_propNames._name1, encoding: value.tags, in: runtime)
            try object.setProperty(_propNames._name2, encoding: value.count, in: runtime)
            slot.emplace(object)
          }
        }

        extension Options: Record {
        }
        """
    )
  }

  @Test
  func `Containers of primitives skip the conformance assertion`() {
    assertExpansion(
      """
      @Record
      struct Layout {
        var grid: [[Int]]
        var labels: [String: String]
        var tags: Set<String>
      }
      """,
      expandedSource: """
        struct Layout {
          var grid: [[Int]]
          var labels: [String: String]
          var tags: Set<String>

          public init() {
            fatalError("\\(Self.self) has required properties and cannot be created with init(); construct it through the @Record-synthesized from(dictionary:) or from(object:) factories")
          }

          public init(grid: [[Int]], labels: [String: String], tags: Set<String>) {
            self.grid = grid
            self.labels = labels
            self.tags = tags
          }

          @JavaScriptActor
          public static func from(object: borrowing JavaScriptObject, appContext: AppContext) throws -> Self {
            let runtime = try appContext.runtime
            return try object.asValue().withUnownedValue(in: runtime) { unownedValue in
              return try decode(unownedValue, in: runtime)
            }
          }

          public static func from(dictionary: [String: Any], appContext: AppContext) throws -> Self {
            let entry0 = dictionary["grid"]
            guard let entry0 else {
              throw RecordPropertyRequiredException("grid")
            }
            let field0 = try [[Int]].getDynamicType().cast(entry0, appContext: appContext) as! [[Int]]
            let entry1 = dictionary["labels"]
            guard let entry1 else {
              throw RecordPropertyRequiredException("labels")
            }
            let field1 = try [String: String].getDynamicType().cast(entry1, appContext: appContext) as! [String: String]
            let entry2 = dictionary["tags"]
            guard let entry2 else {
              throw RecordPropertyRequiredException("tags")
            }
            let field2 = try Set<String>.getDynamicType().cast(entry2, appContext: appContext) as! Set<String>
            return Self(grid: field0, labels: field1, tags: field2)
          }

          public func toDictionary(appContext: AppContext? = nil) -> [String: Any] {
            var dictionary: [String: Any] = [:]
            dictionary["grid"] = self.grid
            dictionary["labels"] = self.labels
            dictionary["tags"] = self.tags
            return dictionary
          }

          @JavaScriptActor
          public func toObject(appContext: AppContext) throws -> JavaScriptObject {
            return try Self.encode(self, in: appContext.runtime).asObject()
          }

          private final class _PropNames {
            static let _key = JavaScriptRuntime.Cache.Key<_PropNames>()

            let _name0: JavaScriptPropNameID
            let _name1: JavaScriptPropNameID
            let _name2: JavaScriptPropNameID

            init(_ runtime: borrowing JavaScriptRuntime) {
              self._name0 = JavaScriptPropNameID(runtime, string: "grid")
              self._name1 = JavaScriptPropNameID(runtime, string: "labels")
              self._name2 = JavaScriptPropNameID(runtime, string: "tags")
            }
          }

          @JavaScriptActor
          public static func decode(_ value: borrowing JavaScriptUnownedValue, in runtime: borrowing JavaScriptRuntime) throws -> Self {
            let object = try value.asObject(in: runtime)
            let _propNames = runtime.cached(_PropNames._key) {
              return _PropNames(runtime)
            }
            let field0 = try object.withUnownedProperty(_propNames._name0) { gridJSValue in
              guard !gridJSValue.isUndefined() else {
                throw RecordPropertyRequiredException("grid")
              }
              return try [[Int]].decode(gridJSValue, in: runtime)
            }
            let field1 = try object.withUnownedProperty(_propNames._name1) { labelsJSValue in
              guard !labelsJSValue.isUndefined() else {
                throw RecordPropertyRequiredException("labels")
              }
              return try [String: String].decode(labelsJSValue, in: runtime)
            }
            let field2 = try object.withUnownedProperty(_propNames._name2) { tagsJSValue in
              guard !tagsJSValue.isUndefined() else {
                throw RecordPropertyRequiredException("tags")
              }
              return try Set<String>.decode(tagsJSValue, in: runtime)
            }
            return Self(grid: field0, labels: field1, tags: field2)
          }

          @JavaScriptActor
          public static func encode(_ value: Layout, in runtime: borrowing JavaScriptRuntime) throws -> JavaScriptValue {
            let object = runtime.createObject()
            let _propNames = runtime.cached(_PropNames._key) {
              return _PropNames(runtime)
            }
            try object.setProperty(_propNames._name0, encoding: value.grid, in: runtime)
            try object.setProperty(_propNames._name1, encoding: value.labels, in: runtime)
            try object.setProperty(_propNames._name2, encoding: value.tags, in: runtime)
            return object.takeValue()
          }

          @JavaScriptActor
          public static func encode(
            _ value: Layout,
            into slot: borrowing JavaScriptValue.Slot,
            in runtime: borrowing JavaScriptRuntime
          ) throws {
            let object = runtime.createObject()
            let _propNames = runtime.cached(_PropNames._key) {
              return _PropNames(runtime)
            }
            try object.setProperty(_propNames._name0, encoding: value.grid, in: runtime)
            try object.setProperty(_propNames._name1, encoding: value.labels, in: runtime)
            try object.setProperty(_propNames._name2, encoding: value.tags, in: runtime)
            slot.emplace(object)
          }
        }

        extension Layout: Record {
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

          private final class _PropNames {
            static let _key = JavaScriptRuntime.Cache.Key<_PropNames>()

            let _name0: JavaScriptPropNameID
            let _name1: JavaScriptPropNameID
            let _name2: JavaScriptPropNameID
            let _name3: JavaScriptPropNameID

            init(_ runtime: borrowing JavaScriptRuntime) {
              self._name0 = JavaScriptPropNameID(runtime, string: "name")
              self._name1 = JavaScriptPropNameID(runtime, string: "ratio")
              self._name2 = JavaScriptPropNameID(runtime, string: "count")
              self._name3 = JavaScriptPropNameID(runtime, string: "flag")
            }
          }

          @JavaScriptActor
          public static func decode(_ value: borrowing JavaScriptUnownedValue, in runtime: borrowing JavaScriptRuntime) throws -> Self {
            let object = try value.asObject(in: runtime)
            let _propNames = runtime.cached(_PropNames._key) {
              return _PropNames(runtime)
            }
            let field0 = try object.withUnownedProperty(_propNames._name0) { nameJSValue in
              return nameJSValue.isUndefined() ? "foo" : try String.decode(nameJSValue, in: runtime)
            }
            let field1 = try object.withUnownedProperty(_propNames._name1) { ratioJSValue in
              return ratioJSValue.isUndefined() ? 1.0 : try Double.decode(ratioJSValue, in: runtime)
            }
            let field2 = try object.withUnownedProperty(_propNames._name2) { countJSValue in
              return countJSValue.isUndefined() ? 0 : try Int.decode(countJSValue, in: runtime)
            }
            let field3 = try object.withUnownedProperty(_propNames._name3) { flagJSValue in
              return flagJSValue.isUndefined() ? false : try Bool.decode(flagJSValue, in: runtime)
            }
            return Self(name: field0, ratio: field1, count: field2, flag: field3)
          }

          @JavaScriptActor
          public static func encode(_ value: Options, in runtime: borrowing JavaScriptRuntime) throws -> JavaScriptValue {
            let object = runtime.createObject()
            let _propNames = runtime.cached(_PropNames._key) {
              return _PropNames(runtime)
            }
            try object.setProperty(_propNames._name0, encoding: value.name, in: runtime)
            try object.setProperty(_propNames._name1, encoding: value.ratio, in: runtime)
            try object.setProperty(_propNames._name2, encoding: value.count, in: runtime)
            try object.setProperty(_propNames._name3, encoding: value.flag, in: runtime)
            return object.takeValue()
          }

          @JavaScriptActor
          public static func encode(
            _ value: Options,
            into slot: borrowing JavaScriptValue.Slot,
            in runtime: borrowing JavaScriptRuntime
          ) throws {
            let object = runtime.createObject()
            let _propNames = runtime.cached(_PropNames._key) {
              return _PropNames(runtime)
            }
            try object.setProperty(_propNames._name0, encoding: value.name, in: runtime)
            try object.setProperty(_propNames._name1, encoding: value.ratio, in: runtime)
            try object.setProperty(_propNames._name2, encoding: value.count, in: runtime)
            try object.setProperty(_propNames._name3, encoding: value.flag, in: runtime)
            slot.emplace(object)
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

          private final class _PropNames {
            static let _key = JavaScriptRuntime.Cache.Key<_PropNames>()

            let _name0: JavaScriptPropNameID

            init(_ runtime: borrowing JavaScriptRuntime) {
              self._name0 = JavaScriptPropNameID(runtime, string: "name")
            }
          }

          @JavaScriptActor
          public static func decode(_ value: borrowing JavaScriptUnownedValue, in runtime: borrowing JavaScriptRuntime) throws -> Self {
            let object = try value.asObject(in: runtime)
            let _propNames = runtime.cached(_PropNames._key) {
              return _PropNames(runtime)
            }
            let field0 = try object.withUnownedProperty(_propNames._name0) { nameJSValue in
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
            let _propNames = runtime.cached(_PropNames._key) {
              return _PropNames(runtime)
            }
            try object.setProperty(_propNames._name0, encoding: value.name, in: runtime)
            return object.takeValue()
          }

          @JavaScriptActor
          public static func encode(
            _ value: Options,
            into slot: borrowing JavaScriptValue.Slot,
            in runtime: borrowing JavaScriptRuntime
          ) throws {
            let object = runtime.createObject()
            let _propNames = runtime.cached(_PropNames._key) {
              return _PropNames(runtime)
            }
            try object.setProperty(_propNames._name0, encoding: value.name, in: runtime)
            slot.emplace(object)
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
            return object.takeValue()
          }

          @JavaScriptActor
          public static func encode(
            _ value: Empty,
            into slot: borrowing JavaScriptValue.Slot,
            in runtime: borrowing JavaScriptRuntime
          ) throws {
            let object = runtime.createObject()
            slot.emplace(object)
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

          private final class _PropNames {
            static let _key = JavaScriptRuntime.Cache.Key<_PropNames>()

            let _name0: JavaScriptPropNameID
            let _name1: JavaScriptPropNameID

            init(_ runtime: borrowing JavaScriptRuntime) {
              self._name0 = JavaScriptPropNameID(runtime, string: "x")
              self._name1 = JavaScriptPropNameID(runtime, string: "y")
            }
          }

          @JavaScriptActor
          public static func decode(_ value: borrowing JavaScriptUnownedValue, in runtime: borrowing JavaScriptRuntime) throws -> Self {
            let object = try value.asObject(in: runtime)
            let _propNames = runtime.cached(_PropNames._key) {
              return _PropNames(runtime)
            }
            let field0 = try object.withUnownedProperty(_propNames._name0) { xJSValue in
              return xJSValue.isUndefined() ? 0 : try Double.decode(xJSValue, in: runtime)
            }
            let field1 = try object.withUnownedProperty(_propNames._name1) { yJSValue in
              return yJSValue.isUndefined() ? 0 : try Double.decode(yJSValue, in: runtime)
            }
            return Self(x: field0, y: field1)
          }

          @JavaScriptActor
          public static func encode(_ value: Point, in runtime: borrowing JavaScriptRuntime) throws -> JavaScriptValue {
            let object = runtime.createObject()
            let _propNames = runtime.cached(_PropNames._key) {
              return _PropNames(runtime)
            }
            try object.setProperty(_propNames._name0, encoding: value.x, in: runtime)
            try object.setProperty(_propNames._name1, encoding: value.y, in: runtime)
            return object.takeValue()
          }

          @JavaScriptActor
          public static func encode(
            _ value: Point,
            into slot: borrowing JavaScriptValue.Slot,
            in runtime: borrowing JavaScriptRuntime
          ) throws {
            let object = runtime.createObject()
            let _propNames = runtime.cached(_PropNames._key) {
              return _PropNames(runtime)
            }
            try object.setProperty(_propNames._name0, encoding: value.x, in: runtime)
            try object.setProperty(_propNames._name1, encoding: value.y, in: runtime)
            slot.emplace(object)
          }
        }

        extension Point: Record {
        }
        """
    )
  }

  @Test
  func `A class with a superclass produces a diagnostic`() {
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
        }
        """,
      diagnostics: [
        DiagnosticSpec(
          message:
            "@Record class 'Child' can't have an inheritance clause: a record class can't have a superclass, and the macro can't tell a superclass from a protocol. Declare protocol conformances in an extension",
          line: 2,
          column: 18
        )
      ]
    )
  }

  @Test
  func `A class whose inheritance clause lists only protocols produces a diagnostic`() {
    assertExpansion(
      """
      @Record
      final class Options: CustomStringConvertible {
        var name: String = ""
        var description: String { name }
      }
      """,
      expandedSource: """
        final class Options: CustomStringConvertible {
          var name: String = ""
          var description: String { name }
        }
        """,
      diagnostics: [
        DiagnosticSpec(
          message:
            "@Record class 'Options' can't have an inheritance clause: a record class can't have a superclass, and the macro can't tell a superclass from a protocol. Declare protocol conformances in an extension",
          line: 2,
          column: 20
        )
      ]
    )
  }

  @Test
  func `A class that isn't final produces a diagnostic with a fix-it`() {
    assertExpansion(
      """
      @Record
      class Options {
        var count: Int = 0
      }
      """,
      expandedSource: """
        class Options {
          var count: Int = 0
        }
        """,
      diagnostics: [
        DiagnosticSpec(
          message: "@Record class 'Options' must be final, because the macro doesn't support subclasses of a record",
          line: 2,
          column: 1,
          fixIts: [FixItSpec(message: "Mark the class 'final'")]
        )
      ],
      fixedSource: """
        @Record
        final class Options {
          var count: Int = 0
        }
        """
    )
  }

  @Test
  func `The final fix-it goes after the other modifiers`() {
    assertExpansion(
      """
      @Record
      public class Options {
        public var count: Int = 0
      }
      """,
      expandedSource: """
        public class Options {
          public var count: Int = 0
        }
        """,
      diagnostics: [
        DiagnosticSpec(
          message: "@Record class 'Options' must be final, because the macro doesn't support subclasses of a record",
          line: 2,
          column: 8,
          fixIts: [FixItSpec(message: "Mark the class 'final'")]
        )
      ],
      fixedSource: """
        @Record
        public final class Options {
          public var count: Int = 0
        }
        """
    )
  }

  @Test
  func `An open class produces a diagnostic without a fix-it`() {
    assertExpansion(
      """
      @Record
      open class Options {
        public var count: Int = 0
      }
      """,
      expandedSource: """
        open class Options {
          public var count: Int = 0
        }
        """,
      diagnostics: [
        DiagnosticSpec(
          message: "@Record class 'Options' must be final, because the macro doesn't support subclasses of a record",
          line: 2,
          column: 6
        )
      ]
    )
  }

  @Test
  func `Final class gets init() and the Record conformance`() {
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

          private final class _PropNames {
            static let _key = JavaScriptRuntime.Cache.Key<_PropNames>()

            let _name0: JavaScriptPropNameID

            init(_ runtime: borrowing JavaScriptRuntime) {
              self._name0 = JavaScriptPropNameID(runtime, string: "name")
            }
          }

          @JavaScriptActor
          public static func decode(_ value: borrowing JavaScriptUnownedValue, in runtime: borrowing JavaScriptRuntime) throws -> Self {
            let object = try value.asObject(in: runtime)
            let _propNames = runtime.cached(_PropNames._key) {
              return _PropNames(runtime)
            }
            let field0 = try object.withUnownedProperty(_propNames._name0) { nameJSValue in
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
            let _propNames = runtime.cached(_PropNames._key) {
              return _PropNames(runtime)
            }
            try object.setProperty(_propNames._name0, encoding: value.name, in: runtime)
            return object.takeValue()
          }

          @JavaScriptActor
          public static func encode(
            _ value: Options,
            into slot: borrowing JavaScriptValue.Slot,
            in runtime: borrowing JavaScriptRuntime
          ) throws {
            let object = runtime.createObject()
            let _propNames = runtime.cached(_PropNames._key) {
              return _PropNames(runtime)
            }
            try object.setProperty(_propNames._name0, encoding: value.name, in: runtime)
            slot.emplace(object)
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

          private final class _PropNames {
            static let _key = JavaScriptRuntime.Cache.Key<_PropNames>()

            let _name0: JavaScriptPropNameID

            init(_ runtime: borrowing JavaScriptRuntime) {
              self._name0 = JavaScriptPropNameID(runtime, string: "name")
            }
          }

          @JavaScriptActor
          public static func decode(_ value: borrowing JavaScriptUnownedValue, in runtime: borrowing JavaScriptRuntime) throws -> Self {
            let object = try value.asObject(in: runtime)
            let _propNames = runtime.cached(_PropNames._key) {
              return _PropNames(runtime)
            }
            let field0 = try object.withUnownedProperty(_propNames._name0) { nameJSValue in
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
            let _propNames = runtime.cached(_PropNames._key) {
              return _PropNames(runtime)
            }
            try object.setProperty(_propNames._name0, encoding: value.name, in: runtime)
            return object.takeValue()
          }

          @JavaScriptActor
          public static func encode(
            _ value: Options,
            into slot: borrowing JavaScriptValue.Slot,
            in runtime: borrowing JavaScriptRuntime
          ) throws {
            let object = runtime.createObject()
            let _propNames = runtime.cached(_PropNames._key) {
              return _PropNames(runtime)
            }
            try object.setProperty(_propNames._name0, encoding: value.name, in: runtime)
            slot.emplace(object)
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
          message:
            "@Field is no longer used — @Record treats every stored property as a record property. Remove the @Field attribute",
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

          private final class _PropNames {
            static let _key = JavaScriptRuntime.Cache.Key<_PropNames>()

            let _name0: JavaScriptPropNameID
            let _name1: JavaScriptPropNameID

            init(_ runtime: borrowing JavaScriptRuntime) {
              self._name0 = JavaScriptPropNameID(runtime, string: "x")
              self._name1 = JavaScriptPropNameID(runtime, string: "y")
            }
          }

          @JavaScriptActor
          public static func decode(_ value: borrowing JavaScriptUnownedValue, in runtime: borrowing JavaScriptRuntime) throws -> Self {
            let object = try value.asObject(in: runtime)
            let _propNames = runtime.cached(_PropNames._key) {
              return _PropNames(runtime)
            }
            let field0 = try object.withUnownedProperty(_propNames._name0) { xJSValue in
              return xJSValue.isUndefined() ? 0 : try Double.decode(xJSValue, in: runtime)
            }
            let field1 = try object.withUnownedProperty(_propNames._name1) { yJSValue in
              return yJSValue.isUndefined() ? 0 : try Double.decode(yJSValue, in: runtime)
            }
            return Self(x: field0, y: field1)
          }

          @JavaScriptActor
          public static func encode(_ value: Options, in runtime: borrowing JavaScriptRuntime) throws -> JavaScriptValue {
            let object = runtime.createObject()
            let _propNames = runtime.cached(_PropNames._key) {
              return _PropNames(runtime)
            }
            try object.setProperty(_propNames._name0, encoding: value.x, in: runtime)
            try object.setProperty(_propNames._name1, encoding: value.y, in: runtime)
            return object.takeValue()
          }

          @JavaScriptActor
          public static func encode(
            _ value: Options,
            into slot: borrowing JavaScriptValue.Slot,
            in runtime: borrowing JavaScriptRuntime
          ) throws {
            let object = runtime.createObject()
            let _propNames = runtime.cached(_PropNames._key) {
              return _PropNames(runtime)
            }
            try object.setProperty(_propNames._name0, encoding: value.x, in: runtime)
            try object.setProperty(_propNames._name1, encoding: value.y, in: runtime)
            slot.emplace(object)
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

          private final class _PropNames {
            static let _key = JavaScriptRuntime.Cache.Key<_PropNames>()

            let _name0: JavaScriptPropNameID
            let _name1: JavaScriptPropNameID

            init(_ runtime: borrowing JavaScriptRuntime) {
              self._name0 = JavaScriptPropNameID(runtime, string: "x")
              self._name1 = JavaScriptPropNameID(runtime, string: "y")
            }
          }

          @JavaScriptActor
          public static func decode(_ value: borrowing JavaScriptUnownedValue, in runtime: borrowing JavaScriptRuntime) throws -> Self {
            let object = try value.asObject(in: runtime)
            let _propNames = runtime.cached(_PropNames._key) {
              return _PropNames(runtime)
            }
            let field0 = try object.withUnownedProperty(_propNames._name0) { xJSValue in
              return xJSValue.isUndefined() ? 0 : try Double.decode(xJSValue, in: runtime)
            }
            let field1 = try object.withUnownedProperty(_propNames._name1) { yJSValue in
              return yJSValue.isUndefined() ? 0 : try Double.decode(yJSValue, in: runtime)
            }
            return Self(x: field0, y: field1)
          }

          @JavaScriptActor
          public static func encode(_ value: Options, in runtime: borrowing JavaScriptRuntime) throws -> JavaScriptValue {
            let object = runtime.createObject()
            let _propNames = runtime.cached(_PropNames._key) {
              return _PropNames(runtime)
            }
            try object.setProperty(_propNames._name0, encoding: value.x, in: runtime)
            try object.setProperty(_propNames._name1, encoding: value.y, in: runtime)
            return object.takeValue()
          }

          @JavaScriptActor
          public static func encode(
            _ value: Options,
            into slot: borrowing JavaScriptValue.Slot,
            in runtime: borrowing JavaScriptRuntime
          ) throws {
            let object = runtime.createObject()
            let _propNames = runtime.cached(_PropNames._key) {
              return _PropNames(runtime)
            }
            try object.setProperty(_propNames._name0, encoding: value.x, in: runtime)
            try object.setProperty(_propNames._name1, encoding: value.y, in: runtime)
            slot.emplace(object)
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

          private final class _PropNames {
            static let _key = JavaScriptRuntime.Cache.Key<_PropNames>()

            let _name0: JavaScriptPropNameID

            init(_ runtime: borrowing JavaScriptRuntime) {
              self._name0 = JavaScriptPropNameID(runtime, string: "default")
            }
          }

          @JavaScriptActor
          public static func decode(_ value: borrowing JavaScriptUnownedValue, in runtime: borrowing JavaScriptRuntime) throws -> Self {
            let object = try value.asObject(in: runtime)
            let _propNames = runtime.cached(_PropNames._key) {
              return _PropNames(runtime)
            }
            let field0 = try object.withUnownedProperty(_propNames._name0) { `defaultJSValue` in
              return `defaultJSValue`.isUndefined() ? 0 : try Int.decode(`defaultJSValue`, in: runtime)
            }
            return Self(`default`: field0)
          }

          @JavaScriptActor
          public static func encode(_ value: Options, in runtime: borrowing JavaScriptRuntime) throws -> JavaScriptValue {
            let object = runtime.createObject()
            let _propNames = runtime.cached(_PropNames._key) {
              return _PropNames(runtime)
            }
            try object.setProperty(_propNames._name0, encoding: value.`default`, in: runtime)
            return object.takeValue()
          }

          @JavaScriptActor
          public static func encode(
            _ value: Options,
            into slot: borrowing JavaScriptValue.Slot,
            in runtime: borrowing JavaScriptRuntime
          ) throws {
            let object = runtime.createObject()
            let _propNames = runtime.cached(_PropNames._key) {
              return _PropNames(runtime)
            }
            try object.setProperty(_propNames._name0, encoding: value.`default`, in: runtime)
            slot.emplace(object)
          }
        }

        extension Options: Record {
        }
        """
    )
  }

  @Test
  func
    `Optional free-form dictionary property converts through the dedicated free-form methods on the JS-object paths`()
  {
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

          private final class _PropNames {
            static let _key = JavaScriptRuntime.Cache.Key<_PropNames>()

            let _name0: JavaScriptPropNameID
            let _name1: JavaScriptPropNameID

            init(_ runtime: borrowing JavaScriptRuntime) {
              self._name0 = JavaScriptPropNameID(runtime, string: "name")
              self._name1 = JavaScriptPropNameID(runtime, string: "attributes")
            }
          }

          @JavaScriptActor
          public static func decode(_ value: borrowing JavaScriptUnownedValue, in runtime: borrowing JavaScriptRuntime) throws -> Self {
            let object = try value.asObject(in: runtime)
            let _propNames = runtime.cached(_PropNames._key) {
              return _PropNames(runtime)
            }
            let field0 = try object.withUnownedProperty(_propNames._name0) { nameJSValue in
              guard !nameJSValue.isUndefined() else {
                throw RecordPropertyRequiredException("name")
              }
              return try String.decode(nameJSValue, in: runtime)
            }
            let field1 = try object.withUnownedProperty(_propNames._name1) { attributesJSValue in
              return try attributesJSValue.isUndefined() || attributesJSValue.isNull() ? nil : JavaScriptValue.decodeAnyDictionary(attributesJSValue, in: runtime)
            }
            return Self(name: field0, attributes: field1)
          }

          @JavaScriptActor
          public static func encode(_ value: Report, in runtime: borrowing JavaScriptRuntime) throws -> JavaScriptValue {
            let object = runtime.createObject()
            let _propNames = runtime.cached(_PropNames._key) {
              return _PropNames(runtime)
            }
            try object.setProperty(_propNames._name0, encoding: value.name, in: runtime)
            object.setProperty(_propNames._name1, value: value.attributes == nil ? .null() : try JavaScriptValue.encodeAnyDictionary(value.attributes!, in: runtime))
            return object.takeValue()
          }

          @JavaScriptActor
          public static func encode(
            _ value: Report,
            into slot: borrowing JavaScriptValue.Slot,
            in runtime: borrowing JavaScriptRuntime
          ) throws {
            let object = runtime.createObject()
            let _propNames = runtime.cached(_PropNames._key) {
              return _PropNames(runtime)
            }
            try object.setProperty(_propNames._name0, encoding: value.name, in: runtime)
            object.setProperty(_propNames._name1, value: value.attributes == nil ? .null() : try JavaScriptValue.encodeAnyDictionary(value.attributes!, in: runtime))
            slot.emplace(object)
          }
        }

        extension Report: Record {
        }
        """
    )
  }

  @Test
  func
    `Array, defaulted dictionary and nested free-form properties pick the dedicated or the generic free-form methods`()
  {
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

          private final class _PropNames {
            static let _key = JavaScriptRuntime.Cache.Key<_PropNames>()

            let _name0: JavaScriptPropNameID
            let _name1: JavaScriptPropNameID
            let _name2: JavaScriptPropNameID

            init(_ runtime: borrowing JavaScriptRuntime) {
              self._name0 = JavaScriptPropNameID(runtime, string: "items")
              self._name1 = JavaScriptPropNameID(runtime, string: "meta")
              self._name2 = JavaScriptPropNameID(runtime, string: "groups")
            }
          }

          @JavaScriptActor
          public static func decode(_ value: borrowing JavaScriptUnownedValue, in runtime: borrowing JavaScriptRuntime) throws -> Self {
            let object = try value.asObject(in: runtime)
            let _propNames = runtime.cached(_PropNames._key) {
              return _PropNames(runtime)
            }
            let field0 = try object.withUnownedProperty(_propNames._name0) { itemsJSValue in
              guard !itemsJSValue.isUndefined() else {
                throw RecordPropertyRequiredException("items")
              }
              return try JavaScriptValue.decodeAnyArray(itemsJSValue, in: runtime)
            }
            let field1 = try object.withUnownedProperty(_propNames._name1) { metaJSValue in
              return metaJSValue.isUndefined() ? [:] : try JavaScriptValue.decodeAnyDictionary(metaJSValue, in: runtime)
            }
            let field2 = try object.withUnownedProperty(_propNames._name2) { groupsJSValue in
              return try JavaScriptValue.decodeAny(groupsJSValue.copied(in: runtime), as: [String: [Any]]?.self, in: runtime)
            }
            return Self(items: field0, meta: field1, groups: field2)
          }

          @JavaScriptActor
          public static func encode(_ value: Payload, in runtime: borrowing JavaScriptRuntime) throws -> JavaScriptValue {
            let object = runtime.createObject()
            let _propNames = runtime.cached(_PropNames._key) {
              return _PropNames(runtime)
            }
            object.setProperty(_propNames._name0, value: try JavaScriptValue.encodeAnyArray(value.items, in: runtime))
            object.setProperty(_propNames._name1, value: try JavaScriptValue.encodeAnyDictionary(value.meta, in: runtime))
            object.setProperty(_propNames._name2, value: try JavaScriptValue.encodeAny(value.groups as Any, in: runtime))
            return object.takeValue()
          }

          @JavaScriptActor
          public static func encode(
            _ value: Payload,
            into slot: borrowing JavaScriptValue.Slot,
            in runtime: borrowing JavaScriptRuntime
          ) throws {
            let object = runtime.createObject()
            let _propNames = runtime.cached(_PropNames._key) {
              return _PropNames(runtime)
            }
            object.setProperty(_propNames._name0, value: try JavaScriptValue.encodeAnyArray(value.items, in: runtime))
            object.setProperty(_propNames._name1, value: try JavaScriptValue.encodeAnyDictionary(value.meta, in: runtime))
            object.setProperty(_propNames._name2, value: try JavaScriptValue.encodeAny(value.groups as Any, in: runtime))
            slot.emplace(object)
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

          private final class _PropNames {
            static let _key = JavaScriptRuntime.Cache.Key<_PropNames>()

            let _name0: JavaScriptPropNameID
            let _name1: JavaScriptPropNameID

            init(_ runtime: borrowing JavaScriptRuntime) {
              self._name0 = JavaScriptPropNameID(runtime, string: "value")
              self._name1 = JavaScriptPropNameID(runtime, string: "maybe")
            }
          }

          @JavaScriptActor
          public static func decode(_ value: borrowing JavaScriptUnownedValue, in runtime: borrowing JavaScriptRuntime) throws -> Self {
            let object = try value.asObject(in: runtime)
            let _propNames = runtime.cached(_PropNames._key) {
              return _PropNames(runtime)
            }
            let field0 = try object.withUnownedProperty(_propNames._name0) { valueJSValue in
              guard !valueJSValue.isUndefined() else {
                throw RecordPropertyRequiredException("value")
              }
              return try JavaScriptValue.decodeAny(valueJSValue, in: runtime)
            }
            let field1 = try object.withUnownedProperty(_propNames._name1) { maybeJSValue in
              return try maybeJSValue.isUndefined() || maybeJSValue.isNull() ? nil : JavaScriptValue.decodeAny(maybeJSValue, in: runtime)
            }
            return Self(value: field0, maybe: field1)
          }

          @JavaScriptActor
          public static func encode(_ value: Payload, in runtime: borrowing JavaScriptRuntime) throws -> JavaScriptValue {
            let object = runtime.createObject()
            let _propNames = runtime.cached(_PropNames._key) {
              return _PropNames(runtime)
            }
            object.setProperty(_propNames._name0, value: try JavaScriptValue.encodeAny(value.value, in: runtime))
            object.setProperty(_propNames._name1, value: value.maybe == nil ? .null() : try JavaScriptValue.encodeAny(value.maybe!, in: runtime))
            return object.takeValue()
          }

          @JavaScriptActor
          public static func encode(
            _ value: Payload,
            into slot: borrowing JavaScriptValue.Slot,
            in runtime: borrowing JavaScriptRuntime
          ) throws {
            let object = runtime.createObject()
            let _propNames = runtime.cached(_PropNames._key) {
              return _PropNames(runtime)
            }
            object.setProperty(_propNames._name0, value: try JavaScriptValue.encodeAny(value.value, in: runtime))
            object.setProperty(_propNames._name1, value: value.maybe == nil ? .null() : try JavaScriptValue.encodeAny(value.maybe!, in: runtime))
            slot.emplace(object)
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
          message:
            "@Record property 'value' can't be typed '\(type)', because a type holding Any converts to and from JavaScript only when it's built from Any, arrays, String-keyed dictionaries and optionals. Use one of those shapes, such as [String: Any], or JavaScriptValue to keep the JavaScript value unconverted",
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

          private final class _PropNames {
            static let _key = JavaScriptRuntime.Cache.Key<_PropNames>()

            let _name0: JavaScriptPropNameID
            let _name1: JavaScriptPropNameID

            init(_ runtime: borrowing JavaScriptRuntime) {
              self._name0 = JavaScriptPropNameID(runtime, string: "value")
              self._name1 = JavaScriptPropNameID(runtime, string: "list")
            }
          }

          @JavaScriptActor
          public static func decode(_ value: borrowing JavaScriptUnownedValue, in runtime: borrowing JavaScriptRuntime) throws -> Self {
            let object = try value.asObject(in: runtime)
            let _propNames = runtime.cached(_PropNames._key) {
              return _PropNames(runtime)
            }
            let field0 = try object.withUnownedProperty(_propNames._name0) { valueJSValue in
              guard !valueJSValue.isUndefined() else {
                throw RecordPropertyRequiredException("value")
              }
              return try JavaScriptValue.decodeAny(valueJSValue, in: runtime)
            }
            let field1 = try object.withUnownedProperty(_propNames._name1) { listJSValue in
              return try listJSValue.isUndefined() || listJSValue.isNull() ? nil : JavaScriptValue.decodeAnyArray(listJSValue, in: runtime)
            }
            return Self(value: field0, list: field1)
          }

          @JavaScriptActor
          public static func encode(_ value: Payload, in runtime: borrowing JavaScriptRuntime) throws -> JavaScriptValue {
            let object = runtime.createObject()
            let _propNames = runtime.cached(_PropNames._key) {
              return _PropNames(runtime)
            }
            object.setProperty(_propNames._name0, value: try JavaScriptValue.encodeAny(value.value, in: runtime))
            object.setProperty(_propNames._name1, value: value.list == nil ? .null() : try JavaScriptValue.encodeAnyArray(value.list!, in: runtime))
            return object.takeValue()
          }

          @JavaScriptActor
          public static func encode(
            _ value: Payload,
            into slot: borrowing JavaScriptValue.Slot,
            in runtime: borrowing JavaScriptRuntime
          ) throws {
            let object = runtime.createObject()
            let _propNames = runtime.cached(_PropNames._key) {
              return _PropNames(runtime)
            }
            object.setProperty(_propNames._name0, value: try JavaScriptValue.encodeAny(value.value, in: runtime))
            object.setProperty(_propNames._name1, value: value.list == nil ? .null() : try JavaScriptValue.encodeAnyArray(value.list!, in: runtime))
            slot.emplace(object)
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

          private final class _PropNames {
            static let _key = JavaScriptRuntime.Cache.Key<_PropNames>()

            let _name0: JavaScriptPropNameID
            let _name1: JavaScriptPropNameID

            init(_ runtime: borrowing JavaScriptRuntime) {
              self._name0 = JavaScriptPropNameID(runtime, string: "default")
              self._name1 = JavaScriptPropNameID(runtime, string: "class")
            }
          }

          @JavaScriptActor
          public static func decode(_ value: borrowing JavaScriptUnownedValue, in runtime: borrowing JavaScriptRuntime) throws -> Self {
            let object = try value.asObject(in: runtime)
            let _propNames = runtime.cached(_PropNames._key) {
              return _PropNames(runtime)
            }
            let field0 = try object.withUnownedProperty(_propNames._name0) { `defaultJSValue` in
              return `defaultJSValue`.isUndefined() ? 0 : try Int.decode(`defaultJSValue`, in: runtime)
            }
            let field1 = try object.withUnownedProperty(_propNames._name1) { `classJSValue` in
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
            let _propNames = runtime.cached(_PropNames._key) {
              return _PropNames(runtime)
            }
            try object.setProperty(_propNames._name0, encoding: value.`default`, in: runtime)
            try object.setProperty(_propNames._name1, encoding: value.`class`, in: runtime)
            return object.takeValue()
          }

          @JavaScriptActor
          public static func encode(
            _ value: Options,
            into slot: borrowing JavaScriptValue.Slot,
            in runtime: borrowing JavaScriptRuntime
          ) throws {
            let object = runtime.createObject()
            let _propNames = runtime.cached(_PropNames._key) {
              return _PropNames(runtime)
            }
            try object.setProperty(_propNames._name0, encoding: value.`default`, in: runtime)
            try object.setProperty(_propNames._name1, encoding: value.`class`, in: runtime)
            slot.emplace(object)
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

          private final class _PropNames {
            static let _key = JavaScriptRuntime.Cache.Key<_PropNames>()

            let _name0: JavaScriptPropNameID
            let _name1: JavaScriptPropNameID

            init(_ runtime: borrowing JavaScriptRuntime) {
              self._name0 = JavaScriptPropNameID(runtime, string: "object")
              self._name1 = JavaScriptPropNameID(runtime, string: "count")
            }
          }

          @JavaScriptActor
          public static func decode(_ value: borrowing JavaScriptUnownedValue, in runtime: borrowing JavaScriptRuntime) throws -> Self {
            let object = try value.asObject(in: runtime)
            let _propNames = runtime.cached(_PropNames._key) {
              return _PropNames(runtime)
            }
            let field0 = try object.withUnownedProperty(_propNames._name0) { objectJSValue in
              guard !objectJSValue.isUndefined() else {
                throw RecordPropertyRequiredException("object")
              }
              return try String.decode(objectJSValue, in: runtime)
            }
            let field1 = try object.withUnownedProperty(_propNames._name1) { countJSValue in
              return countJSValue.isUndefined() ? 0 : try Int.decode(countJSValue, in: runtime)
            }
            return Self(object: field0, count: field1)
          }

          @JavaScriptActor
          public static func encode(_ value: Payload, in runtime: borrowing JavaScriptRuntime) throws -> JavaScriptValue {
            let object = runtime.createObject()
            let _propNames = runtime.cached(_PropNames._key) {
              return _PropNames(runtime)
            }
            try object.setProperty(_propNames._name0, encoding: value.object, in: runtime)
            try object.setProperty(_propNames._name1, encoding: value.count, in: runtime)
            return object.takeValue()
          }

          @JavaScriptActor
          public static func encode(
            _ value: Payload,
            into slot: borrowing JavaScriptValue.Slot,
            in runtime: borrowing JavaScriptRuntime
          ) throws {
            let object = runtime.createObject()
            let _propNames = runtime.cached(_PropNames._key) {
              return _PropNames(runtime)
            }
            try object.setProperty(_propNames._name0, encoding: value.object, in: runtime)
            try object.setProperty(_propNames._name1, encoding: value.count, in: runtime)
            slot.emplace(object)
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

          private final class _PropNames {
            static let _key = JavaScriptRuntime.Cache.Key<_PropNames>()

            let _name0: JavaScriptPropNameID
            let _name1: JavaScriptPropNameID
            let _name2: JavaScriptPropNameID
            let _name3: JavaScriptPropNameID
            let _name4: JavaScriptPropNameID

            init(_ runtime: borrowing JavaScriptRuntime) {
              self._name0 = JavaScriptPropNameID(runtime, string: "dictionary")
              self._name1 = JavaScriptPropNameID(runtime, string: "appContext")
              self._name2 = JavaScriptPropNameID(runtime, string: "runtime")
              self._name3 = JavaScriptPropNameID(runtime, string: "name")
              self._name4 = JavaScriptPropNameID(runtime, string: "nameValue")
            }
          }

          @JavaScriptActor
          public static func decode(_ value: borrowing JavaScriptUnownedValue, in runtime: borrowing JavaScriptRuntime) throws -> Self {
            let object = try value.asObject(in: runtime)
            let _propNames = runtime.cached(_PropNames._key) {
              return _PropNames(runtime)
            }
            let field0 = try object.withUnownedProperty(_propNames._name0) { dictionaryJSValue in
              guard !dictionaryJSValue.isUndefined() else {
                throw RecordPropertyRequiredException("dictionary")
              }
              return try String.decode(dictionaryJSValue, in: runtime)
            }
            let field1 = try object.withUnownedProperty(_propNames._name1) { appContextJSValue in
              guard !appContextJSValue.isUndefined() else {
                throw RecordPropertyRequiredException("appContext")
              }
              return try String.decode(appContextJSValue, in: runtime)
            }
            let field2 = try object.withUnownedProperty(_propNames._name2) { runtimeJSValue in
              guard !runtimeJSValue.isUndefined() else {
                throw RecordPropertyRequiredException("runtime")
              }
              return try String.decode(runtimeJSValue, in: runtime)
            }
            let field3 = try object.withUnownedProperty(_propNames._name3) { nameJSValue in
              guard !nameJSValue.isUndefined() else {
                throw RecordPropertyRequiredException("name")
              }
              return try String.decode(nameJSValue, in: runtime)
            }
            let field4 = try object.withUnownedProperty(_propNames._name4) { nameValueJSValue in
              return nameValueJSValue.isUndefined() ? 0 : try Int.decode(nameValueJSValue, in: runtime)
            }
            return Self(dictionary: field0, appContext: field1, runtime: field2, name: field3, nameValue: field4)
          }

          @JavaScriptActor
          public static func encode(_ value: Conflicts, in runtime: borrowing JavaScriptRuntime) throws -> JavaScriptValue {
            let object = runtime.createObject()
            let _propNames = runtime.cached(_PropNames._key) {
              return _PropNames(runtime)
            }
            try object.setProperty(_propNames._name0, encoding: value.dictionary, in: runtime)
            try object.setProperty(_propNames._name1, encoding: value.appContext, in: runtime)
            try object.setProperty(_propNames._name2, encoding: value.runtime, in: runtime)
            try object.setProperty(_propNames._name3, encoding: value.name, in: runtime)
            try object.setProperty(_propNames._name4, encoding: value.nameValue, in: runtime)
            return object.takeValue()
          }

          @JavaScriptActor
          public static func encode(
            _ value: Conflicts,
            into slot: borrowing JavaScriptValue.Slot,
            in runtime: borrowing JavaScriptRuntime
          ) throws {
            let object = runtime.createObject()
            let _propNames = runtime.cached(_PropNames._key) {
              return _PropNames(runtime)
            }
            try object.setProperty(_propNames._name0, encoding: value.dictionary, in: runtime)
            try object.setProperty(_propNames._name1, encoding: value.appContext, in: runtime)
            try object.setProperty(_propNames._name2, encoding: value.runtime, in: runtime)
            try object.setProperty(_propNames._name3, encoding: value.name, in: runtime)
            try object.setProperty(_propNames._name4, encoding: value.nameValue, in: runtime)
            slot.emplace(object)
          }
        }

        extension Conflicts: Record {
        }
        """
    )
  }

  @Test
  func `A generic record names its properties with strings and caches no property names`() {
    assertExpansion(
      """
      @Record
      struct Box<T: AnyArgument & JavaScriptDecodable & JavaScriptEncodable> {
        var value: T
      }
      """,
      expandedSource: """
        struct Box<T: AnyArgument & JavaScriptDecodable & JavaScriptEncodable> {
          var value: T

          private func _assertTypesConformance() {
            func value(_: (some JavaScriptDecodable & JavaScriptEncodable).Type) {
            }
            value(T.self)
          }

          public init() {
            fatalError("\\(Self.self) has required properties and cannot be created with init(); construct it through the @Record-synthesized from(dictionary:) or from(object:) factories")
          }

          public init(value: T) {
            self.value = value
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
            let field0 = try T.getDynamicType().cast(entry0, appContext: appContext) as! T
            return Self(value: field0)
          }

          public func toDictionary(appContext: AppContext? = nil) -> [String: Any] {
            var dictionary: [String: Any] = [:]
            dictionary["value"] = self.value
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
              return try T.decode(valueJSValue, in: runtime)
            }
            return Self(value: field0)
          }

          @JavaScriptActor
          public static func encode(_ value: Box, in runtime: borrowing JavaScriptRuntime) throws -> JavaScriptValue {
            let object = runtime.createObject()
            try object.setProperty("value", encoding: value.value, in: runtime)
            return object.takeValue()
          }

          @JavaScriptActor
          public static func encode(
            _ value: Box,
            into slot: borrowing JavaScriptValue.Slot,
            in runtime: borrowing JavaScriptRuntime
          ) throws {
            let object = runtime.createObject()
            try object.setProperty("value", encoding: value.value, in: runtime)
            slot.emplace(object)
          }
        }

        extension Box: Record {
        }
        """
    )
  }

  @Test
  func `A record nested in a generic type names its properties with strings and caches no property names`() {
    assertExpansion(
      """
      struct Outer<Element> {
        @Record
        struct Options {
          var name: String
        }
      }
      """,
      expandedSource: """
        struct Outer<Element> {
          struct Options {
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
              try object.setProperty("name", encoding: value.name, in: runtime)
              return object.takeValue()
            }

            @JavaScriptActor
            public static func encode(
              _ value: Options,
              into slot: borrowing JavaScriptValue.Slot,
              in runtime: borrowing JavaScriptRuntime
            ) throws {
              let object = runtime.createObject()
              try object.setProperty("name", encoding: value.name, in: runtime)
              slot.emplace(object)
            }
          }
        }

        extension Outer.Options: Record {
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
