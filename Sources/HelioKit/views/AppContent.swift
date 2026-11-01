//
//  AppContent.swift
//  Helio
//
//  Created by Igor Marcossi on 31/12/23.
//

import Defaults
import SwiftUI

struct AppContent: View {
  @Environment(\.scenePhase) var scenePhase
  @Environment(\.managedObjectContext) private var managedObjectContext

  //  @Default(.ThemesDefSettings) private var themesDefSettings
  @Default(.GeneralDefSettings) private var generalDefSettings
  @Default(.AppearanceDefSettings) private var appearanceDefSettings
  @Default(.BehaviorDefSettings) private var behaviorDefSettings

  //  var selectedTheme: HelioTheme { themesDefSettings.themesPresets.first { $0.id == themesDefSettings.selectedThemeID } ?? defaultTheme }

  let biometrics = Biometrics()
  @State private var isAuthenticating = false
  @State private var tabBarHeight: Double = 0
  @State private var lockBlur: Int = 0 // Set initial startup blur (why wasn't this 0 initially??)
  @State private var restartAlert = false

  func setTabBarHeight(_ val: Double) {
    tabBarHeight = val
  }

  var body: some View {
    GlobalDestinationsProvider {
      Tabber(theme: InMemoryTheme.shared.currentTheme)
    }
    .whatsNewSheet()
    .environment(\.tabBarHeight, tabBarHeight)
    .environment(\.setTabBarHeight, setTabBarHeight)
    // The current width for every tab's feeds; the posts column overrides it with its own.
    .environment(\.contentWidth, WindowMetrics.shared.contentWidth)
    .environment(\.useTheme, InMemoryTheme.shared.currentTheme)
    .environment(\.enableSwipeAnywhere, behaviorDefSettings.enableSwipeAnywhere)
    .readsWindowMetrics()
    .onAppear {
      Defaults[.ThemesDefSettings].themesPresets = Defaults[.ThemesDefSettings].themesPresets.filter { $0.id != "default" }
    }
    .onChange(of: InMemoryTheme.shared.currentTheme, initial: false) { old, new in
      restartAlert = old.general != new.general
    }
    .alert("Restart required", isPresented: $restartAlert) {
      Button("Gotcha!", role: .cancel) {
        restartAlert = false
      }
    } message: {
      Text("This theme changes a few settings (like the visuals of tab/nav bars) that requires an app restart to take effect.")
    }
    .onChange(of: scenePhase) { _, newPhase in
      // No auth on MacOS
      var runningOnMac = false
      #if os(macOS) || targetEnvironment(macCatalyst)
        runningOnMac = true
      #endif

      let useAuth = generalDefSettings.useAuth // Get fresh value

      if useAuth, !runningOnMac {
        if !isAuthenticating, newPhase == .active, lockBlur != 0 {
          // Not authing, active and blur visible = Need to auth
          isAuthenticating = true
          biometrics.authenticateUser { success in
            isAuthenticating = false
            if success {
              lockBlur = 0
            }
          }
        } else if newPhase != .active {
          // Auth enabled but not active = blur
          lockBlur = 50
        }
      } else {
        // Auth not enabled = No blur
        lockBlur = 0
        isAuthenticating = false
      }

      switch newPhase {
      case .active:
        // A quick action that launched the app, applied once.
        if let action = pendingQuickAction {
          pendingQuickAction = nil
          action.perform()
        }
      case .background:
        QuickAction.updateShortcutItems(context: managedObjectContext)
      default:
        break
      }
    }
    .blur(radius: CGFloat(lockBlur)) // Set lockscreen blur
    .preferredColorScheme(appearanceDefSettings.colorScheme.colorScheme)
  }
}
