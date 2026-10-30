//
//  maxRelative.swift
//  Helio
//
//  Created by Igor Marcossi on 30/11/23.
//

import Foundation

func maxRelative(_ value: Double, maxValue: Double) -> Double {
  if value > maxValue {
    maxValue
  } else if value < -maxValue {
    -maxValue
  } else {
    value
  }
}
