import Observation
import QuartzCore
import SwiftUI

/// The live simulation core. A faithful port of the source design's physics:
/// a place's "badness" sets a ceiling, aim + proximity swing the needle within
/// that band, and a Poisson process fires Geiger clicks whose rate tracks the
/// reading. Runs on a `CADisplayLink` and publishes via Observation so the
/// Canvas instruments redraw every frame.
@MainActor
@Observable
final class DetectorEngine {

    // MARK: Settings
    var palette: Palette = .phosphor
    var sensitivity: Double = 1.0
    var autoScan = true
    var audioOn = false { didSet { onAudioToggle?(audioOn) } }

    // MARK: Live, per-frame state
    private(set) var rads = 0.35
    private(set) var cpmDisplay = 0.0
    private(set) var cpmPeak = 0.0
    private(set) var heading = 24.0
    private(set) var scope = [Double](repeating: 0, count: 150)
    /// Monotonic frame counter — instruments read it to force a per-frame redraw.
    private(set) var frame = 0

    // MARK: Selection / interaction
    var targetIndex = 0
    var dragging = false
    var loggedIDs = Set<Int>()

    // MARK: Event sinks (wired by the root to audio + haptics)
    @ObservationIgnored var onClick: ((Double) -> Void)?
    @ObservationIgnored var onAudioToggle: ((Bool) -> Void)?

    // MARK: Internals
    @ObservationIgnored private var spike = 0.0
    @ObservationIgnored private var link: CADisplayLink?
    @ObservationIgnored private var lastTime: CFTimeInterval = 0

    let places = Places.all

    // MARK: Derived
    var target: Place { places[targetIndex] }
    var dangerScale: DangerScale { .forPalette(palette) }
    var locked: Bool { angDiff(heading, target.bearing) < 26 }
    var mapCount: Int { places.filter { $0.rating < 3 }.count }

    enum Status {
        case contaminated, elevated, trace
        var label: String {
            switch self {
            case .contaminated: "CONTAMINATED"
            case .elevated: "ELEVATED"
            case .trace: "TRACE LEVELS"
            }
        }
    }

    var status: Status {
        rads > 0.6 ? .contaminated : (rads > 0.33 ? .elevated : .trace)
    }

    var statusColor: Color {
        switch status {
        case .contaminated: Theme.dangerSoft
        case .elevated: Theme.amber
        case .trace: Theme.phosphorBright
        }
    }

    /// Colour for a given intensity on the active palette.
    func color(_ t: Double, _ alpha: Double = 1) -> Color { dangerScale.color(t, alpha) }

    // MARK: Lifecycle

    func start() {
        guard link == nil else { return }
        let proxy = DisplayProxy { [weak self] now in self?.step(now) }
        let l = CADisplayLink(target: proxy, selector: #selector(DisplayProxy.tick(_:)))
        l.add(to: .main, forMode: .common)
        link = l
        lastTime = CACurrentMediaTime()
    }

    func stop() {
        link?.invalidate()
        link = nil
    }

    private func step(_ now: CFTimeInterval) {
        let dt = min(0.05, now - lastTime)
        lastTime = now
        guard dt > 0 else { return }
        tick(dt: dt)
    }

    // MARK: Physics

    /// How hot a place reads given the current heading. Badness is the ceiling;
    /// aim/proximity only swing the needle within that place's band.
    func intensity(for p: Place, heading: Double) -> Double {
        let badness = (5 - p.rating) / 5
        let prox = max(0.15, 1 - Double(p.dist) / 800)
        let face = (cos(angDiff(heading, p.bearing) * .pi / 180) + 1) / 2
        let detection = prox * (0.4 + 0.6 * face)
        let intensity = badness * (0.62 + 0.38 * detection) * sensitivity
        return min(1, max(0, intensity))
    }

    func angDiff(_ a: Double, _ b: Double) -> Double {
        var d = abs((a - b).truncatingRemainder(dividingBy: 360))
        if d > 180 { d = 360 - d }
        return d
    }

    private func tick(dt: Double) {
        let tgt = target
        if autoScan && !dragging {
            heading = (heading + dt * 11).truncatingRemainder(dividingBy: 360)
        }
        let intensity = intensity(for: tgt, heading: heading)
        rads += (intensity - rads) * min(1, dt * 5)

        // Geiger clicks — Poisson-ish, rate climbs with the reading.
        let rate = 0.6 + rads * 24
        var p = rate * dt
        while p > 0 {
            if Double.random(in: 0..<1) < min(p, 1) {
                spike = min(1, spike + 0.55 + Double.random(in: 0..<1) * 0.4)
                onClick?(0.25 + rads * 0.75)
            }
            p -= 1
        }

        // CPM readout — curved so mid-tier places sit well below the ceiling.
        let cpmTarget = pow(rads, 1.35) * 999
        cpmDisplay += (cpmTarget - cpmDisplay) * 0.12
        cpmPeak = max(cpmPeak, cpmDisplay)

        // Oscilloscope trace.
        spike *= 0.62
        let sample = (Double.random(in: 0..<1) - 0.5) * (0.12 + rads * 0.4)
            + (Double.random(in: 0..<1) < 0.3 ? spike : spike * 0.5)
        scope.removeFirst()
        scope.append(min(1, max(-1, sample)))

        frame &+= 1
    }

    // MARK: Commands

    /// Cycle the active target in worst-first order.
    func cycleTarget() {
        let order = places.indices.sorted { places[$0].rating < places[$1].rating }
        if let pos = order.firstIndex(of: targetIndex) {
            targetIndex = order[(pos + 1) % order.count]
        }
    }

    func aim(at place: Place) {
        // Resolve by identity, not by assuming a Place's id equals its array index.
        if let i = places.firstIndex(where: { $0.id == place.id }) { targetIndex = i }
    }
    func toggleAudio() { audioOn.toggle() }

    func toggleLog(_ place: Place) {
        if loggedIDs.contains(place.id) { loggedIDs.remove(place.id) }
        else { loggedIDs.insert(place.id) }
    }
    func isLogged(_ place: Place) -> Bool { loggedIDs.contains(place.id) }

    // MARK: Derived collections for the screens

    func nearby(_ filter: NearbyFilter) -> [Place] {
        places.filter(filter.matches).sorted { $0.rating < $1.rating }
    }

    func radarPins() -> [RadarPin] {
        // Only sub-3★ places are "contaminants" — keeps the pin count in step
        // with `mapCount`, which the range chip displays.
        places.filter { $0.rating < 3 }.map { p in
            let rFrac = 0.10 + min(1, Double(p.dist) / 560) * 0.38
            let rad = p.bearing * .pi / 180
            return RadarPin(place: p,
                            x: 0.5 + sin(rad) * rFrac,
                            y: 0.5 - cos(rad) * rFrac)
        }
    }
}

/// A contaminant placed on the radar scope by real bearing + distance.
/// `x`/`y` are 0...1 fractions of the scope's bounding box.
struct RadarPin: Identifiable {
    var id: Int { place.id }
    let place: Place
    let x: Double
    let y: Double
}

/// Bridges `CADisplayLink`'s ObjC selector target to a Swift closure.
private final class DisplayProxy: NSObject {
    private let callback: (CFTimeInterval) -> Void
    init(_ callback: @escaping (CFTimeInterval) -> Void) { self.callback = callback }
    @objc func tick(_ link: CADisplayLink) { callback(link.timestamp) }
}
