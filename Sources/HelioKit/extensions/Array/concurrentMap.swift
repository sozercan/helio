//
//  concurrentMap.swift
//  Helio
//
//  Created by Igor Marcossi on 14/12/23.
//

import Dispatch
import Foundation

public extension Array {
  func concurrentMap<B>(_ transform: @escaping (Element) -> B) -> [B] {
    var result = [B?](repeating: nil, count: count)
    let resultAccessQueue = DispatchQueue(label: "Sync queue", attributes: .concurrent)

    DispatchQueue.concurrentPerform(iterations: count) { idx in
      let item = self[idx]
      let transformed = transform(item)
      resultAccessQueue.async(flags: .barrier) {
        result[idx] = transformed
      }
    }

    resultAccessQueue.sync(flags: .barrier) {}

    return result as! [B]
  }
}
