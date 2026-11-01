//
//  Arrows.swift
//  Helio
//
//  Created by Igor Marcossi on 08/07/23.
//

import SwiftUI

enum ArrowKind: Equatable {
  case straight
  case straightCurve
  case curve
  case empty

  var child: ArrowKind {
    switch self {
    case .straightCurve:
      .straight
    case .curve:
      .empty
    case .straight, .empty:
      self
    }
  }
}

struct Arrows: View, Equatable {
  static func == (lhs: Arrows, rhs: Arrows) -> Bool {
    lhs.kind == rhs.kind
  }

  var kind: ArrowKind
  var offset: CGFloat = 0
  @Environment(\.useTheme) private var selectedTheme
  var body: some View {
    let curve = selectedTheme.comments.theme.indentCurve
    let curveColor = selectedTheme.comments.theme.indentColor
    let avatarSize = selectedTheme.comments.theme.badge.avatar.size
    Group {
      switch kind {
      case .curve:
        CurveShape(offset: offset, curve: curve, avatarSize: avatarSize)
          .stroke(curveColor(), style: StrokeStyle(lineWidth: 2, lineCap: .round))
      case .straight:
        StraightShape()
          .stroke(curveColor(), style: StrokeStyle(lineWidth: 2, lineCap: .round))
          .padding(.vertical, -1)
      case .straightCurve:
        StraightCurveShape(offset: offset, curve: curve, avatarSize: avatarSize)
          .stroke(curveColor(), style: StrokeStyle(lineWidth: 2, lineCap: .round))
          .padding(.vertical, -1)
      case .empty:
        Color.clear
      }
    }
    .padding(.all, 1)
    .frame(maxWidth: curve, maxHeight: .infinity, alignment: .topLeading)
  }
}

struct StraightShape: Shape {
  func path(in rect: CGRect) -> Path {
    var path = Path()
    path.move(to: CGPoint(x: rect.minX, y: rect.minY))
    path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
    return path
  }
}

struct StraightCurveShape: Shape {
  var offset: CGFloat = 0
  var curve: CGFloat
  var avatarSize: CGFloat
  func path(in rect: CGRect) -> Path {
    let threshold = (avatarSize - (curve * 2)) / 2
    var path = Path()
    path.move(to: CGPoint(x: rect.minX, y: rect.minY))
    path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
    path.addArc(center: CGPoint(x: rect.minX + curve, y: rect.minY + offset + threshold), radius: curve, startAngle: .degrees(180), endAngle: .degrees(90), clockwise: true)
    return path
  }
}

struct CurveShape: Shape {
  var offset: CGFloat = 0
  var curve: CGFloat
  var avatarSize: CGFloat
  func path(in rect: CGRect) -> Path {
    let threshold = (avatarSize - (curve * 2)) / 2
    var path = Path()
    path.move(to: CGPoint(x: rect.minX, y: rect.minY))
    if offset != 0 {
      path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + offset + threshold))
    }
    if curve == 0 {
      path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + offset + threshold))
    }
    path.addArc(center: CGPoint(x: rect.minX + curve, y: rect.minY + offset + threshold), radius: curve, startAngle: .degrees(180), endAngle: .degrees(90), clockwise: true)
    return path
  }
}

/// Apollo's reply indent: one straight bar in the depth's color, with the content after it.
struct CommentDepthBar: ViewModifier {
  static let width: CGFloat = 2
  static let contentSpacing: CGFloat = 15

  let depth: Int
  let theme: CommentTheme
  var topInset: CGFloat = 0
  var bottomInset: CGFloat = 0
  var separator = false

  static func leading(depth: Int, theme: CommentTheme) -> CGFloat {
    depth > 0 ? (theme.indentCurve * CGFloat(depth)) + width + contentSpacing : theme.innerPadding.horizontal
  }

  func body(content: Content) -> some View {
    let barX = theme.indentCurve * CGFloat(depth)
    content
      .padding(.leading, CommentDepthBar.leading(depth: depth, theme: theme))
      .padding(.trailing, theme.innerPadding.horizontal)
      .background(alignment: .leading) {
        if depth > 0, !theme.indentColors.isEmpty {
          Capsule(style: .continuous)
            .fill(theme.indentColors[(depth - 1) % theme.indentColors.count]())
            .frame(width: CommentDepthBar.width)
            .padding(.top, topInset)
            .padding(.bottom, bottomInset)
            .padding(.leading, barX)
        }
      }
      .overlay(alignment: .top) {
        if separator {
          theme.indentColor()
            .frame(height: 0.5)
            .padding(.leading, depth > 0 ? barX : 0)
        }
      }
  }
}

extension View {
  /// Applies `CommentDepthBar` when `depth` is set, otherwise leaves the view alone.
  @ViewBuilder
  func commentDepthBar(_ depth: Int?, theme: CommentTheme, top: CGFloat = 0, bottom: CGFloat = 0, separator: Bool = false) -> some View {
    if let depth {
      modifier(CommentDepthBar(depth: depth, theme: theme, topInset: top, bottomInset: bottom, separator: separator))
    } else {
      self
    }
  }
}
