// `@SharedObject` classes that `check-compile.js` compiles in each configuration, and whose places in the JavaScript
// class chain `main.swift` checks at run time. Each one conforms to `AnySharedObject` through `SharedObject`, so the
// macro must not add the conformance again.

import Core

// The root of a chain, so its JavaScript parent is the base class. `Client.swift` subclasses it in another module.
@SharedObject
open class ChainRoot: SharedObject {}

// A class without the macro inherits the `_jsClassType` of `ChainRoot`, so core gives it the JavaScript class of
// `ChainRoot`. Swift requires a subclass of an `@unchecked Sendable` class to restate the conformance. With
// `-default-isolation MainActor`, the initializer of a plain subclass of a nonisolated class would be isolated to
// the main actor, which an override can't be, so the class is `nonisolated`.
nonisolated open class ChainMiddle: ChainRoot, @unchecked Sendable {}

// Its JavaScript parent is `ChainRoot`, the nearest class above with the macro.
@SharedObject
public final class ChainLeaf: ChainMiddle, @unchecked Sendable {}

// Its `_jsClassType` keeps the generic arguments of the class.
@SharedObject
open class GenericBox<Value>: SharedObject {}

@SharedObject
public final class IntBox: GenericBox<Int>, @unchecked Sendable {}

@SharedObject
public final class NumberRef: SharedRef<Double> {}

public enum Namespace {
  @SharedObject
  public final class Nested: SharedObject {}
}

@SharedObject
public final class ThrowingObject: SharedObject {
  @JS
  public init(value: Double, limit: Int = 10) throws {}
}
