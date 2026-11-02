//
//  MacIdiom.swift
//  Helio
//

import SwiftUI

/// The Mac app's "Optimize Interface for Mac" idiom. In the iPad idiom, macOS shows the app at
/// 77%, so a 17 pt title is 13 pt on screen; in the Mac idiom points are the Mac's own, 1:1.
/// Helio's type and layout sizes were made for the iPad idiom, so on Mac they're scaled by
/// `scale` to look as they did.
enum MacIdiom {
  /// The app runs in the Mac idiom: its Mac build declares the Mac device family (6).
  static let isActive: Bool = {
    #if targetEnvironment(macCatalyst)
      (Bundle.main.object(forInfoDictionaryKey: "UIDeviceFamily") as? [Int])?.contains(6) == true
    #else
      false
    #endif
  }()

  /// How much smaller an iPad-idiom size is on a Mac: macOS's scale for the iPad idiom.
  static let iPadIdiomScale: CGFloat = 0.77

  static let scale: CGFloat = isActive ? iPadIdiomScale : 1

  /// `size`, made for the iPad idiom, at the size it showed on Mac.
  static func size(_ size: CGFloat) -> CGFloat {
    size * scale
  }
}

extension View {
  /// A menu that looks like its label, as on iPad. In the Mac idiom a menu is otherwise a
  /// bordered pop-up button with a chevron.
  @ViewBuilder
  func borderlessMenuOnMac() -> some View {
    if MacIdiom.isActive {
      menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
    } else {
      self
    }
  }
}
