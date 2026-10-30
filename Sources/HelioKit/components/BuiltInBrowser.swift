//
//  BuiltInBrowser.swift
//  Helio
//
//  Created by Igor Marcossi on 19/09/23.
//

import SafariServices
import SwiftUI

struct SafariWebView: UIViewControllerRepresentable {
  let url: URL

  func makeUIViewController(context: Context) -> SFSafariViewController {
    SFSafariViewController(url: url)
  }

  func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}

extension UIApplication {
  var firstKeyWindow: UIWindow? {
    UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .filter { $0.activationState == .foregroundActive }
      .first?.keyWindow
  }
}
