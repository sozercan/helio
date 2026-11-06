//
//  WebExtensionsPanel.swift
//  Helio
//
//  The web extensions the user added.
//

import SwiftUI
import UniformTypeIdentifiers
import WebKit

/// Adds, turns on and off, and removes the web extensions that run in the pages links open
/// (`WebExtensionStore`), and opens an extension's own settings page.
struct WebExtensionsPanel: View {
  @State private var store = WebExtensionStore.shared
  @State private var choosingFolder = false
  /// What failed, and why: the alert shows it.
  @State private var failure: (title: String, message: String)?
  @State private var optionsPage: OptionsPage?
  @Environment(\.useTheme) private var theme

  var body: some View {
    List {
      Section {
        ForEach(store.extensions) { ext in
          row(ext)
        }
        Button("Add Extension…", systemImage: "plus") { choosingFolder = true }
      } footer: {
        Text("Extensions run in the web pages links open. Add the folder that contains an extension's manifest.json, such as one from uBlock Origin Lite's Safari release. Helio gives an extension every permission it asks for, so only add ones you trust.")
      }
      .themedListSection()

      if store.changedSinceLaunch {
        Section {
          Label("Quit and reopen Helio to apply your changes.", systemImage: "arrow.clockwise")
        }
        .themedListSection()
      }
    }
    .themedListBG(theme.lists.bg)
    .navigationBarTitle("Extensions", displayMode: .inline)
    .fileImporter(isPresented: $choosingFolder, allowedContentTypes: [.folder]) { result in
      attempt("Couldn't Add the Extension") { try store.add(from: result.get()) }
    }
    .alert(failure?.title ?? "", isPresented: Binding { failure != nil } set: {
      if !$0 {
        failure = nil
      }
    }) {
      Button("OK", role: .cancel) {}
    } message: {
      Text(failure?.message ?? "")
    }
    .sheet(item: $optionsPage) { page in
      NavigationStack {
        OptionsPageView(page: page)
          .ignoresSafeArea(edges: .bottom)
          .navigationTitle(page.title)
          .navigationBarTitleDisplayMode(.inline)
          .toolbar {
            ToolbarItem(placement: .confirmationAction) {
              Button("Done") { optionsPage = nil }
            }
          }
      }
    }
  }

  /// Runs a change to the list, showing why it failed if it did.
  private func attempt(_ title: String, _ change: () throws -> Void) {
    do {
      try change()
    } catch {
      failure = (title, error.localizedDescription)
    }
  }

  private func row(_ ext: ManagedWebExtension) -> some View {
    let runtime = WebExtensionRuntime.shared
    let context = runtime.contexts[ext.id]
    return HStack(spacing: 12) {
      Toggle(isOn: Binding { ext.isEnabled } set: { enabled in
        attempt("Couldn't Change the Extension") { try store.setEnabled(enabled, for: ext) }
      }) {
        VStack(alignment: .leading, spacing: 2) {
          Text(ext.name)
          if let error = runtime.loadErrors[ext.id] {
            Text("Couldn't load: \(error)")
              .font(.caption)
              .foregroundStyle(.red)
          } else if let version = ext.version {
            Text("Version \(version)")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
      }
      if let context, let url = context.optionsPageURL, let configuration = context.webViewConfiguration {
        Button("Settings", systemImage: "gearshape") {
          optionsPage = OptionsPage(title: ext.name, url: url, configuration: configuration)
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
      }
      Button("Remove", systemImage: "trash", role: .destructive) {
        attempt("Couldn't Remove the Extension") { try withAnimation { try store.remove(ext) } }
      }
      .labelStyle(.iconOnly)
      .buttonStyle(.borderless)
    }
  }
}

/// An extension's settings page, which it shows with its own configuration (its origin, its
/// storage, its APIs).
private struct OptionsPage: Identifiable {
  let title: String
  let url: URL
  let configuration: WKWebViewConfiguration

  var id: URL {
    url
  }
}

private struct OptionsPageView: UIViewRepresentable {
  let page: OptionsPage

  func makeCoordinator() -> DialogPresenter {
    DialogPresenter()
  }

  func makeUIView(context: Context) -> WKWebView {
    let webView = WKWebView(frame: .zero, configuration: page.configuration)
    webView.uiDelegate = context.coordinator
    webView.load(URLRequest(url: page.url))
    return webView
  }

  func updateUIView(_: WKWebView, context _: Context) {}

  /// Settings pages ask before resetting things (`confirm()`), which needs a dialog.
  @MainActor
  final class DialogPresenter: NSObject, WKUIDelegate {
    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo) async {
      await JavaScriptDialogs.alert(message, by: frame, from: webView)
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo) async -> Bool {
      await JavaScriptDialogs.confirm(message, by: frame, from: webView)
    }

    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?, initiatedByFrame frame: WKFrameInfo) async -> String? {
      await JavaScriptDialogs.prompt(prompt, defaultText: defaultText, by: frame, from: webView)
    }
  }
}
