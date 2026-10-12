@testable import ExpoModulesScanner
import SwiftParser
import Testing

/// Parses a source string and returns the exported surface the visitor extracts.
private func surface(_ source: String) -> SurfaceVisitor {
  let tree = Parser.parse(source: source)
  let visitor = SurfaceVisitor(file: "Test.swift", tree: tree)
  visitor.walk(tree)
  return visitor
}

/// The platforms an unconditional declaration with no `@available` attribute reports.
private let everyPlatform = applePlatforms.map { ExportedPlatform(name: $0, introduced: nil) }

/// The platforms named in `names`, none with an introduced version.
private func platforms(_ names: String...) -> [ExportedPlatform] {
  names.map { ExportedPlatform(name: $0, introduced: nil) }
}

@Suite("Exports surface: access levels")
struct AccessLevelTests {
  @Test
  func `Reports the spelled access level of declarations and members, or none`() throws {
    let visitor = surface(
      """
      @ExpoModule
      public final class M {
        @JS public func a() {}
        @JS private func b() {}
        @JS fileprivate var c: Int { 0 }
        @JS internal var d = 0
        @JS func e() {}
        @Event private var onChange: () -> Void
      }

      @SharedObject
      final class S: SharedObject {
        @JS private init() {}
      }

      @Record
      fileprivate struct R {
        public var x: Int
        var y: Int
      }

      private enum E: String, Enumerable { case a }
      @Union public enum U { case a(Int) }
      """
    )
    let module = try #require(visitor.modules.first)
    #expect(module.accessLevel == "public")
    #expect(module.functions.map(\.accessLevel) == ["public", "private", nil])
    #expect(module.properties.map(\.accessLevel) == ["fileprivate", "internal"])
    #expect(module.events.map(\.accessLevel) == ["private"])

    let shared = try #require(visitor.sharedObjects.first)
    #expect(shared.accessLevel == nil)
    #expect(shared.initializer?.accessLevel == "private")

    let record = try #require(visitor.records.first)
    #expect(record.accessLevel == "fileprivate")
    #expect(record.properties.map(\.accessLevel) == ["public", nil])

    #expect(visitor.enums.first?.accessLevel == "private")
    #expect(visitor.unions.first?.accessLevel == "public")
  }

  @Test
  func `Does not read a setter's access level as the declaration's`() throws {
    let module = try #require(
      surface(
        """
        @ExpoModule
        final class M {
          @JS private(set) var a = 0
          @JS public private(set) var b = 0
        }
        """
      ).modules.first)
    #expect(module.properties.map(\.accessLevel) == [nil, "public"])
  }
}

@Suite("Exports surface: platforms")
struct PlatformTests {
  @Test
  func `Reports every platform for unconditional declarations and members`() throws {
    let visitor = surface(
      """
      @ExpoModule
      final class M {
        @JS func f(x: Int) {}
        @JS var p = 0
        @Event var onChange: () -> Void
      }
      @SharedObject final class S: SharedObject { @JS init() {} }
      @Record struct R { var x: Int }
      enum E: String, Enumerable { case a }
      @Union enum U { case a(Int) }
      """
    )
    let module = try #require(visitor.modules.first)
    #expect(module.platforms == everyPlatform)
    #expect(module.functions.first?.platforms == everyPlatform)
    #expect(module.properties.first?.platforms == everyPlatform)
    #expect(module.events.first?.platforms == everyPlatform)
    #expect(visitor.sharedObjects.first?.platforms == everyPlatform)
    #expect(visitor.sharedObjects.first?.initializer?.platforms == everyPlatform)
    #expect(visitor.records.first?.platforms == everyPlatform)
    #expect(visitor.records.first?.properties.first?.platforms == everyPlatform)
    #expect(visitor.enums.first?.platforms == everyPlatform)
    #expect(visitor.enums.first?.cases.first?.platforms == everyPlatform)
    #expect(visitor.unions.first?.platforms == everyPlatform)
    #expect(visitor.unions.first?.members.first?.platforms == everyPlatform)
  }

  @Test
  func `Reports members in each branch of an #if with the platforms that build it`() throws {
    let module = try #require(
      surface(
        """
        @ExpoModule
        final class M {
          @JS func everywhere() {}
          #if os(iOS)
          @JS func onIOS() {}
          #elseif os(macOS) || os(tvOS)
          @JS var onMacOrTV = 0
          #else
          @Event var onOther: () -> Void
          #endif
        }
        """
      ).modules.first)

    #expect(module.functions.map(\.name) == ["everywhere", "onIOS"])
    #expect(module.functions.last?.platforms == platforms("iOS"))
    #expect(module.properties.map(\.name) == ["onMacOrTV"])
    #expect(module.properties.first?.platforms == platforms("macOS", "tvOS"))
    #expect(module.events.map(\.name) == ["onOther"])
    #expect(module.events.first?.platforms == platforms("watchOS", "visionOS"))
  }

  @Test
  func `Reports types declared in #if blocks, and their members inherit the conditions`() throws {
    let visitor = surface(
      """
      #if !os(watchOS)
      @ExpoModule
      final class M {
        #if canImport(UIKit)
        @JS func f() {}
        #endif

        #if os(iOS)
        @Record struct Options { var x: Int }
        #endif
      }
      #endif
      """
    )
    let module = try #require(visitor.modules.first)
    #expect(module.platforms == platforms("iOS", "macOS", "tvOS", "visionOS"))
    // UIKit is on iOS, tvOS, watchOS, and visionOS; the enclosing `#if` already excludes watchOS.
    #expect(module.functions.first?.platforms == platforms("iOS", "tvOS", "visionOS"))
    #expect(visitor.records.map(\.name) == ["M.Options"])
    #expect(visitor.records.first?.platforms == platforms("iOS"))
    #expect(visitor.records.first?.properties.first?.platforms == platforms("iOS"))
  }

  @Test
  func `Reports record properties, enum cases, and union members in #if blocks`() throws {
    let visitor = surface(
      """
      @Record struct R {
        var a: Int
        #if os(iOS)
        var b: Int
        #endif
      }
      enum E: String, Enumerable {
        case a
        #if os(tvOS)
        case b
        #endif
      }
      @Union enum U {
        case a(Int)
        #if os(macOS)
        case b(String)
        #endif
      }
      """
    )
    #expect(visitor.records.first?.properties.map(\.platforms) == [everyPlatform, platforms("iOS")])
    #expect(visitor.enums.first?.cases.map(\.platforms) == [everyPlatform, platforms("tvOS")])
    #expect(visitor.unions.first?.members.map(\.platforms) == [everyPlatform, platforms("macOS")])
  }

  @Test
  func `Leaves out what no platform builds`() throws {
    let visitor = surface(
      """
      #if DEBUG
      @Record struct Debug { var x: Int }
      #endif

      @ExpoModule
      final class M {
        #if targetEnvironment(simulator)
        @JS func simulatorOnly() {}
        #endif
        @JS func kept() {}
        @JS @available(*, unavailable) func gone() {}
      }
      """
    )
    #expect(visitor.records.isEmpty)
    #expect(visitor.modules.first?.functions.map(\.name) == ["kept"])
  }

  @Test
  func `Reads introduced versions and unavailable platforms from @available`() throws {
    let module = try #require(
      surface(
        """
        @ExpoModule
        final class M {
          @JS @available(iOS 17.0, macOS 14, *) func shorthand() {}
          @JS @available(iOS, introduced: 16.4) func longForm() {}
          @JS @available(tvOS, unavailable) @available(watchOS, unavailable) func notOnTVOrWatch() {}
          @JS @available(macOS, unavailable) @available(iOS 15, *) func combined() {}
          @JS @available(OSX 13, *) func legacyName() {}
          @JS @available(macCatalyst, unavailable) @available(iOSApplicationExtension, unavailable) func ignored() {}
        }
        """
      ).modules.first)

    let byName = Dictionary(uniqueKeysWithValues: module.functions.map { ($0.name, $0.platforms) })
    #expect(
      byName["shorthand"] == [
        ExportedPlatform(name: "iOS", introduced: "17.0"),
        ExportedPlatform(name: "macOS", introduced: "14"),
        ExportedPlatform(name: "tvOS", introduced: nil),
        ExportedPlatform(name: "watchOS", introduced: nil),
        ExportedPlatform(name: "visionOS", introduced: nil),
      ])
    #expect(byName["longForm"]?.first == ExportedPlatform(name: "iOS", introduced: "16.4"))
    #expect(byName["longForm"]?.count == applePlatforms.count)
    #expect(byName["notOnTVOrWatch"] == platforms("iOS", "macOS", "visionOS"))
    #expect(
      byName["combined"] == [
        ExportedPlatform(name: "iOS", introduced: "15"),
        ExportedPlatform(name: "tvOS", introduced: nil),
        ExportedPlatform(name: "watchOS", introduced: nil),
        ExportedPlatform(name: "visionOS", introduced: nil),
      ])
    #expect(byName["legacyName"]?.dropFirst().first == ExportedPlatform(name: "macOS", introduced: "13"))
    #expect(byName["ignored"] == everyPlatform)
  }

  @Test
  func `Applies the enclosing types' @available to members, keeping the latest version`() throws {
    let visitor = surface(
      """
      @available(iOS 16, *)
      @available(tvOS, unavailable)
      enum Namespace {
        @available(iOS 15, macOS 13, *)
        @ExpoModule
        final class M {
          @JS @available(iOS 17, *) func newer() {}
          @JS func inherited() {}
        }
      }

      @available(iOS 16, *)
      extension Outer {
        @Record struct Options { var x: Int }
      }
      """
    )
    // A nested module is not reported, so the record shows the extension's attribute.
    #expect(visitor.records.first?.platforms.first == ExportedPlatform(name: "iOS", introduced: "16"))

    let shared = surface(
      """
      @available(iOS 16, *)
      @available(tvOS, unavailable)
      enum Namespace {
        @available(iOS 15, macOS 13, *)
        @SharedObject
        final class S: SharedObject {
          @JS @available(iOS 17, *) func newer() {}
          @JS func inherited() {}
        }
      }
      """
    ).sharedObjects.first
    let expected: [ExportedPlatform] = [
      ExportedPlatform(name: "iOS", introduced: "16"),
      ExportedPlatform(name: "macOS", introduced: "13"),
      ExportedPlatform(name: "watchOS", introduced: nil),
      ExportedPlatform(name: "visionOS", introduced: nil),
    ]
    #expect(shared?.platforms == expected)
    #expect(shared?.functions.map(\.name) == ["newer", "inherited"])
    #expect(shared?.functions.first?.platforms.first == ExportedPlatform(name: "iOS", introduced: "17"))
    #expect(shared?.functions.last?.platforms == expected)
  }
}

@Suite("Exports surface: default values")
struct DefaultValueTests {
  @Test
  func `Reports parameter defaults as source text`() throws {
    let module = try #require(
      surface(
        """
        @ExpoModule
        final class M {
          @JS func f(a: Int, b: Int = 1, c: String = "x", d: Mode = .fast, e: [Int] = [1, 2], f: Int? = nil) {}
        }
        """
      ).modules.first)
    #expect(module.functions.first?.parameters.map(\.defaultValue) == [nil, "1", "\"x\"", ".fast", "[1, 2]", "nil"])
  }

  @Test
  func `Reports the initial value of a stored @JS property, not of a computed one`() throws {
    let module = try #require(
      surface(
        """
        @ExpoModule
        final class M {
          @JS var a = 0
          @JS let b: Double = 1.5
          @JS var c: Int = 2 { didSet {} }
          @JS var d: Int { 3 }
          @JS var e: Int
        }
        """
      ).modules.first)
    #expect(module.properties.map(\.defaultValue) == ["0", "1.5", "2", nil, nil])
  }

  @Test
  func `Reports record property defaults`() throws {
    let record = try #require(
      surface(
        """
        @Record struct R {
          var a: Int
          var b: Encoding = .hex
          var c: String? = nil
        }
        """
      ).records.first)
    #expect(record.properties.map(\.defaultValue) == [nil, ".hex", "nil"])
    #expect(record.properties.map(\.isRequired) == [true, false, false])
  }

  @Test
  func `Reports initializer parameter defaults`() throws {
    let shared = try #require(
      surface(
        """
        @SharedObject final class S: SharedObject {
          @JS init(size: Int = 10) {}
        }
        """
      ).sharedObjects.first)
    #expect(shared.initializer?.parameters.map(\.defaultValue) == ["10"])
  }
}

@Suite("Exports surface: deprecation")
struct DeprecationTests {
  /// The deprecation each platform of a function reports, keyed by platform name.
  private func deprecations(_ function: ExportedFunction) -> [String: ExportedDeprecation?] {
    Dictionary(uniqueKeysWithValues: function.platforms.map { ($0.name, $0.deprecated) })
  }

  @Test
  func `Reports a deprecation on every platform for the * form`() throws {
    let module = try #require(
      surface(
        """
        @ExpoModule
        final class M {
          @JS @available(*, deprecated) func bare() {}
          @JS @available(*, deprecated, message: "Use the async variant.") func withMessage() {}
          @JS @available(*, deprecated, renamed: "newName") func renamed() {}
          @JS func current() {}
        }
        """
      ).modules.first)

    #expect(module.functions[0].platforms.allSatisfy { $0.deprecated == ExportedDeprecation() })
    #expect(
      module.functions[1].platforms.allSatisfy {
        $0.deprecated == ExportedDeprecation(message: "Use the async variant.")
      })
    #expect(module.functions[2].platforms.allSatisfy { $0.deprecated == ExportedDeprecation(renamed: "newName") })
    #expect(module.functions[3].platforms.allSatisfy { $0.deprecated == nil })
  }

  @Test
  func `Reports per-platform deprecated and obsoleted versions`() throws {
    let module = try #require(
      surface(
        """
        @ExpoModule
        final class M {
          @JS
          @available(iOS, introduced: 13, deprecated: 16, obsoleted: 18, message: "Gone soon.")
          @available(macOS, deprecated, renamed: "other(value:)")
          @available(tvOS, obsoleted: 17)
          func f() {}
        }
        """
      ).modules.first)

    let byPlatform = deprecations(try #require(module.functions.first))
    #expect(byPlatform["iOS"] == ExportedDeprecation(since: "16", obsoleted: "18", message: "Gone soon."))
    #expect(byPlatform["macOS"] == ExportedDeprecation(renamed: "other(value:)"))
    #expect(byPlatform["tvOS"] == ExportedDeprecation(obsoleted: "17"))
    #expect(byPlatform["watchOS"] == .some(nil))
    #expect(module.functions.first?.platforms.first?.introduced == "13")
  }

  @Test
  func `Merges a platform deprecation into the * one`() throws {
    let module = try #require(
      surface(
        """
        @ExpoModule
        final class M {
          @JS
          @available(*, deprecated, message: "Do not use.")
          @available(iOS, deprecated: 15)
          func f() {}
        }
        """
      ).modules.first)

    let byPlatform = deprecations(try #require(module.functions.first))
    #expect(byPlatform["iOS"] == ExportedDeprecation(since: "15", message: "Do not use."))
    #expect(byPlatform["macOS"] == ExportedDeprecation(message: "Do not use."))
  }

  @Test
  func `Reads deprecation from the declaration itself, not from enclosing types`() throws {
    let visitor = surface(
      """
      @available(*, deprecated)
      @SharedObject
      final class S: SharedObject {
        @JS func f() {}
      }
      @Record struct R {
        @available(iOS, deprecated: 17, message: "Unused.")
        var x: Int
      }
      enum E: String, Enumerable {
        @available(*, deprecated, renamed: "b")
        case a
        case b
      }
      """
    )
    #expect(visitor.sharedObjects.first?.platforms.allSatisfy { $0.deprecated == ExportedDeprecation() } == true)
    #expect(visitor.sharedObjects.first?.functions.first?.platforms.allSatisfy { $0.deprecated == nil } == true)
    #expect(
      visitor.records.first?.properties.first?.platforms.first?.deprecated
        == ExportedDeprecation(since: "17", message: "Unused."))
    #expect(
      visitor.enums.first?.cases.map { $0.platforms.first?.deprecated } == [
        ExportedDeprecation(renamed: "b"), nil,
      ])
  }
}
