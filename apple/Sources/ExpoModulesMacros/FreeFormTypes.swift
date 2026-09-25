import SwiftSyntax

/// Recognition of the free-form (`Any`-bearing) boundary types and the spellings the macros emit or
/// suggest for them. None of these types can conform to the JS codable protocols (`Any` can't conform
/// to a protocol, and the container conditional conformances require the element/value to conform), so
/// they can't cross the boundary through the usual `T.decode` / `T.encode` path. Instead they're
/// accepted **only** in decode position (function/constructor arguments), decoded through a dedicated
/// `JavaScriptValue.decodeAny…` entry point; a free-form return or getter is rejected, since there's
/// no free-form encode.
///
/// Shared across the macro pipeline: `TypeConformanceAssertion` skips them, `MacroHelpers.decodeCall`
/// reroutes their decode, and `JSMacro` uses them for the steering diagnostics.
///
/// `@Record` accepts a property whose type mentions `Any` anywhere (`Any?`, `[String: Any]?`,
/// `[String: [Any]]`, …) and converts it on the JS-value paths without `decode`/`encode`: the three
/// free-form shapes, optionally wrapped in one optional, use the dedicated `JavaScriptValue.decodeAny…`
/// and `encodeAny…` methods, and every other type uses the generic `decodeAny(_:as:in:)` and
/// `encodeAny(_:in:)`.

/// The free-form boundary types: an untyped value (`Any`), an untyped array (`[Any]`), and an untyped
/// string-keyed dictionary (`[String: Any]`). Matched by whitespace-normalized spelling so
/// `[String: Any]` and `[String : Any]` both count.
private let freeFormBoundaryTypes: Set<String> = ["Any", "[Any]", "[String:Any]"]

/// The `JavaScriptValue.decodeAny…` method the binding calls to decode a free-form argument, keyed by
/// the free-form type's normalized spelling. `nil` for any non-free-form type.
private let freeFormDecodeMethods: [String: String] = [
  "Any": "decodeAny",
  "[Any]": "decodeAnyArray",
  "[String:Any]": "decodeAnyDictionary",
]

/// The type-safe alternative a free-form type's diagnostic steers to: the same shape with the `Any`
/// element replaced by `JavaScriptValue`, which conforms to the codable protocols. Keyed by the
/// free-form type's normalized spelling; spelled with conventional spacing for the message.
private let typedFreeFormReplacements: [String: String] = [
  "Any": "JavaScriptValue",
  "[Any]": "[JavaScriptValue]",
  "[String:Any]": "[String: JavaScriptValue]",
]

/// True when a boundary type (as written) is one of the free-form spellings, ignoring internal
/// whitespace so `[String: Any]` and `[String :Any]` both match. Optionals are not free-form here: a
/// trailing `?` would route through `Optional.decode`, which free-form can't satisfy, so an optional
/// free-form type isn't recognized and stays a normal (failing) assertion.
internal func isFreeFormBoundaryType(_ type: String) -> Bool {
  return freeFormBoundaryTypes.contains(normalizedTypeSpelling(type))
}

/// The `JavaScriptValue.decodeAny…` method name for a free-form boundary type, or `nil` when the type
/// isn't free-form. The binding emits `JavaScriptValue.<method>(arguments.unownedValue(at:), in:)` in
/// place of the type's own `.decode`.
internal func freeFormDecodeMethod(for type: String) -> String? {
  return freeFormDecodeMethods[normalizedTypeSpelling(type)]
}

/// The type-safe alternative to suggest in place of a free-form type (its `Any` element replaced by
/// `JavaScriptValue`), or `nil` when the type isn't free-form.
internal func typedFreeFormReplacement(for type: String) -> String? {
  return typedFreeFormReplacements[normalizedTypeSpelling(type)]
}

/// A type spelling with all whitespace removed, so spelling variations of the same type
/// (`[String: Any]` vs `[String :Any]`) compare equal.
private func normalizedTypeSpelling(_ type: String) -> String {
  return type.filter { !$0.isWhitespace }
}

/// True when a type mentions `Any` anywhere in its spelling, at any nesting depth: `Any`, `[Any]?`,
/// `[String: Any]`, `Dictionary<String, [Any]>`, `[Int: Any]`, and so on. Such a type can't conform to
/// the JS codable protocols.
internal func mentionsFreeFormAny(_ type: TypeSyntax) -> Bool {
  let finder = AnyTypeFinder(viewMode: .sourceAccurate)
  finder.walk(type)
  return finder.found
}

/// True when a type mentioning `Any` is built only from `Any`, arrays, `String`-keyed dictionaries and
/// optionals, in any nesting (`[String: [Any]]?`, `[[String: Any]]`, …). Those are the only shapes the
/// free-form conversions produce and accept, so any other type holding `Any` (`[Int: Any]`,
/// `Set<[String: Any]>`, a user generic `Box<Any>`) could never convert.
internal func isConvertibleFreeFormType(_ type: TypeSyntax) -> Bool {
  if isAnyType(type) {
    return true
  }
  if let wrapped = optionalWrappedType(type) {
    return isConvertibleFreeFormType(wrapped)
  }
  if let element = arrayElementType(type) {
    return isConvertibleFreeFormType(element)
  }
  if let value = stringKeyedDictionaryValueType(type) {
    return isConvertibleFreeFormType(value)
  }
  return false
}

/// The three free-form shapes that have dedicated conversions.
internal enum FreeFormShape {
  case any
  case array
  case dictionary
}

/// The free-form shape a type has exactly (`Any`, `[Any]` or `[String: Any]`, in any spelling), or
/// `nil` for every other type, including nested and optional ones.
internal func freeFormShape(of type: TypeSyntax) -> FreeFormShape? {
  if isAnyType(type) {
    return .any
  }
  if let element = arrayElementType(type), isAnyType(element) {
    return .array
  }
  if let value = stringKeyedDictionaryValueType(type), isAnyType(value) {
    return .dictionary
  }
  return nil
}

/// True when the type is `Any` itself, spelled `Any` or `Swift.Any` (not `AnyObject`, `AnyHashable` or
/// a generic).
internal func isAnyType(_ type: some SyntaxProtocol) -> Bool {
  if let identifier = type.as(IdentifierTypeSyntax.self) {
    return identifier.name.text == "Any" && identifier.genericArgumentClause == nil
  }
  if let member = type.as(MemberTypeSyntax.self),
    member.name.text == "Any",
    member.genericArgumentClause == nil,
    let base = member.baseType.as(IdentifierTypeSyntax.self) {
    return base.name.text == "Swift"
  }
  return false
}

/// The element type of `[T]` or `Array<T>`, or `nil` for any other type.
private func arrayElementType(_ type: TypeSyntax) -> TypeSyntax? {
  if let array = type.as(ArrayTypeSyntax.self) {
    return array.element
  }
  guard let arguments = genericArguments(of: type, named: "Array"), arguments.count == 1 else {
    return nil
  }
  return arguments[0]
}

/// The value type of `[String: V]` or `Dictionary<String, V>`, or `nil` for any other type, including a
/// dictionary with a different key type.
private func stringKeyedDictionaryValueType(_ type: TypeSyntax) -> TypeSyntax? {
  if let dictionary = type.as(DictionaryTypeSyntax.self) {
    return isStringType(dictionary.key) ? dictionary.value : nil
  }
  guard let arguments = genericArguments(of: type, named: "Dictionary"), arguments.count == 2 else {
    return nil
  }
  return isStringType(arguments[0]) ? arguments[1] : nil
}

/// The type arguments of a generic type spelled `<name><…>` (or `Swift.<name><…>`), or `nil` when the
/// type has another name or no type arguments.
private func genericArguments(of type: TypeSyntax, named name: String) -> [TypeSyntax]? {
  let clause: GenericArgumentClauseSyntax?
  if let identifier = type.as(IdentifierTypeSyntax.self), identifier.name.text == name {
    clause = identifier.genericArgumentClause
  } else if let member = type.as(MemberTypeSyntax.self),
    member.name.text == name,
    member.baseType.as(IdentifierTypeSyntax.self)?.name.text == "Swift" {
    clause = member.genericArgumentClause
  } else {
    return nil
  }
  guard let clause else {
    return nil
  }
  var types: [TypeSyntax] = []
  for argument in clause.arguments {
    guard case .type(let type) = argument.argument else {
      return nil
    }
    types.append(type)
  }
  return types
}

/// True when the type is `String` or `Swift.String`.
private func isStringType(_ type: TypeSyntax) -> Bool {
  if let identifier = type.as(IdentifierTypeSyntax.self) {
    return identifier.name.text == "String" && identifier.genericArgumentClause == nil
  }
  if let member = type.as(MemberTypeSyntax.self), member.name.text == "String" {
    return member.baseType.as(IdentifierTypeSyntax.self)?.name.text == "Swift"
  }
  return false
}

/// Walks a type looking for `Any` (or `Swift.Any`) anywhere inside it.
private final class AnyTypeFinder: SyntaxVisitor {
  var found = false

  override func visit(_ node: IdentifierTypeSyntax) -> SyntaxVisitorContinueKind {
    if isAnyType(node) {
      found = true
      return .skipChildren
    }
    return .visitChildren
  }

  override func visit(_ node: MemberTypeSyntax) -> SyntaxVisitorContinueKind {
    if isAnyType(node) {
      found = true
      return .skipChildren
    }
    return .visitChildren
  }
}
