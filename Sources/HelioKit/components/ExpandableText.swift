//
//  ExpandableText.swift
//  Helio
//
//  Created by Daniel Inama on 05/10/23.
//

import SwiftUI

struct ExpandableText: View {
  @State private var isExpanded: Bool = false
  @State private var isTruncated: Bool = false

  @State private var intrinsicSize: CGSize = .zero
  @State private var truncatedSize: CGSize = .zero
  @State private var moreTextSize: CGSize = .zero

  let text: String
  let font: Font
  let lineLimit: Int
  let moreText: String

  var body: some View {
    content
      .lineLimit(isExpanded ? nil : lineLimit)
      .applyingTruncationMask(moreTextSize: moreTextSize, isExpanded: isExpanded, isTruncated: isTruncated)
      .readSize { size in
        truncatedSize = size
        isTruncated = truncatedSize != intrinsicSize
      }
      .background(
        content
          .lineLimit(nil)
          .fixedSize(horizontal: false, vertical: true)
          .hidden()
          .readSize { size in
            intrinsicSize = size
            isTruncated = truncatedSize != intrinsicSize
          },
      )
      .background(
        Text(moreText)
          .font(font)
          .hidden()
          .readSize { moreTextSize = $0 },
      )
      .contentShape(Rectangle())
      .onTapGesture {
        if !isExpanded, isTruncated {
          withAnimation { isExpanded.toggle() }
        }
      }
      .overlay(alignment: .trailingLastTextBaseline) {
        if !isExpanded, isTruncated {
          Button {
            withAnimation { isExpanded.toggle() }
          } label: {
            Text(moreText)
              .font(font)
          }
        }
      }
  }

  private var content: some View {
    Text(.init(!isExpanded && isTruncated ? textTrimmingDoubleNewlines : text))
      .font(font)
      .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var textTrimmingDoubleNewlines: String {
    text.replacingOccurrences(of: #"\n\s*\n"#, with: "\n", options: .regularExpression)
  }
}

private struct TruncationTextMask: ViewModifier {
  let moreTextSize: CGSize
  let isExpanded: Bool
  let isTruncated: Bool

  @Environment(\.layoutDirection) private var layoutDirection

  func body(content: Content) -> some View {
    if !isExpanded, isTruncated {
      content
        .mask(
          VStack(spacing: 0) {
            Rectangle()
            HStack(spacing: 0) {
              Rectangle()
              HStack(spacing: 0) {
                LinearGradient(
                  gradient: Gradient(stops: [
                    Gradient.Stop(color: .black, location: 0),
                    Gradient.Stop(color: .clear, location: 0.85),
                  ]),
                  startPoint: layoutDirection == .rightToLeft ? .trailing : .leading,
                  endPoint: layoutDirection == .rightToLeft ? .leading : .trailing,
                ).frame(width: moreTextSize.width, height: moreTextSize.height)

                Rectangle()
                  .foregroundColor(.clear)
                  .frame(width: moreTextSize.width)
              }
            }.frame(height: moreTextSize.height)
          },
        )
    } else {
      content
        .fixedSize(horizontal: false, vertical: true)
    }
  }
}

private extension View {
  func applyingTruncationMask(moreTextSize: CGSize, isExpanded: Bool, isTruncated: Bool) -> some View {
    modifier(TruncationTextMask(moreTextSize: moreTextSize, isExpanded: isExpanded, isTruncated: isTruncated))
  }
}

/// https://www.fivestars.blog/articles/swiftui-share-layout-information/
private struct SizePreferenceKey: PreferenceKey {
  static var defaultValue: CGSize = .zero
  static func reduce(value: inout CGSize, nextValue: () -> CGSize) {}
}

extension View {
  func readSize(onChange: @escaping (CGSize) -> Void) -> some View {
    background(
      GeometryReader { geometryProxy in
        Color.clear
          .preference(key: SizePreferenceKey.self, value: geometryProxy.size)
      },
    )
    .onPreferenceChange(SizePreferenceKey.self, perform: onChange)
  }
}
