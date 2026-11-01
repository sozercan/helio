//
//  GlobalDestinationsProvider.swift
//  Helio
//
//  Created by Igor Marcossi on 09/12/23.
//

import Defaults
import SwiftUI

struct GlobalDestinationsProvider<C: View>: View {
  @State var nav = Nav.shared

  @Environment(\.tabBarHeight) private var tabBarHeight

  @ViewBuilder var content: () -> C
  var body: some View {
    content()
      .replyModalPresenter()
      .sheet(item: $nav.presentingSheet) { data in
        GeometryReader { geo in
          Group {
            switch data {
            case let .editingTheme(theme): ThemeEditPanel(theme: theme)
            case let .editingCredential(cred): CredentialEditStack(credential: cred).id("editing-credential-view-\(cred.id)")
            case .onboarding: Onboarding().interactiveDismissDisabled(true)
            case let .redditSignIn(cred): NavigationStack { RedditWebLoginView(credential: cred ?? RedditCredential(), showsCancel: true) }
            case let .selectText(text): SelectableTextSheet(markdown: text)
            }
          }
          .environment(\.tabBarHeight, tabBarHeight)
          .environment(\.sheetHeight, geo.size.height)
        }
        .coordinateSpace(name: "sheet")
        .environment(\.brighterBG, true)
      }
  }
}
