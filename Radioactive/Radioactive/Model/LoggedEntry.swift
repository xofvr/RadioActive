import Foundation

/// A durable, honesty-locked snapshot of a logged place. Persisted so the Logbook
/// stays populated even when the place is out of range / off the current roster.
/// `red` and `ratingSource` are frozen at log time — the ABSOLUTE inversion.
struct LoggedEntry: Identifiable, Hashable, Codable {
    var id: String { logKey }
    let logKey: String
    let name: String
    let type: String
    let red: Int               // ABSOLUTE Place.red, frozen
    let ratingSource: String   // RatingSource.rawValue ("real"/"simulated")
    let date: Date

    init(_ p: Place, date: Date = Date()) {
        logKey = p.logKey
        name = p.name
        type = p.type
        red = p.red
        ratingSource = p.ratingSource.rawValue
        self.date = date
    }
}
