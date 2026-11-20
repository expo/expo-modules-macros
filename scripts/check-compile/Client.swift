// Uses a props type and a view of the `Fixtures` module, which `check-compile.js` builds with library evolution and
// gives to this module only as its `.swiftinterface`.

import Core
import Fixtures

public func position(of name: PublicProps.PropName) -> Int {
  switch name {
  case .title:
    return 0
  case .count:
    return 1
  case .ratio:
    return 2
  }
}

public func bit(of name: PublicProps.PropName) -> UInt64 {
  return PublicProps.propSet(for: name).rawValue
}

// The `PropName` of props that extend other props has a case with the names of the base props.
public func position(of name: ExtendingProps.PropName) -> Int {
  switch name {
  case .label:
    return 0
  case .base(let name):
    return 1 + position(of: name)
  }
}

public func bit(of name: ExtendingProps.PropName) -> UInt64 {
  return ExtendingProps.propSet(for: name).rawValue
}

public func changedBaseProps(_ changed: ExtendingProps.PropSet) -> Bool {
  return !changed.isDisjoint(with: .base(PublicProps.allProps))
}

// Creates a SwiftUI view of the `Fixtures` module as a SwiftUI preview in another module does, without the app
// context, and reads the app context.
@MainActor
public func previewHasAppContext() -> Bool {
  let view = SliderView(props: PublicProps(), children: ExpoSwiftUI.Children())
  return view.appContext != nil
}
