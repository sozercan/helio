//
//  fullscreenPresent.swift
//  Helio
//
//  Created by Igor Marcossi on 12/07/23.
//

import SwiftUI

/// Custom View Modifier Extension
extension View {}

/// Helper Modifier
private struct HelperHeroView<Overlay: View>: ViewModifier {
  @Binding var show: Bool
  var overlay: Overlay

  /// View Properties
  @State private var hostView: CustomHostingView<Overlay>?
  @State private var parentController: UIViewController?

  func body(content: Content) -> some View {
    content
      /// Attatch it as background to fetch the parent Controller
//            .background(content: {
//                ExtractSwiftUIParentController(content: overlay, hostView: $hostView) { viewController in
//                    parentController = viewController
//                }
//            })
      /// Presenting/Dismissing Host View based on Show State
      .onChange(of: show) { newValue in
        if newValue {
          hostView = CustomHostingView(show: $show, rootView: overlay)
          // Present View
          if let hostView {
            // Changing Presentation Style and Transition Style
            hostView.modalPresentationStyle = .overFullScreen
            hostView.modalTransitionStyle = .crossDissolve
            hostView.view.backgroundColor = .clear
            // We Need a parent View controller to present it
            parentController?.present(hostView, animated: false)
          }
        } else {
          // Dismiss View
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
    // Since we don't need any default animation while dismissing
    super.viewWillDisappear(false)
    // Setting show Status to false
    show = false
  }
}

/// Return parent view controller for the given UIView
public extension UIView {}
