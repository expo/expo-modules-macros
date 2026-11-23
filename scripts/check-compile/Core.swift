// Stand-ins for the ExpoModulesJSI and expo-modules-core symbols that the `@ViewProps`, `@ExpoView` and
// `@SharedObject` expansions use, with the signatures of the real ones. `AnyViewProps` and the macro declarations
// are copies of `ios/Core/Views/v2/AnyViewProps.swift` and `ios/Core/ExpoModulesMacros.swift` in
// expo-modules-core. The view protocols keep the requirements and defaults of
// `ios/Core/Views/v2/AnyNativeView.swift` and `AnyNativeSwiftUIView.swift` that the expansions and the views of
// `Views.swift` use. `SharedObject` keeps the hooks of `ios/Core/SharedObjects/SharedObject.swift` that the
// expansions of the classes in `SharedObjects.swift` override. `check-compile.js` builds this file as the `Core`
// module, with library evolution.

import SwiftUI

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

@attached(
  member,
  names: named(PropName),
  named(PropSet),
  named(_eventNames),
  named(Diff),
  named(init),
  named(_resetViewProp),
  named(base)
)
@attached(
  extension,
  conformances: AnyViewProps,
  names: named(allProps),
  named(propSet),
  named(_decode),
  named(_bindEvents)
)
public macro ViewProps<Base: AnyViewProps>(extending base: Base.Type) =
  #externalMacro(module: "ExpoModulesMacros", type: "ViewPropsMacro")

// MARK: - Shared objects

/// The object that the decorator phases of a shared object bind members on. The classes of
/// `SharedObjects.swift` have no `@JS` members, so it has no API.
public struct JavaScriptObject: Sendable, ~Copyable {}

/// The protocol of the classes with a JavaScript class, which types the members of the JavaScript class chain. The
/// one in core has the hooks as requirements, which `SharedObject` implements. This stand-in leaves them out.
public protocol AnyJavaScriptClass: AnyObject {}

/// The protocol of the shared objects, which the `@SharedObject` expansion adds to a class that doesn't conform yet.
/// The one in core has requirements, which `SharedObject` implements. This stand-in leaves them out.
public protocol AnySharedObject: AnyJavaScriptClass {}

/// The base class of the shared objects, with the hooks that the `@SharedObject` expansion overrides. The base
/// class has no JavaScript class in the chain of a `@SharedObject` class, so `_jsClassType` and `_jsSuperclassType`
/// return `nil`.
open class SharedObject: AnySharedObject {
  public init() {}

  open class var _jsName: String {
    return String(describing: self)
  }

  open class var _jsClassType: (any AnyJavaScriptClass.Type)? {
    return nil
  }

  open class var _jsSuperclassType: (any AnyJavaScriptClass.Type)? {
    return nil
  }

  @JavaScriptActor
  open class func _decorateJSClass(prototype: borrowing JavaScriptObject, in runtime: JavaScriptRuntime) throws {}

  @JavaScriptActor
  open class func _decorateJSClass(constructor: borrowing JavaScriptObject, in runtime: JavaScriptRuntime) throws {}
}

open class SharedRef<RefType>: SharedObject {
  public let ref: RefType

  public init(_ ref: RefType) {
    self.ref = ref
  }
}

@attached(
  member,
  names: named(_jsName),
  named(_jsClassType),
  named(_jsSuperclassType),
  named(_decorateJSClass),
  named(_constructInstance),
  named(_assertTypesConformance)
)
@attached(memberAttribute)
@attached(extension, conformances: AnySharedObject, Sendable)
public macro SharedObject(_ name: String? = nil) =
  #externalMacro(module: "ExpoModulesMacros", type: "SharedObjectMacro")

// MARK: - Views

public class AppContext: @unchecked Sendable {
  public init() {}
}

/// The props of a UIKit view, which `ExpoNativeView` holds.
public final class DecodedViewProps<Props: AnyViewProps> {
  public let props: Props

  public init(props: Props) {
    self.props = props
  }
}

/// The base class of the UIKit views. In core, it's a `UIView` subclass, so it's isolated to the main actor.
@MainActor
open class ExpoNativeView {
  public private(set) weak var appContext: AppContext?

  @usableFromInline
  internal final var decodedProps: AnyObject?

  public init(appContext: AppContext? = nil) {
    self.appContext = appContext
  }
}

@MainActor
public protocol AnyNativeView {
  associatedtype Props: AnyViewProps

  nonisolated static var _jsName: String { get }
}

extension AnyNativeView {
  public nonisolated static var _jsName: String {
    return String(describing: self)
  }
}

@MainActor
public protocol AnyNativeUIKitView: AnyNativeView, AnyObject {
  func didUpdateProps(_ diff: PropsDiff<Props>)
}

extension AnyNativeUIKitView {
  public func didUpdateProps(_ diff: PropsDiff<Props>) {}

  @inlinable
  public var props: Props {
    _read {
      if let decodedProps = unsafeDowncast(self, to: ExpoNativeView.self).decodedProps {
        yield unsafeDowncast(decodedProps, to: DecodedViewProps<Props>.self).props
      } else {
        yield Props()
      }
    }
  }
}

public struct ExpoSwiftUI {}

extension ExpoSwiftUI {
  /// The React children of a SwiftUI view. The stand-in has none.
  public struct Children {
    public init() {}
  }
}

// The conformance is in an extension, so it doesn't isolate the type to the main actor.
extension ExpoSwiftUI.Children: SwiftUI.View {
  public var body: some SwiftUI.View {
    EmptyView()
  }
}

@MainActor
public protocol AnyNativeSwiftUIView: AnyNativeView, SwiftUI.View {
  init(props: Props, children: ExpoSwiftUI.Children, appContext: AppContext?)
}

@attached(
  member,
  names: named(Props),
  named(_jsName),
  named(props),
  named(children),
  named(appContext),
  named(init)
)
@attached(extension, conformances: AnyNativeUIKitView, AnyNativeSwiftUIView)
public macro ExpoView<Props: AnyViewProps>(_ name: String? = nil) =
  #externalMacro(module: "ExpoModulesMacros", type: "ExpoViewMacro")

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

// MARK: - Generic use of views

/// Applies the props to a UIKit view and calls its `didUpdateProps(_:)` through the `AnyNativeUIKitView`
/// requirement, as `applyDecodedProps` does.
@MainActor
public func applying<View: AnyNativeUIKitView>(_ props: View.Props, to view: View) {
  unsafeDowncast(view, to: ExpoNativeView.self).decodedProps = DecodedViewProps(props: props)
  view.didUpdateProps(PropsDiff())
}

/// Creates a SwiftUI view through the `AnyNativeSwiftUIView` requirement, as `ExpoSwiftUI.NativeChild.content`
/// does.
@MainActor
public func makingView<Content: AnyNativeSwiftUIView>(
  _ type: Content.Type,
  props: Content.Props,
  appContext: AppContext?
) -> Content {
  return Content(props: props, children: ExpoSwiftUI.Children(), appContext: appContext)
}

/// The name that a view registers under, from generic code with no isolation.
public func jsName<View: AnyNativeView>(of type: View.Type) -> String {
  return View._jsName
}
