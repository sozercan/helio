//
//  Tabber.swift
//  Helio
//
//  Created by Igor Marcossi on 24/06/23.
//

import Defaults
import SpriteKit
import SwiftUI

struct Tabber: View {
  var redditCredentialsManager = RedditCredentialsManager.shared
  @State var nav = Nav.shared

  @State var tabBarHeight: Double? = nil

  @Environment(\.useTheme) private var currentTheme
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.setTabBarHeight) private var setTabBarHeight
  @Default(.AppearanceDefSettings) private var appearanceDefSettings
  #if targetEnvironment(macCatalyst)
    @State private var macTabToolbar = MacTabToolbar()
  #endif

  init(theme: HelioTheme) {
    Tabber.updateTabAndNavBar(tabTheme: theme.general.tabBarBG, navTheme: theme.general.navPanelBG)
  }

  /// Blurry bars are left to the system, which draws them in Liquid Glass with the scroll edge
  /// effect. Only opaque theme colors override the appearance.
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

  var body: some View {
    TabView(selection: $nav.activeTab) {
      Tab("Posts", systemImage: "doc.text.image", value: Nav.TabIdentifier.posts) {
        WithCredentialOnly(credential: redditCredentialsManager.selectedCredential) {
          SubredditsStack(router: nav[.posts])
        }
        .measureTabBar(setTabBarHeight)
        .hidesTabBarOnMac()
      }

      Tab("Inbox", systemImage: "bell.fill", value: Nav.TabIdentifier.inbox) {
        WithCredentialOnly(credential: redditCredentialsManager.selectedCredential) {
          Inbox(router: nav[.inbox])
        }
        .measureTabBar(setTabBarHeight)
        .hidesTabBarOnMac()
      }

      Tab(appearanceDefSettings.showUsernameInTabBar ? RedditAPI.shared.me?.data?.name ?? "Me" : "Me", systemImage: "person.fill", value: Nav.TabIdentifier.me) {
        WithCredentialOnly(credential: redditCredentialsManager.selectedCredential) {
          Me(router: nav[.me])
        }
        .measureTabBar(setTabBarHeight)
        .hidesTabBarOnMac()
      }

      Tab("Settings", systemImage: "gearshape.fill", value: Nav.TabIdentifier.settings) {
        Settings(router: nav[.settings])
          .measureTabBar(setTabBarHeight)
          .hidesTabBarOnMac()
      }

      // The search role puts Search in its own glass button after the tab bar.
      Tab("Search", systemImage: "magnifyingglass", value: Nav.TabIdentifier.search, role: .search) {
        WithCredentialOnly(credential: redditCredentialsManager.selectedCredential) {
          Search(router: nav[.search])
        }
        .measureTabBar(setTabBarHeight)
        .hidesTabBarOnMac()
      }
    }
    .tabBarMinimizeBehavior(.onScrollDown)
    .openFromWebListener()
    .newCredentialListener()
    .themeImportingListener() // From local file
    .globalLoaderProvider()
    .refetchMeListener()
    .task(priority: .background) {
      cleanCredentialOrphanEntities()
      autoSelectCredentialIfNil()
      removeDefaultThemeFromThemes()
      checkForOnboardingStatus()
      if RedditCredentialsManager.shared.selectedCredential != nil {
        RedditCredentialsManager.shared.updateMe()
        Task(priority: .background) { await updatePostsInBox(RedditAPI.shared) }
      }
    }
    .accentColor(currentTheme.general.accentColor())
    #if targetEnvironment(macCatalyst)
      .background(MacTabToolbarInstaller(toolbar: macTabToolbar))
      .onChange(of: nav.activeTab) { _, tab in macTabToolbar.select(tab) }
    #endif
  }
}

private extension View {
  /// Mac shows the tabs in `MacTabToolbar` instead.
  @ViewBuilder
  func hidesTabBarOnMac() -> some View {
    #if targetEnvironment(macCatalyst)
      toolbar(.hidden, for: .tabBar)
    #else
      self
    #endif
  }
}
