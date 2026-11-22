// `@SharedObject` classes that `check-compile.js` compiles in each configuration. Each one conforms to
// `AnySharedObject` through `SharedObject`, so the macro must not add the conformance again.

import Core

@SharedObject
open class ChainRoot: SharedObject {}

// A class without the macro. Swift requires a subclass of an `@unchecked Sendable` class to restate the
// conformance. With `-default-isolation MainActor`, the initializer of a plain subclass of a nonisolated class
// would be isolated to the main actor, which an override can't be, so the class is `nonisolated`.
nonisolated open class ChainMiddle: ChainRoot, @unchecked Sendable {}

@SharedObject
public final class ChainLeaf: ChainMiddle, @unchecked Sendable {}

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
