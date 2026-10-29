//
//  AppDelegate.swift
//  Helio
//
//  Created by Igor Marcossi on 31/07/23.
//

import Foundation
import UIKit
import SwiftUI
import AVKit
import AVFoundation
import Nuke
import CoreHaptics

/// Installed by the app target's `@main` App via `@UIApplicationDelegateAdaptor`.
public class AppDelegate: UIResponder, UIApplicationDelegate {
  static private(set) var instance: AppDelegate! = nil
  var supportsHaptics: Bool = false
  
  public func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
    AppDelegate.instance = self
    _ = WindowMetrics.shared // first read touches UIApplication, so do it on the main thread
    setAudioToMixWithOthers()
    
    let hapticCapability = CHHapticEngine.capabilitiesForHardware()
    supportsHaptics = hapticCapability.supportsHaptics
    
    return true
  }
    
  public func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
    
    if let shortcutItem = options.shortcutItem {
      shortcutItemToProcess = shortcutItem
    }
    
    let sceneConfiguration = UISceneConfiguration(name: "Custom Configuration", sessionRole: connectingSceneSession.role)
    sceneConfiguration.delegateClass = CustomSceneDelegate.self
    
    return sceneConfiguration
  }
}

class CustomSceneDelegate: UIResponder, UIWindowSceneDelegate {
  func windowScene(_ windowScene: UIWindowScene, performActionFor shortcutItem: UIApplicationShortcutItem, completionHandler: @escaping (Bool) -> Void) {
    shortcutItemToProcess = shortcutItem
  }
}

private let audioSessionQueue = DispatchQueue(label: "audio-session", qos: .userInitiated)

/// Runs `setAudioToMixWithOthers` off the main thread, where its session calls can block while
/// audio plays, one at a time and in the order requested, so the last request wins.
func scheduleAudioMixing(_ mix: Bool) {
    audioSessionQueue.async { setAudioToMixWithOthers(mix) }
}

/// - Parameter mix: when false, our audio interrupts other apps' audio (e.g. pauses music);
///   switching back lets the interrupted audio resume.
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
