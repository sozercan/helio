import CoreHaptics
import SwiftUI

class Hap {
  static var shared = Hap()

  private var engine: CHHapticEngine?
  private var engineNeedsStart = true
  private var continuousPlayer: CHHapticAdvancedPatternPlayer?
  private lazy var supportsHaptics: Bool = AppDelegate.instance?.supportsHaptics ?? false

  private let initialIntensity: Float = 1
  private let initialSharpness: Float = 0

  private init() {
    createAndStartHapticEngine()
    createContinuousHapticPlayer()

    NotificationCenter.default.addObserver(self, selector: #selector(appDidBecomeActive), name: UIApplication.didBecomeActiveNotification, object: nil)
  }

  deinit {
    self.stopEngine()
  }

  func startContinuous() {
    guard supportsHaptics, let continuousPlayer = self.continuousPlayer else { return }

    do {
      try continuousPlayer.start(atTime: CHHapticTimeImmediate)
    } catch {
      print("Error starting the continuous haptic player: \(error)")
    }
  }

  func stopContinuous() {
    guard supportsHaptics, let continuousPlayer = self.continuousPlayer else { return }

    do {
      try continuousPlayer.stop(atTime: CHHapticTimeImmediate)
    } catch {
      print("Error stopping the continuous haptic player: \(error)")
    }
  }

  func updateContinuous(intensity: Float, sharpness: Float) {
    guard supportsHaptics, let continuousPlayer = self.continuousPlayer else { return }

    let intensityParameter = CHHapticDynamicParameter(parameterID: .hapticIntensityControl, value: intensity, relativeTime: 0)
    let sharpnessParameter = CHHapticDynamicParameter(parameterID: .hapticSharpnessControl, value: sharpness, relativeTime: 0)

    do {
      try continuousPlayer.sendParameters([intensityParameter, sharpnessParameter], atTime: 0)
    } catch {
      print("Dynamic Parameter Error: \(error)")
    }
  }

  struct TransientBeat: Equatable, Sendable {
    let relativeTime: TimeInterval
    let intensity: Float
    let sharpness: Float
  }

  func play(intensity: Float, sharpness: Float) {
    playSequence([TransientBeat(relativeTime: 0, intensity: intensity, sharpness: sharpness)])
  }

  func playSequence(_ beats: [TransientBeat]) {
    guard supportsHaptics, let engine = self.engine, !beats.isEmpty else { return }

    let events = beats.map { beat in
      CHHapticEvent(
        eventType: .hapticTransient,
        parameters: [
          CHHapticEventParameter(parameterID: .hapticIntensity, value: beat.intensity),
          CHHapticEventParameter(parameterID: .hapticSharpness, value: beat.sharpness),
        ],
        relativeTime: beat.relativeTime,
      )
    }

    do {
      let pattern = try CHHapticPattern(events: events, parameters: [])
      let player = try engine.makePlayer(with: pattern)
      try player.start(atTime: CHHapticTimeImmediate)
    } catch {
      print("Error creating a haptic transient pattern: \(error)")
    }
  }

  func stopEngine() {
    guard self.supportsHaptics, let engine = self.engine else { return }

    engine.stop(completionHandler: { error in
      if let error {
        print("Haptic Engine Shutdown Error: \(error)")
        return
      }
      self.engineNeedsStart = true
    })
  }

  func startEngine() {
    guard self.supportsHaptics, let engine = self.engine else { return }

    engine.playsHapticsOnly = true
    engine.start(completionHandler: { error in
      if let error {
        print("Haptic Engine Startup Error: \(error)")
        return
      }
      self.engineNeedsStart = false
    })
  }

  func createAndStartHapticEngine() {
    guard engineNeedsStart else { return }
    do {
      engine = try CHHapticEngine()
    } catch {
      print("Engine Creation Error: \(error)")
    }
    guard let engine else { return }

    engine.playsHapticsOnly = true

    engine.stoppedHandler = { reason in
      print("Stop Handler: The engine stopped for reason: \(reason.rawValue)")
      switch reason {
      case .audioSessionInterrupt:
        print("Audio session interrupt")
      case .applicationSuspended:
        print("Application suspended")
      case .idleTimeout:
        print("Idle timeout")
      case .systemError:
        print("System error")
      case .notifyWhenFinished:
        print("Playback finished")
      case .gameControllerDisconnect:
        print("Controller disconnected.")
      case .engineDestroyed:
        print("Engine destroyed.")
      @unknown default:
        print("Unknown error")
      }
    }

    engine.resetHandler = {
      print("Reset Handler: Restarting the engine.")
      do {
        try engine.start()
        engine.playsHapticsOnly = true
        self.engineNeedsStart = false
        self.createContinuousHapticPlayer()
      } catch {
        print("Failed to start the engine")
      }
    }

    startEngine()
  }

  @objc func appDidBecomeActive() {
    startEngine()
  }

  func createContinuousHapticPlayer() {
    guard let engine else { return }
    let intensity = CHHapticEventParameter(parameterID: .hapticIntensity, value: initialIntensity)
    let sharpness = CHHapticEventParameter(parameterID: .hapticSharpness, value: initialSharpness)

    let continuousEvent = CHHapticEvent(eventType: .hapticContinuous, parameters: [intensity, sharpness], relativeTime: 0, duration: 100)

    do {
      let pattern = try CHHapticPattern(events: [continuousEvent], parameters: [])
      continuousPlayer = try engine.makeAdvancedPlayer(with: pattern)
    } catch {
      print("Pattern Player Creation Error: \(error)")
    }
  }
}
