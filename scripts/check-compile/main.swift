// Decodes and resets the props of `Props.swift` through the generic code in `Core.swift`, compares
// each reset prop with its value in `Self()`, and dispatches the bound events. Then checks the views of
// `Views.swift` and the JavaScript class chain of the shared objects of `SharedObjects.swift`. Exits with a
// nonzero status when a check fails.

import Core
import Darwin

@JavaScriptActor
func check() throws -> [String] {
  var failures: [String] = []
  func expect<T: Equatable>(_ actual: T, _ expected: T, _ label: String) {
    if actual != expected {
      failures.append("\(label): \(actual) isn't \(expected)")
    }
  }

  let decoded = try decoding(PublicProps(), [(.title, 2), (.count, 3), (.ratio, 0.5)])
  expect(decoded.props.title, "2.0", "PublicProps.title decoded")
  expect(decoded.props.count, 3, "PublicProps.count decoded")
  expect(decoded.props.ratio, 0.5, "PublicProps.ratio decoded")
  expect(decoded.changed, PublicProps.allProps.rawValue, "PublicProps changed props")
  let reset = try decoding(decoded.props, PublicProps.PropName.allCases.map { ($0, nil) }).props
  expect(reset.title, "", "PublicProps.title reset")
  expect(reset.count, 1, "PublicProps.count reset")
  expect(reset.ratio, nil, "PublicProps.ratio reset")

  let fresh = InitialValueProps()
  var changed = fresh
  changed.title = "changed"
  changed.name = "changed"
  changed.source = "changed"
  changed.line = 0
  changed.weights = []
  changed.level = 0
  changed.maybe = 1
  let initialValues = try decoding(changed, InitialValueProps.PropName.allCases.map { ($0, nil) }).props
  expect(initialValues.title, fresh.title, "InitialValueProps.title reset")
  expect(initialValues.name, fresh.name, "InitialValueProps.name reset")
  expect(initialValues.source, fresh.source, "InitialValueProps.source reset")
  expect(initialValues.line, fresh.line, "InitialValueProps.line reset")
  expect(initialValues.weights, fresh.weights, "InitialValueProps.weights reset")
  expect(initialValues.level, fresh.level, "InitialValueProps.level reset")
  expect(initialValues.levelChanges, 2, "InitialValueProps.level observer")
  expect(initialValues.maybe, nil, "InitialValueProps.maybe reset")

  let freeForm = try decoding(FreeFormProps(), FreeFormProps.PropName.allCases.map { ($0, 2) })
  expect(freeForm.props.extraProps?["value"] as? Double, 2, "FreeFormProps.extraProps decoded")
  expect(freeForm.props.modifiers?.first?["value"] as? Double, 2, "FreeFormProps.modifiers decoded")
  expect(freeForm.props.items.first as? Double, 2, "FreeFormProps.items decoded")
  expect(freeForm.props.payload as? Double, 2, "FreeFormProps.payload decoded")
  expect(freeForm.props.options["value"] as? Double, 2, "FreeFormProps.options decoded")
  expect(freeForm.props.maybe as? Double, 2, "FreeFormProps.maybe decoded")
  expect(freeForm.changed, FreeFormProps.allProps.rawValue, "FreeFormProps changed props")
  let freeFormReset = try decoding(freeForm.props, FreeFormProps.PropName.allCases.map { ($0, nil) }).props
  expect(freeFormReset.extraProps == nil, true, "FreeFormProps.extraProps reset")
  expect(freeFormReset.modifiers == nil, true, "FreeFormProps.modifiers reset")
  expect(freeFormReset.items.isEmpty, true, "FreeFormProps.items reset")
  expect(freeFormReset.payload as? Int, 0, "FreeFormProps.payload reset")
  expect(freeFormReset.options as? [String: String], ["key": "default"], "FreeFormProps.options reset")
  expect(freeFormReset.maybe == nil, true, "FreeFormProps.maybe reset")

  var nested = Screen.NestedProps()
  nested.gap = 0
  expect(try decoding(nested, [(.gap, nil)]).props.gap, 8, "Screen.NestedProps.gap reset")

  var authorInit = AuthorInitProps()
  authorInit.title = "changed"
  expect(try decoding(authorInit, [(.title, nil)]).props.title, "set by init()", "AuthorInitProps.title reset")

  var computed = ComputedProps()
  computed.storage = 100
  expect(try decoding(computed, [(.doubled, nil)]).props.storage, 4, "ComputedProps.doubled reset")
  expect(try decoding(computed, [(.halved, nil)]).props.storage, 4, "ComputedProps.halved reset")

  let dispatcher = ViewEventDispatcher()
  let boundEvents = bindingEvents(of: EventsOnlyProps.self, to: dispatcher)
  boundEvents.onTap()
  boundEvents.onValueChange(3)
  // Without events, the props keep the default of `AnyViewProps`, which binds nothing.
  _ = bindingEvents(of: PublicProps.self, to: dispatcher)
  expect(dispatcher.events, ["onTap", "onValueChange: 3"], "EventsOnlyProps dispatched events")

  let kindsDispatcher = ViewEventDispatcher()
  let kinds = bindingEvents(of: EventKindsProps.self, to: kindsDispatcher)
  kinds.onSendable(1)
  try kinds.onThrows(2)
  kinds.onNonSendable(NonSendablePayload())
  kinds._events(4)
  kinds.`default`()
  expect(kindsDispatcher.events.count, 5, "EventKindsProps dispatched events")
  expect(Array(kindsDispatcher.events.suffix(2)), ["_events: 4", "default"], "EventKindsProps event names")

  expect(propNames(of: PublicProps.self), ["title", "count", "ratio"], "PublicProps names")
  expect(propNames(of: EventsOnlyProps.self), ["onTap", "onValueChange"], "EventsOnlyProps names")

  failures += try checkExtendingProps()
  return failures
}

// Decodes, resets and binds the props that extend other props, through the generic code in `Core.swift`. The own
// props take the low bits, and the props of `base` the bits above them.
@JavaScriptActor
func checkExtendingProps() throws -> [String] {
  var failures: [String] = []
  func expect<T: Equatable>(_ actual: T, _ expected: T, _ label: String) {
    if actual != expected {
      failures.append("\(label): \(actual) isn't \(expected)")
    }
  }

  let extending = try decoding(ExtendingProps(), [(.label, 2), (.base(.count), 3), (.base(.title), 4)])
  expect(extending.props.label, "2.0", "ExtendingProps.label decoded")
  expect(extending.props.base.count, 3, "ExtendingProps.base.count decoded")
  expect(extending.props.base.title, "4.0", "ExtendingProps.base.title decoded")
  expect(extending.changed, 0b0111, "ExtendingProps changed props")
  expect(ExtendingProps.allProps.rawValue, 0b1111, "ExtendingProps.allProps")
  expect(ExtendingProps.PropSet.base(.ratio).rawValue, 0b1000, "ExtendingProps.PropSet.base(.ratio)")
  let extendingReset = try decoding(extending.props, [(.label, nil), (.base(.count), nil), (.base(.title), nil)])
  expect(extendingReset.props.label, "label", "ExtendingProps.label reset")
  expect(extendingReset.props.base.count, 1, "ExtendingProps.base.count reset")
  expect(extendingReset.props.base.title, "", "ExtendingProps.base.title reset")
  expect(ExtendingProps.PropName(rawValue: "count"), .base(.count), "ExtendingProps.PropName(rawValue:) of a base prop")
  expect(ExtendingProps.PropName(rawValue: "label"), .label, "ExtendingProps.PropName(rawValue:) of an own prop")
  expect(ExtendingProps.PropName(rawValue: "onSelect"), nil, "ExtendingProps.PropName(rawValue:) of an event")
  expect(
    propNames(of: ExtendingProps.self),
    ["label", "title", "count", "ratio", "onSelect"],
    "ExtendingProps names"
  )

  let chained = try decoding(ChainedProps(), [(.base(.base(.count)), 7), (.level, 4)])
  expect(chained.props.base.base.count, 7, "ChainedProps.base.base.count decoded")
  expect(chained.props.level, 4, "ChainedProps.level decoded")
  expect(chained.changed, 0b01001, "ChainedProps changed props")
  expect(ChainedProps.allProps.rawValue, 0b11111, "ChainedProps.allProps")
  expect(try decoding(chained.props, [(.base(.base(.count)), nil)]).props.base.base.count, 1, "ChainedProps reset")
  expect(
    propNames(of: ChainedProps.self),
    ["level", "label", "title", "count", "ratio", "onSelect"],
    "ChainedProps names"
  )
  let chainedDispatcher = ViewEventDispatcher()
  bindingEvents(of: ChainedProps.self, to: chainedDispatcher).base.onSelect(2)
  expect(chainedDispatcher.events, ["onSelect: 2"], "ChainedProps dispatched events")

  expect(ExtendingEventsOnlyProps.allProps.rawValue, 0, "ExtendingEventsOnlyProps.allProps")
  expect(
    propNames(of: ExtendingEventsOnlyProps.self),
    ["onClose", "onTap", "onValueChange"],
    "ExtendingEventsOnlyProps names"
  )
  let eventsDispatcher = ViewEventDispatcher()
  let events = bindingEvents(of: ExtendingEventsOnlyProps.self, to: eventsDispatcher)
  events.onClose()
  events.base.onTap()
  events.base.onValueChange(3)
  expect(
    eventsDispatcher.events,
    ["onClose", "onTap", "onValueChange: 3"],
    "ExtendingEventsOnlyProps dispatched events"
  )

  var stepper = StepperProps()
  stepper.value = 0
  let stepperDecoded = try decoding(stepper, [(.value, nil), (.base(.modifiers), 2), (.base(.testID), 1)])
  expect(stepperDecoded.props.value, 5, "StepperProps.value reset to its value in init()")
  expect(stepperDecoded.props.base.modifiers?.first?["value"] as? Double, 2, "StepperProps.base.modifiers decoded")
  expect(stepperDecoded.props.base.testID, "1.0", "StepperProps.base.testID decoded")
  let stepperReset = try decoding(stepperDecoded.props, [(.base(.modifiers), nil), (.base(.testID), nil)]).props
  expect(stepperReset.base.modifiers == nil, true, "StepperProps.base.modifiers reset")
  expect(stepperReset.base.testID, nil, "StepperProps.base.testID reset")
  expect(
    propNames(of: StepperProps.self),
    ["value", "modifiers", "testID", "onValueChange", "onGlobalEvent"],
    "StepperProps names"
  )
  let stepperDispatcher = ViewEventDispatcher()
  let stepperEvents = bindingEvents(of: StepperProps.self, to: stepperDispatcher)
  stepperEvents.onValueChange(1)
  stepperEvents.base.onGlobalEvent(2)
  expect(stepperDispatcher.events, ["onValueChange: 1", "onGlobalEvent: 2"], "StepperProps dispatched events")

  var nested = ExtendingNestedProps()
  nested.base.gap = 0
  expect(try decoding(nested, [(.base(.gap), nil)]).props.base.gap, 8, "ExtendingNestedProps.base.gap reset")
  return failures
}

// Applies props to the views of `Views.swift` and creates them through the generic code in `Core.swift`, checks
// the app context that they keep, and their names.
@MainActor
func checkViews() -> [String] {
  var failures: [String] = []
  func expect<T: Equatable>(_ actual: T, _ expected: T, _ label: String) {
    if actual != expected {
      failures.append("\(label): \(actual) isn't \(expected)")
    }
  }

  let card = CardView()
  var cardProps = PublicProps()
  cardProps.title = "Card"
  applying(cardProps, to: card)
  expect(card.titles, ["Card"], "CardView.didUpdateProps")
  expect(jsName(of: CardView.self), "CardView", "CardView name")
  expect(jsName(of: NamedCardView.self), "FancyCard", "NamedCardView name")

  let preview = SliderView(props: PublicProps(), children: ExpoSwiftUI.Children())
  expect(preview.appContext == nil, true, "SliderView.appContext in a preview")
  expect(preview.hasAppContext(), false, "SliderView.hasAppContext() in a preview")

  var appContext: AppContext? = AppContext()
  let slider = makingView(SliderView.self, props: PublicProps(), appContext: appContext)
  expect(slider.appContext === appContext, true, "SliderView.appContext")
  expect(slider.hasAppContext(), true, "SliderView.hasAppContext()")
  // The view keeps a weak reference, so it doesn't keep the app context alive.
  appContext = nil
  expect(slider.appContext == nil, true, "SliderView.appContext after release")
  expect(ObjectIdentifier(SliderView.Props.self), ObjectIdentifier(PublicProps.self), "SliderView.Props")
  expect(jsName(of: SliderView.self), "SliderView", "SliderView name")

  let labeledContext = AppContext()
  expect(LabeledView(props: PublicProps(), children: ExpoSwiftUI.Children()).isPreview, true, "LabeledView preview")
  let labeled = makingView(LabeledView.self, props: PublicProps(), appContext: labeledContext)
  expect(labeled.isPreview, false, "LabeledView.isPreview")
  expect(labeled.appContext === labeledContext, true, "LabeledView.appContext")
  expect(jsName(of: LabeledView.self), "Labeled", "LabeledView name")
  return failures
}

// Checks the places of the shared objects of `SharedObjects.swift` in the JavaScript class chain.
func checkSharedObjects() -> [String] {
  var failures: [String] = []
  func expect(_ actual: (any AnyJavaScriptClass.Type)?, _ expected: (any AnyJavaScriptClass.Type)?, _ label: String) {
    if actual != expected {
      failures.append("\(label): \(String(describing: actual)) isn't \(String(describing: expected))")
    }
  }

  expect(ChainRoot._jsClassType, ChainRoot.self, "ChainRoot._jsClassType")
  expect(ChainRoot._jsSuperclassType, nil, "ChainRoot._jsSuperclassType")
  expect(ChainMiddle._jsClassType, ChainRoot.self, "ChainMiddle._jsClassType")
  expect(ChainLeaf._jsClassType, ChainLeaf.self, "ChainLeaf._jsClassType")
  expect(ChainLeaf._jsSuperclassType, ChainRoot.self, "ChainLeaf._jsSuperclassType")
  expect(GenericBox<Int>._jsClassType, GenericBox<Int>.self, "GenericBox<Int>._jsClassType")
  expect(GenericBox<String>._jsClassType, GenericBox<String>.self, "GenericBox<String>._jsClassType")
  expect(IntBox._jsSuperclassType, GenericBox<Int>.self, "IntBox._jsSuperclassType")
  expect(NumberRef._jsClassType, NumberRef.self, "NumberRef._jsClassType")
  expect(NumberRef._jsSuperclassType, nil, "NumberRef._jsSuperclassType")
  expect(Namespace.Nested._jsClassType, Namespace.Nested.self, "Namespace.Nested._jsClassType")
  return failures
}

// Checks the places of the classes of `JSClasses.swift` in the JavaScript class chain, also through
// `AnyJavaScriptClass`, as core reads them.
func checkJSClasses() -> [String] {
  var failures: [String] = []
  func expect(_ actual: (any AnyJavaScriptClass.Type)?, _ expected: (any AnyJavaScriptClass.Type)?, _ label: String) {
    if actual != expected {
      failures.append("\(label): \(String(describing: actual)) isn't \(String(describing: expected))")
    }
  }

  expect(ClassRoot._jsClassType, ClassRoot.self, "ClassRoot._jsClassType")
  expect(ClassRoot._jsSuperclassType, nil, "ClassRoot._jsSuperclassType")
  expect(ClassMiddle._jsClassType, ClassRoot.self, "ClassMiddle._jsClassType")
  expect(ClassLeaf._jsClassType, ClassLeaf.self, "ClassLeaf._jsClassType")
  expect(ClassLeaf._jsSuperclassType, ClassRoot.self, "ClassLeaf._jsSuperclassType")
  expect(GenericRoot<Int>._jsClassType, GenericRoot<Int>.self, "GenericRoot<Int>._jsClassType")
  expect(IntRoot._jsSuperclassType, GenericRoot<Int>.self, "IntRoot._jsSuperclassType")
  expect(DeclaredRoot._jsSuperclassType, nil, "DeclaredRoot._jsSuperclassType")
  expect(ClassNamespace.Nested._jsClassType, ClassNamespace.Nested.self, "ClassNamespace.Nested._jsClassType")
  expect(Counter._jsSuperclassType, nil, "Counter._jsSuperclassType")
  expect(StepCounter._jsSuperclassType, Counter.self, "StepCounter._jsSuperclassType")
  expect(FinalCounter._jsClassType, FinalCounter.self, "FinalCounter._jsClassType")

  let leaf: any AnyJavaScriptClass.Type = ClassLeaf.self
  expect(leaf._jsSuperclassType, ClassRoot.self, "ClassLeaf._jsSuperclassType through AnyJavaScriptClass")
  if leaf._jsName != "ClassLeaf" {
    failures.append("ClassLeaf._jsName through AnyJavaScriptClass: \(leaf._jsName)")
  }
  return failures
}

let failures = try await check() + checkViews() + checkSharedObjects() + checkJSClasses()
for failure in failures {
  print("error: \(failure)")
}
if !failures.isEmpty {
  exit(1)
}
print("All checks passed")
