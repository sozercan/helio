//
//  HelioApp.swift
//  Helio
//
//  The app target only provides the entry point and the bundle's resources (assets,
//  strings, Core Data model, shaders, media). Everything else lives in HelioKit.
//

import SwiftUI
import HelioKit

@main
struct HelioApp: App {
  @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

  var body: some Scene {
    HelioScene()
  }
}
