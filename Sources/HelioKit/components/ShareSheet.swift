import LinkPresentation
import SwiftUI

struct ShareSheet: UIViewControllerRepresentable {
  var items: [Any]
  func makeUIViewController(context: Context) -> UIActivityViewController {
    let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
    controller.title = "Test"
    return controller
  }

  func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

class ShareImage: UIActivityItemProvider {
  var image: UIImage

  override var item: Any {
    self.image
  }

  override init(placeholderItem: Any) {
    guard let image = placeholderItem as? UIImage else {
      fatalError("Couldn't create image from provided item")
    }

    self.image = image
    super.init(placeholderItem: placeholderItem)
  }

  @available(iOS 13.0, *)
  override func activityViewControllerLinkMetadata(_ activityViewController: UIActivityViewController) -> LPLinkMetadata? {
    let metadata = LPLinkMetadata()
    metadata.title = "Image"

    var thumbnail: NSSecureCoding = NSNull()
    if let imageData = self.image.pngData() {
      thumbnail = NSData(data: imageData)
    }

    metadata.imageProvider = NSItemProvider(item: thumbnail, typeIdentifier: "public.png")

    return metadata
  }
}

@MainActor
class ShareUtils {
  private static var pendingPresentation: Task<Void, Never>?

  static func topViewController(_ base: UIViewController? = nil) -> UIViewController? {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first
    let root = base ?? (scene?.keyWindow ?? scene?.windows.first)?.rootViewController
    if let nav = root as? UINavigationController {
      return topViewController(nav.visibleViewController ?? nav)
    }
    if let tab = root as? UITabBarController {
      return topViewController(tab.selectedViewController ?? tab)
    }
    if let presented = root?.presentedViewController {
      if presented.isBeingDismissed {
        return root
      }
      return topViewController(presented)
    }
    return root
  }

  static func shareItem(item: String, sourceView: UIView? = nil) {
    guard let url = URL(string: item) else { return }
    pendingPresentation?.cancel()
    pendingPresentation = Task { @MainActor in
      let ready = await waitForPresentationReady()
      guard !Task.isCancelled, ready else { return }
      presentActivityController(for: [url], sourceView: sourceView)
    }
  }

  static func waitForPresentationReady(
    resolveTop: @MainActor () -> UIViewController? = { topViewController() },
    maxAttempts: Int = 20,
    yield: @MainActor () async -> Void = { await Task.yield() },
    sleep: @MainActor () async -> Void = { try? await Task.sleep(for: .milliseconds(25)) },
  ) async -> Bool {
    await yield()
    for _ in 0 ..< maxAttempts {
      guard !Task.isCancelled, let top = resolveTop() else { return false }
      if !isTransitioning(top) {
        return true
      }
      if let coordinator = transitionCoordinator(for: top) {
        await withCheckedContinuation { continuation in
          coordinator.animate(alongsideTransition: nil) { _ in
            continuation.resume()
          }
        }
      } else {
        await sleep()
      }
    }
    guard !Task.isCancelled, let top = resolveTop() else { return false }
    return !isTransitioning(top)
  }

  static func isTransitioning(_ viewController: UIViewController) -> Bool {
    viewController.isBeingDismissed
      || viewController.isBeingPresented
      || viewController.transitionCoordinator != nil
      || (viewController.presentedViewController?.isBeingDismissed ?? false)
      || (viewController.presentedViewController?.isBeingPresented ?? false)
  }

  private static func transitionCoordinator(for viewController: UIViewController) -> UIViewControllerTransitionCoordinator? {
    viewController.transitionCoordinator ?? viewController.presentedViewController?.transitionCoordinator
  }

  private static func presentActivityController(for items: [Any], sourceView: UIView?) {
    guard let top = topViewController() else { return }
    let activityViewController = UIActivityViewController(activityItems: items, applicationActivities: nil)
    if let popoverController = activityViewController.popoverPresentationController {
      popoverController.sourceView = sourceView ?? top.view
      popoverController.sourceRect = sourceView?.bounds ?? CGRect(x: top.view.bounds.midX, y: top.view.bounds.midY, width: 0, height: 0)
      popoverController.permittedArrowDirections = []
    }
    top.present(activityViewController, animated: true, completion: nil)
  }
}
