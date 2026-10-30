//
//  MathCGSize.swift
//  Helio
//
//  Created by Igor Marcossi on 06/08/23.
//

import Foundation

extension CGSize {
  static func + (lhs: CGSize, rhs: CGSize) -> CGSize {
    CGSize(width: lhs.width + rhs.width, height: lhs.height + rhs.height)
  }

  static func + (lhs: CGSize, rhs: Double) -> CGSize {
    CGSize(width: lhs.width + rhs, height: lhs.height + rhs)
  }

  static func - (lhs: CGSize, rhs: CGSize) -> CGSize {
    CGSize(width: lhs.width - rhs.width, height: lhs.height - rhs.height)
  }

  static func - (lhs: CGSize, rhs: Double) -> CGSize {
    CGSize(width: lhs.width - rhs, height: lhs.height - rhs)
  }

  static func * (lhs: CGSize, rhs: CGSize) -> CGSize {
    CGSize(width: lhs.width * rhs.width, height: lhs.height * rhs.height)
  }

  static func * (lhs: CGSize, rhs: Double) -> CGSize {
    CGSize(width: lhs.width * rhs, height: lhs.height * rhs)
  }
}
