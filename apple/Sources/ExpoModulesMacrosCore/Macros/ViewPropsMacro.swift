import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

/// Member + extension macro applied to a view-props type. Like `@Record`, **every stored property**
/// that is not `static`, `private`, `fileprivate`, `lazy` or computed is part of the surface — no
/// `@Field` wrapper — but unlike a record, the properties split into two kinds by their type:
///
/// - a **function-typed** property is an **event** (`var onTap: (TapEvent) -> Void`), dispatched by
///   name through the view's event emitter. No JS function object is ever decoded into it.
/// - every other property is a **value prop**, decoded from the raw props Fabric delivers.
///
/// An event must be spelled as a function type. The macro reads only the syntax, so a closure type
/// behind a typealias (`var onTap: TapHandler`) is a value prop.
///
/// Core creates the props with `Self()` and resets a prop that React removes (sends as `null`) to its
/// value there, so every value prop is a `var` with a default. When the type declares its own
/// `init()`, that initializer sets the defaults, and the compiler checks that it sets every stored
/// property. Otherwise each stored value prop needs an initial value, or a type written as `T?` or
/// `T!`, which defaults to `nil` (`Optional<T>` doesn't), and so does each `private` or `fileprivate`
/// stored property, which isn't a prop. The author's `init()` must be non-failable, non-throwing and
/// synchronous, so that core can call it.
///
/// The macro synthesizes the identity surface the batched reaction model reads:
///
/// - `PropName`: a `String`-backed `CaseIterable` enum, one case per value prop, whose raw value is
///   the wire key. It doubles as the string → prop translation table, so the runtime maps a raw
///   changed key with `PropName(rawValue:)` and names a prop in a log with `prop.rawValue`.
/// - `PropSet`: an `OptionSet` over `UInt64`, one bit per value prop in declaration order. This is the
///   membership currency: the changed set on a diff is a bitmask, so asking what changed costs no
///   allocation and no hashing.
/// - `_eventNames`: the event props' names, verbatim, for core to register at view creation.
/// - `typealias Diff = PropsDiff<Self>`, the nested spelling of core's one generic diff.
/// - a public `init()`, which `AnyViewProps` requires, when Swift's own can't satisfy it: when an
///   event prop has no initial value, when the type is `public` or `package` (Swift's `init()` is
///   `internal`), also through a `public` or `package` extension that contains it, or when the type
///   declares other initializers (Swift then synthesizes no `init()`). It gives each
///   event without an initial value an empty closure (`{}`, `{ _ in }`, ...) and leaves the value
///   props at their initial values. It is never generated when the type declares its own `init()`.
///   Like any initializer in the struct body, the generated one removes the memberwise initializer.
/// - `_resetViewProp(_:in:)`: sets one value prop back to its default, by assigning the property's
///   initial value or `nil`, so a reset evaluates only that prop's default. It is a static member of
///   the struct body, because an initial value can name a static member without `Self.` or a member of
///   an enclosing type, which an instance method or the extension can't.
///
/// An event's function type must return `Void`, because JavaScript can't return a value to it, and
/// takes at most one parameter, the payload, because JavaScript gets one payload object for an event.
/// The payload type must be `JavaScriptEncodable`, so it can't be a tuple or `Void`, and the parameter
/// can't be `inout`. Core takes the payload as `sending`, because it encodes it later on the JavaScript
/// thread, so with Swift 6 a payload type that isn't `Sendable` needs `sending` in the event's function
/// type, as in `(sending MoveEvent) -> Void`. An event prop is a `var`, because core assigns it when it binds the events, and an
/// initial value other than an empty closure gets a warning, because core replaces it. Two events can't
/// map to the same React Native event type (`onTap` and `tap` are both `topTap`), and no prop can be
/// named `key` or `ref`, which React keeps for itself. An event's name can't be one that React Native
/// uses for a bubbling event, such as `onPress` or `onChange`: core registers view events as direct
/// events, and an event type can't be both.
///
/// The extension that conforms the type to `AnyViewProps` adds:
///
/// - `allProps`: every bit set, the changed set on the first application.
/// - `propSet(for:)`: one name's bit, for folding raw changed keys into the mask.
/// - `_decode(_:from:in:)`: assigns one value prop from a JavaScript value. `null` and `undefined`
///   reset it with `_resetViewProp(_:in:)`, and any other value decodes through
///   `JavaScriptDecodable`.
/// - `_bindEvents(to:)`, only when the type has events: sets each event prop to a closure that
///   dispatches the event through core's `ViewEventDispatcher`, with its parameter as the payload.
///   Core binds the props that a view starts from, and later decodes copy the bound closures.
///
/// `_decode` and `_resetViewProp` run on the JavaScript actor. The other generated types and members
/// and the conformance are `nonisolated`, so core can use them on any thread also when the module
/// builds with a default isolation, such as `-default-isolation MainActor`. The props' own
/// declarations still take that isolation, so a struct with an event prop, a value prop whose type
/// isn't `Sendable`, or a computed prop needs `nonisolated` on its declaration, and the author's
/// `init()` must be `nonisolated` too. So must a conformance that the author declares
/// (`: nonisolated AnyViewProps`).
///
/// Author-facing shape — no conformance to spell out:
///
///   @ViewProps
///   struct CardProps {
///     var color: UIColor = .red        // value prop, bit 0
///     var radius: CGFloat = 0          // value prop, bit 1
///     var onTap: (TapEvent) -> Void    // event, no bit
///   }
///
/// The diff type itself is deliberately **not** generated. Core's generic
/// `PropsDiff<Props: AnyViewProps>` owns both storage (`old`/`new`/`changedProps`) and behavior
/// (`changed(_:)`, `oldValue(_:)`, `isInitial`, `changedNames`), reaching the per-props types through
/// the conformance's associated types — so the query API can grow without a macro release.
///
/// Event names are emitted **verbatim**, with no `on`-prefix stripping. This differs from `@Event` on
/// modules and shared objects, which strips it (`onStatusChange` → `"statusChange"`): a view event prop
/// is a React prop name that Fabric carries as-is, so the native and JS spellings must match exactly.
public struct ViewPropsMacro: MemberMacro, ExtensionMacro {
  public static func expansion(
    of node: AttributeSyntax,
    providingMembersOf declaration: some DeclGroupSyntax,
    conformingTo protocols: [TypeSyntax],
    in context: some MacroExpansionContext
  ) throws -> [DeclSyntax] {
    let props = try validatedViewProps(of: declaration, in: context.lexicalContext)
    // Reported by the member role only, so each warning appears once.
    for warning in props.warnings {
      context.diagnose(warning)
    }

    var members: [DeclSyntax] = []
    members.append(propNameEnum(valueProps: props.valueProps))
    members.append(propSetStruct(valueProps: props.valueProps))
    members.append(eventNamesConstant(eventProps: props.eventProps))
    members.append(diffTypealias())
    if let initializer = defaultInitializer(props: props) {
      members.append(initializer)
    }
    if let reset = resetFunction(valueProps: props.valueProps) {
      members.append(reset)
    }
    return members
  }

  /// Auto-conforms the type to `AnyViewProps`, supplying the requirements that can only be written
  /// per-props: `allProps` (every bit set, the changed set on the first application),
  /// `propSet(for:)` (one name's bit, for folding raw changed keys into the mask), `_decode`
  /// (one value prop assigned from a JavaScript value) and, when the type has events,
  /// `_bindEvents(to:)` (each event prop set to a closure that dispatches the event).
  ///
  /// A conformance the author already spelled out in the inheritance clause is not repeated.
  public static func expansion(
    of node: AttributeSyntax,
    attachedTo declaration: some DeclGroupSyntax,
    providingExtensionsOf type: some TypeSyntaxProtocol,
    conformingTo protocols: [TypeSyntax],
    in context: some MacroExpansionContext
  ) throws -> [ExtensionDeclSyntax] {
    guard declaration.is(StructDeclSyntax.self) else {
      return []
    }
    // Both roles read the same model, but a validation failure is the member macro's to report:
    // expansion runs each role independently, so throwing here too would surface every diagnostic
    // twice. When the model doesn't validate, the member macro has already emitted the error and
    // there is nothing to extend.
    guard let props = try? validatedViewProps(of: declaration, in: context.lexicalContext) else {
      return []
    }
    let alreadyConforms = inheritsProtocol(named: viewPropsProtocolName, in: declaration)

    // `allProps` is read on every first application of props, once per view instance, so it's a
    // stored constant with the mask already folded rather than a computed property rebuilding an
    // array literal per call. The macro knows the bit count, so the literal is exact: n props
    // occupy bits 0..<n, which is the low n bits set.
    let allPropsMask =
      props.valueProps.isEmpty
      ? "0"
      : "0b" + String(repeating: "1", count: props.valueProps.count)

    // With no value prop, `PropName` has no case, so the function can't be called and its body is
    // empty, like the one of `_decode`. Swift reports any statement in it, also an empty `switch`, as
    // "will never be executed". The body starts with a line break, so the empty one closes on the
    // next line.
    let propSetBody: String
    if props.valueProps.isEmpty {
      propSetBody = ""
    } else {
      let cases = props.valueProps
        .map { "    case .\($0.name):\n      return .\($0.name)" }
        .joined(separator: "\n")
      propSetBody = "\n    switch name {\n\(cases)\n    }"
    }

    let decodeBody = decodeFunctionBody(valueProps: props.valueProps)
    let bindEvents = bindEventsFunction(eventProps: props.eventProps)

    // `nonisolated` keeps the conformance and its members usable on the JavaScript thread when the
    // module builds with a default isolation, which would otherwise isolate them to the main actor.
    let conformanceClause = alreadyConforms ? "" : ": nonisolated \(viewPropsProtocolName)"
    let ext: DeclSyntax = """
      extension \(type.trimmed)\(raw: conformanceClause) {
        nonisolated public static let allProps = PropSet(rawValue: \(raw: allPropsMask))

        /// `@inlinable` so core's raw-key fold can inline the lookup across the module boundary:
        /// it runs once per changed key per props batch.
        @inlinable
        nonisolated public static func propSet(for name: PropName) -> PropSet {\(raw: propSetBody)
        }

        @JavaScriptActor
        public mutating func _decode(_ name: PropName, from value: borrowing JavaScriptUnownedValue, in runtime: borrowing JavaScriptRuntime) throws {\(raw: decodeBody)
        }\(raw: bindEvents)
      }
      """
    guard let extDecl = ext.as(ExtensionDeclSyntax.self) else {
      return []
    }
    return [extDecl]
  }
}

/// The core protocol carrying the `PropName`/`PropSet` associated types plus `allProps` and
/// `propSet(for:)`, through which the generic `PropsDiff` reaches a specific props type.
private let viewPropsProtocolName = "AnyViewProps"

/// The mask is a single `UInt64`, so a props type can carry at most this many value props. Event
/// props take no bit and don't count.
private let maxValueProps = 64

// MARK: - Diagnostics

/// The error for an optional event prop, attached to the declared type and carrying a fix-it that
/// unwraps it. Events are registered once at view creation from a static name list, so there is no
/// shape that could express "sometimes emitted".
private func optionalEventDiagnostic(for type: TypeSyntax, name: String) -> Diagnostic {
  var fixIts: [FixIt] = []
  if let unwrapped = unwrappedOptionalType(type) {
    fixIts.append(
      FixIt(
        message: ViewPropsFixItMessage("Make '\(name)' non-optional", id: "viewprops-unwrap-event"),
        changes: [
          .replace(
            oldNode: Syntax(type),
            newNode: Syntax(unwrapped.with(\.trailingTrivia, type.trailingTrivia))
          )
        ]
      )
    )
  }
  let message = ViewPropsDiagnosticMessage(
    "Event props cannot be optional: '\(name)' is registered once at view creation, so its presence can't vary. Drop the '?'",
    id: "viewprops-optional-event"
  )
  return Diagnostic(node: type, message: message, fixIts: fixIts)
}

/// The type an optional wraps, with the enclosing parentheses of a parenthesized function type kept
/// (`(() -> Void)?` unwraps to `() -> Void`, not to a stray `(() -> Void)`). Returns `nil` for a
/// spelling the fix-it can't rewrite mechanically.
private func unwrappedOptionalType(_ type: TypeSyntax) -> TypeSyntax? {
  guard let wrapped = optionalWrappedType(type) else {
    return nil
  }
  return innerFunctionType(of: wrapped) ?? wrapped
}

/// The function type inside a single-element parenthesized type, so unwrapping `(() -> Void)?`
/// yields `() -> Void` rather than keeping the now-redundant parentheses.
private func innerFunctionType(of type: TypeSyntax) -> TypeSyntax? {
  guard let tuple = type.as(TupleTypeSyntax.self),
    tuple.elements.count == 1,
    let only = tuple.elements.first,
    only.type.is(FunctionTypeSyntax.self)
  else {
    return nil
  }
  return only.type
}

/// The error for a `let` that declares props, attached to the keyword and carrying a fix-it that
/// replaces it with `var`. Core assigns a value prop whenever React sets or removes it, and the closure
/// that dispatches an event prop when it binds the events.
private func letPropDiagnostic(
  for varDecl: VariableDeclSyntax,
  valueNames: [String],
  eventNames: [String]
) -> Diagnostic {
  let specifier = varDecl.bindingSpecifier
  let fixIt = FixIt(
    message: ViewPropsFixItMessage("Replace 'let' with 'var'", id: "viewprops-let-to-var"),
    changes: [
      .replace(
        oldNode: Syntax(specifier),
        newNode: Syntax(specifier.with(\.tokenKind, .keyword(.var)))
      )
    ]
  )
  let quoted = (valueNames + eventNames).map { "'\(withoutBackticks($0))'" }
  let names =
    quoted.count == 1
    ? quoted[0] : "\(quoted.dropLast().joined(separator: ", ")) and \(quoted[quoted.count - 1])"
  let text: String
  if eventNames.isEmpty {
    text =
      quoted.count == 1
      ? "View prop \(names) can't be a 'let' constant, because it's assigned whenever React sets or removes the prop. Declare it with 'var'"
      : "View props \(names) can't be 'let' constants, because they're assigned whenever React sets or removes the props. Declare them with 'var'"
  } else if valueNames.isEmpty {
    text =
      quoted.count == 1
      ? "Event prop \(names) can't be a 'let' constant, because core assigns the closure that dispatches the event. Declare it with 'var'"
      : "Event props \(names) can't be 'let' constants, because core assigns the closures that dispatch the events. Declare them with 'var'"
  } else {
    text = "Props \(names) can't be 'let' constants, because core assigns them. Declare them with 'var'"
  }
  return Diagnostic(
    node: specifier,
    message: ViewPropsDiagnosticMessage(text, id: "viewprops-let-prop"),
    fixIts: [fixIt]
  )
}

/// The error for an event prop whose function type returns something other than `Void`, attached to
/// the return type and carrying a fix-it that changes it to `Void`. Core dispatches the event to
/// JavaScript, which can't return a value to the caller, and the generated `init()` couldn't give the
/// event an empty closure.
private func eventReturnTypeDiagnostic(for returnType: TypeSyntax, name: String) -> Diagnostic {
  let message = ViewPropsDiagnosticMessage(
    "Event prop '\(withoutBackticks(name))' must return Void, because an event is sent to JavaScript, which can't return a value. Change the return type '\(returnType.trimmedDescription)' to 'Void'",
    id: "viewprops-event-return-type"
  )
  let void = TypeSyntax(IdentifierTypeSyntax(name: .identifier("Void")))
    .with(\.leadingTrivia, returnType.leadingTrivia)
    .with(\.trailingTrivia, returnType.trailingTrivia)
  let fixIt = FixIt(
    message: ViewPropsFixItMessage("Change the return type to 'Void'", id: "viewprops-event-return-void"),
    changes: [.replace(oldNode: Syntax(returnType), newNode: Syntax(void))]
  )
  return Diagnostic(node: returnType, message: message, fixIts: [fixIt])
}

/// The error for an event prop whose function type takes more than one parameter, attached to the
/// parameter list. JavaScript gets one payload object for an event, so core can't pass on more than one
/// value. There is no fix-it: the author picks the record that holds the values.
private func eventParameterCountDiagnostic(for functionType: FunctionTypeSyntax, name: String) -> Diagnostic {
  let message = ViewPropsDiagnosticMessage(
    "Event prop '\(withoutBackticks(name))' takes \(functionType.parameters.count) parameters, but JavaScript gets one payload for an event. Take one parameter, such as a record with the values",
    id: "viewprops-event-parameter-count"
  )
  return Diagnostic(node: functionType.parameters, message: message)
}

/// The error for the one parameter of an event prop that `_bindEvents(to:)` can't pass on as the payload, or `nil`
/// when the parameter works. An `inout` parameter can't take the closure's argument, a `Void` parameter has no
/// payload to send, and a tuple can't conform to `JavaScriptEncodable`.
///
/// The fix-its change the function type, so a closure that the struct assigns to the prop must still fit it. They're
/// offered only when that's sure: the prop has no initial value, or an empty closure, and the struct declares no
/// initializer, which could assign another closure. The `Void` fix-it also replaces an empty closure with `{}`.
private func eventParameterDiagnostic(
  for parameter: TupleTypeElementSyntax,
  in functionType: FunctionTypeSyntax,
  binding: PatternBindingSyntax,
  name: String,
  structDeclaresInitializer: Bool
) -> Diagnostic? {
  let eventName = withoutBackticks(name)
  let initialValue = binding.initializer?.value
  let offersFixIt = !structDeclaresInitializer && (initialValue.map(isEmptyClosure) ?? true)

  if let attributed = parameter.type.as(AttributedTypeSyntax.self),
    attributed.specifiers.contains(where: { $0.trimmedDescription == "inout" })
  {
    let specifiers = attributed.specifiers.filter { $0.trimmedDescription != "inout" }
    let newType =
      specifiers.isEmpty && attributed.attributes.isEmpty
      ? attributed.baseType.with(\.leadingTrivia, attributed.leadingTrivia)
      : TypeSyntax(attributed.with(\.specifiers, specifiers))
    let fixIt = FixIt(
      message: ViewPropsFixItMessage("Remove 'inout'", id: "viewprops-event-remove-inout"),
      changes: [.replace(oldNode: Syntax(parameter.type), newNode: Syntax(newType))]
    )
    return Diagnostic(
      node: parameter.type,
      message: ViewPropsDiagnosticMessage(
        "The parameter of event prop '\(eventName)' can't be 'inout', because the payload is sent to JavaScript, which can't write it back. Remove 'inout'",
        id: "viewprops-event-inout-parameter"
      ),
      fixIts: offersFixIt ? [fixIt] : []
    )
  }
  if isVoidType(parameter.type) {
    var changes: [FixIt.Change] = [
      .replace(
        oldNode: Syntax(functionType),
        newNode: Syntax(functionType.with(\.parameters, TupleTypeElementListSyntax([])))
      )
    ]
    // An empty closure that takes the parameter, such as `{ _ in }`, must take none either.
    if let initialValue {
      let emptyClosure = ExprSyntax(stringLiteral: "{}")
        .with(\.leadingTrivia, initialValue.leadingTrivia)
        .with(\.trailingTrivia, initialValue.trailingTrivia)
      changes.append(.replace(oldNode: Syntax(initialValue), newNode: Syntax(emptyClosure)))
    }
    let fixIt = FixIt(
      message: ViewPropsFixItMessage("Remove the parameter", id: "viewprops-event-remove-void-parameter"),
      changes: changes
    )
    return Diagnostic(
      node: parameter.type,
      message: ViewPropsDiagnosticMessage(
        "Event prop '\(eventName)' takes a 'Void' parameter, but an event without a payload takes no parameter. Remove the parameter",
        id: "viewprops-event-void-parameter"
      ),
      fixIts: offersFixIt ? [fixIt] : []
    )
  }
  if let tuple = withoutParentheses(parameter.type).as(TupleTypeSyntax.self), tuple.elements.count > 1 {
    return Diagnostic(
      node: parameter.type,
      message: ViewPropsDiagnosticMessage(
        "Event prop '\(eventName)' takes a tuple, but an event payload must be 'JavaScriptEncodable', which a tuple can't be. Take a record with the values",
        id: "viewprops-event-tuple-parameter"
      )
    )
  }
  return nil
}

/// The warning for an event prop whose initial value isn't an empty closure, attached to the initial value. Core
/// replaces the closure with one that dispatches the event when it binds the events, so the code in it doesn't run
/// when the view calls the event. The fix-it replaces the initial value with an empty closure, rather than removing
/// it, so that every initializer of the struct stays valid, also one the macro can't see.
private func unusedEventInitialValueDiagnostic(
  for initializer: InitializerClauseSyntax,
  name: String,
  arity: Int
) -> Diagnostic {
  let emptyValue = ExprSyntax(stringLiteral: emptyClosure(arity: arity))
    .with(\.leadingTrivia, initializer.value.leadingTrivia)
    .with(\.trailingTrivia, initializer.value.trailingTrivia)
  return Diagnostic(
    node: initializer.value,
    message: ViewPropsDiagnosticMessage(
      "The initial value of event prop '\(withoutBackticks(name))' doesn't run when the view calls the event, because core replaces it with a closure that dispatches the event. Replace it with an empty closure",
      id: "viewprops-event-initial-value",
      severity: .warning
    ),
    fixIts: [
      FixIt(
        message: ViewPropsFixItMessage(
          "Replace the initial value with '\(emptyValue.trimmedDescription)'",
          id: "viewprops-event-empty-initial-value"
        ),
        changes: [.replace(oldNode: Syntax(initializer.value), newNode: Syntax(emptyValue))]
      )
    ]
  )
}

/// The error for an event prop that React Native registers as the same event as an earlier one, attached to the
/// property name. The view config has one entry for each event type, so only one of the two props would get the
/// event in JavaScript.
private func duplicateEventTypeDiagnostic(
  for pattern: IdentifierPatternSyntax,
  name: String,
  otherName: String,
  eventType: String
) -> Diagnostic {
  return Diagnostic(
    node: pattern,
    message: ViewPropsDiagnosticMessage(
      "Event props '\(withoutBackticks(otherName))' and '\(withoutBackticks(name))' are the same event, '\(eventType)', in React Native, so only one of them would get it in JavaScript. Rename one of them",
      id: "viewprops-duplicate-event-type"
    )
  )
}

/// The error for a prop named `key` or `ref`, attached to the property name. React keeps these props for itself,
/// so they never reach a native view.
private func reactReservedPropDiagnostic(for pattern: IdentifierPatternSyntax, name: String) -> Diagnostic {
  return Diagnostic(
    node: pattern,
    message: ViewPropsDiagnosticMessage(
      "Prop '\(withoutBackticks(name))' never reaches the view, because React keeps it for itself. Rename the prop",
      id: "viewprops-react-reserved-name"
    )
  )
}

/// The props that React keeps for itself and never passes to a native view.
private let reactReservedPropNames: Set<String> = ["key", "ref"]

/// The error for an event prop whose name React Native already uses for a bubbling event, attached to the property
/// name. Core registers each view event as a direct event, and React Native throws "Event cannot be both direct and
/// bubbling" when the view renders. There is no fix-it, since the new name is the author's choice.
private func bubblingEventNameDiagnostic(for pattern: IdentifierPatternSyntax, name: String) -> Diagnostic {
  let message = ViewPropsDiagnosticMessage(
    "Event prop '\(withoutBackticks(name))' can't have this name, because React Native already uses it for a bubbling event, and the view would fail to render. Rename the event",
    id: "viewprops-bubbling-event-name"
  )
  return Diagnostic(node: pattern, message: message)
}

/// The bubbling event types in React Native's base view config on iOS (`bubblingEventTypes` in
/// `Libraries/NativeComponent/BaseViewConfig.ios.js`, React Native 0.89). Every native view has them, so a view event
/// with one of these types is both direct and bubbling.
private let bubblingEventTypes: Set<String> = [
  "topPress", "topChange", "topFocus", "topBlur", "topSubmitEditing", "topEndEditing", "topKeyPress",
  "topTouchStart", "topTouchMove", "topTouchCancel", "topTouchEnd", "topClick",
  "topPointerCancel", "topPointerDown", "topPointerMove", "topPointerUp", "topPointerEnter", "topPointerLeave",
  "topPointerOver", "topPointerOut", "topGotPointerCapture", "topLostPointerCapture",
]

/// The event type that React Native registers for a view event, as `RCTNormalizeInputEventName` makes it: `onTap` and
/// `tap` are `topTap`, and a name that starts with `top` stays.
private func normalizedEventType(of eventName: String) -> String {
  if eventName.hasPrefix("on") {
    return "top" + eventName.dropFirst(2)
  }
  if eventName.hasPrefix("top") {
    return eventName
  }
  return "top" + eventName.prefix(1).uppercased() + eventName.dropFirst()
}

/// Whether the expression is a closure literal with no statements, such as `{}` or `{ _ in }`.
private func isEmptyClosure(_ expression: ExprSyntax) -> Bool {
  return expression.as(ClosureExprSyntax.self)?.statements.isEmpty ?? false
}

/// The error for a value prop with no default, attached to the property name. A value prop starts
/// from its value in `Self()` and returns to it when React removes the prop, so it needs an initial
/// value, or a type written as `T?`, whose default is `nil`. There is no fix-it, since the default is
/// the author's choice, except for a type written as `Optional<T>`: rewriting it as `T?` keeps the
/// type and only adds the implicit `nil`.
private func missingDefaultDiagnostic(
  for pattern: IdentifierPatternSyntax,
  name: String,
  type: TypeSyntax?
) -> Diagnostic {
  if let type, let sugared = optionalSugar(for: type) {
    let fixIt = FixIt(
      message: ViewPropsFixItMessage(
        "Write the type as '\(sugared.trimmedDescription)'",
        id: "viewprops-optional-sugar"
      ),
      changes: [.replace(oldNode: Syntax(type), newNode: Syntax(sugared))]
    )
    let message = ViewPropsDiagnosticMessage(
      "View prop '\(withoutBackticks(name))' needs an initial value, which is its default when React removes the prop. A type written as '\(type.trimmedDescription)' gets no implicit nil, so write it as '\(sugared.trimmedDescription)'",
      id: "viewprops-missing-default"
    )
    return Diagnostic(node: pattern, message: message, fixIts: [fixIt])
  }
  let message = ViewPropsDiagnosticMessage(
    "View prop '\(withoutBackticks(name))' needs an initial value, which is its default when React removes the prop. Give it one, or make its type optional with '?', which defaults to nil",
    id: "viewprops-missing-default"
  )
  return Diagnostic(node: pattern, message: message)
}

/// `T?` for a type written as `Optional<T>`, with the trivia of the original, or `nil` for any other
/// type. A wrapped `any P`, `some P` or `P & Q` keeps parentheses, since `any P?` would make only `P`
/// optional.
private func optionalSugar(for type: TypeSyntax) -> TypeSyntax? {
  guard let identifier = type.as(IdentifierTypeSyntax.self), identifier.name.text == "Optional",
    let wrapped = optionalWrappedType(type)
  else {
    return nil
  }
  var wrappedType = wrapped.trimmed
  if wrappedType.is(SomeOrAnyTypeSyntax.self) || wrappedType.is(CompositionTypeSyntax.self) {
    wrappedType = TypeSyntax(TupleTypeSyntax(elements: [TupleTypeElementSyntax(type: wrappedType)]))
  }
  return TypeSyntax(OptionalTypeSyntax(wrappedType: wrappedType))
    .with(\.leadingTrivia, type.leadingTrivia)
    .with(\.trailingTrivia, type.trailingTrivia)
}

/// The error for a `private` or `fileprivate` stored property without an initial value, attached to
/// its name. `@ViewProps` leaves it out of the props, so the `init()` that core calls doesn't set it.
/// There is no fix-it: the value is the author's choice.
private func unsetPrivatePropertyDiagnostic(
  for pattern: IdentifierPatternSyntax,
  access: String
) -> Diagnostic {
  let message = ViewPropsDiagnosticMessage(
    "@ViewProps leaves out the \(access) property '\(withoutBackticks(pattern.identifier.text))', so 'init()' doesn't set it. Give it an initial value, or remove '\(access)' to make it a prop",
    id: "viewprops-unset-private-property"
  )
  return Diagnostic(node: pattern, message: message)
}

/// The errors for an `init()` that core can't call as `Self()`, one for each token that makes it
/// unusable: the `?` or `!` of a failable initializer, `async`, and the `throws` clause. Each is
/// attached to its token and carries a fix-it that removes it with its trailing space, so
/// `init() async throws {` becomes `init() throws {`, and then `init() {`.
private func unusableInitializerDiagnostics(for initializer: InitializerDeclSyntax) -> [Diagnostic] {
  var diagnostics: [Diagnostic] = []
  if let optionalMark = initializer.optionalMark {
    diagnostics.append(
      unusableInitializerDiagnostic(
        on: Syntax(optionalMark),
        removing: Syntax(optionalMark.with(\.presence, .missing)),
        requirement: "non-failable",
        fixItID: "viewprops-remove-failable"
      )
    )
  }
  let effectSpecifiers = initializer.signature.effectSpecifiers
  if let asyncSpecifier = effectSpecifiers?.asyncSpecifier {
    diagnostics.append(
      unusableInitializerDiagnostic(
        on: Syntax(asyncSpecifier),
        removing: Syntax(asyncSpecifier.with(\.presence, .missing)),
        requirement: "synchronous",
        fixItID: "viewprops-remove-async"
      )
    )
  }
  if let throwsClause = effectSpecifiers?.throwsClause {
    let missingClause = ThrowsClauseSyntax(
      throwsSpecifier: throwsClause.throwsSpecifier.with(\.presence, .missing)
    )
    diagnostics.append(
      unusableInitializerDiagnostic(
        on: Syntax(throwsClause),
        removing: Syntax(missingClause),
        requirement: "non-throwing",
        fixItID: "viewprops-remove-throws"
      )
    )
  }
  return diagnostics
}

/// One error of `unusableInitializerDiagnostics`. The fix-it replaces the node, together with its
/// trivia, by a missing node, which prints as nothing.
private func unusableInitializerDiagnostic(
  on node: Syntax,
  removing missingNode: Syntax,
  requirement: String,
  fixItID: String
) -> Diagnostic {
  let text = node.trimmedDescription
  let fixIt = FixIt(
    message: ViewPropsFixItMessage("Remove '\(text)'", id: fixItID),
    changes: [.replace(oldNode: node, newNode: missingNode)]
  )
  let message = ViewPropsDiagnosticMessage(
    "@ViewProps needs a \(requirement) 'init()', because core creates the props with 'Self()'. Remove '\(text)'",
    id: "viewprops-unusable-init"
  )
  return Diagnostic(node: node, message: message, fixIts: [fixIt])
}

private struct ViewPropsDiagnosticMessage: DiagnosticMessage {
  let message: String
  let diagnosticID: MessageID
  let severity: DiagnosticSeverity

  init(_ message: String, id: String, severity: DiagnosticSeverity = .error) {
    self.message = message
    self.diagnosticID = MessageID(domain: "ExpoModulesMacros", id: id)
    self.severity = severity
  }
}

private struct ViewPropsFixItMessage: FixItMessage {
  let message: String
  let fixItID: MessageID

  init(_ message: String, id: String) {
    self.message = message
    self.fixItID = MessageID(domain: "ExpoModulesMacros", id: id)
  }
}

// MARK: - Property model

/// One stored property of the props type, classified as a value prop or an event.
private struct ViewProp {
  /// The property name as written, backticks included for an escaped name. Every identifier position
  /// in the generated code uses this, since `case default` and `static let default` don't parse.
  let name: String
  /// The property's declared type, verbatim, or the type of its literal initial value. `_decode`
  /// doesn't spell it: the decoded type is inferred from the assignment.
  let type: String
  /// Whether the prop is computed with a `mutating get`, which `_resetViewProp` can only read from a
  /// mutable value.
  let hasMutatingGetter: Bool
  /// What `_resetViewProp` assigns when React removes the prop. Events aren't reset.
  let defaultValue: PropDefault

  /// The name with any escaping backticks removed: the JS-visible key, so the enum's raw value and
  /// `_eventNames` both read `"default"`, never `` "`default`" ``.
  var wireName: String {
    return withoutBackticks(name)
  }
}

/// The value that a value prop goes back to when React removes it. Each one equals the prop's value
/// in `Self()`.
private enum PropDefault {
  /// The initial value of a stored property, as written. Evaluating it again gives the value that
  /// `Self()` gives the property.
  case initialValue(ExprSyntax)
  /// The implicit `nil` of a `var` whose type is written as `T?` or `T!`.
  case implicitNil
  /// The prop's value in a new `Self()`, when the macro can't tell it from the declaration: the
  /// struct declares its own `init()`, which can set any value, the prop is computed, the property
  /// has an attribute, such as a property wrapper, whose value after `init(wrappedValue:)` can differ
  /// from its initial value, or the initial value has a `#` expression, such as `#function` or
  /// `#line`, whose value depends on where it's evaluated.
  case newInstance
}

/// The default of a property with the given binding, for a struct that does or doesn't declare its own
/// `init()`.
private func propDefault(
  of binding: PatternBindingSyntax,
  in varDecl: VariableDeclSyntax,
  declaredType: TypeSyntax?,
  declaresUsableInitializer: Bool
) -> PropDefault {
  if declaresUsableInitializer || !isStoredBinding(binding) || !varDecl.attributes.isEmpty {
    return .newInstance
  }
  if let initializer = binding.initializer {
    // A macro expansion, also a literal such as `#function`, can depend on where it's evaluated, so
    // a copy in `_resetViewProp` could give another value.
    let hasPoundExpression = initializer.value.tokens(viewMode: .sourceAccurate).contains {
      $0.tokenKind == .pound
    }
    return hasPoundExpression ? .newInstance : .initialValue(initializer.value)
  }
  if varDecl.bindingSpecifier.tokenKind == .keyword(.var), let declaredType, hasImplicitNilDefault(declaredType) {
    return .implicitNil
  }
  // A value prop without a default is reported, so this is only reached for an event, which isn't
  // reset.
  return .newInstance
}

/// One event prop, which `_bindEvents(to:)` sets to a closure that dispatches the event.
private struct ViewEvent {
  /// The property name as written, backticks included for an escaped name.
  let name: String
  /// Whether the event's function type takes a parameter, the payload that JavaScript gets.
  let takesPayload: Bool

  /// The name with any escaping backticks removed: the event name in JavaScript.
  var wireName: String {
    return withoutBackticks(name)
  }
}

/// An event prop declared without an initial value, which the generated `init()` assigns.
private struct EventDefault {
  /// The property name as written, backticks included.
  let name: String
  /// A closure literal that ignores its arguments and does nothing: `{}`, `{ _ in }`, `{ _, _ in }`
  /// and so on, by the arity of the event's function type.
  let emptyClosure: String
}

private struct ViewPropsModel {
  /// Value props, in declaration order. The order is the bit order, so it is part of the ABI
  /// between a compiled view and the runtime that fills the mask.
  let valueProps: [ViewProp]
  /// Event props, in declaration order.
  let eventProps: [ViewEvent]
  /// The event props without an initial value, in declaration order.
  let eventDefaults: [EventDefault]
  /// Whether the macro generates `init()`. See `needsGeneratedInitializer`.
  let generatesInitializer: Bool
  /// Warnings that don't stop the expansion.
  let warnings: [Diagnostic]
}

/// Reads and validates the props type's stored properties, splitting them into value props and events.
///
/// Rejects what can't be expressed: a non-`struct` declaration (the class form is the SwiftUI path and
/// needs the observable protocol, which is deferred), a leftover `@Field` attribute, an optional
/// function type, an event whose function type returns a value, a property with no determinable type,
/// a value prop declared with `let` or without a default, a `private` stored property without an
/// initial value, an `init()` that is failable, throwing or `async`, and more than 64 value props.
///
/// When the type declares a usable `init()`, that initializer is the default: it must set every
/// stored property, which the compiler checks, so the props need no initial values.
private func validatedViewProps(
  of declaration: some DeclGroupSyntax,
  in lexicalContext: [Syntax]
) throws -> ViewPropsModel {
  guard let structDecl = declaration.as(StructDeclSyntax.self) else {
    throw MacroExpansionErrorMessage(
      "@ViewProps can only be applied to a struct: the class form (for SwiftUI views) is not supported yet"
    )
  }
  // A generic props type can't work: the synthesized extension would have to repeat the generic
  // parameter list and its constraints, and core reaches the props type through a view's static
  // `Props` typealias, which names one concrete type.
  if structDecl.genericParameterClause != nil {
    throw MacroExpansionErrorMessage(
      "@ViewProps does not support generic types: a view's props type must be concrete"
    )
  }

  // `@Field` is the v1 property wrapper and has no meaning here — every stored property is already
  // part of the surface. Left in place it would wrap the value in `Field<T>`, so the props type
  // would decode against the wrong type. Flag every one rather than emit code built on them, all at
  // once, so a `@Field` without a fix-it doesn't hide the fix-its of the others.
  let fieldDiagnostics = declaration.memberBlock.members.compactMap { member -> Diagnostic? in
    guard let varDecl = member.decl.as(VariableDeclSyntax.self), !isExcludedByModifier(varDecl.modifiers),
      let fieldAttribute = varDecl.attributes.firstAttribute(named: "Field")
    else {
      return nil
    }
    return fieldAttributeDiagnostic(for: fieldAttribute, on: varDecl, in: .viewProps)
  }
  if !fieldDiagnostics.isEmpty {
    throw DiagnosticsError(diagnostics: fieldDiagnostics)
  }

  // A usable `init()` belongs to the author and sets the defaults. An `init()` that core can't call
  // as `Self()` doesn't count, and is reported only when there is no usable one: Swift allows an
  // `init() async` next to `init()`, and `Self()` in the synchronous `_decode` calls the latter.
  var propDiagnostics: [Diagnostic] = []
  var unusableInitializerDiagnosticsFound: [Diagnostic] = []
  var declaresUsableInitializer = false
  var declaresOtherInitializer = false
  for member in flattenedMembers(declaration.memberBlock.members) {
    guard let initializer = member.decl.as(InitializerDeclSyntax.self) else {
      continue
    }
    guard initializer.signature.parameterClause.parameters.isEmpty else {
      declaresOtherInitializer = true
      continue
    }
    let unusableDiagnostics = unusableInitializerDiagnostics(for: initializer)
    if unusableDiagnostics.isEmpty {
      declaresUsableInitializer = true
    } else {
      unusableInitializerDiagnosticsFound += unusableDiagnostics
    }
  }
  if !declaresUsableInitializer {
    propDiagnostics += unusableInitializerDiagnosticsFound
  }

  var valueProps: [ViewProp] = []
  var eventProps: [ViewEvent] = []
  var eventDefaults: [EventDefault] = []
  var warnings: [Diagnostic] = []
  // The event prop that registers each event type, to find two props of the same type.
  var eventPropsByType: [String: String] = [:]

  for member in declaration.memberBlock.members {
    guard let varDecl = member.decl.as(VariableDeclSyntax.self) else {
      continue
    }
    if isExcludedByModifier(varDecl.modifiers) {
      if !declaresUsableInitializer {
        propDiagnostics += unsetPrivatePropertyDiagnostics(of: varDecl)
      }
      continue
    }
    // One `let` can declare several props, but its diagnostic and fix-it belong to the keyword, so
    // it comes before the diagnostics of the bindings, in source order.
    var letValuePropNames: [String] = []
    var letEventPropNames: [String] = []
    let letDiagnosticIndex = propDiagnostics.count
    for binding in varDecl.bindings {
      // A computed property is never a prop, but an accessor block alone doesn't mean computed:
      // `willSet`/`didSet` observers imply stored storage. `bindingIsSettable` draws exactly that
      // line, so a stored property with observers stays part of the surface.
      if binding.accessorBlock != nil && !bindingIsSettable(binding) {
        continue
      }
      // A tuple-destructuring binding (`var (a, b) = (1, 2)`) has no single name to key a prop on,
      // and silently dropping it would leave the props type missing fields the author declared.
      guard let ident = binding.pattern.as(IdentifierPatternSyntax.self) else {
        if binding.pattern.is(TuplePatternSyntax.self) {
          throw MacroExpansionErrorMessage(
            "@ViewProps does not support tuple-destructuring properties. Declare each prop separately"
          )
        }
        continue
      }
      // An escaped name (`` var `default`: Int ``) needs both spellings: `identifier.text` keeps the
      // backticks, which every identifier position requires (`case \`default\``), while the wire key
      // and `_eventNames` need the bare name.
      let name = ident.identifier.text

      // Prefer the explicit annotation. When it's omitted, recover the type from a literal default
      // (`var title = ""`). Anything a syntactic macro can't resolve still needs an annotation,
      // since the decode surface names the type.
      let declaredType = binding.typeAnnotation?.type
      let resolvedType =
        declaredType?.trimmedDescription
        ?? binding.initializer.flatMap { inferredLiteralType(of: $0.value) }
      guard let resolvedType else {
        throw MacroExpansionErrorMessage(
          "@ViewProps props must declare an explicit type: '\(name)' has none"
        )
      }

      // React keeps `key` and `ref` for itself and never passes them to a native view.
      if reactReservedPropNames.contains(withoutBackticks(name)) {
        propDiagnostics.append(reactReservedPropDiagnostic(for: ident, name: name))
      }

      // A function type means an event. An *optional* function type would make the event's presence
      // dynamic, but events are registered once at view creation from a static name list, so there
      // is no shape that could express "sometimes emitted".
      if let declaredType, isOptionalType(declaredType), underlyingFunctionType(of: declaredType) != nil {
        propDiagnostics.append(optionalEventDiagnostic(for: declaredType, name: name))
        continue
      }

      let eventFunctionType = declaredType.flatMap(underlyingFunctionType)
      let isEvent = eventFunctionType != nil
      // `PropSet` stores its mask in `rawValue`, so a value prop of that name would emit a static
      // member shadowing it and the option set would not compile ("circular reference"). The error
      // would point at generated code, so catch it here and name the property.
      if !isEvent && withoutBackticks(name) == "rawValue" {
        throw MacroExpansionErrorMessage(
          "'rawValue' can't be used as a prop name: it collides with the synthesized PropSet's storage. Rename the property"
        )
      }
      // Only stored storage takes an initial value; a computed prop with a setter needs none.
      let needsInitialValue =
        binding.initializer == nil && isStoredBinding(binding) && !declaresUsableInitializer
      let prop = ViewProp(
        name: name,
        type: resolvedType,
        hasMutatingGetter: hasMutatingGetter(binding),
        defaultValue: propDefault(
          of: binding,
          in: varDecl,
          declaredType: declaredType,
          declaresUsableInitializer: declaresUsableInitializer
        )
      )
      if let eventFunctionType {
        // An event is dispatched to JavaScript, which can't hand a value back to the caller.
        if !returnsVoid(eventFunctionType) {
          propDiagnostics.append(eventReturnTypeDiagnostic(for: eventFunctionType.returnClause.type, name: name))
        }
        // JavaScript gets one payload object for an event, so the closure that `_bindEvents(to:)`
        // assigns can pass on at most one parameter.
        if eventFunctionType.parameters.count > 1 {
          propDiagnostics.append(eventParameterCountDiagnostic(for: eventFunctionType, name: name))
        } else if let parameter = eventFunctionType.parameters.first,
          let diagnostic = eventParameterDiagnostic(
            for: parameter,
            in: eventFunctionType,
            binding: binding,
            name: name,
            structDeclaresInitializer: declaresUsableInitializer || declaresOtherInitializer
          )
        {
          propDiagnostics.append(diagnostic)
        }
        // `_bindEvents(to:)` assigns every event prop, so none can be a constant.
        if varDecl.bindingSpecifier.tokenKind == .keyword(.let) {
          letEventPropNames.append(name)
        }
        if let initializer = binding.initializer, !isEmptyClosure(initializer.value) {
          warnings.append(
            unusedEventInitialValueDiagnostic(
              for: initializer,
              name: name,
              arity: eventFunctionType.parameters.count
            )
          )
        }
        let eventType = normalizedEventType(of: withoutBackticks(name))
        if bubblingEventTypes.contains(eventType) {
          propDiagnostics.append(bubblingEventNameDiagnostic(for: ident, name: name))
        }
        if let otherName = eventPropsByType[eventType] {
          propDiagnostics.append(
            duplicateEventTypeDiagnostic(for: ident, name: name, otherName: otherName, eventType: eventType)
          )
        } else {
          eventPropsByType[eventType] = name
        }
        if needsInitialValue {
          eventDefaults.append(
            EventDefault(name: name, emptyClosure: emptyClosure(arity: eventFunctionType.parameters.count))
          )
        }
        eventProps.append(ViewEvent(name: name, takesPayload: !eventFunctionType.parameters.isEmpty))
        continue
      }
      // `_decode` assigns every value prop, so none can be a constant.
      if varDecl.bindingSpecifier.tokenKind == .keyword(.let) {
        letValuePropNames.append(name)
      }
      // A removed prop is reset to its value in a fresh `Self()`, so every value prop needs a
      // default: its initial value, or the `nil` that Swift gives an optional `var` without one.
      if needsInitialValue && !(declaredType.map(hasImplicitNilDefault) ?? false) {
        propDiagnostics.append(missingDefaultDiagnostic(for: ident, name: name, type: declaredType))
      }
      valueProps.append(prop)
    }
    if !letValuePropNames.isEmpty || !letEventPropNames.isEmpty {
      propDiagnostics.insert(
        letPropDiagnostic(for: varDecl, valueNames: letValuePropNames, eventNames: letEventPropNames),
        at: letDiagnosticIndex
      )
    }
  }
  // Reported together, so one run names every prop that the generated code can't reset, assign or
  // default.
  if !propDiagnostics.isEmpty {
    throw DiagnosticsError(diagnostics: propDiagnostics)
  }

  guard valueProps.count <= maxValueProps else {
    throw MacroExpansionErrorMessage(
      "@ViewProps supports at most \(maxValueProps) value props (the changed-props mask is a UInt64), but this type declares \(valueProps.count), and '\(valueProps[maxValueProps].name)' is the first over the limit. Event props don't count toward it"
    )
  }
  return ViewPropsModel(
    valueProps: valueProps,
    eventProps: eventProps,
    eventDefaults: eventDefaults,
    generatesInitializer: needsGeneratedInitializer(
      structDecl,
      in: lexicalContext,
      eventDefaults: eventDefaults,
      declaresUsableInitializer: declaresUsableInitializer,
      declaresOtherInitializer: declaresOtherInitializer
    ),
    warnings: warnings
  )
}

/// The members of a type body in source order, with the members of every `#if` clause in place of
/// the conditional declaration. The original conditions remain in the source; this is only for
/// discovering declarations that exist in one or more compilation configurations.
private func flattenedMembers(_ members: MemberBlockItemListSyntax) -> [MemberBlockItemSyntax] {
  return members.flatMap { member -> [MemberBlockItemSyntax] in
    guard let ifConfig = member.decl.as(IfConfigDeclSyntax.self) else {
      return [member]
    }
    return ifConfig.clauses.flatMap { clause -> [MemberBlockItemSyntax] in
      guard case .decls(let declarations) = clause.elements else {
        return []
      }
      return flattenedMembers(declarations)
    }
  }
}

/// Whether Swift's own `init()` can't satisfy `AnyViewProps`, so the macro generates a public one.
/// Swift synthesizes `init()` only when every stored property has a default and the type declares
/// no initializer, and that `init()` is `internal`, which the conformance of a `public` or `package`
/// type can't use. The author's usable `init()` always wins, so there is never a second one.
private func needsGeneratedInitializer(
  _ structDecl: StructDeclSyntax,
  in lexicalContext: [Syntax],
  eventDefaults: [EventDefault],
  declaresUsableInitializer: Bool,
  declaresOtherInitializer: Bool
) -> Bool {
  if declaresUsableInitializer {
    return false
  }
  return !eventDefaults.isEmpty || isAboveInternal(structDecl, in: lexicalContext) || declaresOtherInitializer
}

/// True if the type's access is `public`, `open` or `package`: written on the type, or, when the type
/// has no access modifier, taken from the extension that directly contains it
/// (`public extension Outer { struct Props {} }`). Only that extension sets the default; an enclosing
/// type doesn't, so a type nested in a `public` type without a modifier is `internal`.
private func isAboveInternal(_ structDecl: StructDeclSyntax, in lexicalContext: [Syntax]) -> Bool {
  if let access = accessLevelModifier(in: structDecl.modifiers) {
    return isAboveInternal(access)
  }
  guard let enclosingExtension = lexicalContext.first?.as(ExtensionDeclSyntax.self),
    let access = accessLevelModifier(in: enclosingExtension.modifiers)
  else {
    return false
  }
  return isAboveInternal(access)
}

/// The access level modifier of a declaration, without a `(set)` detail, which only limits a setter.
private func accessLevelModifier(in modifiers: DeclModifierListSyntax) -> TokenKind? {
  return modifiers.first { modifier in
    guard modifier.detail == nil else {
      return false
    }
    switch modifier.name.tokenKind {
    case .keyword(.public), .keyword(.open), .keyword(.package), .keyword(.internal), .keyword(.fileprivate),
      .keyword(.private):
      return true
    default:
      return false
    }
  }?.name.tokenKind
}

private func isAboveInternal(_ access: TokenKind) -> Bool {
  return access == .keyword(.public) || access == .keyword(.open) || access == .keyword(.package)
}

/// True if the binding has storage: no accessor block, or only `willSet`/`didSet` observers.
private func isStoredBinding(_ binding: PatternBindingSyntax) -> Bool {
  guard let accessorBlock = binding.accessorBlock else {
    return true
  }
  guard case .accessors(let accessors) = accessorBlock.accessors else {
    return false
  }
  return accessors.allSatisfy { accessor in
    accessor.accessorSpecifier.tokenKind == .keyword(.willSet)
      || accessor.accessorSpecifier.tokenKind == .keyword(.didSet)
  }
}

/// The errors for the `private` and `fileprivate` stored properties of a declaration that have no
/// initial value. `static`, `class` and `lazy` properties are exempt, and so is an optional `var`
/// written as `T?` or `T!`, which defaults to `nil`.
private func unsetPrivatePropertyDiagnostics(of varDecl: VariableDeclSyntax) -> [Diagnostic] {
  guard
    let access = varDecl.modifiers.first(where: {
      $0.name.tokenKind == .keyword(.private) || $0.name.tokenKind == .keyword(.fileprivate)
    }),
    !varDecl.modifiers.contains(where: {
      $0.name.tokenKind == .keyword(.static) || $0.name.tokenKind == .keyword(.class)
        || $0.name.tokenKind == .keyword(.lazy)
    })
  else {
    return []
  }
  let isVar = varDecl.bindingSpecifier.tokenKind == .keyword(.var)
  return varDecl.bindings.compactMap { binding in
    guard binding.initializer == nil, isStoredBinding(binding),
      let ident = binding.pattern.as(IdentifierPatternSyntax.self),
      !(isVar && resolvedTypeAnnotation(of: binding, in: varDecl).map { hasImplicitNilDefault($0.type) } == true)
    else {
      return nil
    }
    return unsetPrivatePropertyDiagnostic(for: ident, access: access.name.text)
  }
}

/// The binding's own type annotation, or the trailing annotation shared with preceding bindings.
private func resolvedTypeAnnotation(
  of binding: PatternBindingSyntax,
  in varDecl: VariableDeclSyntax
) -> TypeAnnotationSyntax? {
  if let typeAnnotation = binding.typeAnnotation {
    return typeAnnotation
  }
  var foundBinding = false
  for candidate in varDecl.bindings {
    if foundBinding, let typeAnnotation = candidate.typeAnnotation {
      return typeAnnotation
    }
    foundBinding = candidate.id == binding.id
  }
  return nil
}

/// True if the function type returns `Void`, written as `Void`, `Swift.Void` or `()`, in any number
/// of enclosing parentheses, such as `(Void)` or `((()))`.
private func returnsVoid(_ functionType: FunctionTypeSyntax) -> Bool {
  return isVoidType(functionType.returnClause.type)
}

private func isVoidType(_ type: TypeSyntax) -> Bool {
  let type = withoutParentheses(type)
  if let tuple = type.as(TupleTypeSyntax.self) {
    return tuple.elements.isEmpty
  }
  return ["Void", "Swift.Void"].contains(type.trimmedDescription)
}

/// True if the binding is computed with a `mutating get`.
private func hasMutatingGetter(_ binding: PatternBindingSyntax) -> Bool {
  guard case .accessors(let accessors) = binding.accessorBlock?.accessors else {
    return false
  }
  return accessors.contains { accessor in
    accessor.accessorSpecifier.tokenKind == .keyword(.get)
      && accessor.modifiers.contains { $0.name.tokenKind == .keyword(.mutating) }
  }
}

/// A closure literal that takes `arity` arguments, ignores them and does nothing.
private func emptyClosure(arity: Int) -> String {
  if arity == 0 {
    return "{}"
  }
  return "{ \(Array(repeating: "_", count: arity).joined(separator: ", ")) in }"
}

/// True if Swift gives a `var` of this type an implicit `nil` initial value, so `Self()` can leave it
/// out. Only the `T?` and `T!` sugar does, also in parentheses (`(T?)`): a property written as
/// `Optional<T>` has no default.
private func hasImplicitNilDefault(_ type: TypeSyntax) -> Bool {
  let type = withoutParentheses(type)
  return type.is(OptionalTypeSyntax.self) || type.is(ImplicitlyUnwrappedOptionalTypeSyntax.self)
}

/// The function type a props property declares, unwrapping any number of enclosing parentheses and an
/// optional wrapper, or `nil` when the type isn't a function. `@Sendable`/`@escaping` and other
/// attributed forms unwrap to the function type underneath.
private func underlyingFunctionType(of type: TypeSyntax) -> FunctionTypeSyntax? {
  if let functionType = type.as(FunctionTypeSyntax.self) {
    return functionType
  }
  if let tuple = type.as(TupleTypeSyntax.self), tuple.elements.count == 1, let only = tuple.elements.first {
    return underlyingFunctionType(of: only.type)
  }
  if let attributed = type.as(AttributedTypeSyntax.self) {
    return underlyingFunctionType(of: attributed.baseType)
  }
  if let optional = type.as(OptionalTypeSyntax.self) {
    return underlyingFunctionType(of: optional.wrappedType)
  }
  if let implicitlyUnwrapped = type.as(ImplicitlyUnwrappedOptionalTypeSyntax.self) {
    return underlyingFunctionType(of: implicitlyUnwrapped.wrappedType)
  }
  // The long spelling of an optional: `Optional<() -> Void>` has to reach the same diagnostic as
  // `(() -> Void)?` and `(() -> Void)!`, or the same declaration would be an event in one spelling
  // and a value prop in another.
  if let identifier = type.as(IdentifierTypeSyntax.self),
    identifier.name.text == "Optional",
    let argument = identifier.genericArgumentClause?.arguments.first,
    case .type(let wrapped) = argument.argument
  {
    return underlyingFunctionType(of: wrapped)
  }
  return nil
}

// MARK: - Synthesized members

/// The `PropName` enum: one case per value prop, `String`-backed so the raw value is the wire key.
/// Emitted even when empty, so a props type with only events still conforms. An enum with no cases
/// can't declare a raw type, so the empty one conforms to `RawRepresentable` by hand, with `String`
/// as its `RawValue` like the others.
///
/// The enum is `@frozen`, so the `switch` in the `@inlinable` `propSet(for:)` compiles in a module
/// built with library evolution, where it would otherwise need a case for unknown values. The cases
/// and their order are already part of the ABI, as the bits of `PropSet`.
private func propNameEnum(valueProps: [ViewProp]) -> DeclSyntax {
  // An escaped case takes its raw value from the bare identifier already, but spelling it out keeps
  // the wire key visible in the generated source and independent of that implicit rule.
  let cases =
    valueProps
    .map { prop in
      prop.name == prop.wireName
        ? "  case \(prop.name)"
        : "  case \(prop.name) = \"\(prop.wireName)\""
    }
    .joined(separator: "\n")
  if valueProps.isEmpty {
    return """
      @frozen nonisolated public enum PropName: RawRepresentable, CaseIterable {
        public init?(rawValue: String) {
          return nil
        }

        public var rawValue: String {
          switch self {
          }
        }
      }
      """
  }
  return """
    @frozen nonisolated public enum PropName: String, CaseIterable {
    \(raw: cases)
    }
    """
}

/// The `PropSet` option set: one static member per value prop, at its declaration-order bit. This is
/// what a diff's `changedProps` holds, and what `changed(_:)` tests against, so the whole changed set
/// is one machine word.
private func propSetStruct(valueProps: [ViewProp]) -> DeclSyntax {
  let members = valueProps.enumerated()
    .map { index, prop in
      "  public static let \(prop.name) = PropSet(rawValue: 1 << \(index))"
    }
    .joined(separator: "\n")

  if valueProps.isEmpty {
    return """
      nonisolated public struct PropSet: OptionSet, Sendable {
        public let rawValue: UInt64

        public init(rawValue: UInt64) {
          self.rawValue = rawValue
        }
      }
      """
  }
  return """
    nonisolated public struct PropSet: OptionSet, Sendable {
      public let rawValue: UInt64

      public init(rawValue: UInt64) {
        self.rawValue = rawValue
      }

    \(raw: members)
    }
    """
}

/// The event props' names, verbatim, for core to register at view creation. Verbatim because a view
/// event prop is a React prop name Fabric carries as-is — unlike `@Event` on a module, which strips
/// the `on` prefix.
private func eventNamesConstant(eventProps: [ViewEvent]) -> DeclSyntax {
  let names = eventProps.map { "\"\($0.wireName)\"" }.joined(separator: ", ")
  return """
    nonisolated public static let _eventNames: [String] = [\(raw: names)]
    """
}

/// `_bindEvents(to:)`, which sets each event prop to a closure that dispatches the event with its name in
/// JavaScript and its parameter as the payload. Core calls it once for each view, on the props that the
/// view starts from, and the closures stay in the copies that later decodes make. Members are reached
/// through `self.` and the dispatcher is `_events`, so an event named like the parameter isn't shadowed
/// by it. Returns an empty string when there is no event: `AnyViewProps` has a default that does
/// nothing.
private func bindEventsFunction(eventProps: [ViewEvent]) -> String {
  guard !eventProps.isEmpty else {
    return ""
  }
  let assignments = eventProps.map { event in
    let payload = event.takesPayload ? ", $0" : ""
    return "    self.\(event.name) = { _events.dispatch(\"\(event.wireName)\"\(payload)) }"
  }
  return """


      nonisolated public mutating func _bindEvents(to _events: ViewEventDispatcher) {
    \(assignments.joined(separator: "\n"))
      }
    """
}

/// The body of `_decode`, which core calls once per changed prop. React sends a removed prop as
/// `null`, so `null` and `undefined` reset the prop with `_resetViewProp`; any other value decodes
/// through `JavaScriptDecodable`, with the type inferred from the assignment. `_decodeViewProp` is a
/// static member of `AnyViewProps`, reached through `Self.`, so a prop with the same name doesn't
/// shadow it. The checks run once, before the switch, so each case is a single assignment. Members
/// are reached through `self.` so that a prop named like a parameter (`value`, `runtime`) isn't
/// shadowed by it.
///
/// With no value prop the body is empty: `PropName` is uninhabited, so the function is never called.
private func decodeFunctionBody(valueProps: [ViewProp]) -> String {
  if valueProps.isEmpty {
    return ""
  }
  let decodeCases =
    valueProps
    .map { "    case .\($0.name):\n      self.\($0.name) = try Self._decodeViewProp(value, in: runtime)" }
    .joined(separator: "\n")
  // Starts with a line break, so the empty body closes on the next line instead of leaving a blank
  // one.
  return """

        if value.isNull() || value.isUndefined() {
          Self._resetViewProp(name, in: &self)
          return
        }
        switch name {
    \(decodeCases)
        }
    """
}

/// `_resetViewProp(_:in:)`, which sets one value prop back to its default when React removes it. Each
/// case assigns the prop's initial value or `nil`, so a reset evaluates only that prop's default. A
/// prop whose default the macro can't tell from the declaration reads it from a new `Self()`.
///
/// A static function of the struct body resolves names as a property initializer does: a static
/// member without `Self.` and a member of an enclosing type, which `_decode` in the extension can't
/// name. The parameters are `_name` and `_props`, with a number after the name when an initial value
/// uses it, so they don't hide a declaration that an initial value names.
///
/// A default argument such as `#function` or `#line` of a function that an initial value calls gets
/// the location of `_resetViewProp`, which the macro can't see.
///
/// `nil` with no value prop: `PropName` is uninhabited, so `_decode` never resets.
private func resetFunction(valueProps: [ViewProp]) -> DeclSyntax? {
  if valueProps.isEmpty {
    return nil
  }
  let usedNames = Set(
    valueProps.flatMap { prop -> [String] in
      guard case .initialValue(let expression) = prop.defaultValue else {
        return []
      }
      return expression.tokens(viewMode: .sourceAccurate).compactMap { token in
        guard case .identifier(let text) = token.tokenKind else {
          return nil
        }
        return withoutBackticks(text)
      }
    }
  )
  let nameParameter = unusedName("_name", in: usedNames)
  let propsParameter = unusedName("_props", in: usedNames)
  let cases =
    valueProps
    .map { prop -> String in
      let assignment: String
      switch prop.defaultValue {
      case .initialValue(let expression):
        assignment = "\(propsParameter).\(prop.name) = \(expression.trimmedDescription)"
      case .implicitNil:
        assignment = "\(propsParameter).\(prop.name) = nil"
      case .newInstance where prop.hasMutatingGetter:
        // A mutating getter can't be read from a constant. The local is scoped to its case, where
        // no initial value is copied.
        assignment = "var _defaults = Self()\n    \(propsParameter).\(prop.name) = _defaults.\(prop.name)"
      case .newInstance:
        assignment = "\(propsParameter).\(prop.name) = Self().\(prop.name)"
      }
      return "  case .\(prop.name):\n    \(assignment)"
    }
    .joined(separator: "\n")
  return """
    @JavaScriptActor
    static func _resetViewProp(_ \(raw: nameParameter): PropName, in \(raw: propsParameter): inout Self) {
      switch \(raw: nameParameter) {
    \(raw: cases)
      }
    }
    """
}

/// `base`, or `base` with the lowest number after it that gives a name not in `names`.
private func unusedName(_ base: String, in names: Set<String>) -> String {
  if !names.contains(base) {
    return base
  }
  var number = 1
  while names.contains("\(base)\(number)") {
    number += 1
  }
  return "\(base)\(number)"
}

/// The public `init()` that `AnyViewProps` requires, when Swift's own can't satisfy it: it gives each
/// event prop without an initial value an empty closure, and leaves the value props at their initial
/// values. `nil` when the type declares a usable `init()`, or when Swift's `init()` is enough (see
/// `needsGeneratedInitializer`).
private func defaultInitializer(props: ViewPropsModel) -> DeclSyntax? {
  if !props.generatesInitializer {
    return nil
  }
  if props.eventDefaults.isEmpty {
    return """
      nonisolated public init() {
      }
      """
  }
  let assignments = props.eventDefaults
    .map { "  self.\($0.name) = \($0.emptyClosure)" }
    .joined(separator: "\n")
  return """
    nonisolated public init() {
    \(raw: assignments)
    }
    """
}

/// The nested spelling of core's one generic diff, so a view writes `MyProps.Diff`.
private func diffTypealias() -> DeclSyntax {
  return """
    public typealias Diff = PropsDiff<Self>
    """
}
