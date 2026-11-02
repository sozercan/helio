//
//  WebPageView.swift
//  Helio
//
//  A web page shown in the app beside the feed, in the post column (iPad, Mac, the open iPhone
//  Duo). Compact layouts open pages in a Safari sheet instead.
//

import SwiftUI
import WebKit

struct WebPageView: View {
  let url: URL
  @State private var page: WebPage?

  var body: some View {
    Group {
      if let page {
        WebView(page)
          .overlay(alignment: .top) {
            if page.isLoading {
              ProgressView(value: page.estimatedProgress)
                .progressViewStyle(.linear)
            }
          }
          .navigationTitle(page.title.isEmpty ? url.host() ?? url.absoluteString : page.title)
          .toolbar { toolbar(page) }
      } else {
        Color.clear
      }
    }
    .navigationBarTitleDisplayMode(.inline)
    .onAppear {
      // Loads when shown, not before: only what the user opens.
      guard page == nil else { return }
      let page = Self.makePage()
      _ = page.load(URLRequest(url: url))
      self.page = page
    }
  }

  /// A page with its own store, kept in memory only: no cookies or storage shared with other
  /// pages, the Reddit session, or the next launch.
  static func makePage() -> WebPage {
    var configuration = WebPage.Configuration()
    configuration.websiteDataStore = .nonPersistent()
    return WebPage(configuration: configuration)
  }

  @ToolbarContentBuilder
  private func toolbar(_ page: WebPage) -> some ToolbarContent {
    let pageURL = page.url ?? url
    ToolbarItemGroup(placement: .bottomBar) {
      Button("Previous Page", systemImage: "chevron.backward") {
        if let item = page.backForwardList.backList.last {
          _ = page.load(item)
        }
      }
      .disabled(page.backForwardList.backList.isEmpty)
      Button("Next Page", systemImage: "chevron.forward") {
        if let item = page.backForwardList.forwardList.first {
          _ = page.load(item)
        }
      }
      .disabled(page.backForwardList.forwardList.isEmpty)
      Spacer()
      if page.isLoading {
        Button("Stop", systemImage: "xmark") { page.stopLoading() }
      } else {
        Button("Reload", systemImage: "arrow.clockwise") { _ = page.reload() }
      }
    }
    ToolbarItemGroup(placement: .primaryAction) {
      ShareLink(item: pageURL)
      Button("Open in Browser", systemImage: "safari") {
        UIApplication.shared.open(pageURL)
      }
    }
  }
}
