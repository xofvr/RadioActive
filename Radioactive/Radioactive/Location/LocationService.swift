import CoreLocation
import Observation

/// Live position for the moving-user experience. Publishes a *smoothed* coordinate the
/// physics loop (Clock 1) reads continuously — radar/needle/geiger react as you walk,
/// with zero network — and owns the throttle gate for the expensive rediscovery
/// (Clock 2). Everything degrades gracefully: deny location and the app simply scans
/// around the default centre.
@MainActor
@Observable
final class LocationService {

    /// Fallback centre when location is unavailable or denied: Park Street, Bristol —
    /// a steep café/pub/restaurant strip, perfect for a proximity scan.
    static let defaultCoordinate = CLLocationCoordinate2D(latitude: 51.4548, longitude: -2.6045)

    /// The tight "radius around you" the main pages (Detector + Radar) scan — keeps
    /// the hunt local and uncluttered.
    static let localRadius: CLLocationDistance = 450

    /// The wider net the explore page casts to "look into the city in general".
    static let cityRadius: CLLocationDistance = 2500

    private(set) var coordinate = LocationService.defaultCoordinate
    private(set) var isAuthorized = false
    private(set) var hasFix = false
    private(set) var isStationary = false
    /// Bumps on every accepted smoothed update — a cheap trigger for `onChange`.
    private(set) var updates = 0

    @ObservationIgnored private let manager = CLLocationManager()
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var smoothed: CLLocationCoordinate2D?
    @ObservationIgnored private var lastRaw: CLLocation?

    // Clock-2 refetch gate.
    @ObservationIgnored private var lastFetchAnchor: CLLocationCoordinate2D?
    @ObservationIgnored private var lastFetchAt: Date?

    /// The smallest gap between any two rediscoveries (incl. manual RESCAN) — the hard
    /// cost floor when a real paid provider is wired in.
    static let minFetchInterval: TimeInterval = 45
    /// How far you must displace before an *automatic* rediscovery — a third of the
    /// local ring, the PoGo "crossed a cell boundary" analog.
    static let refetchDistance: CLLocationDistance = 150

    /// Request permission and begin streaming live updates.
    func start() {
        manager.requestWhenInUseAuthorization()
        guard task == nil else { return }
        task = Task { [weak self] in
            do {
                for try await update in CLLocationUpdate.liveUpdates() {
                    guard let self else { return }
                    self.ingest(update)
                }
            } catch {
                // Stream ended / unauthorised — stay on the last good coordinate.
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    private func ingest(_ update: CLLocationUpdate) {
        isStationary = update.stationary
        isAuthorized = true
        guard let loc = update.location else { return }

        // Accuracy gate — a coarse fix may smooth the physics but must never feel like
        // movement (and, with a paid provider, must never arm a billed refetch).
        guard loc.horizontalAccuracy >= 0, loc.horizontalAccuracy <= 65 else { return }

        // Teleport reject — discard implausible jumps (GPS noise, not a walk).
        if let last = lastRaw {
            let dt = loc.timestamp.timeIntervalSince(last.timestamp)
            if dt > 0, loc.distance(from: last) / dt > 30 { return }
        }
        lastRaw = loc

        // EWMA smoothing (alpha 0.3) so the needle drifts rather than twitches.
        let a = 0.3
        if let s = smoothed {
            smoothed = CLLocationCoordinate2D(
                latitude: s.latitude + (loc.coordinate.latitude - s.latitude) * a,
                longitude: s.longitude + (loc.coordinate.longitude - s.longitude) * a)
        } else {
            smoothed = loc.coordinate
        }
        coordinate = smoothed ?? loc.coordinate
        hasFix = true
        updates &+= 1
    }

    /// Should we run an expensive rediscovery now? `force` is a manual RESCAN, which
    /// bypasses the distance check but still honours the time floor.
    func shouldRefetch(force: Bool = false) -> Bool {
        if let at = lastFetchAt, Date().timeIntervalSince(at) < Self.minFetchInterval { return false }
        if force || lastFetchAnchor == nil { return true }
        guard let anchor = lastFetchAnchor else { return true }
        let here = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let there = CLLocation(latitude: anchor.latitude, longitude: anchor.longitude)
        return here.distance(from: there) > Self.refetchDistance
    }

    /// Arm the gate BEFORE awaiting the network so concurrent ticks can't double-fire
    /// one boundary crossing.
    func markFetched() {
        lastFetchAnchor = coordinate
        lastFetchAt = Date()
    }
}
