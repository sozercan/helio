//
//  ShareSheet.swift
//  winston
//
//  Created by Daniel Inama on 31/08/23.
//

import SwiftUI
import LinkPresentation

struct ShareSheet: UIViewControllerRepresentable {
  var items: [Any]
  func makeUIViewController(context: Context) -> UIActivityViewController {
    let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
    controller.title = "Test"
    return controller
  }
  
  func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {
    
  }
  
}

/// Image that you can share using a Share Sheet
/// This will also display all the metadata correctly
class ShareImage: UIActivityItemProvider {
  var image: UIImage
  
  override var item: Any {
    get {
      return self.image
    }
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
  /// Walk to the top-most presented view controller so presentation works even when a context
  /// menu, sheet, or fullscreen cover is on screen.
  static func topViewController(_ base: UIViewController? = nil) -> UIViewController? {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first
    let root = base ?? (scene?.keyWindow ?? scene?.windows.first)?.rootViewController
    if let nav = root as? UINavigationController { return topViewController(nav.visibleViewController ?? nav) }
    if let tab = root as? UITabBarController { return topViewController(tab.selectedViewController ?? tab) }
    if let presented = root?.presentedViewController { return topViewController(presented) }
    return root
  }

  static func shareItem(item: String, sourceView: UIView? = nil) {
    guard let url = URL(string: item) else { return }
    // The small delay lets a dismissing context menu clear first; presenting on the top-most VC
    // makes this work from a context-menu Button (SwiftUI's ShareLink inside .contextMenu is broken
    // — the menu dismisses but the share sheet never presents).
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
      guard let top = topViewController() else { return }
      let activityViewController = UIActivityViewController(activityItems: [url], applicationActivities: nil)
      // Source for iPad popover.
      if let popoverController = activityViewController.popoverPresentationController {
        popoverController.sourceView = sourceView ?? top.view
        popoverController.sourceRect = sourceView?.bounds ?? CGRect(x: top.view.bounds.midX, y: top.view.bounds.midY, width: 0, height: 0)
        popoverController.permittedArrowDirections = []
      }
      top.present(activityViewController, animated: true, completion: nil)
    }
  }
}
