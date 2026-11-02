//
//  timeSince.swift
//  Helio
//
//  Created by Igor Marcossi on 25/07/23.
//

import Foundation

func timeSince(_ timestamp: Int) -> String {
  let currentTime = Int(Date().timeIntervalSince1970)
  let timeInterval = currentTime - timestamp

  let minute = 60
  let hour = minute * 60
  let day = hour * 24
  let year = day * 365

  switch timeInterval {
  case 0 ..< hour:
    return "\(timeInterval / minute)m"
  case hour ..< day:
    return "\(timeInterval / hour)h"
  case day ..< year:
    return "\(timeInterval / day)d"
  default:
    return "\(timeInterval / year)y"
  }
}

/// `timeSince` as VoiceOver should read it: "2 hours ago" instead of "2h".
func spokenTimeSince(_ timestamp: Int) -> String {
  let timeInterval = Int(Date().timeIntervalSince1970) - timestamp
  let minute = 60
  let hour = minute * 60
  let day = hour * 24
  let year = day * 365

  func ago(_ count: Int, _ unit: String) -> String {
    "\(count) \(unit)\(count == 1 ? "" : "s") ago"
  }

  switch timeInterval {
  case 0 ..< hour:
    return ago(timeInterval / minute, "minute")
  case hour ..< day:
    return ago(timeInterval / hour, "hour")
  case day ..< year:
    return ago(timeInterval / day, "day")
  default:
    return ago(timeInterval / year, "year")
  }
}
