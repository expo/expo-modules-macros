// Built with the macro plugin, either by SwiftPM as the `MacroConsumer` target or by `swiftc` with
// `-load-plugin-executable` pointing at a release binary, then run. Building proves that the compiler
// loads the plugin and expands the macro; running checks that the expansion is the expected one.

@ViewProps
public struct CardProps {
  public var title: String = ""
  public var radius: Double = 0
  public var onTap: (String) -> Void = { _ in }
}

precondition(CardProps.PropName.allCases.map(\.rawValue) == ["title", "radius"])
precondition(CardProps.propSet(for: .radius) == .radius)
precondition(CardProps.allProps == [.title, .radius])
precondition(CardProps._eventNames == ["onTap"])
print("The plugin loaded and expanded @ViewProps")
