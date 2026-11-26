import SwiftUI

extension View {}

private struct HelperHeroView<Overlay: View>: ViewModifier {
  @Binding var show: Bool
  var overlay: Overlay

  @State private var hostView: CustomHostingView<Overlay>?
  @State private var parentController: UIViewController?

  func body(content: Content) -> some View {
    content
      .onChange(of: show) { newValue in
        if newValue {
          hostView = CustomHostingView(show: $show, rootView: overlay)
          if let hostView {
            hostView.modalPresentationStyle = .overFullScreen
            hostView.modalTransitionStyle = .crossDissolve
            hostView.view.backgroundColor = .clear
            parentController?.present(hostView, animated: false)
          }
        } else {
          hostView?.dismiss(animated: false)
        }
      }
  }
}

class CustomHostingView<Content: View>: UIHostingController<Content> {
  @Binding var show: Bool

  init(show: Binding<Bool>, rootView: Content) {
    self._show = show
    super.init(rootView: rootView)
  }

  @available(*, unavailable)
  dynamic required init?(coder aDecoder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func viewWillDisappear(_ animated: Bool) {
    super.viewWillDisappear(false)
    show = false
  }
}

public extension UIView {}
