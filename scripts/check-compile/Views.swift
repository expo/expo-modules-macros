// `@ExpoView` views that `check-compile.js` compiles in each configuration, with the props of `Props.swift`, and
// that `main.swift` checks at run time.

import Core
import SwiftUI

// A UIKit view. Its `didUpdateProps(_:)` names the diff through the props type, and it must still match the
// `AnyNativeUIKitView` requirement, so core calls it in place of the default that does nothing.
@ExpoView<PublicProps>
public final class CardView: ExpoNativeView {
  public private(set) var titles: [String] = []

  public func didUpdateProps(_ diff: PublicProps.Diff) {
    titles.append(props.title)
  }
}

@ExpoView<PublicProps>("FancyCard")
final class NamedCardView: ExpoNativeView {}

// A SwiftUI view. A parent view can call `hasAppContext()` outside of `body`, where only the stored
// `appContext` has the app context.
@ExpoView<PublicProps>
public struct SliderView: View {
  @State private var isEditing = false

  public var body: some View {
    VStack {
      Toggle(props.title, isOn: $isEditing)
      children
    }
  }

  public func hasAppContext() -> Bool {
    return appContext != nil
  }
}

// A SwiftUI view with an initializer that a SwiftUI preview calls. It's a separate overload of the initializer
// that the macro adds, so both compile, and a call without the app context uses it.
@ExpoView<PublicProps>("Labeled")
struct LabeledView: View {
  private(set) var isPreview = false

  init(props: PublicProps, children: ExpoSwiftUI.Children) {
    self.init(props: props, children: children, appContext: nil)
    isPreview = true
  }

  var body: some View {
    Text(props.title)
  }
}
