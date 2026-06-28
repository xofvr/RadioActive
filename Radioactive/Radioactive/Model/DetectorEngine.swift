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

    // MARK: Shared constants
    static let aimConeDegrees: Double = 26      // forward aim cone (== old `locked` literal)
    static let aimHoldSeconds: TimeInterval = 6 // manual-selection hold cap

    // MARK: Settings
    var palette: Palette = .phosphor
    var sensitivity: Double = 1.0
    var autoScan = true
    var audioOn = false { didSet { onAudioToggle?(audioOn) } }

    // Phase 2 — relative reading gate (default ON). Views may flip this from AppSettings.
    var relativeReadingEnabled = true

    // Phase 4 — dosimeter
    private(set) var sessionRads: Double = 0     // resets per launch (fresh engine)
    var discoveredKeys = Set<String>(UserDefaults.standard.stringArray(forKey: "discoveredKeys") ?? [])
    var placesDiscovered: Int { discoveredKeys.count }

    // Phase 4 — proximity heat
    private(set) var radsTrend: RadsTrend = .steady
    @ObservationIgnored private var radsFast = 0.35
    @ObservationIgnored private var radsSlow = 0.35

    // Phase 4 — field log snapshots (durable)
    private(set) var loggedEntries: [LoggedEntry] = DetectorEngine.loadLoggedEntries()

    // Phase 3 — manual-aim hold (gates aimByHeading auto-snap)
    @ObservationIgnored private var aimHoldUntil: Date? = nil
    /// WHY the hold was armed. `true` (cycleInCone) → cone-aware: the hold also clears
    /// the instant the user points away from the held target's ±aimConeDegrees cone.
    /// `false` (cycleTarget) → time-cap only: the picked target may sit OUTSIDE the cone,
    /// so the heading-leaves-cone early-clear must NOT fire or the manual NEXT would be
    /// overridden within one frame on a live compass.
    @ObservationIgnored private var aimHoldStrict = false

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
    /// Bookmarked places, keyed by stable `logKey` (persisted) so a bookmark survives
    /// rescans and never silently points at a different business.
    var loggedKeys = Set<String>(UserDefaults.standard.stringArray(forKey: "loggedKeys") ?? [])
    /// Places the user reported / asked to remove — filtered out of future discovery.
    var suppressedKeys = Set<String>(UserDefaults.standard.stringArray(forKey: "suppressedKeys") ?? [])
    @ObservationIgnored private var isLiveRoster = false

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
    var locked: Bool { angDiff(heading, target.bearing) < Self.aimConeDegrees }

    /// The tight "radius around you" set — what the Detector and Radar work within,
    /// worst-first. The Nearby/explore page uses the full `places` (city) set instead.
    var localPlaces: [Place] {
        places.filter { Double($0.dist) <= localRadius }.sorted { $0.rating < $1.rating }
    }

    /// A RELATIVE contamination bar: the local median badness (floored), so the radar
    /// and map are never empty when real ratings cluster high — the hero surfaces the
    /// WORST nearby, not an absolute "< 3★" toxicity (which real UK data rarely hits).
    var contaminationFloor: Double {
        DetectorMath.contaminationFloor(badnesses: localPlaces.map(\.badness))
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

    /// Per-place RELATIVE reading badness, normalised against the local field so the
    /// hero surfaces the WORST-nearby relatively. Gated by `relativeReadingEnabled`.
    /// OFF → returns absolute Place.badness (the legacy reading).
    func readingBadness(for p: Place) -> Double {
        guard relativeReadingEnabled else { return p.badness }
        let locals = localPlaces.map(\.badness)
        let rel = DetectorMath.relativeBadness(p.badness, localBadnesses: locals)
        return DetectorMath.readingBadness(absolute: p.badness, relative: rel)
    }

    /// How hot a place reads given the current heading. Badness is the ceiling;
    /// aim/proximity only swing the needle within that place's band. The badness
    /// fed in is the RELATIVE reading (gated by `relativeReadingEnabled`) so the
    /// needle, colour, CPM, audio and status all surface the worst-nearby together.
    func intensity(for p: Place, heading: Double) -> Double {
        DetectorMath.intensity(
            badness: readingBadness(for: p),
            distance: Double(p.dist),
            headingError: angDiff(heading, p.bearing),
            sensitivity: sensitivity)
    }

    func angDiff(_ a: Double, _ b: Double) -> Double { DetectorMath.angDiff(a, b) }

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

        // Dosimeter + proximity trend ride the display link (no new timers).
        sessionRads += rads * dt                                          // dosimeter
        radsFast += (rads - radsFast) * min(1, dt * 3.0)                  // fast EWMA
        radsSlow += (rads - radsSlow) * min(1, dt * 0.6)                  // slow EWMA
        let d = radsFast - radsSlow
        radsTrend = d > 0.02 ? .warmer : (d < -0.02 ? .cooler : .steady)

        // Lock-acquired edge → one-shot "you found it" cue + discovery accrual.
        let nowLocked = locked
        if nowLocked && !wasLocked {
            onLock?()
            if discoveredKeys.insert(target.logKey).inserted {
                UserDefaults.standard.set(Array(discoveredKeys), forKey: "discoveredKeys")
            }
        }
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
        aimHoldStrict = false                                          // time-cap only: target may be out-of-cone
        aimHoldUntil = Date().addingTimeInterval(Self.aimHoldSeconds)   // hold (survives live compass)
    }

    /// Local places whose bearing is inside the forward aim cone, worst-first
    /// (localPlaces order preserved → stable cycling).
    func targetsInCone(_ heading: Double) -> [Place] {
        localPlaces.filter { angDiff(heading, $0.bearing) <= Self.aimConeDegrees }
    }

    /// Advance the active target to the next place inside the cone, and arm the hold.
    func cycleInCone() {
        let cone = targetsInCone(heading)
        guard !cone.isEmpty else { return }
        let nextID: Int
        if let pos = cone.firstIndex(where: { $0.id == target.id }) {
            nextID = cone[(pos + 1) % cone.count].id
        } else { nextID = cone[0].id }
        if let i = places.firstIndex(where: { $0.id == nextID }) { targetIndex = i }
        aimHoldStrict = true                                           // cone-aware: target is always in-cone
        aimHoldUntil = Date().addingTimeInterval(Self.aimHoldSeconds)   // hold
    }

    /// Compass blips — the contaminants, with relative reading colour + target flag.
    func compassBlips() -> [CompassBlip] {
        contaminants.map { p in
            CompassBlip(place: p,
                        bearing: p.bearing,
                        distance: Double(p.dist),
                        readingBadness: readingBadness(for: p),
                        isTarget: p.id == target.id)
        }
    }

    func aim(at place: Place) {
        // Resolve by identity, not by assuming a Place's id equals its array index.
        if let i = places.firstIndex(where: { $0.id == place.id }) { targetIndex = i }
    }

    /// Swap in a freshly discovered roster (MapKit/provider results) and re-centre the
    /// scan. Aims at the worst LOCAL place so the hero opens hot.
    func setPlaces(_ newPlaces: [Place], center: CLLocationCoordinate2D, localRadius: Double, force: Bool) {
        guard !newPlaces.isEmpty else { return }
        let previousKey = target.logKey          // `places` is always non-empty (demo init)
        let firstLoad = !isLiveRoster
        places = newPlaces
        isLiveRoster = true
        self.center = center
        self.localRadius = localRadius

        // Carry the aimed target forward by identity across an auto-rediscovery, so a
        // walk never snaps the cone you carefully aimed. Re-home to worst-local only on
        // the first real load or an explicit RESCAN (force). Bookmarks are NEVER cleared.
        if !force, !firstLoad, let i = places.firstIndex(where: { $0.logKey == previousKey }) {
            targetIndex = i
        } else {
            let worst = localPlaces.first ?? places.min(by: { $0.rating < $1.rating })
            targetIndex = worst.flatMap { w in places.firstIndex(where: { $0.id == w.id }) } ?? 0
        }
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
        // Honour a manual NEXT (cycleInCone / cycleTarget) until it expires OR the user
        // physically points away from the held target's cone — then resume auto-snap.
        if let until = aimHoldUntil {
            let expired = Date() >= until
            // Only a STRICT (cycleInCone) hold self-clears when the heading leaves the
            // held target's cone — its target is always in-cone, so leaving it is a
            // genuine intent to re-aim. A non-strict (cycleTarget) hold may have picked
            // an out-of-cone target, so it must survive on the time cap alone.
            let leftCone = aimHoldStrict && angDiff(heading, target.bearing) > Self.aimConeDegrees
            if !expired && !leftCone { return }           // hold active: do not override
            aimHoldUntil = nil                            // expired, or a strict hold left its cone
        }

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
        DetectorMath.smoothHeading(current, toward: target, factor: factor)
    }

    func toggleAudio() { audioOn.toggle() }

    func toggleLog(_ place: Place) {
        let key = place.logKey
        if loggedKeys.contains(key) {
            loggedKeys.remove(key)
            loggedEntries.removeAll { $0.logKey == key }
        } else {
            loggedKeys.insert(key)
            loggedEntries.append(LoggedEntry(place))
        }
        UserDefaults.standard.set(Array(loggedKeys), forKey: "loggedKeys")
        persistLoggedEntries()
    }
    func isLogged(_ place: Place) -> Bool { loggedKeys.contains(place.logKey) }

    private func persistLoggedEntries() {
        if let data = try? JSONEncoder().encode(loggedEntries) {
            UserDefaults.standard.set(data, forKey: "loggedEntries")
        }
    }
    private static func loadLoggedEntries() -> [LoggedEntry] {
        guard let data = UserDefaults.standard.data(forKey: "loggedEntries"),
              let entries = try? JSONDecoder().decode([LoggedEntry].self, from: data)
        else { return [] }
        return entries
    }

    func suppress(_ place: Place) {
        suppressedKeys.insert(place.logKey)
        UserDefaults.standard.set(Array(suppressedKeys), forKey: "suppressedKeys")
    }
    func isSuppressed(_ place: Place) -> Bool { suppressedKeys.contains(place.logKey) }

    // MARK: Derived collections for the screens

    func nearby(_ filter: NearbyFilter) -> [Place] {
        places.filter(filter.matches).sorted { $0.rating < $1.rating }
    }

    func radarPins() -> [RadarPin] {
        let raw = contaminants.map { p -> (place: Place, pt: CGPoint) in
            let rFrac = DetectorMath.scopeRadiusFraction(distanceM: Double(p.dist))
            let rad = p.bearing * .pi / 180
            return (p, CGPoint(x: 0.5 + sin(rad) * rFrac, y: 0.5 - cos(rad) * rFrac))
        }
        let clusters = DetectorMath.cluster(raw, position: { $0.pt }, minSeparation: 0.08)
        return clusters.map { c in
            RadarPin(place: c.representative.place,
                     x: c.representative.pt.x,
                     y: c.representative.pt.y,
                     count: c.count,
                     readingBadness: readingBadness(for: c.representative.place))
        }
    }
}

/// Proximity heat from fast-vs-slow rads EWMA.
enum RadsTrend { case warmer, steady, cooler }

/// A contaminant for the Pip-Boy compass. CompassView places it at
/// (bearing − heading), radius by distance, colour by readingBadness.
struct CompassBlip: Identifiable {
    var id: Int { place.id }
    let place: Place
    let bearing: Double         // absolute compass bearing, deg, 0 = N
    let distance: Double        // metres
    let readingBadness: Double  // RELATIVE reading → blip colour
    let isTarget: Bool          // the currently-aimed place
}

/// A contaminant placed on the radar scope by real bearing + distance.
/// `x`/`y` are 0...1 fractions. `count` ≥1 (cluster size). `readingBadness`
/// is the RELATIVE reading used for pin COLOUR (number stays place.red).
struct RadarPin: Identifiable {
    var id: Int { place.id }
    let place: Place
    let x: Double
    let y: Double
    let count: Int             // NEW
    let readingBadness: Double // NEW
}

/// Bridges `CADisplayLink`'s ObjC selector target to a Swift closure.
private final class DisplayProxy: NSObject {
    private let callback: (CFTimeInterval) -> Void
    init(_ callback: @escaping (CFTimeInterval) -> Void) { self.callback = callback }
    @objc func tick(_ link: CADisplayLink) { callback(link.timestamp) }
}
