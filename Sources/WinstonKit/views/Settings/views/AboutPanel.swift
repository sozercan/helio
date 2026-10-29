//
//  AboutPanel.swift
//  winston
//
//  Created by Igor Marcossi on 01/08/23.
//

import SwiftUI

/// The projects Helio is built from, credited in About.
private let credits: [(name: String, role: String, repo: String)] = [
  ("Winston by lo.cafe", "The original app", "lo-cafe/winston"),
  ("phubbard", "The fork Helio is based on", "phubbard/winston"),
  ("eliburke", "Fork with fixes ported to Helio", "eliburke/winston"),
  ("d0lb33", "Fork with fixes ported to Helio", "d0lb33/winston"),
]

struct AboutPanel: View {
  let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
  let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
  @Environment(\.openURL) private var openURL
  @Environment(\.useTheme) private var theme
  var body: some View {
    List {
      Group {
        Section {
          HStack {
            AppMark(size: 44)
            
            VStack(alignment: .leading) {
              Text("Helio")
                .fontSize(20, .bold)
              HStack{
                Text("v" + (appVersion ?? "-1") + " Build \(build ?? "-1")")
              }
            }
          }
          
          Text("Helio is a privacy-focused, open-source Reddit client. No analytics, no tracking, no ads, no third-party data collection. Your data stays on your device.")

          WListButton {
            openURL(URL(string: "https://github.com/sozercan/helio")!)
          } label: {
            Label("View on GitHub", systemImage: "arrow.branch").foregroundStyle(Color.accentColor)
          }

        }

        Section("Privacy") {
          Label("No analytics or tracking", systemImage: "eye.slash.fill")
          Label("No ads or ad networks", systemImage: "xmark.shield.fill")
          Label("No third-party data collection", systemImage: "lock.shield.fill")
          Label("Communicates only with Reddit", systemImage: "network")
        }

        Section {
          Text("Helio is free and open source software. It builds on Winston and the forks below.")
          ForEach(credits, id: \.repo) { credit in
            WListButton {
              openURL(URL(string: "https://github.com/\(credit.repo)")!)
            } label: {
              VStack(alignment: .leading, spacing: 2) {
                Text(credit.name).foregroundStyle(Color.accentColor)
                Text(credit.role).font(.footnote).foregroundStyle(.secondary)
              }
            }
          }
        } header: {
          Text("Credits")
        }
      }
      .themedListSection()
    }
    .themedListBG(theme.lists.bg)
    .navigationTitle("About")
    .navigationBarTitleDisplayMode(.inline)
  }
}

//struct AboutPanel_Previews: PreviewProvider {
//    static var previews: some View {
//        AboutPanel()
//    }
//}
