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
  public var onChange: (Int) -> Void
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
