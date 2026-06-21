import CoreLocation

extension Place {
    /// A real map coordinate for this place. Real places (from TripAdvisor) carry
    /// their own `lat`/`lon`; demo places are projected from a base coordinate
    /// using their fixed bearing + distance, so they still land plausibly on a map.
    func coordinate(base: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        if let lat, let lon {
            return CLLocationCoordinate2D(latitude: lat, longitude: lon)
        }
        return Place.project(from: base, bearingDeg: bearing, distanceM: Double(dist))
    }

    /// Forward geodesic: the point `distanceM` metres from `base` along `bearingDeg`.
    static func project(from base: CLLocationCoordinate2D, bearingDeg: Double, distanceM: Double) -> CLLocationCoordinate2D {
        let radius = 6_371_000.0
        let angular = distanceM / radius
        let bearing = bearingDeg * .pi / 180
        let lat1 = base.latitude * .pi / 180
        let lon1 = base.longitude * .pi / 180

        let lat2 = asin(sin(lat1) * cos(angular) + cos(lat1) * sin(angular) * cos(bearing))
        let lon2 = lon1 + atan2(sin(bearing) * sin(angular) * cos(lat1),
                                cos(angular) - sin(lat1) * sin(lat2))

        return CLLocationCoordinate2D(latitude: lat2 * 180 / .pi, longitude: lon2 * 180 / .pi)
    }

    /// Bearing in degrees from `base` to `coord` (0 = North, clockwise).
    static func bearing(from base: CLLocationCoordinate2D, to coord: CLLocationCoordinate2D) -> Double {
        let lat1 = base.latitude * .pi / 180
        let lat2 = coord.latitude * .pi / 180
        let dLon = (coord.longitude - base.longitude) * .pi / 180
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        let deg = atan2(y, x) * 180 / .pi
        return (deg + 360).truncatingRemainder(dividingBy: 360)
    }
}
