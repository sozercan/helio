//
//  GuidedCredsCapturedScene.swift
//  winston
//
//  Created by Igor Marcossi on 06/01/24.
//

import SwiftUI

struct GuidedCredsCapturedScene: View {
  let authorize: ()->()
    var body: some View {
      VStack {
        VStack(alignment: .center, spacing: 24) {
          
          VStack(spacing: 8) {
            BetterLottieView("edit-appear", size: 104)
            VStack(alignment: .center, spacing: 4) {
              Text("Credentials registered!").fontSize(32, .bold)
              Text("Now we need you to authorize your API credentials to access your own account. I know, it's redundant.")
            }
          }
          
          WinstonButton(config: .success) {
            authorize()
          } label: {
            Text("Take me there!")
          }
          
        }
      }
      .multilineTextAlignment(.center)
      .padding(EdgeInsets(top: 48, leading: 32, bottom: 0, trailing: 32))
      .frame(maxHeight: .infinity, alignment: .top)
    }
}
