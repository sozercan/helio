//
//  External to Internal Links.swift
//  Helio
//
//  Created by Ethan Bills on 1/10/24.
//

import Foundation
import MarkdownUI

class MarkdownUtil {
  static func containsSpoiler(_ text: String) -> Bool {
    text.contains("&gt;!") && text.contains("!&lt;") ||
      text.contains(">!") && text.contains("!<")
  }

  private final class ParsedMarkdown {
    let content: MarkdownContent
    init(_ content: MarkdownContent) {
      self.content = content
    }
  }

  private static let parsed: NSCache<NSString, ParsedMarkdown> = {
    let cache = NSCache<NSString, ParsedMarkdown>()
    cache.countLimit = 2000
    return cache
  }()

  /// `text` rewritten by `formatForMarkdown` and parsed. Rows render it on every update and on
  /// every scroll back into view, so each text is formatted and parsed once.
  static func markdownContent(_ text: String, showSpoiler: Bool = false) -> MarkdownContent {
    let key = "\(showSpoiler ? "s" : "h")\(text)" as NSString
    if let cached = parsed.object(forKey: key) {
      return cached.content
    }
    let content = MarkdownContent(formatForMarkdown(text, showSpoiler: showSpoiler))
    parsed.setObject(ParsedMarkdown(content), forKey: key)
    return content
  }

  static func formatForMarkdown(_ text: String, showSpoiler: Bool = false) -> String {
    var processedText = text

    // Replace http:// or https:// in existing markdown links
    processedText = processedText.replacingOccurrences(
      of: #"([[(\w\])\/.:*]+])\((https?:\/\/)(\S+?|)(?:)\)"#,
      with: "$1(helioapp://$3)",
      options: .regularExpression,
    )

    // Replace URLs with http:// or https:// (if not already in markdown format)
    processedText = processedText.replacingOccurrences(
      of: #"\b(?<!\[)(https?:\/\/)(.*\.(?:png|jpe?g|bmp|tiff|webp|svgz?|ico)(?:\?.*)?)(?!\])\b"#,
      with: "[![$0]($0)](helioapp://$2)",
      options: .regularExpression,
    )

    // Replace URLs with http:// or https:// (if not already in markdown format)
    processedText = processedText.replacingOccurrences(
      of: "\\b(?<!\\[|\\()(https?://)(\\S+)(?!\\]|\\))\\b",
      with: "[$0](helioapp://$2)",
      options: .regularExpression,
    )

    // Replace /u/example or u/example
    processedText = processedText.replacingOccurrences(
      of: "(\\s|^)(/?u/\\w+)(\\s|\\b)",
      with: " [$2](helioapp://$2) ",
      options: [.regularExpression, .caseInsensitive],
    )

    // Replace /r/example or r/example
    processedText = processedText.replacingOccurrences(
      of: "(\\s|^)(/?r/\\w+)(\\s|\\b)",
      with: " [$2](helioapp://$2) ",
      options: [.regularExpression, .caseInsensitive],
    )

    // Replace &#x200B; and &nbsp; with a space
    processedText = processedText.replacingOccurrences(
      of: "&amp;#x200B;|&amp;nbsp;",
      with: " ",
      options: [.regularExpression, .caseInsensitive],
    )

    processedText = processedText.replacingOccurrences(
      of: "&gt;",
      with: ">",
    )

    processedText = processedText.replacingOccurrences(
      of: "&lt;",
      with: "<",
    )

    processedText = processedText.replacingOccurrences(
      of: "&Hat;",
      with: "^",
    )

    if containsSpoiler(processedText) {
      if showSpoiler {
        processedText = processedText.replacingOccurrences(
          of: ">!",
          with: "",
        )

        processedText = processedText.replacingOccurrences(
          of: "!<",
          with: "",
        )
      } else {
        processedText = processedText.replacingOccurrences(
          of: ">!(.*?)!<",
          with: "■",
          options: .regularExpression,
        )
      }
    }

    return processedText
  }
}
