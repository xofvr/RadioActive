import CoreLocation
import Observation

/// Decides where the roster comes from. With a TripAdvisor key configured it
/// pulls the worst real places near you; otherwise it leaves the engine on its
/// bundled demo roster. Either way the app is fully functional.
@MainActor
@Observable
final class PlacesProvider {
    enum Source: String { case demo = "Demo data", tripAdvisor = "TripAdvisor" }

    private(set) var source: Source = .demo
    private(set) var isLoading = false
    private(set) var didAttempt = false

    var statusLabel: String {
        if isLoading { return "LINKING TRIPADVISOR…" }
        return source == .tripAdvisor ? "LIVE · TRIPADVISOR" : "DEMO ROSTER"
    }

    /// Load real places into the engine if possible. Safe to call repeatedly;
    /// no-ops while a load is in flight.
    func load(into engine: DetectorEngine, near coordinate: CLLocationCoordinate2D) async {
        guard !isLoading else { return }
        guard TripAdvisorConfig.isConfigured else {
            source = .demo
            didAttempt = true
            return
        }
        isLoading = true
        defer { isLoading = false; didAttempt = true }

        if let places = await TripAdvisorService().fetchWorstPlaces(near: coordinate), !places.isEmpty {
            engine.setPlaces(places)
            source = .tripAdvisor
        } else {
            source = .demo
        }
    }
}
