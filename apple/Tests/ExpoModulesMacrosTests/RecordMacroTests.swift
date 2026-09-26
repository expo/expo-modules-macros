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
  sourceLocation: Testing.SourceLocation = #_sourceLocation,
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
    failureHandler: { spec in
      Issue.record(Comment(rawValue: spec.message), sourceLocation: sourceLocation)
    },
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
            let nameJSValue = object.getProperty("name")
            guard !nameJSValue.isUndefined() else {
              throw RecordPropertyRequiredException("name")
            }
            let name = try String.decode(nameJSValue, in: runtime)
            let countJSValue = object.getProperty("count")
            let count = countJSValue.isUndefined() ? 0 : try Int.decode(countJSValue, in: runtime)
            let noteJSValue = object.getProperty("note")
            let note = try String?.decode(noteJSValue, in: runtime)
            return Self(name: name, count: count, note: note)
          }

          public static func from(dictionary: [String: Any], appContext: AppContext) throws -> Self {
            let nameValue = dictionary["name"]
            guard let nameValue else {
              throw RecordPropertyRequiredException("name")
            }
            let name = try String.getDynamicType().cast(nameValue, appContext: appContext) as! String
            let countValue = dictionary["count"]
            let count = countValue == nil ? 0 : try Int.getDynamicType().cast(countValue, appContext: appContext) as! Int
            let noteValue = dictionary["note"]
            let note: String? = (noteValue == nil || noteValue! is NSNull) ? nil : try String?.getDynamicType().cast(noteValue, appContext: appContext) as! String?
            return Self(name: name, count: count, note: note)
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
            let runtime = try appContext.runtime
            let object = runtime.createObject()
            object.setProperty("name", value: try String.encode(self.name, in: runtime))
            object.setProperty("count", value: try Int.encode(self.count, in: runtime))
            object.setProperty("note", value: try String?.encode(self.note, in: runtime))
            return object
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
            let ownerJSValue = object.getProperty("owner")
            let owner = try MyRecord?.decode(ownerJSValue, in: runtime)
            return Self(owner: owner)
          }

          public static func from(dictionary: [String: Any], appContext: AppContext) throws -> Self {
            let ownerValue = dictionary["owner"]
            let owner: MyRecord! = (ownerValue == nil || ownerValue! is NSNull) ? nil : try MyRecord?.getDynamicType().cast(ownerValue, appContext: appContext) as! MyRecord?
            return Self(owner: owner)
          }

          public func toDictionary(appContext: AppContext? = nil) -> [String: Any] {
            var dictionary: [String: Any] = [:]
            dictionary["owner"] = self.owner
            return dictionary
          }

          @JavaScriptActor
          public func toObject(appContext: AppContext) throws -> JavaScriptObject {
            let runtime = try appContext.runtime
            let object = runtime.createObject()
            object.setProperty("owner", value: try MyRecord?.encode(self.owner, in: runtime))
            return object
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
            let primaryJSValue = object.getProperty("primary")
            guard !primaryJSValue.isUndefined() else {
              throw RecordPropertyRequiredException("primary")
            }
            let primary = try MyRecord.decode(primaryJSValue, in: runtime)
            let tagsJSValue = object.getProperty("tags")
            guard !tagsJSValue.isUndefined() else {
              throw RecordPropertyRequiredException("tags")
            }
            let tags = try [String].decode(tagsJSValue, in: runtime)
            let countJSValue = object.getProperty("count")
            let count = countJSValue.isUndefined() ? 0 : try Int.decode(countJSValue, in: runtime)
            return Self(primary: primary, tags: tags, count: count)
          }

          public static func from(dictionary: [String: Any], appContext: AppContext) throws -> Self {
            let primaryValue = dictionary["primary"]
            guard let primaryValue else {
              throw RecordPropertyRequiredException("primary")
            }
            let primary = try MyRecord.getDynamicType().cast(primaryValue, appContext: appContext) as! MyRecord
            let tagsValue = dictionary["tags"]
            guard let tagsValue else {
              throw RecordPropertyRequiredException("tags")
            }
            let tags = try [String].getDynamicType().cast(tagsValue, appContext: appContext) as! [String]
            let countValue = dictionary["count"]
            let count = countValue == nil ? 0 : try Int.getDynamicType().cast(countValue, appContext: appContext) as! Int
            return Self(primary: primary, tags: tags, count: count)
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
            let runtime = try appContext.runtime
            let object = runtime.createObject()
            object.setProperty("primary", value: try MyRecord.encode(self.primary, in: runtime))
            object.setProperty("tags", value: try [String].encode(self.tags, in: runtime))
            object.setProperty("count", value: try Int.encode(self.count, in: runtime))
            return object
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
            let nameJSValue = object.getProperty("name")
            let name = nameJSValue.isUndefined() ? "foo" : try String.decode(nameJSValue, in: runtime)
            let ratioJSValue = object.getProperty("ratio")
            let ratio = ratioJSValue.isUndefined() ? 1.0 : try Double.decode(ratioJSValue, in: runtime)
            let countJSValue = object.getProperty("count")
            let count = countJSValue.isUndefined() ? 0 : try Int.decode(countJSValue, in: runtime)
            let flagJSValue = object.getProperty("flag")
            let flag = flagJSValue.isUndefined() ? false : try Bool.decode(flagJSValue, in: runtime)
            return Self(name: name, ratio: ratio, count: count, flag: flag)
          }

          public static func from(dictionary: [String: Any], appContext: AppContext) throws -> Self {
            let nameValue = dictionary["name"]
            let name = nameValue == nil ? "foo" : try String.getDynamicType().cast(nameValue, appContext: appContext) as! String
            let ratioValue = dictionary["ratio"]
            let ratio = ratioValue == nil ? 1.0 : try Double.getDynamicType().cast(ratioValue, appContext: appContext) as! Double
            let countValue = dictionary["count"]
            let count = countValue == nil ? 0 : try Int.getDynamicType().cast(countValue, appContext: appContext) as! Int
            let flagValue = dictionary["flag"]
            let flag = flagValue == nil ? false : try Bool.getDynamicType().cast(flagValue, appContext: appContext) as! Bool
            return Self(name: name, ratio: ratio, count: count, flag: flag)
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
            let runtime = try appContext.runtime
            let object = runtime.createObject()
            object.setProperty("name", value: try String.encode(self.name, in: runtime))
            object.setProperty("ratio", value: try Double.encode(self.ratio, in: runtime))
            object.setProperty("count", value: try Int.encode(self.count, in: runtime))
            object.setProperty("flag", value: try Bool.encode(self.flag, in: runtime))
            return object
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
            let nameJSValue = object.getProperty("name")
            guard !nameJSValue.isUndefined() else {
              throw RecordPropertyRequiredException("name")
            }
            let name = try String.decode(nameJSValue, in: runtime)
            return Self(name: name)
          }

          public static func from(dictionary: [String: Any], appContext: AppContext) throws -> Self {
            let nameValue = dictionary["name"]
            guard let nameValue else {
              throw RecordPropertyRequiredException("name")
            }
            let name = try String.getDynamicType().cast(nameValue, appContext: appContext) as! String
            return Self(name: name)
          }

          public func toDictionary(appContext: AppContext? = nil) -> [String: Any] {
            var dictionary: [String: Any] = [:]
            dictionary["name"] = self.name
            return dictionary
          }

          @JavaScriptActor
          public func toObject(appContext: AppContext) throws -> JavaScriptObject {
            let runtime = try appContext.runtime
            let object = runtime.createObject()
            object.setProperty("name", value: try String.encode(self.name, in: runtime))
            return object
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
            return Self()
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
            let runtime = try appContext.runtime
            let object = runtime.createObject()
            return object
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
            let xJSValue = object.getProperty("x")
            let x = xJSValue.isUndefined() ? 0 : try Double.decode(xJSValue, in: runtime)
            let yJSValue = object.getProperty("y")
            let y = yJSValue.isUndefined() ? 0 : try Double.decode(yJSValue, in: runtime)
            return Self(x: x, y: y)
          }

          public static func from(dictionary: [String: Any], appContext: AppContext) throws -> Self {
            let xValue = dictionary["x"]
            let x = xValue == nil ? 0 : try Double.getDynamicType().cast(xValue, appContext: appContext) as! Double
            let yValue = dictionary["y"]
            let y = yValue == nil ? 0 : try Double.getDynamicType().cast(yValue, appContext: appContext) as! Double
            return Self(x: x, y: y)
          }

          public func toDictionary(appContext: AppContext? = nil) -> [String: Any] {
            var dictionary: [String: Any] = [:]
            dictionary["x"] = self.x
            dictionary["y"] = self.y
            return dictionary
          }

          @JavaScriptActor
          public func toObject(appContext: AppContext) throws -> JavaScriptObject {
            let runtime = try appContext.runtime
            let object = runtime.createObject()
            object.setProperty("x", value: try Double.encode(self.x, in: runtime))
            object.setProperty("y", value: try Double.encode(self.y, in: runtime))
            return object
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
            let extraJSValue = object.getProperty("extra")
            let extra = extraJSValue.isUndefined() ? "" : try String.decode(extraJSValue, in: runtime)
            return Self(extra: extra)
          }

          public static func from(dictionary: [String: Any], appContext: AppContext) throws -> Self {
            let extraValue = dictionary["extra"]
            let extra = extraValue == nil ? "" : try String.getDynamicType().cast(extraValue, appContext: appContext) as! String
            return Self(extra: extra)
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
            let nameJSValue = object.getProperty("name")
            guard !nameJSValue.isUndefined() else {
              throw RecordPropertyRequiredException("name")
            }
            let name = try String.decode(nameJSValue, in: runtime)
            return Self(name: name)
          }

          public static func from(dictionary: [String: Any], appContext: AppContext) throws -> Self {
            let nameValue = dictionary["name"]
            guard let nameValue else {
              throw RecordPropertyRequiredException("name")
            }
            let name = try String.getDynamicType().cast(nameValue, appContext: appContext) as! String
            return Self(name: name)
          }

          public func toDictionary(appContext: AppContext? = nil) -> [String: Any] {
            var dictionary: [String: Any] = [:]
            dictionary["name"] = self.name
            return dictionary
          }

          @JavaScriptActor
          public func toObject(appContext: AppContext) throws -> JavaScriptObject {
            let runtime = try appContext.runtime
            let object = runtime.createObject()
            object.setProperty("name", value: try String.encode(self.name, in: runtime))
            return object
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
            let nameJSValue = object.getProperty("name")
            guard !nameJSValue.isUndefined() else {
              throw RecordPropertyRequiredException("name")
            }
            let name = try String.decode(nameJSValue, in: runtime)
            return Self(name: name)
          }

          public static func from(dictionary: [String: Any], appContext: AppContext) throws -> Self {
            let nameValue = dictionary["name"]
            guard let nameValue else {
              throw RecordPropertyRequiredException("name")
            }
            let name = try String.getDynamicType().cast(nameValue, appContext: appContext) as! String
            return Self(name: name)
          }

          public func toDictionary(appContext: AppContext? = nil) -> [String: Any] {
            var dictionary: [String: Any] = [:]
            dictionary["name"] = self.name
            return dictionary
          }

          @JavaScriptActor
          public func toObject(appContext: AppContext) throws -> JavaScriptObject {
            let runtime = try appContext.runtime
            let object = runtime.createObject()
            object.setProperty("name", value: try String.encode(self.name, in: runtime))
            return object
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
            let xJSValue = object.getProperty("x")
            let x = xJSValue.isUndefined() ? 0 : try Double.decode(xJSValue, in: runtime)
            let yJSValue = object.getProperty("y")
            let y = yJSValue.isUndefined() ? 0 : try Double.decode(yJSValue, in: runtime)
            return Self(x: x, y: y)
          }

          public static func from(dictionary: [String: Any], appContext: AppContext) throws -> Self {
            let xValue = dictionary["x"]
            let x = xValue == nil ? 0 : try Double.getDynamicType().cast(xValue, appContext: appContext) as! Double
            let yValue = dictionary["y"]
            let y = yValue == nil ? 0 : try Double.getDynamicType().cast(yValue, appContext: appContext) as! Double
            return Self(x: x, y: y)
          }

          public func toDictionary(appContext: AppContext? = nil) -> [String: Any] {
            var dictionary: [String: Any] = [:]
            dictionary["x"] = self.x
            dictionary["y"] = self.y
            return dictionary
          }

          @JavaScriptActor
          public func toObject(appContext: AppContext) throws -> JavaScriptObject {
            let runtime = try appContext.runtime
            let object = runtime.createObject()
            object.setProperty("x", value: try Double.encode(self.x, in: runtime))
            object.setProperty("y", value: try Double.encode(self.y, in: runtime))
            return object
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
            let xJSValue = object.getProperty("x")
            let x = xJSValue.isUndefined() ? 0 : try Double.decode(xJSValue, in: runtime)
            let yJSValue = object.getProperty("y")
            let y = yJSValue.isUndefined() ? 0 : try Double.decode(yJSValue, in: runtime)
            return Self(x: x, y: y)
          }

          public static func from(dictionary: [String: Any], appContext: AppContext) throws -> Self {
            let xValue = dictionary["x"]
            let x = xValue == nil ? 0 : try Double.getDynamicType().cast(xValue, appContext: appContext) as! Double
            let yValue = dictionary["y"]
            let y = yValue == nil ? 0 : try Double.getDynamicType().cast(yValue, appContext: appContext) as! Double
            return Self(x: x, y: y)
          }

          public func toDictionary(appContext: AppContext? = nil) -> [String: Any] {
            var dictionary: [String: Any] = [:]
            dictionary["x"] = self.x
            dictionary["y"] = self.y
            return dictionary
          }

          @JavaScriptActor
          public func toObject(appContext: AppContext) throws -> JavaScriptObject {
            let runtime = try appContext.runtime
            let object = runtime.createObject()
            object.setProperty("x", value: try Double.encode(self.x, in: runtime))
            object.setProperty("y", value: try Double.encode(self.y, in: runtime))
            return object
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
            let nameJSValue = object.getProperty("name")
            guard !nameJSValue.isUndefined() else {
              throw RecordPropertyRequiredException("name")
            }
            let name = try String.decode(nameJSValue, in: runtime)
            let attributesJSValue = object.getProperty("attributes")
            let attributes = attributesJSValue.isUndefined() || attributesJSValue.isNull() ? nil : try JavaScriptValue.decodeAnyDictionary(attributesJSValue, in: runtime)
            return Self(name: name, attributes: attributes)
          }

          public static func from(dictionary: [String: Any], appContext: AppContext) throws -> Self {
            let nameValue = dictionary["name"]
            guard let nameValue else {
              throw RecordPropertyRequiredException("name")
            }
            let name = try String.getDynamicType().cast(nameValue, appContext: appContext) as! String
            let attributesValue = dictionary["attributes"]
            let attributes: [String: Any]? = (attributesValue == nil || attributesValue! is NSNull) ? nil : try [String: Any]?.getDynamicType().cast(attributesValue, appContext: appContext) as! [String: Any]?
            return Self(name: name, attributes: attributes)
          }

          public func toDictionary(appContext: AppContext? = nil) -> [String: Any] {
            var dictionary: [String: Any] = [:]
            dictionary["name"] = self.name
            dictionary["attributes"] = self.attributes
            return dictionary
          }

          @JavaScriptActor
          public func toObject(appContext: AppContext) throws -> JavaScriptObject {
            let runtime = try appContext.runtime
            let object = runtime.createObject()
            object.setProperty("name", value: try String.encode(self.name, in: runtime))
            object.setProperty("attributes", value: self.attributes == nil ? .null : try JavaScriptValue.encodeAnyDictionary(self.attributes!, in: runtime))
            return object
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
            let itemsJSValue = object.getProperty("items")
            guard !itemsJSValue.isUndefined() else {
              throw RecordPropertyRequiredException("items")
            }
            let items = try JavaScriptValue.decodeAnyArray(itemsJSValue, in: runtime)
            let metaJSValue = object.getProperty("meta")
            let meta = metaJSValue.isUndefined() ? [:] : try JavaScriptValue.decodeAnyDictionary(metaJSValue, in: runtime)
            let groupsJSValue = object.getProperty("groups")
            let groups = try JavaScriptValue.decodeAny(groupsJSValue, as: [String: [Any]]?.self, in: runtime)
            return Self(items: items, meta: meta, groups: groups)
          }

          public static func from(dictionary: [String: Any], appContext: AppContext) throws -> Self {
            let itemsValue = dictionary["items"]
            guard let itemsValue else {
              throw RecordPropertyRequiredException("items")
            }
            let items = try [Any].getDynamicType().cast(itemsValue, appContext: appContext) as! [Any]
            let metaValue = dictionary["meta"]
            let meta = metaValue == nil ? [:] : try [String : Any].getDynamicType().cast(metaValue, appContext: appContext) as! [String : Any]
            let groupsValue = dictionary["groups"]
            let groups: [String: [Any]]? = (groupsValue == nil || groupsValue! is NSNull) ? nil : try [String: [Any]]?.getDynamicType().cast(groupsValue, appContext: appContext) as! [String: [Any]]?
            return Self(items: items, meta: meta, groups: groups)
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
            let runtime = try appContext.runtime
            let object = runtime.createObject()
            object.setProperty("items", value: try JavaScriptValue.encodeAnyArray(self.items, in: runtime))
            object.setProperty("meta", value: try JavaScriptValue.encodeAnyDictionary(self.meta, in: runtime))
            object.setProperty("groups", value: try JavaScriptValue.encodeAny(self.groups as Any, in: runtime))
            return object
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
            let valueJSValue = object.getProperty("value")
            guard !valueJSValue.isUndefined() else {
              throw RecordPropertyRequiredException("value")
            }
            let value = try JavaScriptValue.decodeAny(valueJSValue, in: runtime)
            let maybeJSValue = object.getProperty("maybe")
            let maybe = maybeJSValue.isUndefined() || maybeJSValue.isNull() ? nil : try JavaScriptValue.decodeAny(maybeJSValue, in: runtime)
            return Self(value: value, maybe: maybe)
          }

          public static func from(dictionary: [String: Any], appContext: AppContext) throws -> Self {
            let valueValue = dictionary["value"]
            guard let valueValue else {
              throw RecordPropertyRequiredException("value")
            }
            let value = valueValue
            let maybeValue = dictionary["maybe"]
            let maybe: Any? = (maybeValue == nil || maybeValue! is NSNull) ? nil : maybeValue
            return Self(value: value, maybe: maybe)
          }

          public func toDictionary(appContext: AppContext? = nil) -> [String: Any] {
            var dictionary: [String: Any] = [:]
            dictionary["value"] = self.value
            dictionary["maybe"] = self.maybe
            return dictionary
          }

          @JavaScriptActor
          public func toObject(appContext: AppContext) throws -> JavaScriptObject {
            let runtime = try appContext.runtime
            let object = runtime.createObject()
            object.setProperty("value", value: try JavaScriptValue.encodeAny(self.value, in: runtime))
            object.setProperty("maybe", value: self.maybe == nil ? .null : try JavaScriptValue.encodeAny(self.maybe!, in: runtime))
            return object
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
            let valueJSValue = object.getProperty("value")
            guard !valueJSValue.isUndefined() else {
              throw RecordPropertyRequiredException("value")
            }
            let value = try JavaScriptValue.decodeAny(valueJSValue, in: runtime)
            let listJSValue = object.getProperty("list")
            let list = listJSValue.isUndefined() || listJSValue.isNull() ? nil : try JavaScriptValue.decodeAnyArray(listJSValue, in: runtime)
            return Self(value: value, list: list)
          }

          public static func from(dictionary: [String: Any], appContext: AppContext) throws -> Self {
            let valueValue = dictionary["value"]
            guard let valueValue else {
              throw RecordPropertyRequiredException("value")
            }
            let value = valueValue
            let listValue = dictionary["list"]
            let list: [Swift.Any]? = (listValue == nil || listValue! is NSNull) ? nil : try [Swift.Any]?.getDynamicType().cast(listValue, appContext: appContext) as! [Swift.Any]?
            return Self(value: value, list: list)
          }

          public func toDictionary(appContext: AppContext? = nil) -> [String: Any] {
            var dictionary: [String: Any] = [:]
            dictionary["value"] = self.value
            dictionary["list"] = self.list
            return dictionary
          }

          @JavaScriptActor
          public func toObject(appContext: AppContext) throws -> JavaScriptObject {
            let runtime = try appContext.runtime
            let object = runtime.createObject()
            object.setProperty("value", value: try JavaScriptValue.encodeAny(self.value, in: runtime))
            object.setProperty("list", value: self.list == nil ? .null : try JavaScriptValue.encodeAnyArray(self.list!, in: runtime))
            return object
          }
        }

        extension Payload: Record {
        }
        """
    )
  }
}
