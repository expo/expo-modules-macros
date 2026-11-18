// Stand-ins for the ExpoModulesJSI and expo-modules-core symbols that the `@ViewProps` expansion uses,
// with the signatures of the real ones. `AnyViewProps` and the `@ViewProps` declaration are copies of
// `ios/Core/Views/v2/AnyViewProps.swift` and `ios/Core/ExpoModulesMacros.swift` in expo-modules-core.
// `check-compile.js` builds this file as the `Core` module, with library evolution.

// MARK: - ExpoModulesJSI

@globalActor
public actor JavaScriptActor: GlobalActor {
  public static let shared = JavaScriptActor()

  private init() {}
}

public final class JavaScriptRuntime: Sendable {
  public init() {}
}

/// A JavaScript value that is `null` or a number.
public struct JavaScriptUnownedValue: ~Copyable {
  let number: Double?

  public init(number: Double?) {
    self.number = number
  }

  public func isNull() -> Bool {
    return number == nil
  }

  public func isUndefined() -> Bool {
    return false
  }

  public func copied(in runtime: JavaScriptRuntime) -> JavaScriptValue {
    return JavaScriptValue(number: number)
  }
}

/// An owning JavaScript value that is `null` or a number.
public final class JavaScriptValue {
  let number: Double?

  public init(number: Double?) {
    self.number = number
  }
}

// The free-form decoding of `JavaScriptCodable+Any.swift` in ExpoModulesJSI, for types that hold `Any`.
// Each method puts the number in the shape that it returns.
extension JavaScriptValue {
  @JavaScriptActor
  public static func decodeAny(
    _ value: borrowing JavaScriptUnownedValue,
    in runtime: borrowing JavaScriptRuntime
  ) throws -> Any {
    return try freeFormNumber(value.number)
  }

  @JavaScriptActor
  public static func decodeAnyArray(
    _ value: borrowing JavaScriptUnownedValue,
    in runtime: borrowing JavaScriptRuntime
  ) throws -> [Any] {
    return [try freeFormNumber(value.number)]
  }

  @JavaScriptActor
  public static func decodeAnyDictionary(
    _ value: borrowing JavaScriptUnownedValue,
    in runtime: borrowing JavaScriptRuntime
  ) throws -> [String: Any] {
    return ["value": try freeFormNumber(value.number)]
  }

  /// Puts the number in an array with one dictionary, the shape of a modifier array, and casts it to `type`.
  @JavaScriptActor
  public static func decodeAny<T>(
    _ value: borrowing JavaScriptValue,
    as type: T.Type,
    in runtime: borrowing JavaScriptRuntime
  ) throws -> T {
    let decoded: [[String: Any]] = [["value": try freeFormNumber(value.number)]]
    guard let result = decoded as Any as? T else {
      throw DecodingError()
    }
    return result
  }

  private static func freeFormNumber(_ number: Double?) throws -> Double {
    guard let number else {
      throw DecodingError()
    }
    return number
  }
}

public struct DecodingError: Error {}

public protocol JavaScriptEncodable: ~Copyable {}

extension Int: JavaScriptEncodable {}

public protocol JavaScriptDecodable: ~Copyable {
  @JavaScriptActor
  static func decode(_ value: borrowing JavaScriptUnownedValue, in runtime: borrowing JavaScriptRuntime) throws -> Self
}

extension Int: JavaScriptDecodable {
  public static func decode(_ value: borrowing JavaScriptUnownedValue, in runtime: borrowing JavaScriptRuntime) throws
    -> Int
  {
    guard let number = value.number else {
      throw DecodingError()
    }
    return Int(number)
  }
}

extension Double: JavaScriptDecodable {
  public static func decode(_ value: borrowing JavaScriptUnownedValue, in runtime: borrowing JavaScriptRuntime) throws
    -> Double
  {
    guard let number = value.number else {
      throw DecodingError()
    }
    return number
  }
}

extension String: JavaScriptDecodable {
  public static func decode(_ value: borrowing JavaScriptUnownedValue, in runtime: borrowing JavaScriptRuntime) throws
    -> String
  {
    guard let number = value.number else {
      throw DecodingError()
    }
    return String(number)
  }
}

extension Array: JavaScriptDecodable where Element: JavaScriptDecodable {
  public static func decode(_ value: borrowing JavaScriptUnownedValue, in runtime: borrowing JavaScriptRuntime) throws
    -> Array
  {
    return [try Element.decode(value, in: runtime)]
  }
}

extension Optional: JavaScriptDecodable where Wrapped: JavaScriptDecodable {
  public static func decode(_ value: borrowing JavaScriptUnownedValue, in runtime: borrowing JavaScriptRuntime) throws
    -> Optional
  {
    return value.isNull() ? nil : try Wrapped.decode(value, in: runtime)
  }
}

// MARK: - expo-modules-core

public protocol AnyViewProps {
  associatedtype PropName: RawRepresentable, CaseIterable where PropName.RawValue == String

  associatedtype PropSet: OptionSet, Sendable where PropSet.RawValue == UInt64, PropSet.Element == PropSet

  static var allProps: PropSet { get }

  static var _eventNames: [String] { get }

  static func propSet(for name: PropName) -> PropSet

  init()

  @JavaScriptActor
  mutating func _decode(
    _ name: PropName,
    from value: borrowing JavaScriptUnownedValue,
    in runtime: borrowing JavaScriptRuntime
  ) throws

  mutating func _bindEvents(to events: ViewEventDispatcher)
}

extension AnyViewProps {
  public mutating func _bindEvents(to events: ViewEventDispatcher) {}

  @JavaScriptActor
  @inlinable
  public static func _decodeViewProp<T: JavaScriptDecodable>(
    _ value: borrowing JavaScriptUnownedValue,
    in runtime: borrowing JavaScriptRuntime
  ) throws -> T {
    return try T.decode(value, in: runtime)
  }
}

public struct PropsDiff<Props: AnyViewProps> {}

/// Records the events that bound props dispatch, in place of sending them to JavaScript.
public final class ViewEventDispatcher: @unchecked Sendable {
  public private(set) var events: [String] = []

  public init() {}

  public func dispatch(_ name: String) {
    events.append(name)
  }

  public func dispatch<Payload: JavaScriptEncodable>(_ name: String, _ payload: sending Payload) {
    events.append("\(name): \(payload)")
  }
}

@attached(
  member,
  names: named(PropName),
  named(PropSet),
  named(_eventNames),
  named(Diff),
  named(init),
  named(_resetViewProp)
)
@attached(
  extension,
  conformances: AnyViewProps,
  names: named(allProps),
  named(propSet),
  named(_decode),
  named(_bindEvents)
)
public macro ViewProps() =
  #externalMacro(module: "ExpoModulesMacros", type: "ViewPropsMacro")

// MARK: - Generic use, as in `ViewPropsDecoder`

/// Decodes the given values into a copy of `props`, from generic code on the JavaScript actor, as
/// `ViewPropsDecoder` does. A `nil` value is the `null` that React sends for a removed prop. Returns the
/// props and the bits of the props that changed.
@JavaScriptActor
public func decoding<Props: AnyViewProps>(
  _ props: Props,
  _ values: [(Props.PropName, Double?)]
) throws -> (props: Props, changed: UInt64) {
  var props = props
  var changed = Props.PropSet()
  let runtime = JavaScriptRuntime()
  for (name, number) in values {
    try props._decode(name, from: JavaScriptUnownedValue(number: number), in: runtime)
    changed.insert(Props.propSet(for: name))
  }
  return (props, changed.rawValue)
}

/// Returns new props with the events bound to the given dispatcher, from generic code with no isolation,
/// as `ViewPropsDecoder` makes the first props of a view.
public func bindingEvents<Props: AnyViewProps>(of type: Props.Type, to dispatcher: ViewEventDispatcher) -> Props {
  var props = Props()
  props._bindEvents(to: dispatcher)
  return props
}

/// The names of the value props and of the events, from generic code with no isolation.
public func propNames<Props: AnyViewProps>(of type: Props.Type) -> [String] {
  let valueProps = Props.PropName.allCases.filter { !Props.propSet(for: $0).isEmpty }.map(\.rawValue)
  assert(Props.allProps.rawValue.nonzeroBitCount == valueProps.count)
  return valueProps + Props._eventNames
}
