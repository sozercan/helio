import Foundation
import Synchronization
import Testing
@testable import HelioKit

@MainActor
struct CredentialAuthorizationLeaseTests {
  enum Invalidation: CaseIterable, Sendable { case replace, delete, wipe }
  private enum CommitFailure: Error { case expected }

  private final class Gate: @unchecked Sendable {
    private let condition = NSCondition()
    private var leaseEntered = false
    private var mutationAttempted = false
    private var mutationCompleted = false
    private var releaseCommit = false
    private var commitCompleted = false
    private var invalidationRanBeforeCommit = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func holdCommit() {
      condition.lock()
      leaseEntered = true
      let ready = waiters
      waiters = []
      ready.forEach { $0.resume() }
      while !releaseCommit {
        condition.wait()
      }
      commitCompleted = true
      condition.unlock()
    }

    func waitForLease() async {
      await withCheckedContinuation { continuation in
        condition.lock()
        if leaseEntered {
          condition.unlock()
          continuation.resume()
        } else {
          waiters.append(continuation)
          condition.unlock()
        }
      }
    }

    func attemptMutation() {
      condition.lock()
      mutationAttempted = true
      condition.broadcast()
      condition.unlock()
    }

    func completeMutation() {
      condition.lock()
      mutationCompleted = true
      invalidationRanBeforeCommit = !commitCompleted
      condition.broadcast()
      condition.unlock()
    }

    func releaseAfterContention() {
      condition.lock()
      while !mutationAttempted {
        condition.wait()
      }
      let deadline = Date().addingTimeInterval(0.25)
      while !mutationCompleted, condition.wait(until: deadline) {}
      releaseCommit = true
      condition.broadcast()
      condition.unlock()
    }

    var invalidatedBeforeCommit: Bool {
      condition.lock()
      defer { condition.unlock() }
      return invalidationRanBeforeCommit
    }
  }

  private func invalidate(_ operation: Invalidation, manager: RedditCredentialsManager, account: RedditCredential) {
    switch operation {
    case .replace:
      var replacement = account
      replacement.refreshToken = "placeholder-replacement-grant"
      manager.saveCred(replacement)
    case .delete: manager.deleteCred(account)
    case .wipe: manager.wipeAllCredentials()
    }
  }

  @Test(arguments: Invalidation.allCases, [false, true])
  func aHeldCommitFinishesBeforeGrantInvalidation(operation: Invalidation, throwingCommit: Bool) async throws {
    let account = RedditCredential(apiAppID: "placeholder-client-id", refreshToken: "placeholder-original-grant")
    let authorization = try #require(account.authorizationID)
    let manager = RedditCredentialsManager(credentials: [account])
    let gate = Gate()
    let commit = Task.detached {
      await withCheckedContinuation { (continuation: CheckedContinuation<Bool?, Never>) in
        Thread {
          do {
            try continuation.resume(returning: manager.withCurrentAuthorization(authorization) {
              gate.holdCommit()
              if throwingCommit {
                throw CommitFailure.expected
              }
              return true
            })
          } catch CommitFailure.expected {
            continuation.resume(returning: false)
          } catch {
            continuation.resume(returning: nil)
          }
        }.start()
      }
    }
    await gate.waitForLease()
    Thread { gate.releaseAfterContention() }.start()
    gate.attemptMutation()
    invalidate(operation, manager: manager, account: account)
    gate.completeMutation()
    let saved = await commit.value
    #expect(saved == !throwingCommit)
    #expect(!gate.invalidatedBeforeCommit)
    #expect(!manager.containsAuthorization(authorization))
  }

  @Test(arguments: Invalidation.allCases)
  func anInvalidatedGrantNeverInvokesItsCommitClosure(operation: Invalidation) async throws {
    let account = RedditCredential(apiAppID: "placeholder-client-id", refreshToken: "placeholder-original-grant")
    let authorization = try #require(account.authorizationID)
    let manager = RedditCredentialsManager(credentials: [account])
    invalidate(operation, manager: manager, account: account)
    let called = Mutex(false)
    let result = await Task.detached {
      manager.withCurrentAuthorization(authorization) {
        called.withLock { $0 = true }
        return true
      }
    }.value
    #expect(result == nil)
    #expect(!called.withLock { $0 })
  }
}
