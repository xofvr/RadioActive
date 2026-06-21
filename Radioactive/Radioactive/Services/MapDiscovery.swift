import CoreLocation
import MapKit

/// Keyless, real-business discovery via MapKit — the proximity layer. Returns nearby
/// food/drink establishments as `Place` values carrying real coordinates, category and
/// Apple identity, each with a DETERMINISTIC simulated reading (until a `RatingProvider`
/// supplies a real rating). The scan radius IS the proximity control.
///
/// MapKit gives us discovery + coordinates for free and never vends a rating — so every
/// place here is flagged `.simulated` and only ever upgraded to `.real` downstream.
struct MapDiscovery {

    /// The "things you'd scan" — food and drink only.
    static let foodFilter = MKPointOfInterestFilter(including: [
        .restaurant, .cafe, .bakery, .brewery, .distillery, .winery, .nightlife, .foodMarket,
    ])

    /// Discover up to `limit` real food/drink places within `radius` of `center`,
    /// worst-first by their (simulated) reading, deduped by Apple identity. Returns
    /// an empty array on failure so the caller can fall back to the demo roster.
    func discover(near center: CLLocationCoordinate2D,
                  radius: CLLocationDistance,
                  limit: Int = 40) async -> [Place] {
        let capped = min(radius, MKLocalPointsOfInterestRequest.maxRadius)
        let request = MKLocalPointsOfInterestRequest(center: center, radius: capped)
        request.pointOfInterestFilter = Self.foodFilter

        do {
            let response = try await MKLocalSearch(request: request).start()
            let base = CLLocation(latitude: center.latitude, longitude: center.longitude)

            var byKey: [String: Place] = [:]
            for item in response.mapItems {
                guard let place = Self.makePlace(from: item, center: center, base: base) else { continue }
                let key = place.mapItemID ?? "\(place.name)|\(place.dist)|\(place.bearing)"
                if byKey[key] == nil { byKey[key] = place }
            }

            let worstFirst = byKey.values.sorted { $0.rating < $1.rating }
            // Reassign ids 0…n by final order so engine indexing stays valid.
            return worstFirst.prefix(limit).enumerated().map { index, place in
                var p = place
                p.id = index
                return p
            }
        } catch {
            return []
        }
    }

    // MARK: Mapping

    private static func makePlace(from item: MKMapItem, center: CLLocationCoordinate2D, base: CLLocation) -> Place? {
        let coord = item.location.coordinate
        guard CLLocationCoordinate2DIsValid(coord),
              !item.isCurrentLocation,
              let name = item.name, !name.isEmpty else { return nil }

        let category = mapCategory(item.pointOfInterestCategory)
        let mapID = item.identifier?.rawValue
        // Seed determinism on Apple identity; fall back to name + rounded coordinate.
        let seed = mapID ?? "\(name)|\(Int(coord.latitude * 10_000))|\(Int(coord.longitude * 10_000))"

        let distance = base.distance(from: CLLocation(latitude: coord.latitude, longitude: coord.longitude))
        let bearing = Place.bearing(from: center, to: coord)

        return Place(
            id: 0,
            name: name,
            short: String(name.prefix(18)),
            type: typeLabel(item.pointOfInterestCategory) ?? category.singular,
            cat: category,
            rating: Reading.rating(seed: seed, category: category),
            reviews: Reading.reviewCount(seed: seed),
            dist: Int(distance.rounded()),
            bearing: bearing,
            quotes: [],
            lat: coord.latitude,
            lon: coord.longitude,
            mapItemID: mapID,
            ratingSource: .simulated
        )
    }

    /// Fold MapKit's fine-grained POI categories into the app's three buckets.
    private static func mapCategory(_ poi: MKPointOfInterestCategory?) -> PlaceCategory {
        switch poi {
        case .some(.cafe), .some(.bakery): return .cafes
        case .some(.brewery), .some(.distillery), .some(.winery), .some(.nightlife): return .pubs
        default: return .eats
        }
    }

    /// A human label for the place's type, from its POI category.
    private static func typeLabel(_ poi: MKPointOfInterestCategory?) -> String? {
        switch poi {
        case .some(.restaurant):  return "Restaurant"
        case .some(.cafe):        return "Café"
        case .some(.bakery):      return "Bakery"
        case .some(.brewery):     return "Brewery"
        case .some(.distillery):  return "Distillery"
        case .some(.winery):      return "Wine Bar"
        case .some(.nightlife):   return "Bar"
        case .some(.foodMarket):  return "Food Market"
        default:                  return nil
        }
    }
}
