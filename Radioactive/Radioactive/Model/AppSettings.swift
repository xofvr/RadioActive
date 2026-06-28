import Foundation
import Observation

/// The entire "theme"/testing state. No ThemeStore, no palette overhaul.
/// NOTE: do NOT use @AppStorage inside @Observable (it does not participate in
/// Observation tracking). Plain stored props + didSet persistence is the contract.
@MainActor
@Observable
final class AppSettings {
    /// Compass hero instead of the analog gauge. Default false.
    var useCompass: Bool {
        didSet { UserDefaults.standard.set(useCompass, forKey: Keys.useCompass) }
    }
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

    init() {
        let d = UserDefaults.standard
        useCompass      = d.object(forKey: Keys.useCompass) as? Bool ?? false
        relativeReading = d.object(forKey: Keys.relativeReading) as? Bool ?? true
        liveRatings     = d.object(forKey: Keys.liveRatings) as? Bool ?? false
    }

    private enum Keys {
        static let useCompass = "settings.useCompass"
        static let relativeReading = "settings.relativeReading"
        static let liveRatings = "settings.liveRatings"
    }
}
