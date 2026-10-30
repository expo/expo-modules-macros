// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import CompilerPluginSupport
import Foundation
import PackageDescription

let package = Package(
  name: "ExpoModulesMacros",
  platforms: [.macOS(.v13)],
  products: [
    // Lets a SwiftPM package depend on the macros, so the compiler builds and loads the plugin from
    // source, with no `-load-plugin-executable` flag. A target that declares the macros with
    // `#externalMacro(module: "ExpoModulesMacros", ...)` depends on this product, and the targets that
    // depend on it get the plugin too. CocoaPods builds keep loading the prebuilt binary. The name
    // differs from the macro target's, because SwiftPM already has a product of that name for it.
    .library(name: "ExpoModulesMacrosPlugin", targets: ["ExpoModulesMacros"])
  ],
  dependencies: [
    .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "604.0.0-latest")
  ],
  targets: [
    // The plugin executable doubles as the scanner CLI: the compiler launches it without arguments
    // and speaks the plugin protocol over stdin, while an invocation with arguments dispatches into
    // `ScannerCLI` (see the entry point in Plugin.swift). Sharing the binary keeps the package to a
    // single shipped executable; the scanner adds little on top of the SwiftSyntax the macros
    // already link.
    .macro(
      name: "ExpoModulesMacros",
      dependencies: [
        "ExpoModulesCLI",
        .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
        .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
        // For `expand`, which runs the macros in process.
        .product(name: "SwiftSyntaxMacroExpansion", package: "swift-syntax"),
        .product(name: "SwiftParser", package: "swift-syntax"),
        .product(name: "SwiftParserDiagnostics", package: "swift-syntax"),
        .product(name: "SwiftBasicFormat", package: "swift-syntax"),
      ],
      path: "apple/Sources/ExpoModulesMacros"
    ),
    .target(
      name: "ExpoModulesCLI",
      dependencies: [
        .product(name: "SwiftSyntax", package: "swift-syntax"),
        .product(name: "SwiftParser", package: "swift-syntax"),
        .product(name: "SwiftIfConfig", package: "swift-syntax"),
      ],
      path: "apple/Sources/ExpoModulesCLI"
    ),
  ]
)

// The Tests directory is excluded from the published npm package,
// so only declare the test target when building from the repository.
if FileManager.default.fileExists(atPath: Context.packageDirectory + "/apple/Tests") {
  package.targets.append(
    .testTarget(
      name: "ExpoModulesMacrosTests",
      dependencies: [
        "ExpoModulesMacros",
        "ExpoModulesCLI",
        .product(name: "SwiftSyntaxMacrosGenericTestSupport", package: "swift-syntax"),
      ],
      path: "apple/Tests/ExpoModulesMacrosTests"
    )
  )
  package.targets.append(
    .testTarget(
      name: "ExpoModulesCLITests",
      dependencies: [
        "ExpoModulesCLI",
        .product(name: "SwiftParser", package: "swift-syntax"),
      ],
      path: "apple/Tests/ExpoModulesCLITests"
    )
  )
}
