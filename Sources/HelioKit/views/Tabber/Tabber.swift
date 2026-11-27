import Defaults
import SpriteKit
import SwiftUI

struct Tabber: View {
  var redditCredentialsManager = RedditCredentialsManager.shared
  @State var nav = Nav.shared

  @Environment(\.useTheme) private var currentTheme
  @Default(.AppearanceDefSettings) private var appearanceDefSettings
  #if targetEnvironment(macCatalyst)
    @State private var macTabToolbar = MacTabToolbar()
  #endif

  init(theme: HelioTheme) {
    Tabber.updateTabAndNavBar(tabTheme: theme.general.tabBarBG, navTheme: theme.general.navPanelBG)
  }

  static func updateTabAndNavBar(tabTheme: ThemeForegroundBG, navTheme: ThemeForegroundBG) {
    if !navTheme.blurry {
      let navAppearance = UINavigationBarAppearance()
      navAppearance.configureWithOpaqueBackground()
      navAppearance.backgroundColor = UIColor(navTheme.color())
      UINavigationBar.appearance().standardAppearance = navAppearance
    }
    if !tabTheme.blurry {
      let tabAppearance = UITabBarAppearance()
      tabAppearance.configureWithOpaqueBackground()
      tabAppearance.backgroundColor = UIColor(tabTheme.color())
      UITabBar.appearance().standardAppearance = tabAppearance
    }
  }

  private var meTitle: String {
    appearanceDefSettings.showUsernameInTabBar ? RedditCredentialsManager.profile.user?.data?.name ?? "Me" : "Me"
  }

  var body: some View {
    TabView(selection: $nav.activeTab) {
      Tab("Posts", systemImage: "doc.text.image", value: Nav.TabIdentifier.posts) {
        WithCredentialOnly(credential: redditCredentialsManager.selectedCredential) {
          SubredditsStack(router: nav[.posts])
        }
        .hidesTabBarOnMac()
      }

      Tab("Inbox", systemImage: "bell.fill", value: Nav.TabIdentifier.inbox) {
        WithCredentialOnly(credential: redditCredentialsManager.selectedCredential) {
          Inbox(router: nav[.inbox])
        }
        .columnContentWidth()
        .hidesTabBarOnMac()
      }

      Tab(meTitle, systemImage: "person.fill", value: Nav.TabIdentifier.me) {
        WithCredentialOnly(credential: redditCredentialsManager.selectedCredential) {
          Me(router: nav[.me])
        }
        .columnContentWidth()
        .hidesTabBarOnMac()
      }

      Tab("Settings", systemImage: "gearshape.fill", value: Nav.TabIdentifier.settings) {
        Settings(router: nav[.settings])
          .columnContentWidth()
          .hidesTabBarOnMac()
      }

      Tab("Search", systemImage: "magnifyingglass", value: Nav.TabIdentifier.search, role: .search) {
        WithCredentialOnly(credential: redditCredentialsManager.selectedCredential) {
          Search(router: nav[.search])
        }
        .columnContentWidth()
        .hidesTabBarOnMac()
      }
    }
    .tabBarMinimizeBehavior(isWideLayout ? .automatic : .onScrollDown)
    .openFromWebListener()
    .newCredentialListener()
    .themeImportingListener()
    .globalLoaderProvider()
    .refetchMeListener()
    .task(priority: .userInitiated) {
      autoSelectCredentialIfNil()
      checkForOnboardingStatus()
      if RedditCredentialsManager.shared.selectedCredential != nil {
        RedditCredentialsManager.shared.updateMe()
      }
    }
    .task(priority: .utility) {
      if Nav.opensWebPagesInApp || WebExtensionStore.shared.hasEnabledExtensions {
        await WebExtensionRuntime.shared.start()
      }
    }
    .task(priority: .background) {
      cleanCredentialOrphanEntities()
      removeDefaultThemeFromThemes()
    }
    .accentColor(currentTheme.general.accentColor())
    #if targetEnvironment(macCatalyst)
      .background(MacTabToolbarInstaller(toolbar: macTabToolbar))
      .onChange(of: nav.activeTab) { _, tab in macTabToolbar.select(tab) }
      .onChange(of: meTitle, initial: true) { _, title in macTabToolbar.setTitle(title, for: .me) }
    #endif
  }
}

private extension View {
  func hidesTabBarOnMac() -> some View {
    #if targetEnvironment(macCatalyst)
      toolbar(.hidden, for: .tabBar)
        .ignoresSafeArea(.container, edges: .top)
    #else
      self
    #endif
  }
}
