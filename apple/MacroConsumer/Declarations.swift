// Stand-ins for the `expo-modules-core` declarations that the `@ViewProps` expansion refers to. The
// real ones need the JavaScript runtime, which this program doesn't have.

@attached(member, names: named(PropName), named(PropSet), named(_eventNames), named(Diff))
@attached(extension, conformances: AnyViewProps, names: named(allProps), named(propSet))
public macro ViewProps() = #externalMacro(module: "ExpoModulesMacros", type: "ViewPropsMacro")

public protocol AnyViewProps {}

public struct PropsDiff<Props: AnyViewProps> {}
