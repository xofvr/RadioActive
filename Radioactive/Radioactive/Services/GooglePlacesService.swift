import CoreLocation
import Foundation

/// Configuration for the Google Places API (New). Get a key at
/// https://console.cloud.google.com → enable **Places API (New)** → create an API key,
/// then restrict it (iOS bundle id + "Places API (New)"). Provide it one of three ways:
///   • add `GOOGLE_PLACES_API_KEY` to the app's Info.plist, or
///   • set it as an environment variable on the run scheme, or
///   • paste it into `hardcodedKey` below for quick local testing.
/// Leave it empty and the app falls back to keyless MapKit discovery (simulated readings).
enum GooglePlacesConfig {
    private static let hardcodedKey = ""

    static var apiKey: String {
        if let k = Bundle.main.object(forInfoDictionaryKey: "GOOGLE_PLACES_API_KEY") as? String, !k.isEmpty { return k }
        if let k = ProcessInfo.processInfo.environment["GOOGLE_PLACES_API_KEY"], !k.isEmpty { return k }
        if let k = secretsPlistKey, !k.isEmpty { return k }
        return hardcodedKey
    }

    static var isConfigured: Bool { !apiKey.isEmpty }

    /// A gitignored `Secrets.plist` bundled into the app (key `GOOGLE_PLACES_API_KEY`).
    /// Keeps the key out of source control while still shipping it in the build. Absent
    /// on a fresh clone ⇒ the app simply runs keyless (MapKit simulated readings).
    private static var secretsPlistKey: String? {
        guard let url = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
              let dict = NSDictionary(contentsOf: url) else { return nil }
        return dict["GOOGLE_PLACES_API_KEY"] as? String
    }
}

/// Google Places (New) **Nearby Search** client — the app's real-ratings layer.
///
/// One `places:searchNearby` call returns up to 20 nearby food/drink places *with* their
/// real `rating` + `userRatingCount` in a single billed event, so we get discovery AND
/// ratings without the fragile name/coordinate matching a MapKit→Google bolt-on needs.
/// Requesting the `rating` field bills at Google's Enterprise SKU (1,000 free events/month
/// as of 2026) — comfortably free for a single, throttled user. We deliberately do NOT
/// request `places.reviews` (a costlier Enterprise+Atmosphere field); quotes stay empty.
///
/// Returns `nil` (never throws to the caller) when unconfigured or on any failure, so the
/// caller can fall back to MapKit discovery and then the demo roster.
struct GooglePlacesService {
    var key = GooglePlacesConfig.apiKey
    private let endpoint = URL(string: "https://places.googleapis.com/v1/places:searchNearby")!

    /// Food/drink types (Places New "Table A") we scan for — mirrors the MapKit filter.
    private static let includedTypes = [
        "restaurant", "cafe", "bar", "pub", "bakery",
        "coffee_shop", "meal_takeaway", "fast_food_restaurant",
    ]

    /// Only these fields are requested — the field mask is what determines the billed SKU,
    /// so keep it tight. `id` is free to cache; `rating`/`userRatingCount` are the Enterprise
    /// fields we actually need.
    private static let fieldMask = [
        "places.id", "places.displayName", "places.location",
        "places.rating", "places.userRatingCount",
        "places.primaryType", "places.primaryTypeDisplayName",
    ].joined(separator: ",")

    /// The app's bundle id, sent so the API key can be locked to this app (an iOS
    /// API-key restriction). Falls back to the known id if the bundle has none.
    private static let bundleID = Bundle.main.bundleIdentifier ?? "com.xofvr.radioactive"

    /// Discover up to 20 real, *rated* food/drink places within `radius` of `center`,
    /// worst-first by real rating. Unrated places are dropped — we never attach a reading
    /// to a real business we have no rating for.
    func fetchPlaces(near center: CLLocationCoordinate2D, radius: CLLocationDistance, limit: Int = 20) async -> [Place]? {
        guard !key.isEmpty else { return nil }

        // Google caps a Nearby Search circle at 50 km; the app's radii are far smaller.
        let cappedRadius = min(max(radius, 1), 50_000)
        let body: [String: Any] = [
            "includedTypes": Self.includedTypes,
            "maxResultCount": min(limit, 20),
            "rankPreference": "DISTANCE",
            "locationRestriction": [
                "circle": [
                    "center": ["latitude": center.latitude, "longitude": center.longitude],
                    "radius": cappedRadius,
                ],
            ],
        ]

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(key, forHTTPHeaderField: "X-Goog-Api-Key")
        request.setValue(Self.fieldMask, forHTTPHeaderField: "X-Goog-FieldMask")
        request.setValue(Self.bundleID, forHTTPHeaderField: "X-Ios-Bundle-Identifier")
        guard let httpBody = try? JSONSerialization.data(withJSONObject: body) else { return nil }
        request.httpBody = httpBody

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else { return nil }
            let decoded = try JSONDecoder().decode(GooglePlacesResponse.self, from: data)

            let base = CLLocation(latitude: center.latitude, longitude: center.longitude)
            let mapped = decoded.places.compactMap { $0.toPlace(base: base, center: center) }
            guard !mapped.isEmpty else { return nil }

            // Worst-first; final id (re)assignment is owned by PlacesProvider.reindex.
            return Array(mapped.sorted { $0.rating < $1.rating }.prefix(limit))
        } catch {
            return nil
        }
    }
}

// MARK: - Wire models

private struct GooglePlacesResponse: Decodable {
    let places: [GooglePlace]
    // Tolerate both an absent `places` key (zero results) and a single malformed entry:
    // decode element-by-element and keep the ones that parse, so one odd record never
    // collapses the whole real-ratings batch down to simulated readings.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let raw = (try? c.decode([Failable<GooglePlace>].self, forKey: .places)) ?? []
        places = raw.compactMap(\.value)
    }
    enum CodingKeys: String, CodingKey { case places }
}

/// Decodes to `nil` instead of throwing, so one bad element never sinks the whole array.
private struct Failable<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) { value = try? T(from: decoder) }
}

private struct GooglePlace: Decodable {
    let id: String
    let displayName: GoogleLocalizedText?
    let location: GoogleLatLng?
    let rating: Double?
    let userRatingCount: Int?
    let primaryType: String?
    let primaryTypeDisplayName: GoogleLocalizedText?

    /// Map to the app's `Place`. Returns nil for places we can't honestly use — no name,
    /// no coordinate, or (critically) **no real rating**.
    func toPlace(base: CLLocation, center: CLLocationCoordinate2D) -> Place? {
        guard let name = displayName?.text, !name.isEmpty,
              let loc = location,
              let rating, rating > 0 else { return nil }

        let coord = CLLocationCoordinate2D(latitude: loc.latitude, longitude: loc.longitude)
        guard CLLocationCoordinate2DIsValid(coord) else { return nil }

        let distance = base.distance(from: CLLocation(latitude: loc.latitude, longitude: loc.longitude))
        let bearing = Place.bearing(from: center, to: coord)
        let category = Self.mapCategory(primaryType)
        let typeLabel = primaryTypeDisplayName?.text ?? Self.humanize(primaryType) ?? category.singular

        return Place(
            id: 0,
            name: name,
            short: String(name.prefix(18)),
            type: typeLabel,
            cat: category,
            rating: rating,
            reviews: userRatingCount ?? 0,
            dist: Int(distance.rounded()),
            bearing: bearing,
            quotes: [],
            lat: loc.latitude,
            lon: loc.longitude,
            providerID: "google:\(id)",
            ratingSource: .real
        )
    }

    /// Fold Google's fine-grained primary type into the app's three buckets.
    private static func mapCategory(_ type: String?) -> PlaceCategory {
        let t = (type ?? "").lowercased()
        if t.contains("cafe") || t.contains("coffee") || t.contains("bakery") || t.contains("tea") { return .cafes }
        if t.contains("bar") || t.contains("pub") || t.contains("night_club") || t.contains("brewery") || t.contains("wine") { return .pubs }
        return .eats
    }

    /// "fast_food_restaurant" → "Fast Food Restaurant" when Google gives no display name.
    private static func humanize(_ type: String?) -> String? {
        guard let type, !type.isEmpty else { return nil }
        return type.split(separator: "_").map { $0.capitalized }.joined(separator: " ")
    }
}

private struct GoogleLocalizedText: Decodable { let text: String }
private struct GoogleLatLng: Decodable { let latitude: Double; let longitude: Double }
