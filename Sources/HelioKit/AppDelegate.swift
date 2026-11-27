import AVFoundation
import AVKit
import CoreHaptics
import Foundation
import Nuke
import SwiftUI
import UIKit

public class AppDelegate: UIResponder, UIApplicationDelegate {
  private(set) static var instance: AppDelegate!
  var supportsHaptics: Bool = false

  public func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
    AppDelegate.instance = self
    _ = WindowMetrics.shared
    setAudioToMixWithOthers()

    let hapticCapability = CHHapticEngine.capabilitiesForHardware()
    supportsHaptics = hapticCapability.supportsHaptics

    return true
  }

  public func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
    if let shortcutItem = options.shortcutItem {
      pendingQuickAction = QuickAction(shortcutItem)
    }

    let sceneConfiguration = UISceneConfiguration(name: "Custom Configuration", sessionRole: connectingSceneSession.role)
    sceneConfiguration.delegateClass = CustomSceneDelegate.self

    return sceneConfiguration
  }
}

class CustomSceneDelegate: UIResponder, UIWindowSceneDelegate {
  func windowScene(_ windowScene: UIWindowScene, performActionFor shortcutItem: UIApplicationShortcutItem, completionHandler: @escaping (Bool) -> Void) {
    guard let action = QuickAction(shortcutItem) else {
      completionHandler(false)
      return
    }
    action.perform()
    completionHandler(true)
  }
}

private let audioSessionQueue = DispatchQueue(label: "audio-session", qos: .userInitiated)

func scheduleAudioMixing(_ mix: Bool) {
  audioSessionQueue.async { setAudioToMixWithOthers(mix) }
}

public func setAudioToMixWithOthers(_ mix: Bool = true) {
  let session = AVAudioSession.sharedInstance()
  do {
    if mix {
      try session.setCategory(.playback, options: .mixWithOthers)
      try? session.setActive(false, options: .notifyOthersOnDeactivation)
    } else {
      try session.setCategory(.playback)
      try session.setActive(true)
    }
  } catch {
    print("Error setting audio session: \(error)")
  }
}
