//
//  Me.swift
//  Helio
//
//  Created by Igor Marcossi on 24/06/23.
//

import Defaults
import SwiftUI

struct Me: View {
  @State var router: Router

  init(router: Router) {
    self._router = .init(initialValue: router)
  }

  var body: some View {
    NavigationStack(path: $router.fullPath) {
      Group {
        if let user = RedditAPI.shared.me {
          UserView(user: user)
            .id("me-user-view-\(user.id)")

        } else if RedditCredentialsManager.profile.state == .error {
          ContentUnavailableView {
            Label("Unable to load profile", systemImage: "person.crop.circle.badge.exclamationmark")
          } actions: {
            Button("Retry") { Task { await RedditCredentialsManager.profile.refresh() } }
          }
        } else {
          ProgressView()
            .progressViewStyle(.circular)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear {
              Task(priority: .userInitiated) {
                await RedditCredentialsManager.profile.refresh()
              }
            }
        }
      }
      .readableWidth()
      .toolbar {
        // On Mac it's in the window toolbar.
        if ScreenAction.showsInNavigationBar, RedditCredentialsManager.shared.selectedCredential != nil {
          ToolbarItem(placement: .topBarLeading) { AccountSwitcherMenu() }
        }
      }
      .commandTarget(CommandTargets.Target(kind: .profile, actions: [ScreenAction.switchAccount()].compactMap(\.self)))
      .attachViewControllerToRouter(tabID: .me)
      .injectInTabDestinations()
    }
//    .swipeAnywhere()
  }
}

/// Switches between the signed-in Reddit accounts and logs out of the selected one.
struct AccountSwitcherMenu: View {
  var body: some View {
    let manager = RedditCredentialsManager.shared
    let selected = manager.selectedCredential
    Menu {
      // Also with one other account while the selected one is signed out.
      if manager.validCredentials.contains(where: { $0.id != selected?.id }) {
        Picker("Account", selection: Binding(
          get: { selected?.id },
          set: {
            if let id = $0 {
              Defaults[.GeneralDefSettings].redditCredentialSelectedID = id
            }
          },
        )) {
          ForEach(manager.validCredentials) { cred in
            Text(cred.userName ?? "Account").tag(Optional(cred.id))
          }
        }
      }
      if let selected {
        Section {
          Button(LogOutConfirmation.title(selected), systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
            LogOutConfirmation.shared.ask(selected)
          }
        }
      }
    } label: {
      Label("Accounts", systemImage: "person.2.circle")
    }
  }
}

// struct Me_Previews: PreviewProvider {
//  static var previews: some View {
//    Me()
//  }
// }
