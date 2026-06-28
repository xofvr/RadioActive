import CoreLocation
import Observation

/// Decides where the roster comes from, worst source-degradation first:
///   1. **Google Places (New)** — REAL ratings, when a `GOOGLE_PLACES_API_KEY` is set.
///      One Nearby Search returns nearby places *with* real ratings (no fragile matching).
///   2. **MapKit** — keyless real-business discovery; readings are deterministic
///      SIMULATED stand-ins, always flagged, never passed off as real.
///   3. **Demo roster** — the bundled fiction, when offline / nothing nearby.
/// The app is always fully functional; each tier falls through to the next on any failure.
@MainActor
@Observable
final class PlacesProvider {
    enum Source: String { case demo, mapKit, google, tripAdvisor }

    private(set) var source: Source = .demo
    private(set) var isLoading = false
    private(set) var didAttempt = false
    /// How many loaded places carry a REAL rating (vs a simulated stand-in).
    private(set) var matchedCount = 0
    /// Google quota hit this cycle (HTTP 429) — we fell through to a SIM reading.
    private(set) var throttled: Bool = false
    /// The last Google failure reason (used to distinguish OFFLINE from a plain demo roster).
    private(set) var lastReason: Reason? = nil
    /// KILL-SWITCH: when false, the Google tier is skipped entirely (zero network calls).
    /// Set by RootView from `AppSettings.liveRatings`.
    var liveRatingsEnabled: Bool = false

    var statusLabel: String {
        if isLoading { return "SCANNING…" }
        switch source {
        case .google:      return "LIVE · GOOGLE"
        case .tripAdvisor: return "LIVE · TRIPADVISOR"
        case .mapKit:      return throttled ? "QUOTA THROTTLED · SIM READING"
                                            : "LIVE PLACES · SIM READING"
        case .demo:        return lastReason == .network ? "OFFLINE · DEMO ROSTER"
                                                         : "DEMO ROSTER"
        }
    }

    /// Discover real places near `coordinate` and load them into the engine. `force` is
    /// a manual RESCAN (re-home the aim); otherwise the aimed target is preserved. Safe
    /// to call repeatedly; no-ops while a load is in flight.
    func load(into engine: DetectorEngine, near coordinate: CLLocationCoordinate2D, force: Bool) async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false; didAttempt = true }

        // Reset per-cycle state up front so a stale outcome from a PRIOR load can never
        // leak into this one's status (e.g. a 429 in an earlier cycle must not keep
        // reporting "QUOTA THROTTLED" once a later .empty/.failed cycle replaces it).
        // Each outcome below sets only what it is responsible for; an all-suppressed
        // success (empty `visible`) leaves them cleared.
        throttled = false
        lastReason = nil
        matchedCount = 0

        // 1. REAL ratings via Google Places (New) — ONLY when a key is configured AND the
        //    live-ratings kill-switch is ON. When the gate is false we skip the tier
        //    entirely (no network call) and fall straight through to MapKit/demo. A single
        //    Nearby Search returns nearby places already carrying real ratings. Any
        //    non-success outcome records the throttle / reason and falls through to MapKit.
        if GooglePlacesConfig.isConfigured && liveRatingsEnabled {
            switch await GooglePlacesService().fetchPlaces(near: coordinate,
                                                           radius: LocationService.cityRadius,
                                                           limit: 20) {
            case .success(let rated):
                let visible = reindex(rated, engine: engine)
                if !visible.isEmpty {
                    matchedCount = visible.filter { $0.ratingSource == .real }.count
                    engine.setPlaces(visible, center: coordinate,
                                     localRadius: LocationService.localRadius, force: force)
                    source = .google
                    return
                }
            case .rateLimited:
                throttled = true                        // fall through to MapKit
            case .empty:
                break                                   // fall through (state already clear)
            case .failed(let r):
                lastReason = r                          // fall through
            }
        }

        // 2. Keyless MapKit discovery across the city radius (the main pages narrow to the
        //    local radius themselves). Real places, deterministic SIMULATED readings.
        let discovered = await MapDiscovery().discover(near: coordinate,
                                                       radius: LocationService.cityRadius,
                                                       limit: 40)
        let visible = reindex(discovered, engine: engine)
        guard !visible.isEmpty else {
            source = .demo   // offline / no POIs nearby — keep the bundled roster
            return
        }
        matchedCount = visible.filter { $0.ratingSource == .real }.count
        engine.setPlaces(visible, center: coordinate,
                         localRadius: LocationService.localRadius, force: force)
        source = .mapKit
    }

    /// Drop anything the user reported / asked to remove, then re-id 0…n so engine
    /// indexing stays valid regardless of which provider supplied the roster.
    private func reindex(_ places: [Place], engine: DetectorEngine) -> [Place] {
        places.filter { !engine.isSuppressed($0) }.enumerated().map { index, place in
            var p = place; p.id = index; return p
        }
    }
}
