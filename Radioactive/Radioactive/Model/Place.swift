import Foundation

/// A place you can "scan". The worse its star rating, the more radioactive it reads.
struct Place: Identifiable, Hashable {
    let id: Int
    let name: String
    let short: String
    let type: String
    let cat: PlaceCategory
    let rating: Double
    let reviews: Int
    let dist: Int          // metres from "you"
    let bearing: Double     // degrees, 0 = North
    let quotes: [Quote]

    /// Real coordinate when sourced from TripAdvisor; nil for demo places, which
    /// get projected onto the map from `bearing` + `dist`.
    var lat: Double? = nil
    var lon: Double? = nil

    // MARK: Derived readouts

    /// Red stars — the inverse of a normal rating. 5 = maximally toxic.
    var red: Int { Int((5 - rating).rounded()) }

    /// 0...1 "badness", the quantity that actually drives every reading.
    var badness: Double { (5 - rating) / 5 }

    var distLabel: String { "\(dist) m" }
    var ratingLabel: String { String(format: "%.1f", rating) }

    var bearingLabel: String {
        let dirs = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        return dirs[Int((bearing / 45).rounded()) % 8]
    }

    static func == (lhs: Place, rhs: Place) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

struct Quote: Identifiable, Hashable {
    let id = UUID()
    let stars: Int          // red stars on this review (0...5)
    let text: String
    let author: String
}

enum PlaceCategory: String, CaseIterable {
    case eats = "Eats"
    case pubs = "Pubs"
    case cafes = "Cafés"
}

/// The Nearby-screen filter chips. `all` plus each category.
enum NearbyFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case pubs = "Pubs"
    case cafes = "Cafés"
    case eats = "Eats"

    var id: String { rawValue }
    func matches(_ p: Place) -> Bool { self == .all ? true : p.cat.rawValue == rawValue }
}

/// One bar in the rating-breakdown histogram on the detail screen.
struct RatingBar: Identifiable {
    let id = UUID()
    let star: Int
    let pct: Double          // 0...1 width fraction
    let count: Int
    let isHot: Bool          // 1–2★ → red
    let isMid: Bool          // 3★ → amber
}

extension Place {
    /// Believable review histogram: counts cluster (Gaussian) around the place's
    /// actual average, so a 0.9★ dive skews hard to 1–2★ while a 3.4★ café peaks
    /// mid. (The source design used fixed weights that always peaked at 5★
    /// regardless of rating — a bug corrected here.)
    var ratingBars: [RatingBar] {
        let stars = [5, 4, 3, 2, 1]
        let sigma = 1.15
        let ws = stars.map { s -> Double in
            let d = Double(s) - rating
            return max(0.6, exp(-(d * d) / (2 * sigma * sigma)) * 100)
        }
        let total = ws.reduce(0, +)
        return zip(stars, ws).map { star, w in
            RatingBar(
                star: star,
                pct: w / total,
                count: Int((Double(reviews) * w / total).rounded()),
                isHot: star <= 2,
                isMid: star == 3
            )
        }
    }

    var peakCPM: Int { Int((120 + badness * 180).rounded()) }
    var daysSinceGood: Int { Int((40 + badness * 320).rounded()) }
}

/// The full field roster — seven establishments of varying toxicity.
enum Places {
    static let all: [Place] = [
        Place(id: 0, name: "Glow Kebab House", short: "Glow Kebab", type: "Kebab House",
              cat: .eats, rating: 0.9, reviews: 412, dist: 90, bearing: 22, quotes: [
                Quote(stars: 0, text: "Meat of indeterminate origin. Glowed faintly in the dark.", author: "Dave R."),
                Quote(stars: 1, text: "Asked for no onions. Received only onions, and regret.", author: "Priya K."),
              ]),
        Place(id: 1, name: "Pier Pressure Fish Bar", short: "Pier Fish", type: "Chippy",
              cat: .eats, rating: 1.1, reviews: 188, dist: 150, bearing: 305, quotes: [
                Quote(stars: 0, text: "The \"fish\" filed a missing persons report.", author: "Gemma T."),
                Quote(stars: 1, text: "Batter so thick it has its own gravitational field.", author: "Liam O."),
              ]),
        Place(id: 2, name: "The Crispy Badger", short: "Crispy Badger", type: "Pub",
              cat: .pubs, rating: 1.4, reviews: 529, dist: 120, bearing: 78, quotes: [
                Quote(stars: 1, text: "Carpet older than the landlord. Stickier, too.", author: "Mark H."),
                Quote(stars: 0, text: "The \"live music\" was a man arguing with the fruit machine.", author: "Sofia L."),
              ]),
        Place(id: 3, name: "The Rusty Tap", short: "Rusty Tap", type: "Pub",
              cat: .pubs, rating: 1.8, reviews: 340, dist: 210, bearing: 168, quotes: [
                Quote(stars: 1, text: "Ordered a lager, received a warning.", author: "Tom B."),
                Quote(stars: 2, text: "Toilet door doubles as the wine list.", author: "Aisha M."),
              ]),
        Place(id: 4, name: "Mum's Not Cooking", short: "Mum's", type: "Café",
              cat: .cafes, rating: 2.3, reviews: 97, dist: 340, bearing: 242, quotes: [
                Quote(stars: 2, text: "It shows. It really shows.", author: "Nina F."),
                Quote(stars: 1, text: "The avocado toast was, frankly, a dare.", author: "Joe P."),
              ]),
        Place(id: 5, name: "La Trattoria Tragica", short: "Trattoria", type: "Italian",
              cat: .eats, rating: 2.7, reviews: 233, dist: 520, bearing: 128, quotes: [
                Quote(stars: 2, text: "Carbonara with a generous side of regret.", author: "Elena V."),
                Quote(stars: 3, text: "Waiter sighed louder than the espresso machine.", author: "Chris D."),
              ]),
        Place(id: 6, name: "Beanwave Coffee", short: "Beanwave", type: "Café",
              cat: .cafes, rating: 3.4, reviews: 610, dist: 460, bearing: 200, quotes: [
                Quote(stars: 3, text: "Aggressively fine. The wifi password is a 40-character apology.", author: "Sam W."),
                Quote(stars: 4, text: "Almost good, which is somehow worse.", author: "Ria N."),
              ]),
    ]
}
