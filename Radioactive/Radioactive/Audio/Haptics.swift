import Foundation
import CoreHaptics

/// CoreHaptics transient per click, intensity scaled by click volume.
///
/// On hardware without haptics (the Simulator!) every method is a no-op. The
/// engine is created lazily on first enable, restarts itself after a reset or
/// unexpected stop, and swallows playback errors so a missed tick can never
/// crash the app. Gated by `setEnabled`.
final class Haptics {

    private static let supportsHaptics = CHHapticEngine.capabilitiesForHardware().supportsHaptics

    private var engine: CHHapticEngine?
    private var enabled = false

    // MARK: - Enable / disable

    func setEnabled(_ on: Bool) {
        guard Self.supportsHaptics else { return }
        guard on != enabled else { return }
        if on {
            start()
        } else {
            stop()
        }
    }

    private func start() {
        do {
            let engine = try makeEngine()
            try engine.start()
            self.engine = engine
            enabled = true
        } catch {
            engine = nil
            enabled = false
        }
    }

    private func stop() {
        enabled = false
        engine?.stop(completionHandler: nil)
    }

    private func makeEngine() throws -> CHHapticEngine {
        let engine = try CHHapticEngine()

        // CoreHaptics fires these on its own callback queue. Hop back to the
        // main thread (where all our state lives) and only act if this exact
        // engine is still the active, enabled one — avoids a data race and
        // restarting a stale engine after a quick off/on toggle.
        engine.resetHandler = { [weak self, weak engine] in
            DispatchQueue.main.async {
                guard let self, let engine, self.enabled, self.engine === engine else { return }
                try? engine.start()
            }
        }
        engine.stoppedHandler = { [weak self, weak engine] reason in
            DispatchQueue.main.async {
                guard let self, let engine, self.enabled, self.engine === engine else { return }
                switch reason {
                case .audioSessionInterrupt, .applicationSuspended,
                     .idleTimeout, .systemError:
                    try? engine.start()
                default:
                    break
                }
            }
        }
        return engine
    }

    // MARK: - Click

    func click(_ volume: Double) {
        guard Self.supportsHaptics, enabled, let engine else { return }

        let intensity = Float(min(max(volume, 0.2), 1))
        let event = CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.6)
            ],
            relativeTime: 0
        )

        do {
            let pattern = try CHHapticPattern(events: [event], parameters: [])
            let playerNode = try engine.makePlayer(with: pattern)
            try playerNode.start(atTime: CHHapticTimeImmediate)
        } catch {
            // A dropped tick is harmless; never propagate.
        }
    }
}
