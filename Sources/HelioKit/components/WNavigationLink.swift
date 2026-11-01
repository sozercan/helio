//
//  WNavigationLink.swift
//  Helio
//
//  Created by Igor Marcossi on 19/09/23.
//

import SwiftUI

struct WListButton<Content: View>: View {
  var showArrow: Bool = false
  var active: Bool = false
  var action: () -> Void
  @ViewBuilder var label: () -> Content
  @State private var forcedActive = false

  init(showArrow: Bool = false, active: Bool = false, _ action: @escaping () -> Void, @ViewBuilder label: @escaping () -> Content) {
    self.active = active
    self.action = action
    self.label = label
    self.showArrow = showArrow
  }

  var body: some View {
    Button {
      forcedActive = true
      doThisAfter(0) {
        action()
      }
      doThisAfter(1) {
        forcedActive = false
      }
    } label: {
      HStack {
        label()

        Spacer()

        if showArrow {
          Image(systemName: "chevron.right")
            .fontSize(14, .semibold)
            .opacity(0.35)
            .foregroundColor(.primary)
        }
      }
      .contentShape(Rectangle())
    }
    .themedListRow(active: forcedActive || active, isButton: !showArrow)
    .onAppear { withAnimation { forcedActive = false } }
//    .id("\(uuid.uuidString)-\(pressed ? "pressed" : "")")
//    .themedListRowLikeBG(enablePadding: true, disableBG: true, active: active)
  }
}

struct WSListButton: View {
  var showArrow: Bool = false
  var active: Bool = false
  var action: () -> Void
  var label: String
  var icon: String?

  init(showArrow: Bool = false, _ label: String, active: Bool = false, icon: String? = nil, _ action: @escaping () -> Void) {
    self.active = active
    self.action = action
    self.label = label
    self.icon = icon
    self.showArrow = showArrow
  }

  var body: some View {
    WListButton(showArrow: showArrow, active: active) {
      action()
    } label: {
      if let icon {
        Label(label, systemImage: icon)
      } else {
        Text(label)
      }
    }
  }
}

struct WSNavigationLink: View {
  var value: Router.NavDest
  var active: Bool = false
  var icon: String?
  let label: String

  init(_ value: Router.NavDest, active: Bool = false, _ label: String, icon: String? = nil) {
    self.value = value
    self.active = active
    self.label = label
    self.icon = icon
  }

  var body: some View {
    WListButton(showArrow: true, active: active) {
      Nav.to(value)
    } label: {
      if let icon {
        Label(label, systemImage: icon)
          .labelStyle(NormalLabelStyle())
      } else {
        Text(label)
      }
    }
  }
}

struct NormalLabelStyle: LabelStyle {
  func makeBody(configuration: Configuration) -> some View {
    Label {
      configuration.title.foregroundStyle(.primary)
    } icon: {
      configuration.icon.foregroundStyle(Color.accentColor)
    }
    .labelStyle(.automatic)
  }
}
