import Foundation
import SwiftUI

extension String {
  static func + (lhs: String, rhs: String?) -> String {
    "\(lhs)\(rhs ?? "")"
  }
}
