//
//  BuiltInBrowser.swift
//  Helio
//
//  Created by Igor Marcossi on 19/09/23.
//

import SafariServices
import SwiftUI

extension UIApplication {
  var firstKeyWindow: UIWindow? {
    UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .filter { $0.activationState == .foregroundActive }
      .first?.keyWindow
  }
}
