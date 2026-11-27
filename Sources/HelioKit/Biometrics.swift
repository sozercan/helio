import Foundation
import LocalAuthentication
import SwiftUI

class Biometrics {
  let context = LAContext()
  var error: NSError?

  func checkIfEnrolled() -> Bool {
    var isEnrolled = false
    if context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) {
      print("Biometrics are available on this device")
      isEnrolled = true
    } else {
      print("Biometrics are not available on this device")
    }
    return isEnrolled
  }

  func biometricType() -> String {
    if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
      switch context.biometryType {
      case .opticID:
        "Optic ID"
      case .faceID:
        "Face ID"
      case .touchID:
        "Touch ID"
      case .none:
        "None"
      @unknown default:
        "Unknown"
      }
    } else {
      "Passcode"
    }
  }

  func authenticateUser(completion: @escaping (Bool) -> Void) {
    if !checkIfEnrolled() {
      completion(false)
      return
    }
    context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Identify Yourself!") { success, error in
      if success {
        print("Auth Success")
        completion(true)
      } else {
        print("Auth Failure: \(error?.localizedDescription ?? "Failed to authenticate")")
        completion(false)
      }
    }
  }
}
