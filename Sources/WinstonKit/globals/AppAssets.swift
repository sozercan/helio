//
//  AppAssets.swift
//  winston
//
//  Xcode generates asset symbols (`Image(.loader)`) per module, and the asset catalog
//  is compiled into the app target, so WinstonKit declares the ones it uses against the
//  main bundle.
//

import SwiftUI

extension ImageResource {
  static let discordLogo = ImageResource(name: "discordLogo", bundle: .main)
  static let loader = ImageResource(name: "loader", bundle: .main)
  static let redditLogo = ImageResource(name: "redditLogo", bundle: .main)
  static let spotlight = ImageResource(name: "spotlight", bundle: .main)
}

extension ColorResource {
  static let acceptablePrimary = ColorResource(name: "acceptablePrimary", bundle: .main)
  static let listBG = ColorResource(name: "listBG", bundle: .main)
  static let primaryInverted = ColorResource(name: "primaryInverted", bundle: .main)
  static let starsBGGradient = ColorResource(name: "starsBGGradient", bundle: .main)
}

extension Color {
  static var acceptablePrimary: Color { Color(.acceptablePrimary) }
  static var listBG: Color { Color(.listBG) }
  static var starsBGGradient: Color { Color(.starsBGGradient) }
}
