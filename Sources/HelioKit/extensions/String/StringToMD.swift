//
//  StringToMD.swift
//  Helio
//
//  Created by Igor Marcossi on 04/07/23.
//

import Foundation
import SwiftUI

extension String {
  func md() -> AttributedString {
    //    if let htmlDecodedString = self.escape() {
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

// extension String {
//    var markdownToAttributedString: AttributedString {
//        var as = AttributedString(self)
//
//        let patterns = [
//            "\\*\\*(.+?)\\*\\*": UIFont.boldSystemFont(ofSize: UIFont.systemFontSize),
//            "\\*(.+?)\\*": UIFont.italicSystemFont(ofSize: UIFont.systemFontSize),
//            "\\#\\s(.+?)": UIFont.systemFont(ofSize: 24.0, weight: .bold),
//            "\\#\\#\\s(.+?)": UIFont.systemFont(ofSize: 18.0, weight: .bold),
//            "\\#\\#\\#\\s(.+?)": UIFont.systemFont(ofSize: 14.0, weight: .bold),
//            "\\#\\#\\#\\#\\s(.+?)": UIFont.systemFont(ofSize: 10.0, weight: .bold),
//            "\\>(.+?)\\n": UIFont.systemFont(ofSize: UIFont.systemFontSize)
//        ]
//
//        patterns.forEach { pattern, font in
//            guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return }
//            let matches = regex.matches(in: as.string, options: [], range: NSRange(location: 0, length: as.string.utf16.count))
//
//            for match in matches {
//                let matchRange = match.range(at: 1)
//                if let range = Range(matchRange, in: as.string) {
//                    as[range].font = font
//                }
//            }
//        }
//
//        // Match Links
//        do {
//            let detector = try NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
//            let matches = detector.matches(in: as.string, options: [], range: NSRange(location: 0, length: as.string.utf16.count))
//            for match in matches {
//                if let urlRange = Range(match.range, in: as.string) {
//                    as[urlRange].link = URL(string: as.string[urlRange])
//                }
//            }
//        } catch {
//            print("Failed to match links: \(error)")
//        }
//
//        return as
//    }
// }

extension String {}
