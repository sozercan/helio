import Combine
import Foundation
import Nuke
import NukeUI
import SwiftUI

@MainActor
@available(iOS 14.0, tvOS 14.0, watchOS 7.0, macOS 10.16, *)
public struct LazyImageOpt<Content: View>: View {
  @State private var viewModel = FetchImageOpt()

  private var context: LazyImageContextOpt?
  private var makeContent: ((LazyImageStateOpt) -> Content)?
  private var transaction: Transaction
  private var pipeline: ImagePipeline = .shared
  private var onStart: ((ImageTask) -> Void)?
  private var onDisappearBehavior: DisappearBehavior? = .cancel
  private var onCompletion: ((Result<ImageResponse, Error>) -> Void)?

  public init(url: URL?) where Content == Image {
    self.init(request: url.map { ImageRequest(url: $0) })
  }

  public init(request: ImageRequest?) where Content == Image {
    self.context = request.map(LazyImageContextOpt.init)
    self.transaction = Transaction(animation: nil)
  }

  public init(url: URL?,
              transaction: Transaction = Transaction(animation: nil),
              @ViewBuilder content: @escaping (LazyImageStateOpt) -> Content)
  {
    self.init(request: url.map { ImageRequest(url: $0) }, transaction: transaction, content: content)
  }

  public init(request: ImageRequest?,
              transaction: Transaction = Transaction(animation: nil),
              @ViewBuilder content: @escaping (LazyImageStateOpt) -> Content)
  {
    self.context = request.map { LazyImageContextOpt(request: $0) }
    self.transaction = transaction
    self.makeContent = content
  }

  public func processors(_ processors: [any ImageProcessing]?) -> Self {
    map { $0.context?.request.processors = processors ?? [] }
  }

  public enum DisappearBehavior {
    case cancel
    case lowerPriority
  }

  public func onDisappear(_ behavior: DisappearBehavior?) -> Self {
    map { $0.onDisappearBehavior = behavior }
  }

  private func map(_ closure: (inout LazyImageOpt) -> Void) -> Self {
    var copy = self
    closure(&copy)
    return copy
  }

  public var body: some View {
    ZStack {
      if let makeContent {
        makeContent(viewModel)
      } else {
        makeDefaultContent(for: viewModel)
      }
    }
    .onAppear { onAppear() }
    .onDisappear { onDisappear() }
    .onChange(of: context) {
      viewModel.load($1?.request)
    }
  }

  @ViewBuilder
  private func makeDefaultContent(for state: LazyImageStateOpt) -> some View {
    if let image = state.image {
      image
    } else {
      Color(.secondarySystemBackground)
    }
  }

  private func onAppear() {
    viewModel.transaction = transaction
    viewModel.pipeline = pipeline
    viewModel.onStart = onStart
    viewModel.onCompletion = onCompletion
    viewModel.load(context?.request)
  }

  private func onDisappear() {
    guard let behavior = onDisappearBehavior else { return }
    switch behavior {
    case .cancel:
      viewModel.cancel()
    case .lowerPriority:
      viewModel.priority = .veryLow
    }
  }
}

private struct LazyImageContextOpt: Equatable {
  var request: ImageRequest

  static func == (lhs: LazyImageContextOpt, rhs: LazyImageContextOpt) -> Bool {
    let lhs = lhs.request
    let rhs = rhs.request
    return lhs.preferredImageIdCopy == rhs.preferredImageIdCopy &&
      lhs.priority == rhs.priority &&
      lhs.description == rhs.description &&
      lhs.priority == rhs.priority &&
      lhs.options == rhs.options
  }
}

extension ImageRequest {
  var preferredImageIdCopy: String {
    if !userInfo.isEmpty, let imageId = userInfo[.imageIdKey] as? String {
      return imageId
    }
    return imageId ?? ""
  }
}
