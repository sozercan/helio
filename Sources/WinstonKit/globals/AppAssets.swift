//
//  AppAssets.swift
//  winston
//
//  Xcode generates asset symbols (`Image(.winstonFlat)`) per module, and the asset catalog
//  is compiled into the app target, so WinstonKit declares the ones it uses against the
//  main bundle.
//

import SwiftUI

extension ImageResource {
  static let discordLogo = ImageResource(name: "discordLogo", bundle: .main)
  static let emptyCredential = ImageResource(name: "emptyCredential", bundle: .main)
  static let loader = ImageResource(name: "loader", bundle: .main)
  static let redditLogo = ImageResource(name: "redditLogo", bundle: .main)
  static let spotlight = ImageResource(name: "spotlight", bundle: .main)
  static let winstonEOF = ImageResource(name: "winstonEOF", bundle: .main)
  static let winstonEyes = ImageResource(name: "winstonEyes", bundle: .main)
  static let winstonFlat = ImageResource(name: "winstonFlat", bundle: .main)
  static let winstonNoBG = ImageResource(name: "winstonNoBG", bundle: .main)
  static let winstonSide = ImageResource(name: "winstonSide", bundle: .main)
}

extension ColorResource {
  static let acceptablePrimary = ColorResource(name: "acceptablePrimary", bundle: .main)
  static let listBG = ColorResource(name: "listBG", bundle: .main)
  static let primaryInverted = ColorResource(name: "primaryInverted", bundle: .main)
  static let starsBGGradient = ColorResource(name: "starsBGGradient", bundle: .main)
  static let winstonEOFOverlay = ColorResource(name: "winstonEOFOverlay", bundle: .main)
}

extension Color {
  static var acceptablePrimary: Color { Color(.acceptablePrimary) }
  static var listBG: Color { Color(.listBG) }
  static var starsBGGradient: Color { Color(.starsBGGradient) }
  static var winstonEOFOverlay: Color { Color(.winstonEOFOverlay) }
}
