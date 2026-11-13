import SwiftParser
import SwiftSyntax

/// The JavaScript property key that a `@JS` function or property binds under: a string name, from
/// `@JS("name")` or the Swift name, or a symbol, from `@JS(symbol: ...)`.
///
/// - `@JS(symbol: .iterator)` binds under a well-known symbol, `Symbol.iterator`. The case name is
///   a case of `JavaScriptSymbol.WellKnown`, which the macro declaration type-checks.
/// - `@JS(symbol: "app.id")` binds under the symbol that the global registry holds for the key,
///   `Symbol.for("app.id")`.
internal enum JSMemberKey: Hashable {
  /// The name as written in the string literal, which the generated code puts in a literal again.
  case name(String)
  /// The name of a case of `JavaScriptSymbol.WellKnown`, such as `iterator`.
  case wellKnownSymbol(String)
  /// The registry key, the value of the string literal with its escape sequences decoded.
  case registeredSymbol(String)

  /// The key of a `@JS` member: the `symbol:` argument of the attribute when it has one, else the
  /// string name of the attribute, else `defaultName`.
  init(attribute: AttributeSyntax, defaultName: String) {
    self = symbolKey(of: attribute) ?? .name(jsNameArgument(of: attribute) ?? defaultName)
  }

  var isSymbol: Bool {
    if case .name = self {
      return false
    }
    return true
  }

  /// True for a well-known symbol that an object up the prototype chain of a binding target holds in a
  /// way that an assignment can't shadow:
  /// - `Symbol.hasInstance`, a read-only property of `Function.prototype`, which a shared object
  ///   constructor inherits;
  /// - `Symbol.toStringTag`, an accessor without a setter on the prototype of the base `SharedObject`
  ///   class, which core defines.
  ///
  /// A function under such a key is defined with `defineProperty` before it is bound.
  var isInheritedReadOnly: Bool {
    guard case .wellKnownSymbol(let name) = self else {
      return false
    }
    return name == "hasInstance" || name == "toStringTag"
  }

  /// How diagnostics name the key, as JavaScript code would write it: `name`, `Symbol.iterator` or
  /// `Symbol.for("app.id")`.
  var description: String {
    switch self {
    case .name(let name):
      return name
    case .wellKnownSymbol(let name):
      return "Symbol.\(name)"
    case .registeredSymbol(let key):
      return "Symbol.for(\(swiftStringLiteral(key)))"
    }
  }

  /// The string literal of the `name` of a function bound under the key, as JavaScript gives it to a
  /// method: the string name, or the description of the symbol in brackets, such as
  /// `[Symbol.iterator]` or `[app.id]`. It names the function in an argument count error.
  var functionNameLiteral: String {
    switch self {
    case .name(let name):
      return "\"\(name)\""
    case .wellKnownSymbol(let name):
      return "\"[Symbol.\(name)]\""
    case .registeredSymbol(let key):
      return swiftStringLiteral("[\(key)]")
    }
  }

  /// The expression that the generated code passes as the key: a string literal, or a throwing call
  /// that gets the symbol from the runtime in scope (see `tryPrefix`). A well-known symbol is cached
  /// in the runtime after its first use.
  var expression: String {
    switch self {
    case .name(let name):
      return "\"\(name)\""
    case .wellKnownSymbol(let name):
      return "JavaScriptSymbol.wellKnown(runtime, .\(name))"
    case .registeredSymbol(let key):
      return "JavaScriptSymbol.for(runtime, \(swiftStringLiteral(key)))"
    }
  }

  /// The `try ` that a statement passing `expression` needs, or an empty string for a string key.
  var tryPrefix: String {
    return isSymbol ? "try " : ""
  }
}

/// The spellings of the type of the well-known symbols that a `symbol:` argument can name before the
/// case. Any other base, such as a constant `Keys.iterator` of type `String`, isn't a well-known
/// symbol.
private let wellKnownSymbolTypeNames: Set<String> = [
  "JavaScriptSymbol.WellKnown",
  "ExpoModulesJSI.JavaScriptSymbol.WellKnown",
  "ExpoModulesCore.JavaScriptSymbol.WellKnown",
]

/// The key of a `symbol:` argument, or `nil` when the attribute has none or the argument is neither
/// a case of `JavaScriptSymbol.WellKnown` (`.iterator`, `JavaScriptSymbol.WellKnown.iterator`) nor a
/// string literal without interpolation, which `@JS` reports.
internal func symbolKey(of attribute: AttributeSyntax) -> JSMemberKey? {
  guard let argument = symbolArgument(of: attribute) else {
    return nil
  }
  if let member = argument.expression.as(MemberAccessExprSyntax.self) {
    if let base = member.base, !wellKnownSymbolTypeNames.contains(base.trimmedDescription) {
      return nil
    }
    return .wellKnownSymbol(withoutBackticks(member.declName.baseName.text))
  }
  if let value = argument.expression.as(StringLiteralExprSyntax.self)?.representedLiteralValue {
    return .registeredSymbol(value)
  }
  return nil
}

/// A Swift string literal whose value is `value`. A quote, a backslash and the control characters are
/// escaped, so any value gives a valid literal.
private func swiftStringLiteral(_ value: String) -> String {
  var literal = "\""
  for scalar in value.unicodeScalars {
    switch scalar {
    case "\"":
      literal += "\\\""
    case "\\":
      literal += "\\\\"
    case "\n":
      literal += "\\n"
    case "\r":
      literal += "\\r"
    case "\t":
      literal += "\\t"
    case _ where scalar.value < 0x20 || scalar.value == 0x7F:
      literal += "\\u{\(String(scalar.value, radix: 16))}"
    default:
      literal.unicodeScalars.append(scalar)
    }
  }
  return literal + "\""
}

/// The `symbol:` argument of an attribute, or `nil` when it has none.
internal func symbolArgument(of attribute: AttributeSyntax) -> LabeledExprSyntax? {
  return attribute.arguments?.as(LabeledExprListSyntax.self)?.first { $0.label?.text == "symbol" }
}
