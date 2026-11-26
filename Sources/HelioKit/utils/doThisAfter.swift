import Foundation

func doThisAfter(_ seconds: CGFloat, callback: @escaping () -> Void) {
  return DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
    callback()
  }
}
