//
//  CredentialsPanel.swift
//  Helio
//
//  Created by Igor Marcossi on 05/07/23.
//

import Defaults
import Nuke
import SwiftUI

struct CredentialsPanel: View {
  private let credentialsManager = RedditCredentialsManager.shared

  var body: some View {
    Group {
      if credentialsManager.credentials.isEmpty {
        CredentialsPanelEmptyView()
      } else {
        CredentialsPanelList(credentials: credentialsManager.credentials, selectedCredentialID: credentialsManager.selectedCredential?.id)
      }
    }
    .navigationTitle("Credentials")
    .toolbar {
      ToolbarItem {
        Button {
          Nav.present(.editingCredential(.init()))
        } label: {
          Image(systemName: "plus")
        }
      }
    }
    .navigationBarTitleDisplayMode(.large)
  }
}

struct CredentialsPanelList: View {
  var credentials: [RedditCredential]
  var selectedCredentialID: UUID?

  var body: some View {
    List {
      Group {
        Section {
          ForEach(credentials) { cred in
            CredentialPanelItem(cred: cred, inUse: cred.id == selectedCredentialID)
          }
        } footer: {
          Text("To switch accounts, hold the \"me\" (or your username) tab pressed in the bottom bar.")
        }
      }
      .themedListSection()
    }
    .navigationBarTitleDisplayMode(.large)
  }
}
