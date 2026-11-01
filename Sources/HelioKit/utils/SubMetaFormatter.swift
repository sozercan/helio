//
//  SubMetaFormatter.swift
//  Helio
//
//  Created by Igor Marcossi on 06/02/24.
//

import Foundation

struct SubMetaFormatter {
  var name: String?

  init(name: String) {
    var formattedName = name
    if formattedName.hasPrefix("r/") {
      formattedName.removeFirst(2)
    } else if formattedName.hasPrefix("/r/") {
      formattedName.removeFirst(3)
    } else if formattedName.hasPrefix("/") {
      formattedName.removeFirst()
    }
    if formattedName.hasSuffix("/") {
      formattedName.removeLast()
    }
    self.name = formattedName
  }
}
