import SwiftDiagnostics
import SwiftSyntax

/// A macro that treats every stored property as part of its surface, so that a leftover `@Field`
/// from the v1 API has no meaning in it.
internal enum FieldAttributeOwner {
  case record
  case viewProps

  fileprivate var macroName: String {
    switch self {
    case .record:
      return "@Record"
    case .viewProps:
      return "@ViewProps"
    }
  }

  fileprivate var idPrefix: String {
    switch self {
    case .record:
      return "record"
    case .viewProps:
      return "viewprops"
    }
  }

  /// What the macro makes of each stored property.
  fileprivate var memberKind: String {
    switch self {
    case .record:
      return "record property"
    case .viewProps:
      return "prop"
    }
  }

  /// What the name of a stored property sets.
  fileprivate var nameKind: String {
    switch self {
    case .record:
      return "key"
    case .viewProps:
      return "prop name"
    }
  }
}

/// The error for a leftover `@Field`, attached to the attribute itself and carrying a fix-it that
/// deletes it. `@Record` and `@ViewProps` treat every stored property as part of their surface, so
/// the attribute has no meaning there; left in place it would wrap the value in `Field<T>` and the
/// synthesized conversions would be generated against the wrong type. A `@Field` with arguments, such
/// as `@Field(.keyed("borderColor"))`, gets no fix-it: they can set the name, which removing the
/// attribute would change silently, so the message tells the author to rename the property.
internal func fieldAttributeDiagnostic(
  for attribute: AttributeSyntax,
  on varDecl: VariableDeclSyntax,
  in owner: FieldAttributeOwner
) -> Diagnostic {
  let fixIt = FixIt(
    message: FieldFixItMessage("Remove the '@Field' attribute", id: "\(owner.idPrefix)-remove-field"),
    changes: removalChanges(of: attribute)
  )
  let hasArguments = attribute.arguments?.as(LabeledExprListSyntax.self)?.isEmpty == false
  let message = FieldDiagnosticMessage(
    hasArguments
      ? "@Field is no longer used: \(owner.macroName) treats every stored property as a \(owner.memberKind), named after the property. Remove the @Field attribute, and rename the property if its arguments set another \(owner.nameKind)"
      : "@Field is no longer used: \(owner.macroName) treats every stored property as a \(owner.memberKind). Remove the @Field attribute",
    id: "\(owner.idPrefix)-field-attribute"
  )
  return Diagnostic(node: attribute, message: message, fixIts: hasArguments ? [] : [fixIt])
}

private struct FieldDiagnosticMessage: DiagnosticMessage {
  let message: String
  let diagnosticID: MessageID
  let severity: DiagnosticSeverity = .error

  init(_ message: String, id: String) {
    self.message = message
    self.diagnosticID = MessageID(domain: "ExpoModulesMacros", id: id)
  }
}

private struct FieldFixItMessage: FixItMessage {
  let message: String
  let fixItID: MessageID

  init(_ message: String, id: String) {
    self.message = message
    self.fixItID = MessageID(domain: "ExpoModulesMacros", id: id)
  }
}
