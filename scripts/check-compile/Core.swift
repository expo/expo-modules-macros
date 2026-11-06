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
}

public struct DecodingError: Error {}

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
}

extension AnyViewProps {
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

@attached(
  member,
  names: named(PropName),
  named(PropSet),
  named(_eventNames),
  named(Diff),
  named(init),
  named(_resetViewProp)
)
@attached(extension, conformances: AnyViewProps, names: named(allProps), named(propSet), named(_decode))
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

/// The names of the value props and of the events, from generic code with no isolation.
public func propNames<Props: AnyViewProps>(of type: Props.Type) -> [String] {
  let valueProps = Props.PropName.allCases.filter { !Props.propSet(for: $0).isEmpty }.map(\.rawValue)
  assert(Props.allProps.rawValue.nonzeroBitCount == valueProps.count)
  return valueProps + Props._eventNames
}
