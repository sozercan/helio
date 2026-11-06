//
//  LogOutConfirmation.swift
//  Helio
//

import SwiftUI

/// Asks before logging out of an account, wherever Log Out was chosen: the accounts menu in a
/// navigation bar, the Mac window toolbar or the menu bar. The alert is on the app's root view.
@MainActor
@Observable
final class LogOutConfirmation {
  static let shared = LogOutConfirmation()

  /// The account waiting for the answer.
  var credential: RedditCredential?

  func ask(_ cred: RedditCredential) {
    credential = cred
  }

  static func title(_ cred: RedditCredential) -> String {
    cred.userName.map { "Log Out u/\($0)" } ?? "Log Out"
  }
}

extension View {
  /// Shows `LogOutConfirmation`'s alert. Logging out removes the account from Helio, as
  /// deleting its credential in Settings does.
  func logOutConfirmation() -> some View {
    modifier(LogOutConfirmationModifier())
  }
}

private struct LogOutConfirmationModifier: ViewModifier {
  private var confirmation = LogOutConfirmation.shared

  func body(content: Content) -> some View {
    let credential = confirmation.credential
    content
      .alert(
        Text(credential?.userName.map { "Log out of u/\($0)?" } ?? "Log out?"),
        isPresented: Binding(get: { confirmation.credential != nil }, set: {
          if !$0 {
            confirmation.credential = nil
          }
        }),
        presenting: credential,
      ) { cred in
        Button("Log Out", role: .destructive) {
          RedditCredentialsManager.shared.deleteCred(cred)
        }
        Button("Cancel", role: .cancel) {}
      } message: { _ in
        Text("Helio forgets this account and its sign-in. You can sign in again in Settings > Credentials.")
      }
  }
}
