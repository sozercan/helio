import CoreData
import Foundation
import SwiftUI

private let samplePost = Post(data: postSampleData)
private let sampleSub = Subreddit(id: postSampleData.subreddit)
private let samplePostHelioData = samplePost.helioData ?? PostHelioData()

private struct ContextPostKey: EnvironmentKey {
  static let defaultValue: Post = samplePost
}

private struct ContextSubredditKey: EnvironmentKey {
  static let defaultValue: Subreddit = sampleSub
}

private struct ContextPostHelioDataKey: EnvironmentKey {
  static let defaultValue: PostHelioData = samplePostHelioData
}

private struct SheetHeightKey: EnvironmentKey {
  static let defaultValue: Double = 0
}

private struct EnableSwipeAnywhereKey: EnvironmentKey {
  static let defaultValue = false
}

private struct IsInSidebarKey: EnvironmentKey {
  static let defaultValue = false
}

private struct BrighterBGKey: EnvironmentKey {
  static let defaultValue = false
}

private struct PrimaryBGContextKey: EnvironmentKey {
  static let defaultValue: NSManagedObjectContext = PersistenceController.shared.primaryBGContext
}

private struct CurrentThemeKey: EnvironmentKey {
  static let defaultValue = defaultTheme
}

private struct NavColumnKey: EnvironmentKey {
  static let defaultValue: Router.Column? = nil
}

private struct ContentWidthKey: EnvironmentKey {
  static let defaultValue: Double = .screenW
}

extension EnvironmentValues {
  var contextPost: Post {
    get { self[ContextPostKey.self] }
    set { self[ContextPostKey.self] = newValue }
  }

  var contextSubreddit: Subreddit {
    get { self[ContextSubredditKey.self] }
    set { self[ContextSubredditKey.self] = newValue }
  }

  var contextPostHelioData: PostHelioData {
    get { self[ContextPostHelioDataKey.self] }
    set { self[ContextPostHelioDataKey.self] = newValue }
  }

  var sheetHeight: Double {
    get { self[SheetHeightKey.self] }
    set { self[SheetHeightKey.self] = newValue }
  }

  var enableSwipeAnywhere: Bool {
    get { self[EnableSwipeAnywhereKey.self] }
    set { self[EnableSwipeAnywhereKey.self] = newValue }
  }

  var brighterBG: Bool {
    get { self[BrighterBGKey.self] }
    set { self[BrighterBGKey.self] = newValue }
  }

  var isInSidebar: Bool {
    get { self[IsInSidebarKey.self] }
    set { self[IsInSidebarKey.self] = newValue }
  }

  var primaryBGContext: NSManagedObjectContext {
    get { self[PrimaryBGContextKey.self] }
    set { self[PrimaryBGContextKey.self] = newValue }
  }

  var navColumn: Router.Column? {
    get { self[NavColumnKey.self] }
    set { self[NavColumnKey.self] = newValue }
  }

  var contentWidth: Double {
    get { self[ContentWidthKey.self] }
    set { self[ContentWidthKey.self] = newValue }
  }

  var useTheme: HelioTheme {
    get { self[CurrentThemeKey.self] }
    set { self[CurrentThemeKey.self] = newValue }
  }
}
