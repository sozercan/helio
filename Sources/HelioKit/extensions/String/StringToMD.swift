import Foundation
import SwiftUI

extension String {
  func md() -> AttributedString {
    let htmlDecodedString = self
    do {
      return try AttributedString(markdown: htmlDecodedString, options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace))
    } catch {}

    let lines = htmlDecodedString.split(whereSeparator: \.isNewline)
    var attributedString = AttributedString("")

    for line in lines {
      var newLineStr = String(line)
      if newLineStr.hasPrefix("#") {
        newLineStr.removeFirst()
        do {
          var newLineAttrStr = try AttributedString(markdown: newLineStr)
          newLineAttrStr.foregroundColor = .orange
          newLineAttrStr.backgroundColor = .white
          attributedString.append(newLineAttrStr)
        } catch {}
      } else {
        do {
          let newLineAttrStr = try AttributedString(markdown: newLineStr)
          attributedString.append(newLineAttrStr)
        } catch {}
      }
    }

    return attributedString
  }
}

extension String {}
