<p>
  <a href="https://docs.expo.dev/modules/">
    <img
      src=".github/resources/expo-modules-macros.svg"
      alt="expo-modules-macros"
      height="64" />
  </a>
</p>

`expo-modules-macros` is the Swift compiler plugin behind the Expo Modules API. It implements the macros that [`expo-modules-core`](https://github.com/expo/expo/tree/main/packages/expo-modules-core) declares, so a module author writes plain Swift declarations and the plugin synthesizes the code that binds them to JavaScript.

The same executable doubles as a source scanner CLI.

# Installation

This package is not meant to be installed directly. It is a dependency of `expo-modules-core`, so every Expo project already has it. The published package contains prebuilt binaries, so consumers never build the plugin themselves:

- `apple/ExpoModulesMacros`: a universal (arm64 + x86_64) macOS binary.
- `apple/ExpoModulesMacros-x64.exe` and `apple/ExpoModulesMacros-arm64.exe`: Windows binaries. The Swift runtime is linked in statically, so they run without a Swift toolchain; they need only Windows system libraries and the Microsoft Visual C++ runtime.

# Macros

- **`@ExpoModule(_ name: String? = nil, classes: [Any.Type] = [])`** on a class. Turns the class into a module: binds its `@JS` members into the module's JavaScript object and resolves the module name from the argument, falling back to the class name. It also synthesizes everything inheriting from `Module` used to provide, so a module class can carry any superclass, or none.
- **`@JS(_ jsName: String? = nil, _ options: JSOptions...)`** on a member of a module or shared object. Marks a function, property or initializer for export. `@ExpoModule` and `@SharedObject` bind each marked member straight into the JavaScript object, with the argument decoding, the call and the result encoding inlined, so there is no dynamic per-call path. The JS name defaults to the Swift name; pass a string to override it. The macro also checks that every type crossing the boundary is convertible in the direction it travels, so a bad type is reported on the author's own declaration rather than on the enclosing type. The `.concurrent` option moves an `async` body off the JavaScript thread while still decoding and encoding on it. A function or initializer can take a closure argument, such as `(Point) throws -> Size` or `(String) async throws -> Data`. JavaScript passes a function for it, and native code can store the closure and call it from any thread. A closure that throws or returns a value blocks the caller until JavaScript returns, and an `async` closure suspends instead and awaits a promise that the function returns. A closure that returns a value must be `throws`, so that an error from JavaScript can reach the caller. A non-throwing `Void` closure returns before JavaScript reads its arguments, so don't change a class instance after passing it to one.
- **`@Event(_ name: String? = nil, sync: Bool = false)`** on a function-typed `var`. Expands the property into a closure that emits the event, so calling the property sends it to JavaScript with the closure's parameter as the payload. The JS name defaults to the property name with a leading `on` stripped. `sync: true` dispatches inline instead of asynchronously.
- **`@SharedObject(_ name: String? = nil)`** on a `SharedObject` subclass. Collects the class's `@JS` members into a class definition that a module exposes through `@ExpoModule(classes:)`.
- **`@Record()`** on a record type. Treats every non-static, non-private, non-computed stored property as a field, with no per-field wrapper, and synthesizes the memberwise initializer, the conversions in both directions, and the `Record` conformance. Requiredness is inferred: a default value makes a field optional, an optional type makes it nullable and optional.
- **`@Union()`** on an enum whose cases each carry one associated value. Models a TypeScript union. Synthesizes the conversions in both directions, a typed accessor per payload type, and the `JavaScriptDecodable` and `JavaScriptEncodable` conformances. Decoding is ordered: the first case whose payload decodes wins, so the more specific case goes first.

How that looks in a module:

```swift
import ExpoModulesCore

@ExpoModule(classes: [Cache.self])
public final class MyModule {
  @JS
  func greet(name: String) -> String {
    "Hi, \(name)"
  }

  @JS("doWork")
  func performWork() async throws { ... }

  @Event
  var onProgress: (ProgressEvent) -> Void
}

@SharedObject
final class Cache: SharedObject {
  @JS
  init(name: String) { ... }

  @JS
  func get(_ key: String) -> String? { ... }
}
```

The author-facing documentation for each macro lives next to its declaration in `expo-modules-core`, in `ios/Core/ExpoModulesMacros.swift`. This repository holds the implementations.

# Scanner

The Swift compiler launches a plugin executable with no arguments and speaks the plugin protocol over stdin, so the binary treats any argument as a scanner invocation instead:

```
ExpoModulesMacros <subcommand> [options] <path> [<path> ...]

subcommands:
  scan-modules   fast scan for top-level @ExpoModule types (autolinking)
  scan-exports   deep scan of the full JS-exported surface (type generation)

options (scan-modules only):
  --define <flag>   treat a conditional compilation flag as set; repeatable
```

Each path is a `.swift` file or a directory, scanned recursively for `.swift` files. `scan-modules` reports each module's `platforms` from the `#if os(...)` conditions around it: the Apple OSes and `Windows`. Both subcommands print a JSON report to stdout, each carrying its own `schemaVersion` so a consumer can check it understands the shape before trusting it. The two versions are independent: the commands serve different consumers and change for different reasons.

# TypeScript wrapper

Node consumers can call the scanner through this package instead of locating the binary and shelling out themselves:

```ts
import { scanModules, scanExports } from 'expo-modules-macros';

const { modules, warnings } = await scanModules(['ios/'], { defines: ['DEBUG'] });
const { exports } = await scanExports(['ios/']);
```

The binary is a compiled executable, so each call still spawns a process. What the wrapper owns is the part consumers would otherwise duplicate: resolving the shipped binary, building the arguments, parsing the JSON, checking `schemaVersion`, and turning a non-zero exit into a `ScannerError`. The result types are hand-written mirrors of the Swift `Codable` types, which is what the version check guards against drifting.

# How the plugin reaches the compiler

`expo-modules-core` declares the macro signatures with `#externalMacro(module: "ExpoModulesMacros", type: …)`. During `pod install`, `expo-modules-autolinking` resolves this package from the core package and appends

```
-Xfrontend -load-plugin-executable -Xfrontend <plugin>/apple/ExpoModulesMacros#ExpoModulesMacros
```

to `OTHER_SWIFT_FLAGS` for `ExpoModulesCore`, every pod that depends on it, and their test specs. Expo's SPM prebuilds pass the same flag when they generate `Package.swift`, so both build systems load the same binary.

On Windows, the compiler loads `apple/ExpoModulesMacros-<arch>.exe` with the same flag. `getScannerBinaryPath()` in the TypeScript wrapper returns the binary for the current platform and architecture.

The module and type names in `#externalMacro` must stay in sync with `apple/Sources/ExpoModulesMacros/Plugin.swift`.

# Development

Requires a toolchain with Swift 6.2 or newer: on macOS 13 or newer that means Xcode 26 or newer, and on Windows the Swift toolchain from swift.org (CI uses 6.4).

```sh
cd apple
swift build
swift test
swift run MacroConsumer
```

`MacroConsumer` is a small program that uses the macros like a client target does: SwiftPM builds the plugin as its dependency and loads it into the compiler. CI also compiles it with `swiftc -load-plugin-executable` against the release binary.

`npm run build` runs `apple/build.js`, which builds the release binary with SwiftPM's native build system (Swift Build, the default since Swift 6.4, doesn't build a macro tool that no target in the package uses).

- On macOS, it builds for arm64 and x86_64, merges the slices into `apple/ExpoModulesMacros` with `lipo`, strips it, and verifies both slices are present. SwiftPM only builds macro tools for the host architecture, so the x86_64 slice is produced by running the toolchain under Rosetta; the script installs Rosetta if it is missing.
- On Windows, it builds for the host architecture only, with the Swift runtime linked in statically and without debug info, and writes `apple/ExpoModulesMacros-<arch>.exe` (`x64` or `arm64`, as Node's `process.arch` names them). It strips the executable with `llvm-strip` from the Swift toolchain and checks the architecture in its header.

The resulting binaries are committed to the repository.

# Releasing

The **Publish** workflow is manual (`workflow_dispatch`) and takes a release type. It builds the Windows binaries on a Windows runner per architecture, then bumps the version, builds the universal macOS binary, and publishes to npm through OIDC trusted publishing. The commit, tag and GitHub release are created only after the publish succeeds, so a failed build leaves the branch untouched.

# Contributing

Contributions are very welcome! Please refer to the guidelines described in the [contributing guide](https://github.com/expo/expo#contributing).
