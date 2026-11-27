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
        if let user = RedditCredentialsManager.profile.user {
          UserView(user: user, isOwnProfile: true)
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
        if ScreenAction.showsInNavigationBar, RedditCredentialsManager.shared.selectedCredential != nil {
          ToolbarItem(placement: .topBarLeading) { AccountSwitcherMenu() }
        }
      }
      .commandTarget(CommandTargets.Target(kind: .profile, actions: [ScreenAction.switchAccount()].compactMap(\.self)))
      .attachViewControllerToRouter(tabID: .me)
      .injectInTabDestinations()
    }
  }
}

struct AccountSwitcherMenu: View {
  var body: some View {
    let manager = RedditCredentialsManager.shared
    let selected = manager.selectedCredential
    Menu {
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
      Section {
        Button("Add Account", systemImage: "person.badge.plus") {
          Nav.present(.editingCredential(.init()))
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
