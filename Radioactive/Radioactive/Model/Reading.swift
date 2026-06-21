import Foundation

/// RADIOACTIVE has no real review feed for a freshly MapKit-discovered place (Apple
/// vends no ratings via API). Until a real `RatingProvider` matches it, the place's
/// reading is a DETERMINISTIC novelty stand-in: stable per place, seeded from its
/// identity so it never changes between launches, biased a little by category for
/// comedy — and always surfaced flagged `.simulated`, never passed off as real.
enum Reading {

    /// A stable pseudo-rating in ~[1.0, 4.6] for a place identity. Lower = more
    /// "contaminated". The per-place hash supplies the spread; category nudges the
    /// centre (kebabs and chippies skew hot). Same seed → same rating, every time.
    static func rating(seed: String, category: PlaceCategory) -> Double {
        let unit = Double(stableHash(seed) % 10_000) / 10_000.0   // 0..<1, stable
        let centre = categoryCentre(category)
        let r = centre + (unit - 0.5) * 2.8                        // ±1.4 spread
        return min(4.6, max(1.0, r))
    }

    /// A stable, plausible review count for the same identity.
    static func reviewCount(seed: String) -> Int {
        40 + Int(stableHash(seed + "#rv") % 900)
    }

    private static func categoryCentre(_ c: PlaceCategory) -> Double {
        switch c {
        case .eats:  return 2.5     // kebabs, chippies, late-night — peak comedy
        case .pubs:  return 2.8
        case .cafes: return 3.1
        }
    }

    /// FNV-1a — a small, stable hash. (Swift's `Hasher` is per-process randomised, so
    /// it would give a different rating every launch; we need determinism.)
    static func stableHash(_ s: String) -> UInt64 {
        var h: UInt64 = 1469598103934665603
        for b in s.utf8 {
            h ^= UInt64(b)
            h = h &* 1099511628211
        }
        return h
    }
}
