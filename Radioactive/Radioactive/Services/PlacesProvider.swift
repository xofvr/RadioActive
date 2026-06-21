import CoreLocation
import Observation

/// Decides where the roster comes from. It always tries REAL nearby businesses via
/// MapKit first (keyless, proximity-bounded); their red-star readings are deterministic
/// simulations — clearly flagged — until a real `RatingProvider` (e.g. Google Places)
/// is wired in behind the same seam. Falls back to the bundled demo roster when offline
/// or when nothing is nearby, so the app is always fully functional.
@MainActor
@Observable
final class PlacesProvider {
    enum Source: String { case demo, mapKit, tripAdvisor }

    private(set) var source: Source = .demo
    private(set) var isLoading = false
    private(set) var didAttempt = false
    /// How many loaded places carry a REAL rating (vs a simulated stand-in).
    private(set) var matchedCount = 0

    var statusLabel: String {
        if isLoading { return "SCANNING…" }
        switch source {
        case .tripAdvisor: return "LIVE · TRIPADVISOR"
        case .mapKit:      return "LIVE PLACES · SIM READING"
        case .demo:        return "DEMO ROSTER"
        }
    }

    /// Discover real places near `coordinate` and load them into the engine. `force` is
    /// a manual RESCAN (re-home the aim); otherwise the aimed target is preserved. Safe
    /// to call repeatedly; no-ops while a load is in flight.
    func load(into engine: DetectorEngine, near coordinate: CLLocationCoordinate2D, force: Bool) async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false; didAttempt = true }

        // Real MapKit discovery across the city radius; the main pages narrow to the
        // local radius themselves. No key, no billing.
        let discovered = await MapDiscovery().discover(near: coordinate,
                                                       radius: LocationService.cityRadius,
                                                       limit: 40)
        // Drop anything the user reported / asked to remove, then re-id sequentially.
        let visible = discovered.filter { !engine.isSuppressed($0) }.enumerated().map { index, place -> Place in
            var p = place; p.id = index; return p
        }
        guard !visible.isEmpty else {
            source = .demo   // offline / no POIs nearby — keep the bundled roster
            return
        }

        // SEAM: a real RatingProvider (e.g. Google Places New) would replace the
        // simulated readings here, matching by name + coordinate and bumping
        // `matchedCount`. Until then every reading is a deterministic simulation,
        // surfaced flagged so a stand-in is never passed off as a real verdict.
        matchedCount = visible.filter { $0.ratingSource == .real }.count
        engine.setPlaces(visible, center: coordinate,
                         localRadius: LocationService.localRadius, force: force)
        source = .mapKit
    }
}
