//
//  WinstonApp.swift
//  winston
//
//  The app target only provides the entry point and the bundle's resources (assets,
//  strings, Core Data model, shaders, media). Everything else lives in WinstonKit.
//

import SwiftUI
import WinstonKit

@main
struct WinstonApp: App {
  @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

  var body: some Scene {
    WinstonScene()
  }
}
