//
//  JavaScriptDialogs.swift
//  Helio
//
//  A web page's alert, confirm and prompt dialogs.
//

import UIKit
import WebKit

/// Shows a web page's JavaScript dialogs, for a web view's `WKUIDelegate`. Without them WebKit
/// answers on its own: `confirm()` as Cancel and `prompt()` with nothing, so a page's actions
/// that ask first can never go ahead.
@MainActor
enum JavaScriptDialogs {
  static func alert(_ message: String, by frame: WKFrameInfo, from webView: WKWebView) async {
    _ = await present(message, by: frame, from: webView, buttons: [Button("OK", .cancel, ())])
  }

  static func confirm(_ message: String, by frame: WKFrameInfo, from webView: WKWebView) async -> Bool {
    await present(message, by: frame, from: webView, buttons: [Button("Cancel", .cancel, false), Button("OK", .default, true)]) ?? false
  }

  static func prompt(_ message: String, defaultText: String?, by frame: WKFrameInfo, from webView: WKWebView) async -> String? {
    var field: UITextField?
    let confirmed = await present(message, by: frame, from: webView, buttons: [Button("Cancel", .cancel, false), Button("OK", .default, true)]) { alert in
      alert.addTextField { $0.text = defaultText }
      field = alert.textFields?.first
    }
    return confirmed == true ? field?.text ?? "" : nil
  }

  private struct Button<Value> {
    let title: String
    let style: UIAlertAction.Style
    let value: Value

    init(_ title: String, _ style: UIAlertAction.Style, _ value: Value) {
      self.title = title
      self.style = style
      self.value = value
    }
  }

  /// Shows `message` over whatever the web view's window shows on top, and returns the value of
  /// the button picked. Nil when there's nothing to show it from. Titled with the site of the
  /// frame that asked, not the page's: a frame from another site mustn't pass for the page.
  private static func present<Value>(_ message: String, by frame: WKFrameInfo, from webView: WKWebView, buttons: [Button<Value>], configure: (UIAlertController) -> Void = { _ in }) async -> Value? {
    var presenter = webView.window?.rootViewController
    while let presented = presenter?.presentedViewController {
      presenter = presented
    }
    guard let presenter else { return nil }
    return await withCheckedContinuation { continuation in
      let host = frame.securityOrigin.host
      let alert = UIAlertController(title: host.isEmpty ? nil : host, message: message, preferredStyle: .alert)
      for button in buttons {
        alert.addAction(UIAlertAction(title: button.title, style: button.style) { _ in continuation.resume(returning: button.value) })
      }
      configure(alert)
      presenter.present(alert, animated: true)
    }
  }
}
