import CoreLocation
import Foundation

/// Configuration for the TripAdvisor Content API.
enum TripAdvisorConfig {
    /// Your TripAdvisor Content API key. Get one free at
    /// https://www.tripadvisor.com/developers — then either:
    ///   • add `TRIPADVISOR_API_KEY` to the app's Info.plist, or
    ///   • set it as an environment variable on the run scheme, or
    ///   • paste it into `hardcodedKey` below for quick local testing.
    /// Leave it empty and the app runs on the bundled demo roster.
    private static let hardcodedKey = ""

    static var apiKey: String {
        if let k = Bundle.main.object(forInfoDictionaryKey: "TRIPADVISOR_API_KEY") as? String, !k.isEmpty { return k }
        if let k = ProcessInfo.processInfo.environment["TRIPADVISOR_API_KEY"], !k.isEmpty { return k }
        return hardcodedKey
    }

    static var isConfigured: Bool { !apiKey.isEmpty }

    /// The Content API restricts keys by Referer (or IP) in the developer portal.
    /// Set this to a value you've allow-listed there.
    static let referer = "https://radioactive.app"
}

/// A minimal TripAdvisor Content API client: nearby search → details → reviews,
/// mapped into the app's `Place` model. Returns `nil` (never throws to the caller)
/// when unconfigured or on any failure, so the app can fall back to demo data.
struct TripAdvisorService {
    var key = TripAdvisorConfig.apiKey
    private let base = URL(string: "https://api.content.tripadvisor.com/api/v1/")!

    /// Find nearby places, rank them worst-first by rating, and return up to
    /// `limit` mapped to `Place` (with real coordinates + worst reviews as quotes).
    func fetchWorstPlaces(near center: CLLocationCoordinate2D, limit: Int = 7) async -> [Place]? {
        guard !key.isEmpty else { return nil }
        do {
            let nearby = try await searchNearby(center)
            guard !nearby.isEmpty else { return nil }

            // Fetch details concurrently to get ratings + coordinates.
            var detailed: [TADetails] = []
            try await withThrowingTaskGroup(of: TADetails?.self) { group in
                for loc in nearby.prefix(20) {
                    group.addTask { try? await self.details(loc.locationId) }
                }
                for try await item in group { if let item { detailed.append(item) } }
            }

            let worst = detailed
                .filter { $0.ratingValue != nil }
                .sorted { ($0.ratingValue ?? 5) < ($1.ratingValue ?? 5) }
                .prefix(limit)
            guard !worst.isEmpty else { return nil }

            var places: [Place] = []
            for (index, detail) in worst.enumerated() {
                let reviews = (try? await self.reviews(detail.locationId)) ?? []
                places.append(detail.toPlace(id: index, base: center, reviews: reviews))
            }
            return places.isEmpty ? nil : places
        } catch {
            return nil
        }
    }

    // MARK: Endpoints

    private func searchNearby(_ c: CLLocationCoordinate2D) async throws -> [TANearby] {
        let query = [
            URLQueryItem(name: "latLong", value: "\(c.latitude),\(c.longitude)"),
            URLQueryItem(name: "category", value: "restaurants"),
            URLQueryItem(name: "radius", value: "5"),
            URLQueryItem(name: "radiusUnit", value: "km"),
        ]
        let response: TANearbyResponse = try await get("location/nearby_search", query: query)
        return response.data
    }

    private func details(_ id: String) async throws -> TADetails {
        try await get("location/\(id)/details", query: [])
    }

    private func reviews(_ id: String) async throws -> [TAReview] {
        let response: TAReviewsResponse = try await get("location/\(id)/reviews", query: [])
        return response.data
    }

    // MARK: Transport

    private func get<T: Decodable>(_ path: String, query: [URLQueryItem]) async throws -> T {
        guard var comps = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false) else {
            throw URLError(.badURL)
        }
        comps.queryItems = query + [
            URLQueryItem(name: "key", value: key),
            URLQueryItem(name: "language", value: "en"),
        ]
        guard let url = comps.url else { throw URLError(.badURL) }

        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "accept")
        request.setValue(TripAdvisorConfig.referer, forHTTPHeaderField: "Referer")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}

// MARK: - Wire models (TripAdvisor returns many numbers as strings)

private struct TANearbyResponse: Decodable { let data: [TANearby] }

private struct TANearby: Decodable {
    let locationId: String
    let name: String
    enum CodingKeys: String, CodingKey { case locationId = "location_id", name }
}

private struct TADetails: Decodable {
    let locationId: String
    let name: String
    let latitude: String?
    let longitude: String?
    let rating: String?
    let numReviews: String?
    let category: TANamed?
    let subcategory: [TANamed]?

    enum CodingKeys: String, CodingKey {
        case locationId = "location_id", name, latitude, longitude, rating
        case numReviews = "num_reviews", category, subcategory
    }

    var ratingValue: Double? { rating.flatMap(Double.init) }

    func toPlace(id: Int, base: CLLocationCoordinate2D, reviews: [TAReview]) -> Place {
        let lat = latitude.flatMap(Double.init)
        let lon = longitude.flatMap(Double.init)
        let ratingValue = self.ratingValue ?? 3.0
        let reviewCount = numReviews.flatMap(Int.init) ?? reviews.count

        let coord: CLLocationCoordinate2D
        if let lat, let lon { coord = CLLocationCoordinate2D(latitude: lat, longitude: lon) } else { coord = base }
        let distance = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
            .distance(from: CLLocation(latitude: base.latitude, longitude: base.longitude))
        let bearing = Place.bearing(from: base, to: coord)

        let typeLabel: String = subcategory?.first?.name ?? category?.name?.capitalized ?? "Place"
        let category: PlaceCategory = TADetails.mapCategory(self.category?.name, subcategory?.first?.name)

        let sortedReviews = reviews.sorted { ($0.rating ?? 5) < ($1.rating ?? 5) }
        var quotes: [Quote] = []
        for review in sortedReviews.prefix(2) {
            let redStars = max(0, 5 - (review.rating ?? 3))
            let body = review.text ?? review.title ?? ""
            let author = review.user?.username ?? "Anonymous"
            quotes.append(Quote(stars: redStars, text: body, author: author))
        }

        return Place(
            id: id,
            name: name,
            short: String(name.prefix(16)),
            type: typeLabel,
            cat: category,
            rating: ratingValue,
            reviews: reviewCount,
            dist: Int(distance.rounded()),
            bearing: bearing,
            quotes: quotes,
            lat: lat,
            lon: lon
        )
    }

    private static func mapCategory(_ category: String?, _ sub: String?) -> PlaceCategory {
        let blob = ((sub ?? "") + " " + (category ?? "")).lowercased()
        if blob.contains("pub") || blob.contains("bar") { return .pubs }
        if blob.contains("cafe") || blob.contains("café") || blob.contains("coffee") { return .cafes }
        return .eats
    }
}

private struct TANamed: Decodable { let name: String? }

private struct TAReviewsResponse: Decodable { let data: [TAReview] }

private struct TAReview: Decodable {
    let rating: Int?
    let title: String?
    let text: String?
    let user: TAUser?
}

private struct TAUser: Decodable { let username: String? }
