//
//  AppearancePanel.swift
//  Helio
//
//  Created by Igor Marcossi on 05/07/23.
//

import Defaults
import SwiftUI

struct AppearancePanel: View {
  @Default(.AppearanceDefSettings) var appearanceDefSettings
  @Default(.ThemesDefSettings) private var themesDefSettings
  @Default(.contentTextSizeAdjustment) private var textSizeAdjustment

  @Environment(\.useTheme) private var theme

  var body: some View {
    List {
      Group {
        Section("Appearance") {
          Picker("Appearance", selection: $appearanceDefSettings.colorScheme) {
            ForEach(AppColorScheme.allCases, id: \.self) { scheme in
              Text(scheme.label).tag(scheme)
            }
          }
          .pickerStyle(.inline)
          .labelsHidden()
        }

        Section("Theme") {
          ForEach(ThemePreset.all) { preset in
            ThemeRow(theme: preset.theme, tag: preset.modes.label, selected: theme.id == preset.id) { select(preset.theme) }
          }
        }

        // Themes imported from a file, which the theme engine still loads.
        let saved = themesDefSettings.themesPresets.filter { $0.id != defaultTheme.id }
        if !saved.isEmpty {
          Section("My Themes") {
            ForEach(saved) { saved in
              ThemeRow(theme: saved, tag: "Custom", selected: theme.id == saved.id) { select(saved) }
            }
          }
        }

        Section {
          TextSizeControl(adjustment: $textSizeAdjustment, titleSize: theme.postLinks.theme.titleText.size)
        } header: {
          Text("Text Size")
        } footer: {
          Text(TextSizeControl.footer)
        }
      }
      .themedListSection()
    }
    .themedListBG(theme.lists.bg)
    .navigationTitle("Appearance")
    .navigationBarTitleDisplayMode(.inline)
  }

  private func select(_ theme: HelioTheme) {
    themesDefSettings.selectedThemeID = theme.id
  }
}

/// A theme in the gallery: a preview of its feed in light and dark mode, its name, what it's
/// for and the modes it changes. Selecting it applies it.
private struct ThemeRow: View {
  let theme: HelioTheme
  let tag: String
  let selected: Bool
  let select: () -> Void

  var body: some View {
    Button(action: select) {
      HStack(spacing: 14) {
        HStack(spacing: 4) {
          ThemeSwatch(theme: theme, scheme: .light)
          ThemeSwatch(theme: theme, scheme: .dark)
        }
        VStack(alignment: .leading, spacing: 3) {
          Text(theme.metadata.name)
            .font(.headline)
          if !theme.metadata.description.isEmpty {
            Text(theme.metadata.description)
              .font(.subheadline)
              .foregroundStyle(Color.secondaryText)
              .fixedSize(horizontal: false, vertical: true)
          }
          Text(tag)
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color.secondaryText)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Capsule().strokeBorder(Color.secondaryText.opacity(0.5), lineWidth: 1))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        Image(systemName: "checkmark")
          .font(.body.weight(.semibold))
          .foregroundStyle(Color.accentColor)
          .opacity(selected ? 1 : 0)
          .accessibilityHidden(true)
      }
      .padding(.vertical, 4)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityElement(children: .combine)
    .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
  }
}

/// A small feed drawn in a theme's colors for one color scheme: two posts, their titles and meta
/// lines, and the divider between them.
private struct ThemeSwatch: View {
  let theme: HelioTheme
  let scheme: ColorScheme

  private func color(_ colors: ColorSchemes<ThemeColor>) -> Color {
    colors.cs(scheme).color()
  }

  var body: some View {
    let postLink = theme.postLinks.theme
    let divider = theme.postLinks.divider
    let border: Color = scheme == .dark ? .white.opacity(0.2) : .black.opacity(0.2)
    VStack(spacing: 0) {
      post(postLink)
      if divider.style != .no {
        color(divider.color)
          .frame(height: divider.style == .fancy ? 4 : 0.5)
          .overlay(alignment: .top) { Rectangle().fill(border).frame(height: 0.5) }
          .overlay(alignment: .bottom) { Rectangle().fill(border).frame(height: 0.5) }
      }
      post(postLink)
    }
    .frame(width: 34, height: 52)
    .background(color(postLink.bg.color))
    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(border, lineWidth: 1))
    .environment(\.colorScheme, scheme)
    .accessibilityHidden(true)
  }

  private func post(_ postLink: PostLinkTheme) -> some View {
    VStack(alignment: .leading, spacing: 3) {
      Capsule().fill(color(postLink.titleText.color)).frame(width: 24, height: 3)
      Capsule().fill(color(postLink.titleText.color)).frame(width: 16, height: 3)
      Capsule().fill(color(postLink.badge.statsText.color)).frame(width: 12, height: 2)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    .padding(.horizontal, 5)
  }
}

/// Moves content text (posts, comments, link previews) a few steps from the system text size.
private struct TextSizeControl: View {
  @Binding var adjustment: Int
  let titleSize: CGFloat

  static var footer: String {
    #if targetEnvironment(macCatalyst)
      "Sizes posts and comments."
    #else
      "Sizes posts and comments on top of the system text size, which Settings > Accessibility > Display & Text Size sets."
    #endif
  }

  private var value: Binding<Double> {
    Binding { Double(adjustment) } set: { adjustment = Int($0.rounded()) }
  }

  var body: some View {
    let range = ContentTextScale.adjustmentRange
    VStack(spacing: 8) {
      HStack(spacing: 12) {
        Image(systemName: "textformat.size.smaller")
          .accessibilityHidden(true)
        Slider(value: value, in: Double(range.lowerBound) ... Double(range.upperBound), step: 1) {
          Text("Text Size")
        }
        .accessibilityValue(Self.label(adjustment))
        Image(systemName: "textformat.size.larger")
          .accessibilityHidden(true)
      }
      HStack {
        Text("A post title at this size")
          .contentFont(titleSize, relativeTo: .title)
          .lineLimit(2)
          .animation(.default, value: adjustment)
        Spacer(minLength: 8)
        if adjustment != 0 {
          Button("Reset") { adjustment = 0 }
            .buttonStyle(.borderless)
        }
      }
    }
    .padding(.vertical, 4)
  }

  static func label(_ adjustment: Int) -> String {
    switch adjustment {
    case 0: "Default"
    case ..<0: "\(-adjustment) smaller"
    default: "\(adjustment) larger"
    }
  }
}
