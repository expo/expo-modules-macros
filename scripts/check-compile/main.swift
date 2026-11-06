// Decodes and resets the props of `Props.swift` through the generic code in `Core.swift`, and compares
// each reset prop with its value in `Self()`. Exits with a nonzero status when a check fails.

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

  expect(propNames(of: PublicProps.self), ["title", "count", "ratio"], "PublicProps names")
  expect(propNames(of: EventsOnlyProps.self), ["onTap", "onChange"], "EventsOnlyProps names")
  return failures
}

let failures = try await check()
for failure in failures {
  print("error: \(failure)")
}
if !failures.isEmpty {
  exit(1)
}
print("All checks passed")
