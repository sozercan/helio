//
//  loader.swift
//  Helio
//
//  Created by Igor Marcossi on 07/08/23.
//

import SwiftUI

extension View {
  func loader(_ loading: Bool, _ hideSpinner: Bool = false, _ onAppear: (() -> Void)? = nil) -> some View {
    self
      .overlay(
        Group {
          if loading {
            ProgressView()
              .frame(.screenSize)
              .ignoresSafeArea()
              .onAppear {
                if let onAppear {
                  onAppear()
                }
              }
          } else if hideSpinner {
            Text("*No results found*")
              .foregroundColor(.secondary)
              .frame(.screenSize)
              .ignoresSafeArea()
              .onAppear {
                if let onAppear {
                  onAppear()
                }
              }
          }
        },
      )
  }
}
