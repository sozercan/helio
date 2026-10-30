//
//  Prepend.swift
//  Helio
//
//  Created by Igor Marcossi on 08/10/23.
//

import Foundation
import SwiftUI
import SwiftyUI
import UIKit

struct PrependTag: Hashable, Equatable {
  let label: String
  let bgColor: UIColor
  let textColor: UIColor
}

func createTitleTagsAttrString(titleTheme: ThemeText, postData: PostData, textColor: UIColor) -> NSAttributedString {
  let tagFont = UIFont.systemFont(ofSize: Double(((titleTheme.size - 2) * 100) / 120), weight: .semibold)
  let titleFont = UIFont.systemFont(ofSize: titleTheme.size, weight: titleTheme.weight.ut)
  let titleTagsImages = getTagsFromTitle(postData).compactMap { createTagImage(withTitle: $0.label, textColor: $0.textColor, backgroundColor: $0.bgColor, font: tagFont) }

  let attrTitle = NSMutableAttributedString(string: postData.title, attributes: [.font: titleFont, .foregroundColor: textColor])

  for img in titleTagsImages {
    let attach = NSTextAttachment(image: img)
    attach.bounds = CGRect(x: 0, y: titleFont.descender - img.size.height / 2 + (titleFont.descender + titleFont.capHeight) + 2, width: img.size.width, height: img.size.height).integral
    let attachmentString = NSAttributedString(attachment: attach)
    attrTitle.append(NSAttributedString(string: " "))
    attrTitle.append(attachmentString)
  }

  if !titleTagsImages.isEmpty {
    attrTitle.append(NSAttributedString(string: " "))
  }

  attrTitle.append(NSAttributedString(string: "\n\n\n\n\n\n\n"))
  return attrTitle

  func createTagImage(withTitle title: String, textColor: UIColor, backgroundColor: UIColor, font: UIFont) -> UIImage? {
    let paragraphStyle = NSMutableParagraphStyle()
    paragraphStyle.alignment = .center

    let attrs: [NSAttributedString.Key: Any] = [
      .font: font,
      .paragraphStyle: paragraphStyle,
      .foregroundColor: textColor,
    ]

    let attributedString = NSAttributedString(string: title, attributes: attrs)
    let textSize = attributedString.size()

    let padding = UIEdgeInsets(top: 0, left: 4, bottom: 0, right: 4)
    let size = CGSize(width: textSize.width + padding.left + padding.right, height: textSize.height + padding.top + padding.bottom)
    let rect = CGRect(origin: .zero, size: size)

    UIGraphicsBeginImageContextWithOptions(rect.size, false, 0)

    guard let context = UIGraphicsGetCurrentContext() else { return nil }

    let path = UIBezierPath(roundedRect: rect, cornerRadius: 4)
    context.addPath(path.cgPath)
    backgroundColor.setFill()
    context.fillPath()

    attributedString.draw(with: rect.inset(by: padding), options: [.usesLineFragmentOrigin], context: nil)

    let image = UIGraphicsGetImageFromCurrentImageContext()

    UIGraphicsEndImageContext()

    return image
  }
}

func buildTitleWithTags(attrString: NSAttributedString, title: String, fontSize: Double, fontWeight: UIFont.Weight, color: UIColor, size: CGSize) -> SwiftyLabel {
//  let text = UITextView(usingTextLayoutManager: false)
  let text = SwiftyLabel()
  text.frame = .init(x: 0, y: 0, width: size.width, height: size.height)

//  text.layer.shouldRasterize = true
//  text.layer.rasterizationScale = UIScreen.main.scale
  text.textColor = color
  text.textAlignment = .topLeft
  text.backgroundColor = .clear
  text.numberOfLines = 0
  text.lineBreakMode = .byWordWrapping
  text.isUserInteractionEnabled = false
  text.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
  text.translatesAutoresizingMaskIntoConstraints = false
  text.attributedText = titleColored(attrString, title: title, color: color)
//  text.sizeToFit()
  return text
}

/// The title with `color`, leaving the tags after it as they are.
private func titleColored(_ attrString: NSAttributedString, title: String, color: UIColor) -> NSAttributedString {
  let colored = NSMutableAttributedString(attributedString: attrString)
  let range = NSRange(location: 0, length: min((title as NSString).length, colored.length))
  colored.addAttribute(.foregroundColor, value: color, range: range)
  return colored
}

struct Prepend: UIViewRepresentable, Equatable {
  static func == (lhs: Prepend, rhs: Prepend) -> Bool {
    lhs.title == rhs.title && lhs.size == rhs.size && lhs.color == rhs.color && lhs.fontWeight == rhs.fontWeight
  }

  var attrString: NSAttributedString
  var title: String
  var fontSize: CGFloat
  var fontWeight: UIFont.Weight
  var color: UIColor
  var size: CGSize

  func makeUIView(context: Context) -> SwiftyLabel {
    buildTitleWithTags(attrString: attrString, title: title, fontSize: fontSize, fontWeight: fontWeight, color: color, size: size)
  }

  func updateUIView(_ uiLabel: SwiftyLabel, context: Context) {
    let current = uiLabel.attributedText.flatMap { $0.length > 0 ? $0.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? UIColor : nil }
    if current != color {
      uiLabel.attributedText = titleColored(attrString, title: title, color: color)
    }
//    if size != uiLabel.frame.size { uiLabel.frame.size = size }
//    if !(uiLabel.attributedText?.isEqual(to: attrString) ?? false) { uiLabel.attributedText = attrString }
  }
}
