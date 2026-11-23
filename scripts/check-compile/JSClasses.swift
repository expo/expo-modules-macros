// `@JSClass` classes that `check-compile.js` compiles in each configuration, and whose places in the JavaScript class
// chain `main.swift` checks at run time. The compiler passes the `AnyJavaScriptClass` conformance to the macro only for
// a root, so a root implements the hooks of the protocol and a subclass overrides them.

import Core

// A root without a superclass. `Client.swift` subclasses it in another module.
@JSClass
open class ClassRoot {
  public init() {}
}

// A class without the macro inherits the `_jsClassType` of `ClassRoot`, so core gives it the JavaScript class of
// `ClassRoot`. Swift requires a subclass of an `@unchecked Sendable` class to restate the conformance. The root is
// nonisolated also with `-default-isolation MainActor`, so the initializer of a plain subclass would be isolated to the
// main actor, which an override can't be, and the class is `nonisolated`.
nonisolated open class ClassMiddle: ClassRoot, @unchecked Sendable {}

// Its JavaScript parent is `ClassRoot`, the nearest class above with the macro.
@JSClass
public final class ClassLeaf: ClassMiddle, @unchecked Sendable {}

// Its `_jsClassType` keeps the generic arguments of the class.
@JSClass
open class GenericRoot<Value> {
  public init() {}
}

@JSClass
public final class IntRoot: GenericRoot<Int>, @unchecked Sendable {}

// A root that names the protocol in its clause implements the hooks, and gets only the other conformances.
@JSClass
public final class DeclaredRoot: AnyJavaScriptClass {}

public enum ClassNamespace {
  @JSClass
  public final class Nested {}
}

// A root with a `@JS init` and an instance function that takes an instance of the class, so the expansion constructs
// the class, guards the constructor against a subclass, unwraps `this` with `_native(from:)` and decodes an argument
// of the class.
@JSClass
open class Counter {
  @JS
  public init(start: Double) {}

  @JS
  public func add(_ other: Counter) {}
}

// A `final` root constructs itself without the guard.
@JSClass
public final class FinalCounter {
  @JS
  public init(start: Double) {}

  @JS
  public func reset() {}
}
