import SwiftIfConfig
import SwiftSyntax

/// The Apple OSes `scan-exports` attributes declarations to, in the order they are reported. Spelled
/// as `os(...)` spells them.
let applePlatforms = ["iOS", "macOS", "tvOS", "watchOS", "visionOS"]

/// The platform names `@available` accepts for each reported OS, including the legacy `OSX`. Other
/// names (`iOSApplicationExtension`, `macCatalyst`, `swift`, …) do not change where a declaration is
/// built for an app, so they are ignored.
private let availabilityPlatformNames: [String: String] = [
  "iOS": "iOS",
  "macOS": "macOS",
  "OSX": "macOS",
  "tvOS": "tvOS",
  "watchOS": "watchOS",
  "visionOS": "visionOS",
]

/// Answers which platforms build a declaration in one file: those whose `#if` evaluation keeps it,
/// less those an `@available` attribute on it or on an enclosing type makes unavailable. The `#if`
/// regions are evaluated once per platform for the whole file.
///
/// A condition the scan cannot answer (`#if DEBUG`, `targetEnvironment`, a non-SDK `canImport`)
/// makes its region inactive on every platform, so a declaration under one is built nowhere.
struct PlatformResolver {
  private let regions: [(platform: String, regions: ConfiguredRegions)]

  init(tree: SourceFileSyntax) {
    regions = applePlatforms.map { platform in
      (platform, tree.configuredRegions(in: ScanBuildConfiguration(platform: platform, defines: [])))
    }
  }

  /// The platforms that build `node`, in `applePlatforms` order. Empty when none does.
  func platforms(of node: some SyntaxProtocol) -> [ExportedPlatform] {
    let availability = Availability(of: node)
    return regions.compactMap { platform, regions in
      guard regions.isActive(node) == .active, !availability.isUnavailable(on: platform) else {
        return nil
      }
      return ExportedPlatform(name: platform, introduced: availability.introduced[platform])
    }
  }
}

/// What the `@available` attributes on a declaration and its enclosing declarations say. A member
/// cannot be more available than the type it is declared in, so the attributes combine: a platform
/// any of them makes unavailable is unavailable, and the latest introduced version wins.
private struct Availability {
  private var unavailable: Set<String> = []
  private var isUnavailableEverywhere = false
  private(set) var introduced: [String: String] = [:]

  init(of node: some SyntaxProtocol) {
    var current: Syntax? = Syntax(node)
    while let decl = current {
      if let attributes = decl.asProtocol(WithAttributesSyntax.self)?.attributes {
        for element in attributes {
          if let attribute = element.as(AttributeSyntax.self),
            attribute.attributeName.trimmedDescription == "available",
            case .availability(let arguments) = attribute.arguments {
            read(arguments)
          }
        }
      }
      current = decl.parent
    }
  }

  func isUnavailable(on platform: String) -> Bool {
    isUnavailableEverywhere || unavailable.contains(platform)
  }

  /// Reads one attribute. The long form names one platform (or `*`) first and then what applies to
  /// it: `@available(iOS, introduced: 16)`, `@available(tvOS, unavailable)`. The shorthand lists
  /// platforms with versions: `@available(iOS 17, macOS 14, *)`.
  private mutating func read(_ arguments: AvailabilityArgumentListSyntax) {
    guard case .token(let first) = arguments.first?.argument else {
      for argument in arguments {
        if case .availabilityVersionRestriction(let restriction) = argument.argument,
          let platform = availabilityPlatformNames[restriction.platform.text],
          let version = restriction.version {
          raiseIntroduced(on: platform, to: version.trimmedDescription)
        }
      }
      return
    }
    let isWildcard = first.tokenKind == .binaryOperator("*")
    let platform = availabilityPlatformNames[first.text]
    guard isWildcard || platform != nil else {
      return
    }
    for argument in arguments.dropFirst() {
      switch argument.argument {
      case .token(let token) where token.text == "unavailable":
        if let platform {
          unavailable.insert(platform)
        } else {
          isUnavailableEverywhere = true
        }
      case .availabilityLabeledArgument(let labeled) where labeled.label.text == "introduced":
        if let platform, case .version(let version) = labeled.value {
          raiseIntroduced(on: platform, to: version.trimmedDescription)
        }
      default:
        continue
      }
    }
  }

  private mutating func raiseIntroduced(on platform: String, to version: String) {
    if let current = introduced[platform], !isVersion(version, laterThan: current) {
      return
    }
    introduced[platform] = version
  }
}

/// Compares two dotted version spellings component by component, treating a missing component as
/// `0`, so `17` and `17.0` are equal.
private func isVersion(_ lhs: String, laterThan rhs: String) -> Bool {
  let left = lhs.split(separator: ".").map { Int($0) ?? 0 }
  let right = rhs.split(separator: ".").map { Int($0) ?? 0 }
  for index in 0..<max(left.count, right.count) {
    let l = index < left.count ? left[index] : 0
    let r = index < right.count ? right[index] : 0
    if l != r {
      return l > r
    }
  }
  return false
}

/// The spelled access modifier of a declaration (`open`, `public`, `package`, `internal`,
/// `fileprivate`, `private`), or `nil` when none is written. A modifier with a detail, like the
/// `private` in `private(set)`, limits only the setter, so it is not the declaration's.
func spelledAccessLevel(of modifiers: DeclModifierListSyntax) -> String? {
  modifiers.first { modifier in
    modifier.detail == nil && accessModifierNames.contains(modifier.name.text)
  }?.name.text
}

private let accessModifierNames: Set<String> = ["open", "public", "package", "internal", "fileprivate", "private"]
