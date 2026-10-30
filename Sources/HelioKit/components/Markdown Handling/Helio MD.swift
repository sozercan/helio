//
//  Helio MD.swift
//  Helio
//
//  Created by Ethan Bills on 1/12/24.
//

import MarkdownUI
import SwiftUI

public extension Theme {
  /// Helio Markdown theme.
  static func helioMarkdown(fontSize: CGFloat, lineSpacing: CGFloat = 0.2, textSelection: Bool = false) -> Theme {
    Theme()
      .text {
        FontSize(fontSize)
      }
      .paragraph { configuration in
        configuration.label
          .lineSpacing(lineSpacing)
          .fontSize(fontSize)
          .helioTextSelection(textSelection)
      }
      .heading1 { configuration in
        configuration.label
          .markdownTextStyle {
            FontSize(fontSize * 2)
          }
          .helioTextSelection(textSelection)
      }
      .heading2 { configuration in
        configuration.label
          .markdownTextStyle {
            FontSize(fontSize * 1.5)
          }
          .helioTextSelection(textSelection)
      }
      .heading3 { configuration in
        configuration.label
          .markdownTextStyle {
            FontSize(fontSize * 1.25)
          }
          .helioTextSelection(textSelection)
      }
      .listItem { configuration in
        configuration.label
          .markdownMargin(top: .em(0.3))
          .helioTextSelection(textSelection)
      }
      .codeBlock { configuration in
        configuration.label
          .markdownTextStyle {
            FontSize(.em(0.85))
            FontFamilyVariant(.monospaced)
          }
          .padding()
          .background(Color(.secondarySystemBackground))
          .clipShape(RoundedRectangle(cornerRadius: 8))
          .markdownMargin(top: .zero, bottom: .em(0.8))
          .helioTextSelection(textSelection)
      }
      .table { configuration in
        ScrollView(.horizontal) {
          configuration.label
            .fixedSize(horizontal: false, vertical: true)
            .markdownTableBackgroundStyle(
              .alternatingRows(Color(.systemBackground), Color(.secondarySystemBackground)),
            )
            .markdownMargin(top: 0, bottom: 16)
        }
      }
      .tableCell { configuration in
        configuration.label
          .markdownTextStyle {
            if configuration.row == 0 {
              FontWeight(.semibold)
            }
            BackgroundColor(nil)
          }
          .fixedSize(horizontal: false, vertical: true)
          .padding(.vertical, 6)
          .padding(.horizontal, 13)
          .relativeLineSpacing(.em(0.25))
      }
      .blockquote { configuration in
        HStack(spacing: 0) {
          RoundedRectangle(cornerRadius: 6)
            .fill(Color(rgba: 0x4244_4EFF))
            .relativeFrame(width: .em(0.2))
          configuration.label
            .markdownTextStyle { ForegroundColor(Color(rgba: 0x9294_A0FF)) }
            .relativePadding(.horizontal, length: .em(1))
        }
        .fixedSize(horizontal: false, vertical: true)
      }
      .image { configuration in
        configuration.label
          .relativePadding(.horizontal, length: .em(isWideLayout ? 4 : 1))
      }
  }
}

private extension View {
  /// `TextSelectability` is read from the type (`static var allowsSelection`), so a single
  /// conformance can't switch selection on and off: the old one always allowed it. Branch on
  /// the concrete types instead, so bodies are only selectable when asked.
  @ViewBuilder
  func helioTextSelection(_ enabled: Bool) -> some View {
    if enabled {
      textSelection(.enabled)
    } else {
      textSelection(.disabled)
    }
  }
}
