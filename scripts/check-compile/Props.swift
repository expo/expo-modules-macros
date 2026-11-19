// `@ViewProps` structs that `check-compile.js` compiles in each configuration, and that `main.swift`
// checks at run time.

import Core

// A `public` struct with value props only. With library evolution, the `switch` of the `@inlinable`
// `propSet(for:)` needs a `@frozen` `PropName`. With a default isolation, core can use the struct only
// through `nonisolated` members and conformances.
@ViewProps
public struct PublicProps {
  public var title = ""
  public var count: Int = 1
  public var ratio: Double?
}

// Events only, so `PropName` has no case. One event has no initial value, so the macro generates
// `init()`.
@ViewProps
nonisolated public struct EventsOnlyProps {
  public var onTap: () -> Void = {}
  public var onValueChange: (Int) -> Void
}

// A struct nested in another type, with an initial value that names a static member of that type
// without `Screen.`.
nonisolated public struct Screen {
  static let spacing = 8

  @ViewProps
  public struct NestedProps {
    public var gap: Int = spacing
  }
}

// Initial values that a reset assigns again or reads from `Self()`: a static member without `Self.`,
// a static member named like a parameter of `_resetViewProp`, `#` expressions, a literal on several
// lines, and a property with a `didSet` observer.
@ViewProps
nonisolated struct InitialValueProps {
  static let defaultTitle = "Untitled"
  static let _name = "Named"

  var title: String = defaultTitle
  var name: String = _name
  var source: String = #function
  var line: Int = #line
  var weights: [Double] = [
    0.25,
    0.5, // half
  ]
  var level: Int = 1 {
    didSet {
      levelChanges += 1
    }
  }
  var maybe: Int?

  private(set) var levelChanges = 0
}

// The author's `init()` sets the defaults, so a reset reads them from `Self()`.
@ViewProps
nonisolated struct AuthorInitProps {
  var title: String

  init() {
    title = "set by init()"
  }
}

// Computed props, one with a mutating getter.
@ViewProps
nonisolated struct ComputedProps {
  var storage: Int = 4
  var doubled: Int {
    mutating get { storage * 2 }
    set { storage = newValue / 2 }
  }
  var halved: Int {
    get { storage / 2 }
    set { storage = newValue * 2 }
  }
}

@ViewProps
private struct PrivateProps {
  var title = ""
}

// Free-form props, whose types hold `Any`, so they can't conform to `JavaScriptDecodable`. They decode through
// the free-form methods of `JavaScriptValue`. They aren't `Sendable`, so with a default isolation the struct needs
// `nonisolated`.
@ViewProps
nonisolated public struct FreeFormProps {
  public var extraProps: [String: Any]?
  public var modifiers: [[String: Any]]?
  public var items: [Any] = []
  public var payload: Any = 0
  public var options: [String: Any] = ["key": "default"]
  public var maybe: Any!
}

// Event function types other than a plain closure, and a payload that isn't `Sendable`, which core takes as `sending`,
// so its event declares the parameter `sending`. `_bindEvents(to:)` assigns a closure to each of them.
nonisolated public final class NonSendablePayload: JavaScriptEncodable {
  public var count = 0

  public init() {}
}

// Props that extend other props, which `base` holds. `PublicProps` isn't `Sendable`, so with a default isolation the
// struct needs `nonisolated`. Library evolution checks the `@frozen` `PropName` with a case for the base props, and
// `Client.swift` switches over it.
@ViewProps(extending: PublicProps.self)
nonisolated public struct ExtendingProps {
  public var label = "label"
  public var onSelect: (Int) -> Void
}

// The common props of a family of views, as in `@expo/ui`: free-form props and an event, which an extending struct
// binds through `base`.
@ViewProps
nonisolated public struct CommonProps {
  public var modifiers: [[String: Any]]?
  public var testID: String?
  public var onGlobalEvent: (Int) -> Void
}

// Props that extend props that extend other props, so the base props of the base take the bits above both.
@ViewProps(extending: ExtendingProps.self)
nonisolated struct ChainedProps {
  var level = 3
}

// Events only, extending props with events only, so `PropName` has only the case for the base props, whose
// `PropName` has no case.
@ViewProps(extending: EventsOnlyProps.self)
nonisolated struct ExtendingEventsOnlyProps {
  var onClose: () -> Void
}

// Props that extend the common props, with an `init()` of their own, which doesn't set `base`.
@ViewProps(extending: CommonProps.self)
nonisolated struct StepperProps {
  var value: Int
  var onValueChange: (Int) -> Void

  init() {
    value = 5
    onValueChange = { _ in }
  }
}

// A base named with the type that encloses it.
@ViewProps(extending: Screen.NestedProps.self)
nonisolated struct ExtendingNestedProps {
  var title = ""
}

// A `private` struct that extends a `private` struct, so `base` and the case of `PropName` use a `private` type.
@ViewProps(extending: PrivateProps.self)
private struct ExtendingPrivateProps {
  var count = 0
}

@ViewProps
nonisolated public struct EventKindsProps {
  public var onSendable: @Sendable (Int) -> Void
  public var onMainActor: @MainActor (Int) -> Void
  public var onAsync: (Int) async -> Void
  public var onThrows: (Int) throws -> Void
  public var onNonSendable: (sending NonSendablePayload) -> Void
  // Named like the parameter of `_bindEvents(to:)`, and escaped with backticks.
  public var _events: (Int) -> Void
  public var `default`: () -> Void
}
