//
//  urlEncoded.swift
//  Helio
//
//  Created by Igor Marcossi on 26/01/24.
//

import Foundation

extension String {
  var urlEncoded: String {
    self.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ""
//        let allowedCharacterSet = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "~-_."))
//        return self.addingPercentEncoding(withAllowedCharacters: allowedCharacterSet)
  }
}
