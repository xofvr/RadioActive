import Foundation
import AVFoundation

/// Bandpassed white-noise burst per click via a persistent `AVAudioEngine`.
///
/// One short decaying white-noise buffer is synthesised on first enable and
/// reused for every click. Each click randomises the bandpass centre frequency
/// so successive ticks differ, and schedules the buffer without interrupting
/// in-flight playback (overlapping clicks are allowed). `click` is a no-op
/// until `setEnabled(true)`.
///
/// Everything is defensive: on the Simulator audio may simply be silent, and
/// any session/engine failure leaves the object inert rather than crashing.
final class GeigerAudio {

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let eq = AVAudioUnitEQ(numberOfBands: 1)

    /// The shared decaying white-noise burst, built once on first enable.
    private var noiseBuffer: AVAudioBuffer?
    private var enabled = false

    // MARK: - Enable / disable

    func setEnabled(_ on: Bool) {
        guard on != enabled else { return }
        if on {
            start()
        } else {
            stop()
        }
    }

    private func start() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)

            buildGraphIfNeeded()

            if !engine.isRunning {
                try engine.start()
            }
            player.play()
            enabled = true
        } catch {
            // Silent failure (e.g. Simulator / unavailable hardware): stay inert.
            enabled = false
        }
    }

    private func stop() {
        enabled = false
        player.stop()
        engine.stop()
        // Deactivating can throw if nothing was active; ignore.
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }

    // MARK: - Click

    func click(_ volume: Double) {
        guard enabled, let buffer = noiseBuffer as? AVAudioPCMBuffer else { return }
        guard engine.isRunning else { return }

        // Randomise the bandpass centre so each tick has its own character.
        eq.bands.first?.frequency = Float(900 + Double.random(in: 0...1) * 2200)

        let clamped = min(max(volume, 0), 1)
        player.volume = Float(clamped * 0.5)

        // Overlap-friendly: do NOT interrupt currently-playing copies.
        player.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
    }

    // MARK: - Graph

    private func buildGraphIfNeeded() {
        guard noiseBuffer == nil else { return }

        let format = engine.mainMixerNode.outputFormat(forBus: 0)
        // A 0-rate placeholder format (queried before the route is live) leaves
        // noiseBuffer nil so a later enable rebuilds, rather than baking in junk.
        guard format.sampleRate > 0, format.channelCount > 0,
              let buffer = makeNoiseBuffer(format: format) else { return }
        noiseBuffer = buffer

        if let band = eq.bands.first {
            band.filterType = .bandPass
            band.bandwidth = 0.7
            band.bypass = false
            band.gain = 0
        }

        engine.attach(player)
        engine.attach(eq)
        engine.connect(player, to: eq, format: buffer.format)
        engine.connect(eq, to: engine.mainMixerNode, format: buffer.format)
    }

    /// A ~0.05s mono burst of white noise with a quadratic decay envelope:
    /// `sample[i] = random(-1...1) * (1 - i/len)^2`.
    private func makeNoiseBuffer(format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let length = AVAudioFrameCount(format.sampleRate * 0.05)
        guard length > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: length),
              let channels = buffer.floatChannelData else { return nil }

        buffer.frameLength = length
        let len = Float(length)
        let channelCount = Int(format.channelCount)

        for frame in 0..<Int(length) {
            let env = 1 - Float(frame) / len
            let sample = Float.random(in: -1...1) * env * env
            for ch in 0..<channelCount {
                channels[ch][frame] = sample
            }
        }
        return buffer
    }
}
