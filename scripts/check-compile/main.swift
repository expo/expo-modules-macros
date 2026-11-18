// Decodes and resets the props of `Props.swift` through the generic code in `Core.swift`, compares
// each reset prop with its value in `Self()`, and dispatches the bound events. Then checks the views of
// `Views.swift`. Exits with a nonzero status when a check fails.

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

let failures = try await check() + checkViews()
for failure in failures {
  print("error: \(failure)")
}
if !failures.isEmpty {
  exit(1)
}
print("All checks passed")
