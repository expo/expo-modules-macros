// Uses a props type of the `Props` module, which `check-compile.js` builds with library evolution and
// gives to this module only as its `.swiftinterface`.

import Core
import Props

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
