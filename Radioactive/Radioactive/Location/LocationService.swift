import CoreLocation
import Observation

/// Thin wrapper over CoreLocation. Publishes the user's coordinate (defaulting to
/// central London — the field roster is unmistakably British) and authorization
/// state. Everything degrades gracefully: deny location and the app simply scans
/// around the default centre.
@MainActor
@Observable
final class LocationService: NSObject, CLLocationManagerDelegate {

    /// Fallback centre when location is unavailable or denied.
    static let defaultCoordinate = CLLocationCoordinate2D(latitude: 51.5074, longitude: -0.1278)

    private(set) var coordinate = LocationService.defaultCoordinate
    private(set) var isAuthorized = false
    private(set) var hasFix = false

    @ObservationIgnored private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    /// Ask for When-In-Use permission (no-op if already decided).
    func requestIfNeeded() {
        manager.requestWhenInUseAuthorization()
    }

    // CoreLocation delivers these on the manager's queue (the main thread here),
    // but the delegate requirements are non-isolated — so keep them `nonisolated`
    // and hop to the main actor before touching @Observable state. Silences the
    // actor-isolation conformance warning and is Swift 6 clean.
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        let authorized = status == .authorizedWhenInUse || status == .authorizedAlways
        Task { @MainActor in
            self.isAuthorized = authorized
            if authorized { self.manager.startUpdatingLocation() }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let coordinate = locations.last?.coordinate else { return }
        Task { @MainActor in
            self.coordinate = coordinate
            self.hasFix = true
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Stay on the last good (or default) coordinate; never surface an error.
    }
}
