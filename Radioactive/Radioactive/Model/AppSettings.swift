import Foundation
import Observation

/// The entire "theme"/testing state. No ThemeStore, no palette overhaul.
/// NOTE: do NOT use @AppStorage inside @Observable (it does not participate in
/// Observation tracking). Plain stored props + didSet persistence is the contract.
@MainActor
@Observable
final class AppSettings {
    /// Relative (normalised-to-local-field) reading. Default true.
    var relativeReading: Bool {
        didSet { UserDefaults.standard.set(relativeReading, forKey: Keys.relativeReading) }
    }
    /// Live (real Google Places) ratings instead of simulated. Default false — the
    /// kill-switch for any network fetch. PlacesProvider attempts the Google tier ONLY
    /// when this is ON; OFF returns to simulated readings with zero network calls.
    var liveRatings: Bool {
        didSet { UserDefaults.standard.set(liveRatings, forKey: Keys.liveRatings) }
    }
    /// Tactile detection — Geiger clicks + the lock cue buzz. Default true, and
    /// independent of audio, so silent handheld scanning works out of the box.
    var haptics: Bool {
        didSet { UserDefaults.standard.set(haptics, forKey: Keys.haptics) }
    }

    init() {
        let d = UserDefaults.standard
        relativeReading = d.object(forKey: Keys.relativeReading) as? Bool ?? true
        liveRatings     = d.object(forKey: Keys.liveRatings) as? Bool ?? false
        haptics         = d.object(forKey: Keys.haptics) as? Bool ?? true
    }

    private enum Keys {
        static let relativeReading = "settings.relativeReading"
        static let liveRatings = "settings.liveRatings"
        static let haptics = "settings.haptics"
    }
}
