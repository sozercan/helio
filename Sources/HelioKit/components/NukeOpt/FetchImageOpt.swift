import Combine
import Nuke
import NukeUI
import SwiftUI

@MainActor @Observable
public final class FetchImageOpt: Identifiable, LazyImageStateOpt {
  public private(set) var result: Result<ImageResponse, Error>?

  public private(set) var imageContainer: ImageContainer?

  public private(set) var isLoading = false

  public var transaction = Transaction(animation: nil)

  private var _progress: Progress?

  @Observable
  public final class Progress {
    public internal(set) var completed: Int64 = 0

    public internal(set) var total: Int64 = 0
  }

  public var priority: ImageRequest.Priority? {
    didSet { priority.map { imageTask?.priority = $0 } }
  }

  public var pipeline: ImagePipeline = .shared

  public var processors: [any ImageProcessing] = []

  public var onStart: ((ImageTask) -> Void)?

  public var onCompletion: ((Result<ImageResponse, Error>) -> Void)?

  private var imageTask: ImageTask?
  private var lastResponse: ImageResponse?
  private var cancellable: AnyCancellable?

  public init() {}

  public func load(_ request: ImageRequest?) {
    assert(Thread.isMainThread, "Must be called from the main thread")

    reset()

    guard var request else {
      handle(result: .failure(ImagePipeline.Error.imageRequestMissing))
      return
    }

    if !processors.isEmpty, request.processors.isEmpty {
      request.processors = processors
    }
    if let priority {
      request.priority = priority
    }

    if let image = pipeline.cache[request] {
      if image.isPreview {
        imageContainer = image
      } else {
        let response = ImageResponse(container: image, request: request, cacheType: .memory)
        handle(result: .success(response))
        return
      }
    }

    isLoading = true

    let task = pipeline.loadImage(
      with: request,
      progress: { [weak self] response, completed, total in
        guard let self else { return }
        if let response {
          withTransaction(self.transaction) {
            self.handle(preview: response)
          }
        } else {
          self._progress?.completed = completed
          self._progress?.total = total
        }
      },
      completion: { [weak self] result in
        guard let self else { return }
        withTransaction(self.transaction) {
          self.handle(result: result.mapError { $0 })
        }
      },
    )
    imageTask = task
    onStart?(task)
  }

  private func handle(preview: ImageResponse) {
    self.imageContainer = preview.container
  }

  private func handle(result: Result<ImageResponse, Error>) {
    isLoading = false
    imageTask = nil

    if case let .success(response) = result {
      self.imageContainer = response.container
    }
    self.result = result
    self.onCompletion?(result)
  }

  public func cancel() {
    imageTask?.cancel()
    imageTask = nil

    cancellable = nil
  }

  public func reset() {
    cancel()

    if isLoading {
      isLoading = false
    }
    if imageContainer != nil {
      imageContainer = nil
    }
    if result != nil {
      result = nil
    }
    if _progress != nil {
      _progress = nil
    }
    lastResponse = nil
  }
}
