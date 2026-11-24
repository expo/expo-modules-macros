import SwiftSyntax
import SwiftSyntaxMacros

/// A macro that the plugin provides, with the attribute name and the conformances of its declaration in
/// `expo-modules-core`: those of the extension role, and those that only the member role lists.
public struct ProvidedMacro {
  public let name: String
  public let type: Macro.Type
  public var conformances: [TypeSyntax] = []

  /// Every macro of the plugin. The compiler gets the types from `providingMacros`, and `expand`
  /// matches the attributes by name and passes the conformances, so both read this list. swift-syntax
  /// passes one list to every role, so `@JSClass` lists `AnySharedObject`, which only its member role
  /// declares, and its extension role leaves it out.
  public static var all: [ProvidedMacro] {
    [
      ProvidedMacro(name: "OptimizedFunction", type: OptimizedFunctionAttachedMacro.self),
      ProvidedMacro(name: "JS", type: JSMacro.self),
      ProvidedMacro(name: "Event", type: EventMacro.self),
      ProvidedMacro(name: "ExpoModule", type: ExpoModuleMacro.self, conformances: ["AnyModule", "Sendable"]),
      ProvidedMacro(
        name: "SharedObject",
        type: SharedObjectMacro.self,
        conformances: ["AnySharedObject", "Sendable"]
      ),
      ProvidedMacro(
        name: "JSClass",
        type: JSClassMacro.self,
        conformances: ["AnyJavaScriptClass", "AnySharedObject", "JavaScriptDecodable", "Sendable"]
      ),
      ProvidedMacro(name: "Record", type: RecordMacro.self, conformances: ["Record"]),
      ProvidedMacro(
        name: "Union",
        type: UnionMacro.self,
        conformances: ["JavaScriptDecodable", "JavaScriptEncodable"]
      ),
      ProvidedMacro(name: "ViewProps", type: ViewPropsMacro.self, conformances: ["AnyViewProps"]),
      ProvidedMacro(
        name: "ExpoView",
        type: ExpoViewMacro.self,
        conformances: ["AnyNativeUIKitView", "AnyNativeSwiftUIView"]
      ),
    ]
  }
}
