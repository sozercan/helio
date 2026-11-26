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

class ShareUtils {
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
      return topViewController(presented)
    }
    return root
  }

  static func shareItem(item: String, sourceView: UIView? = nil) {
    guard let url = URL(string: item) else { return }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
      guard let top = topViewController() else { return }
      let activityViewController = UIActivityViewController(activityItems: [url], applicationActivities: nil)
      if let popoverController = activityViewController.popoverPresentationController {
        popoverController.sourceView = sourceView ?? top.view
        popoverController.sourceRect = sourceView?.bounds ?? CGRect(x: top.view.bounds.midX, y: top.view.bounds.midY, width: 0, height: 0)
        popoverController.permittedArrowDirections = []
      }
      top.present(activityViewController, animated: true, completion: nil)
    }
  }
}
