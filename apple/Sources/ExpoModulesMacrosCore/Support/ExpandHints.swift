/// What the `expand` command knows about the files that it expands, for the macros that read more than
/// their own declaration. The compiler tells a macro which conformances a class already has, through the
/// `conformingTo` list of its roles. `expand` passes every conformance of the macro declaration for every
/// class, so it sets these hints instead. They are `nil` in the compiler and in the expansion tests.
public enum ExpandHints {
  /// The names of the classes in the expanded files that have a JavaScript class: the classes with
  /// `@JSClass` or `@SharedObject`, and the classes that inherit from one of them. `@JSClass` treats a
  /// class whose superclass has one of these names as a subclass. A superclass in another file or
  /// package isn't in the set, so `expand` shows such a class as a root.
  @TaskLocal public static var jsClassNames: Set<String>?
}
