/// What the `expand` command knows about the files that it expands, for the macros that read more than
/// their own declaration. The compiler tells a macro which conformances a class already has, through the
/// `conformingTo` list of its roles. `expand` passes every conformance of the macro declaration for every
/// class, so it sets these hints instead. They are `nil` in the compiler and in the expansion tests.
public struct ExpandHints: Sendable {
  /// The names of the classes in the expanded files that have a JavaScript class: the classes with
  /// `@JSClass` or `@SharedObject`, and the classes that inherit from one of them or from a shared
  /// object base. `@JSClass` treats a class whose superclass has one of these names as a subclass. A
  /// superclass in another file or package isn't in the set, so `expand` shows such a class as a root.
  public var jsClassNames: Set<String>

  /// The names of the classes in the expanded files that are shared objects: the classes with
  /// `@SharedObject`, and the classes that inherit from one of them or from `SharedObject` or `SharedRef`.
  /// `@JSClass` reports a class whose superclass has one of these names.
  public var sharedObjectNames: Set<String>

  public init(jsClassNames: Set<String>, sharedObjectNames: Set<String>) {
    self.jsClassNames = jsClassNames
    self.sharedObjectNames = sharedObjectNames
  }

  /// The hints of the files that `expand` expands now.
  @TaskLocal public static var current: ExpandHints?
}
