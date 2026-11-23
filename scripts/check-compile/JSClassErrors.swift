// `@JSClass` classes that inherit from shared objects, which the macro must report. `check-compile.js` type-checks
// this file on its own and expects an error on each line after an `expect-error` comment, and on no other line. The
// compiler leaves `AnySharedObject` out of the conformances of the member role for such a class, also when the
// superclass doesn't name `SharedObject`.

import Core

@SharedObject
open class Store: SharedObject {}

open class PlainStore: SharedObject, @unchecked Sendable {}

// expect-error
@JSClass
public final class BelowSharedObject: Store, @unchecked Sendable {}

// expect-error
@JSClass
public final class BelowPlainSharedObject: PlainStore, @unchecked Sendable {}

// A chain of `@JSClass` classes isn't reported.
@JSClass
open class Root {}

@JSClass
public final class Leaf: Root, @unchecked Sendable {}
