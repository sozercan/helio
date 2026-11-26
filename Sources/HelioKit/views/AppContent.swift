import Defaults
import SwiftUI

struct AppContent: View {
  @Environment(\.scenePhase) var scenePhase
  @Environment(\.managedObjectContext) private var managedObjectContext

  @Default(.GeneralDefSettings) private var generalDefSettings
  @Default(.AppearanceDefSettings) private var appearanceDefSettings
  @Default(.BehaviorDefSettings) private var behaviorDefSettings

  let biometrics = Biometrics()
  @State private var isAuthenticating = false
  @State private var tabBarHeight: Double = 0
  @State private var lockBlur: Int = 0
  @State private var restartAlert = false

  func setTabBarHeight(_ val: Double) {
    tabBarHeight = val
  }

  var body: some View {
    GlobalDestinationsProvider {
      Tabber(theme: InMemoryTheme.shared.currentTheme)
        .lightBoxPresenting()
    }
    .whatsNewSheet()
    .logOutConfirmation()
    .environment(\.tabBarHeight, tabBarHeight)
    .environment(\.setTabBarHeight, setTabBarHeight)
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
      var runningOnMac = false
      #if os(macOS) || targetEnvironment(macCatalyst)
        runningOnMac = true
      #endif

      let useAuth = generalDefSettings.useAuth

      if useAuth, !runningOnMac {
        if !isAuthenticating, newPhase == .active, lockBlur != 0 {
          isAuthenticating = true
          biometrics.authenticateUser { success in
            isAuthenticating = false
            if success {
              lockBlur = 0
            }
          }
        } else if newPhase != .active {
          lockBlur = 50
        }
      } else {
        lockBlur = 0
        isAuthenticating = false
      }

      switch newPhase {
      case .active:
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
    .blur(radius: CGFloat(lockBlur))
    .preferredColorScheme(appearanceDefSettings.colorScheme.colorScheme)
  }
}
