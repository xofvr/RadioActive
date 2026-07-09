import CoreLocation
import Observation

/// The compass. Publishes the device's heading (degrees, 0 = North) so you can *point
/// the phone at a place* and have the detector aim itself — the app's hero interaction.
/// `heading` is nil when no compass is available (e.g. the Simulator), letting the
/// engine fall back to its demo sweep. `needsCalibration` drives a "wave the phone"
/// hint when the magnetometer is uncertain, and `accuracy` carries the magnitude of
/// that uncertainty (degrees, lower = better) so the detector can widen its aim cone
/// and never claim more confidence than the magnetometer actually has.
@MainActor
@Observable
final class HeadingService: NSObject, CLLocationManagerDelegate {

    private(set) var heading: Double? = nil
    private(set) var needsCalibration = false
    /// `CLHeading.headingAccuracy` when the last reading was valid (positive degrees,
    /// lower = better); `nil` when invalid/uncalibrated. Drives the confidence + cone.
    private(set) var accuracy: Double? = nil

    @ObservationIgnored private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.headingFilter = 1            // degrees of change before an update
        manager.headingOrientation = .portrait
    }

    func start() {
        guard CLLocationManager.headingAvailable() else { return }
        manager.startUpdatingHeading()
    }

    func stop() {
        manager.stopUpdatingHeading()
    }

    // CoreLocation delivers on the main thread here, but the delegate requirement is
    // non-isolated — hop to the main actor before touching @Observable state.
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        // Negative accuracy means the reading is unreliable / uncalibrated.
        let accurate = newHeading.headingAccuracy >= 0
        // Prefer true north; fall back to magnetic when location isn't supplying declination.
        let value = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
        Task { @MainActor in
            self.needsCalibration = !accurate
            // Keep the accuracy magnitude while valid; drop it to nil when invalid so
            // the confidence maths reads it as untrustworthy. `heading` freezes at its
            // last good value (the deliberate "hold last good heading" behaviour).
            self.accuracy = accurate ? newHeading.headingAccuracy : nil
            if accurate { self.heading = value }
        }
    }

    nonisolated func locationManagerShouldDisplayHeadingCalibration(_ manager: CLLocationManager) -> Bool {
        true
    }
}
