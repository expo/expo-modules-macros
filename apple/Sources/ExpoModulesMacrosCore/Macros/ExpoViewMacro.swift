import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

/// Member and extension macro applied to an `ExpoNativeView` subclass or to a SwiftUI view struct, binding it to its
/// props type. The class form:
///
///   @ExpoView<CardProps>
///   final class CardView: ExpoNativeView {
///     func didUpdateProps(_ diff: CardProps.Diff) {
///       if diff.changed(.color) {
///         backgroundColor = props.color
///       }
///     }
///   }
///
/// The props type is the attribute's **generic argument**, so it sits in type position: no
/// `.self` metatype to write, and the macro reads it straight off the attribute's
/// `genericArgumentClause`. Core's declaration constrains the parameter
/// (`macro ExpoView<Props: AnyViewProps>()`), so passing a type that isn't a props type is a
/// compile error at the author's own line ("requires that 'X' conform to 'AnyViewProps'")
/// rather than a macro diagnostic. This macro therefore validates nothing about the props type.
///
/// The expansion is a typealias and a conformance:
///
///   public typealias Props = CardProps
///   extension CardView: AnyNativeUIKitView {}
///
/// The struct form is a SwiftUI view. Core keeps the props and the React children and creates the struct again
/// with them, so the macro adds both as constants and the initializer that core calls:
///
///   @ExpoView<SliderProps>
///   struct SliderView: View {
///     var body: some View {
///       Slider(value: .constant(props.value))
///     }
///   }
///
/// expands to:
///
///   public typealias Props = SliderProps
///   public let props: Props
///   public let children: ExpoSwiftUI.Children
///   public init(props: Props, children: ExpoSwiftUI.Children) {
///     self.props = props
///     self.children = children
///   }
///   extension SliderView: AnyNativeSwiftUIView {}
///
/// The struct must name `View` in its inheritance clause, and it can't declare members with these names.
/// The view registers under its class name. Pass `@ExpoView<CardProps>("FancyCard")` to override it,
/// and the expansion also gets a `_jsName` static that core reads in place of the class name:
///
///   public nonisolated static let _jsName = "FancyCard"
///
/// There is **no view definition**: no `ViewDefinition`, no `View(…) { }` builder, no `Props(_:)` or
/// `Events(_:)` element. Core reaches the view through the conformance to `AnyNativeUIKitView` or
/// `AnyNativeSwiftUIView`, which refine `AnyNativeView`: it reads the props type from the `Props`
/// typealias, which satisfies the protocol's associated type, and the
/// event names from the props type's own `_eventNames` (synthesized by `@ViewProps`). Both are
/// static, so no builder has to be evaluated.
///
/// Views also get no `_decorateView` hook: `_decorateModule` and `_decorateSharedObject` exist to bind
/// members into a JS object, and a view has no such object. Props reach a view through Fabric's
/// mounting layer, not a JS call, so a view's runtime entry point is the props update hook.
///
/// `didUpdateProps` is an `AnyNativeUIKitView` requirement with a default in core, not synthesized here.
/// It isn't an `override`: `ExpoNativeView` has no such method, because its parameter type depends on
/// the props type.
public struct ExpoViewMacro: MemberMacro, ExtensionMacro {
  public static func expansion(
    of node: AttributeSyntax,
    providingMembersOf declaration: some DeclGroupSyntax,
    conformingTo protocols: [TypeSyntax],
    in context: some MacroExpansionContext
  ) throws -> [DeclSyntax] {
    if let structDecl = declaration.as(StructDeclSyntax.self) {
      return try swiftUIViewMembers(of: node, structDecl: structDecl)
    }
    guard let classDecl = declaration.as(ClassDeclSyntax.self) else {
      throw MacroExpansionErrorMessage("@ExpoView can only be applied to a class or a struct")
    }

    guard inheritsFromAny(classDecl, names: expoViewBaseClassNames) else {
      throw DiagnosticsError(diagnostics: [missingBaseClassDiagnostic(for: classDecl)])
    }

    // A generic view can't be registered: `@ExpoModule(views: [CardView.self])` on a generic type
    // fails with "generic parameter 'T' could not be inferred", and the props type ignores the
    // parameter anyway. Reject it here, at the author's line, rather than at the registration site.
    // `@ViewProps` rejects generic props types for the same reason.
    if classDecl.genericParameterClause != nil {
      throw MacroExpansionErrorMessage(
        "@ExpoView does not support generic classes: a view registered with @ExpoModule(views:) must be concrete"
      )
    }

    // The expansion is a `Props` typealias, so a member of that name already on the class collides.
    // Left alone, the compiler reports "invalid redeclaration of 'Props'" positioned inside the
    // macro expansion, which is code the author never wrote. Name it here instead.
    if let existing = existingPropsMemberKind(in: classDecl.memberBlock) {
      throw MacroExpansionErrorMessage(
        "@ExpoView synthesizes a `Props` typealias, but this class already declares a \(existing) named 'Props'. Rename it"
      )
    }

    // The props type is the attribute's generic argument. Core's declaration is generic, so a bare
    // `@ExpoView` never reaches expansion: it fails type-checking first with "generic parameter
    // 'Props' could not be inferred". This diagnostic covers the case where the macro is declared
    // differently than core declares it, so the author still gets a message naming the attribute.
    guard let propsType = genericArgument(of: node) else {
      throw MacroExpansionErrorMessage(
        "@ExpoView requires its props type as a generic argument, as in `@ExpoView<MyViewProps>`"
      )
    }

    // Reported without throwing, so the class still gets its members and conformance.
    if let diagnostic = didUpdatePropsDiagnostic(in: classDecl.memberBlock, propsType: propsType) {
      context.diagnose(diagnostic)
    }

    var emitted: [DeclSyntax] = [
      """
      public typealias Props = \(raw: propsType)
      """
    ]

    // `AnyNativeView` defaults `_jsName` to the type name, so it's emitted only for an override.
    // `nonisolated`, because the protocol is `@MainActor` and core reads the name off the main actor.
    if let jsName = jsNameArgument(of: node) {
      emitted.append("public nonisolated static let _jsName = \"\(raw: jsName)\"")
    }
    return emitted
  }

  public static func expansion(
    of node: AttributeSyntax,
    attachedTo declaration: some DeclGroupSyntax,
    providingExtensionsOf type: some TypeSyntaxProtocol,
    conformingTo protocols: [TypeSyntax],
    in context: some MacroExpansionContext
  ) throws -> [ExtensionDeclSyntax] {
    // A type that the member macro rejects gets no conformance either: the member macro has already
    // reported the error, and a conformance without the `Props` typealias would only add a second
    // error about the associated type.
    let conformance: String
    if let structDecl = declaration.as(StructDeclSyntax.self) {
      guard isValidSwiftUIView(structDecl), genericArgument(of: node) != nil else {
        return []
      }
      conformance = swiftUIViewProtocolName
    } else if let classDecl = declaration.as(ClassDeclSyntax.self),
      inheritsFromAny(classDecl, names: expoViewBaseClassNames),
      classDecl.genericParameterClause == nil,
      existingPropsMemberKind(in: classDecl.memberBlock) == nil,
      genericArgument(of: node) != nil
    {
      conformance = uiKitViewProtocolName
    } else {
      return []
    }
    guard !inheritsProtocol(named: conformance, in: declaration) else {
      return []
    }
    let ext: DeclSyntax = """
      extension \(type.trimmed): \(raw: conformance) {}
      """
    guard let extDecl = ext.as(ExtensionDeclSyntax.self) else {
      return []
    }
    return [extDecl]
  }
}

// MARK: - didUpdateProps

/// The warning for `didUpdateProps` methods of which none matches the `AnyNativeUIKitView` requirement, attached to the
/// first one, or `nil` when one matches or there is none. Core calls the requirement. A method with another parameter
/// label or type, with `async` or `throws`, with a result or with generic parameters is a separate overload, so the
/// default that does nothing runs instead, and Swift reports nothing. It's a warning, because the macro can't resolve
/// a type alias that names the right type.
///
/// The fix-it changes only the parameter, so it's offered only when the parameter is the one difference: removing
/// `async` or `throws` could break the method's body.
private func didUpdatePropsDiagnostic(in memberBlock: MemberBlockSyntax, propsType: String) -> Diagnostic? {
  let methods = memberBlock.members.compactMap { $0.decl.as(FunctionDeclSyntax.self) }.filter { method in
    method.name.text == "didUpdateProps"
      && !method.modifiers.contains { [.keyword(.static), .keyword(.class)].contains($0.name.tokenKind) }
  }
  guard let method = methods.first,
    !methods.contains(where: { hasDidUpdatePropsShape($0) && hasDidUpdatePropsParameter($0, propsType: propsType) })
  else {
    return nil
  }
  let expectedType = "\(propsType).Diff"
  var fixIts: [FixIt] = []
  let parameters = method.signature.parameterClause.parameters
  if hasDidUpdatePropsShape(method), parameters.count == 1, let parameter = parameters.first {
    let parameterName = parameter.secondName ?? parameter.firstName
    let newParameter =
      parameter
      .with(\.firstName, .wildcardToken(trailingTrivia: .space))
      .with(\.secondName, parameterName.with(\.leadingTrivia, []).with(\.trailingTrivia, []))
      .with(
        \.type,
        TypeSyntax(stringLiteral: expectedType)
          .with(\.leadingTrivia, parameter.type.leadingTrivia)
          .with(\.trailingTrivia, parameter.type.trailingTrivia)
      )
    fixIts.append(
      FixIt(
        message: ExpoViewFixItMessage(
          "Change the parameter to '_ \(parameterName.text): \(expectedType)'",
          id: "expoview-fix-did-update-props"
        ),
        changes: [.replace(oldNode: Syntax(parameter), newNode: Syntax(newParameter))]
      )
    )
  }
  return Diagnostic(
    node: method.name,
    message: ExpoViewDiagnosticMessage(
      "'didUpdateProps' never runs, because it doesn't match the method that core calls: 'func didUpdateProps(_ diff: \(expectedType))', which isn't 'async', doesn't throw and returns nothing. Change the method to match it",
      id: "expoview-did-update-props-signature",
      severity: .warning
    ),
    fixIts: fixIts
  )
}

/// Whether the method has the shape of the `AnyNativeUIKitView` requirement apart from its parameters: it isn't
/// `async`, doesn't throw, has no generic parameters and returns nothing.
private func hasDidUpdatePropsShape(_ method: FunctionDeclSyntax) -> Bool {
  let effects = method.signature.effectSpecifiers
  guard effects?.asyncSpecifier == nil, effects?.throwsClause == nil, method.genericParameterClause == nil else {
    return false
  }
  guard let returnType = method.signature.returnClause?.type else {
    return true
  }
  let type = withoutParentheses(returnType)
  if let tuple = type.as(TupleTypeSyntax.self) {
    return tuple.elements.isEmpty
  }
  return ["Void", "Swift.Void"].contains(type.trimmedDescription)
}

/// Whether the method has the parameter of the `AnyNativeUIKitView` requirement: one unlabeled parameter whose type is
/// the diff of the props type, in one of the spellings that name it without a type alias.
private func hasDidUpdatePropsParameter(_ method: FunctionDeclSyntax, propsType: String) -> Bool {
  let parameters = method.signature.parameterClause.parameters
  guard parameters.count == 1, let parameter = parameters.first, parameter.firstName.tokenKind == .wildcard else {
    return false
  }
  let props = propsType.filter { !$0.isWhitespace }
  let diffTypes: Set<String> = [
    "\(props).Diff", "Props.Diff", "Self.Props.Diff",
    "PropsDiff<\(props)>", "PropsDiff<Props>", "PropsDiff<Self.Props>",
    "ExpoModulesCore.PropsDiff<\(props)>", "ExpoModulesCore.PropsDiff<Props>",
  ]
  return diffTypes.contains(parameter.type.trimmedDescription.filter { !$0.isWhitespace })
}

// MARK: - SwiftUI views

/// The members of a SwiftUI view struct: the `Props` typealias, the `props` and `children` constants, the initializer
/// that core calls with them, and the `_jsName` override.
private func swiftUIViewMembers(of node: AttributeSyntax, structDecl: StructDeclSyntax) throws -> [DeclSyntax] {
  guard conformsToSwiftUIView(structDecl) else {
    throw DiagnosticsError(diagnostics: [missingViewConformanceDiagnostic(for: structDecl)])
  }
  // Like a generic class, a generic struct can't be listed in `@ExpoModule(views:)`.
  if structDecl.genericParameterClause != nil {
    throw MacroExpansionErrorMessage(
      "@ExpoView does not support generic structs: a view registered with @ExpoModule(views:) must be concrete"
    )
  }
  if let existing = existingPropsMemberKind(in: structDecl.memberBlock) {
    throw MacroExpansionErrorMessage(
      "@ExpoView synthesizes a `Props` typealias, but this struct already declares a \(existing) named 'Props'. Rename it"
    )
  }
  if let existing = existingSynthesizedSwiftUIMember(in: structDecl.memberBlock) {
    throw MacroExpansionErrorMessage(
      "@ExpoView synthesizes `\(existing)` for a SwiftUI view, but this struct already declares it. Remove or rename it"
    )
  }
  guard let propsType = genericArgument(of: node) else {
    throw MacroExpansionErrorMessage(
      "@ExpoView requires its props type as a generic argument, as in `@ExpoView<MyViewProps>`"
    )
  }

  var members: [DeclSyntax] = [
    "public typealias Props = \(raw: propsType)",
    "public let props: Props",
    "public let children: ExpoSwiftUI.Children",
    """
    public init(props: Props, children: ExpoSwiftUI.Children) {
      self.props = props
      self.children = children
    }
    """,
  ]
  if let jsName = jsNameArgument(of: node) {
    members.append("public nonisolated static let _jsName = \"\(raw: jsName)\"")
  }
  return members
}

/// Whether the struct is a SwiftUI view that the member macro accepts, so the extension macro conforms it.
private func isValidSwiftUIView(_ structDecl: StructDeclSyntax) -> Bool {
  return conformsToSwiftUIView(structDecl)
    && structDecl.genericParameterClause == nil
    && existingPropsMemberKind(in: structDecl.memberBlock) == nil
    && existingSynthesizedSwiftUIMember(in: structDecl.memberBlock) == nil
}

/// Whether the struct names `View` or `SwiftUI.View` in its inheritance clause. A macro can't resolve names, so a
/// conformance through another protocol or an extension isn't seen.
private func conformsToSwiftUIView(_ structDecl: StructDeclSyntax) -> Bool {
  return structDecl.inheritanceClause?.inheritedTypes.contains { baseIdentifier(of: $0.type) == "View" } ?? false
}

/// The name of a member that the struct form synthesizes and the struct already declares: a `props` or `children`
/// property, or an initializer with the labels `props:children:`. `nil` when there is none.
private func existingSynthesizedSwiftUIMember(in memberBlock: MemberBlockSyntax) -> String? {
  for member in memberBlock.members {
    if let variable = member.decl.as(VariableDeclSyntax.self) {
      for binding in variable.bindings {
        if let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text,
          ["props", "children"].contains(withoutBackticks(name))
        {
          return withoutBackticks(name)
        }
      }
    }
    if let initializer = member.decl.as(InitializerDeclSyntax.self) {
      let labels = initializer.signature.parameterClause.parameters.map { $0.firstName.text }
      if labels == ["props", "children"] {
        return "init(props:children:)"
      }
    }
  }
  return nil
}

/// The error for a struct that doesn't name `View` in its inheritance clause, carrying a fix-it that adds it. A struct
/// has no superclass, so the conformance can always go at the end of the clause.
private func missingViewConformanceDiagnostic(for structDecl: StructDeclSyntax) -> Diagnostic {
  let message = ExpoViewDiagnosticMessage(
    "@ExpoView struct must be a SwiftUI view. Add `: View` to the struct declaration",
    id: "expoview-missing-view-conformance"
  )
  let viewType = InheritedTypeSyntax(type: TypeSyntax(IdentifierTypeSyntax(name: .identifier("View"))))
  let fixIt: FixIt
  if let clause = structDecl.inheritanceClause {
    var inherited = clause.inheritedTypes
    if var last = inherited.last {
      // The trivia after the last entry, such as the space before `{`, moves to the new last entry.
      let trailingTrivia = last.trailingTrivia
      last = last.with(\.trailingTrivia, []).with(\.trailingComma, .commaToken(trailingTrivia: .space))
      inherited = InheritedTypeListSyntax(
        Array(inherited.dropLast()) + [last, viewType.with(\.trailingTrivia, trailingTrivia)]
      )
    }
    fixIt = FixIt(
      message: ExpoViewFixItMessage("Conform to 'View'", id: "expoview-add-view-conformance"),
      changes: [.replace(oldNode: Syntax(clause), newNode: Syntax(clause.with(\.inheritedTypes, inherited)))]
    )
  } else {
    let name = structDecl.name
    let clause = InheritanceClauseSyntax(
      colon: .colonToken(trailingTrivia: .space),
      inheritedTypes: InheritedTypeListSyntax([viewType])
    )
    fixIt = FixIt(
      message: ExpoViewFixItMessage("Conform to 'View'", id: "expoview-add-view-conformance"),
      changes: [
        .replace(
          oldNode: Syntax(structDecl),
          newNode: Syntax(
            structDecl
              .with(\.name, name.with(\.trailingTrivia, []))
              .with(\.inheritanceClause, clause.with(\.trailingTrivia, name.trailingTrivia))
          )
        )
      ]
    )
  }
  return Diagnostic(node: structDecl.name, message: message, fixIts: [fixIt])
}

// MARK: - Diagnostics

/// The error for a class that doesn't name `ExpoNativeView` in its inheritance clause, carrying a fix-it
/// that adds it.
///
/// The fix-it only applies where the edit is unambiguous. With no inheritance clause at all it
/// inserts `: ExpoNativeView`; with an existing clause it prepends `ExpoNativeView` as the first entry, since
/// Swift requires the superclass to come before any protocol. A class that already names some other
/// superclass gets the diagnostic without a fix-it: replacing that superclass is a decision the macro
/// can't make (see the indirect-inheritance note on `expoViewBaseClassNames`).
private func missingBaseClassDiagnostic(for classDecl: ClassDeclSyntax) -> Diagnostic {
  let message = ExpoViewDiagnosticMessage(
    "@ExpoView class must inherit from ExpoNativeView. Add `: ExpoNativeView` to the class declaration",
    id: "expoview-missing-base-class"
  )
  var fixIts: [FixIt] = []

  if classDecl.inheritanceClause == nil {
    // `class CardView {` → `class CardView: ExpoNativeView {`. The name carries the space before `{` as
    // trailing trivia, so move it onto the clause to keep the spacing.
    let name = classDecl.name
    let clause = InheritanceClauseSyntax(
      colon: .colonToken(trailingTrivia: .space),
      inheritedTypes: InheritedTypeListSyntax([
        InheritedTypeSyntax(type: TypeSyntax(IdentifierTypeSyntax(name: .identifier("ExpoNativeView"))))
      ])
    )
    fixIts.append(
      FixIt(
        message: ExpoViewFixItMessage("Inherit from 'ExpoNativeView'", id: "expoview-add-base-class"),
        changes: [
          .replace(
            oldNode: Syntax(classDecl),
            newNode: Syntax(
              classDecl
                .with(\.name, name.with(\.trailingTrivia, []))
                .with(\.inheritanceClause, clause.with(\.trailingTrivia, name.trailingTrivia))
            )
          )
        ]
      )
    )
  } else if let clause = classDecl.inheritanceClause, inheritsOnlyProtocolsByConvention(clause) {
    // `class CardView: Identifiable {` → `class CardView: ExpoNativeView, Identifiable {`.
    var inherited = clause.inheritedTypes
    if var first = inherited.first {
      first.trailingComma = .commaToken(trailingTrivia: .space)
      first.type = TypeSyntax(IdentifierTypeSyntax(name: .identifier("ExpoNativeView")))
      inherited.insert(first, at: inherited.startIndex)
    }
    fixIts.append(
      FixIt(
        message: ExpoViewFixItMessage("Inherit from 'ExpoNativeView'", id: "expoview-add-base-class"),
        changes: [
          .replace(
            oldNode: Syntax(clause),
            newNode: Syntax(clause.with(\.inheritedTypes, inherited))
          )
        ]
      )
    )
  }

  return Diagnostic(node: classDecl.name, message: message, fixIts: fixIts)
}

/// Whether every entry in the clause looks like a protocol rather than a superclass, by the
/// capitalization-free heuristic that a Swift superclass must come first: if the first entry is one
/// the macro would be replacing, prepending `ExpoNativeView` would produce two superclasses. A macro can't
/// resolve names, so this only reports true when the clause is empty of anything that could be a
/// base class the author chose deliberately. Conservative by design: a wrong guess here would emit a
/// fix-it that doesn't compile.
private func inheritsOnlyProtocolsByConvention(_ clause: InheritanceClauseSyntax) -> Bool {
  // Any entry at all could be a superclass, so only offer the prepend when the author wrote
  // something that is definitely not one: a known protocol-shaped name from the standard library.
  let knownProtocols: Set<String> = [
    "Identifiable", "Equatable", "Hashable", "Codable", "Encodable", "Decodable",
    "Sendable", "CustomStringConvertible", "ObservableObject",
  ]
  return clause.inheritedTypes.allSatisfy { entry in
    guard let name = baseIdentifier(of: entry.type) else {
      return false
    }
    return knownProtocols.contains(name)
  }
}

private struct ExpoViewDiagnosticMessage: DiagnosticMessage {
  let message: String
  let diagnosticID: MessageID
  let severity: DiagnosticSeverity

  init(_ message: String, id: String, severity: DiagnosticSeverity = .error) {
    self.message = message
    self.diagnosticID = MessageID(domain: "ExpoModulesMacros", id: id)
    self.severity = severity
  }
}

private struct ExpoViewFixItMessage: FixItMessage {
  let message: String
  let fixItID: MessageID

  init(_ message: String, id: String) {
    self.message = message
    self.fixItID = MessageID(domain: "ExpoModulesMacros", id: id)
  }
}

/// Describes an existing `Props` member on the type, for the collision diagnostic, or `nil` when the
/// name is free. Covers the shapes that would clash with the synthesized typealias: another typealias,
/// and a nested type of any kind.
private func existingPropsMemberKind(in memberBlock: MemberBlockSyntax) -> String? {
  for member in memberBlock.members {
    let decl = member.decl
    if let typealiasDecl = decl.as(TypeAliasDeclSyntax.self), typealiasDecl.name.text == "Props" {
      return "typealias"
    }
    if let structDecl = decl.as(StructDeclSyntax.self), structDecl.name.text == "Props" {
      return "struct"
    }
    if let nestedClass = decl.as(ClassDeclSyntax.self), nestedClass.name.text == "Props" {
      return "class"
    }
    if let enumDecl = decl.as(EnumDeclSyntax.self), enumDecl.name.text == "Props" {
      return "enum"
    }
    if let actorDecl = decl.as(ActorDeclSyntax.self), actorDecl.name.text == "Props" {
      return "actor"
    }
  }
  return nil
}

/// Base classes an `@ExpoView` may inherit from. The check is syntactic, matching the name in the
/// class's own inheritance clause: both `: ExpoNativeView` and a qualified `: ExpoModulesCore.ExpoNativeView`
/// pass, since `baseIdentifier` reads the trailing name.
///
/// Indirect inheritance does not: a view whose superclass is itself an `ExpoNativeView` subclass
/// (`class Base: ExpoNativeView` then `class CardView: Base`) is rejected, because a macro can't resolve
/// the superclass to check. `@SharedObject` has the same limitation, through the same helper. The
/// workaround is to apply `@ExpoView` to the class that names `ExpoNativeView` directly.
private let expoViewBaseClassNames: Set<String> = ["ExpoNativeView"]

/// The attribute's single generic argument, verbatim (`@ExpoView<CardProps>` → `"CardProps"`), or
/// `nil` when the attribute carries no generic argument clause.
///
/// The type is available syntactically, with no type resolution. Two spellings carry it, mirroring
/// `baseIdentifier`'s handling of the inheritance clause: a bare `@ExpoView<CardProps>` parses as an
/// `IdentifierTypeSyntax`, and a qualified `@ExpoModulesCore.ExpoView<CardProps>` as a
/// `MemberTypeSyntax`. Both have a `genericArgumentClause`, and both are legal at the use site, so
/// reading only the bare form would reject valid code while claiming the author omitted the argument.
///
/// Only the first argument is read: core's declaration has exactly one parameter, so a second is
/// already a compile error at the use site ("specialized with too many type parameters").
private func genericArgument(of attribute: AttributeSyntax) -> String? {
  let arguments: GenericArgumentListSyntax?
  if let identifier = attribute.attributeName.as(IdentifierTypeSyntax.self) {
    arguments = identifier.genericArgumentClause?.arguments
  } else if let member = attribute.attributeName.as(MemberTypeSyntax.self) {
    arguments = member.genericArgumentClause?.arguments
  } else {
    arguments = nil
  }
  guard let first = arguments?.first, case .type(let type) = first.argument else {
    return nil
  }
  return type.trimmedDescription
}

/// The core protocol that `@ExpoView` conforms a class to. Core registers the view, decodes its props and applies
/// them through it.
private let uiKitViewProtocolName = "AnyNativeUIKitView"

/// The core protocol that `@ExpoView` conforms a SwiftUI view struct to. Core registers the view, decodes its props
/// and creates the struct with them through it.
private let swiftUIViewProtocolName = "AnyNativeSwiftUIView"
