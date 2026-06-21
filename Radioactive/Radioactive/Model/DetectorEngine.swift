import CoreLocation
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
    /// Fires once when the detector locks onto a target — a "you found it" cue.
    @ObservationIgnored var onLock: (() -> Void)?

    /// Live device heading (degrees) when a compass is available — point the phone at a
    /// place and the detector aims itself. `nil` ⇒ no compass (Simulator) ⇒ demo sweep.
    @ObservationIgnored var deviceHeading: Double? = nil
    @ObservationIgnored private var wasLocked = false

    // MARK: Internals
    @ObservationIgnored private var spike = 0.0
    @ObservationIgnored private var link: CADisplayLink?
    @ObservationIgnored private var lastTime: CFTimeInterval = 0

    private(set) var places = Places.all
    /// Centre of the current scan, and the tight radius the main pages work within.
    private(set) var center = LocationService.defaultCoordinate
    private(set) var localRadius: Double = LocationService.localRadius
    /// The live, smoothed user position the radar/needle drift around between rediscoveries.
    private(set) var userCoordinate = LocationService.defaultCoordinate

    // MARK: Derived
    var target: Place { places[min(targetIndex, places.count - 1)] }
    var dangerScale: DangerScale { .forPalette(palette) }
    var locked: Bool { angDiff(heading, target.bearing) < 26 }

    /// The tight "radius around you" set — what the Detector and Radar work within,
    /// worst-first. The Nearby/explore page uses the full `places` (city) set instead.
    var localPlaces: [Place] {
        places.filter { Double($0.dist) <= localRadius }.sorted { $0.rating < $1.rating }
    }

    /// A RELATIVE contamination bar: the local median badness (floored), so the radar
    /// and map are never empty when real ratings cluster high — the hero surfaces the
    /// WORST nearby, not an absolute "< 3★" toxicity (which real UK data rarely hits).
    var contaminationFloor: Double {
        let bs = localPlaces.map(\.badness).sorted()
        guard !bs.isEmpty else { return 0.4 }
        return max(0.35, min(0.6, bs[bs.count / 2]))
    }

    /// The worst local places — what the radar and map plot, and what the range chip
    /// counts. Always non-empty when anything is nearby (shows the worst few as a floor).
    var contaminants: [Place] {
        let floor = contaminationFloor
        let hot = localPlaces.filter { $0.badness >= floor }
        return hot.isEmpty ? Array(localPlaces.prefix(6)) : Array(hot.prefix(10))
    }
    var mapCount: Int { contaminants.count }

    // Labels describe the SCAN READING, never the business — no "contaminated" claim
    // is made about any real place (a public-ship + defamation requirement).
    enum Status {
        case hot, elevated, faint
        var label: String {
            switch self {
            case .hot: "HOT SIGNAL"
            case .elevated: "ELEVATED"
            case .faint: "FAINT TRACE"
            }
        }
    }

    var status: Status {
        rads > 0.6 ? .hot : (rads > 0.33 ? .elevated : .faint)
    }

    var statusColor: Color {
        switch status {
        case .hot: Theme.dangerSoft
        case .elevated: Theme.amber
        case .faint: Theme.phosphorBright
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
        // Heading: the real device compass when available (point-to-scan), smoothed to
        // avoid jitter; else the demo sweep so the Simulator still animates.
        if let dh = deviceHeading {
            heading = smoothHeading(heading, toward: dh, factor: 0.25)
            aimByHeading()
        } else if autoScan && !dragging {
            heading = (heading + dt * 11).truncatingRemainder(dividingBy: 360)
        }

        let tgt = target
        let intensity = intensity(for: tgt, heading: heading)
        rads += (intensity - rads) * min(1, dt * 5)

        // Lock-acquired edge → one-shot "you found it" cue.
        let nowLocked = locked
        if nowLocked && !wasLocked { onLock?() }
        wasLocked = nowLocked

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

    /// Cycle the active target through the LOCAL places, worst-first.
    func cycleTarget() {
        let order = localPlaces.map(\.id)
        guard !order.isEmpty else { return }
        let nextID: Int
        if let pos = order.firstIndex(of: target.id) {
            nextID = order[(pos + 1) % order.count]
        } else {
            nextID = order[0]
        }
        if let i = places.firstIndex(where: { $0.id == nextID }) { targetIndex = i }
    }

    func aim(at place: Place) {
        // Resolve by identity, not by assuming a Place's id equals its array index.
        if let i = places.firstIndex(where: { $0.id == place.id }) { targetIndex = i }
    }

    /// Swap in a freshly discovered roster (MapKit/provider results) and re-centre the
    /// scan. Aims at the worst LOCAL place so the hero opens hot.
    func setPlaces(_ newPlaces: [Place], center: CLLocationCoordinate2D, localRadius: Double) {
        guard !newPlaces.isEmpty else { return }
        places = newPlaces
        self.center = center
        self.localRadius = localRadius
        let worst = localPlaces.first ?? places.min(by: { $0.rating < $1.rating })
        targetIndex = worst.flatMap { w in places.firstIndex(where: { $0.id == w.id }) } ?? 0
        loggedIDs.removeAll()
    }

    /// Clock 1: recompute each located place's distance + bearing from the live, smoothed
    /// coordinate so the radar and needle drift as you walk — entirely on-device.
    func updateUser(_ coord: CLLocationCoordinate2D) {
        userCoordinate = coord
        let here = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
        for i in places.indices {
            guard let lat = places[i].lat, let lon = places[i].lon else { continue }
            let there = CLLocation(latitude: lat, longitude: lon)
            places[i].dist = Int(here.distance(from: there).rounded())
            places[i].bearing = Place.bearing(from: coord, to: there.coordinate)
        }
    }

    /// Compass mode: snap the active target to the local place you're pointing at, with
    /// hysteresis so the needle doesn't flicker between two adjacent venues.
    private func aimByHeading() {
        let candidates = localPlaces
        guard let best = candidates.min(by: { angDiff(heading, $0.bearing) < angDiff(heading, $1.bearing) }) else { return }
        let current = target
        if best.id != current.id,
           angDiff(heading, best.bearing) + 12 < angDiff(heading, current.bearing),
           let i = places.firstIndex(where: { $0.id == best.id }) {
            targetIndex = i
        }
    }

    /// Shortest-angle lerp toward a target heading (handles the 359°→0° wrap).
    private func smoothHeading(_ current: Double, toward target: Double, factor: Double) -> Double {
        var delta = (target - current).truncatingRemainder(dividingBy: 360)
        if delta > 180 { delta -= 360 } else if delta < -180 { delta += 360 }
        return (current + delta * factor + 360).truncatingRemainder(dividingBy: 360)
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
        contaminants.map { p in
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
