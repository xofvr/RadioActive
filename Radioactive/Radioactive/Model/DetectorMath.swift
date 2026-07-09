import CoreGraphics
import Foundation

/// Result of `DetectorMath.cluster`. `members[0] == representative` (the worst,
/// since callers pass items worst-first). `count` is exposed for the "+N" badge.
struct Cluster<Item> {
    let representative: Item
    let members: [Item]
    var count: Int { members.count }
}

/// How much to trust the compass right now. CoreLocation semantics:
/// `CLHeading.headingAccuracy` is negative (⇒ nil upstream) when invalid; otherwise
/// positive degrees, lower = better. Top-level so the engine and detector face share it.
enum HeadingConfidence { case good, low, invalid }

/// Pure, dependency-free detector maths — extracted from `DetectorEngine` so the
/// error-prone bits (compass wrap-around, aim band, the relative-contaminant floor,
/// the intensity model) can be unit-tested without the SwiftUI/CADisplayLink engine.
enum DetectorMath {

    /// Smallest absolute angle between two bearings, in degrees (0…180).
    static func angDiff(_ a: Double, _ b: Double) -> Double {
        var d = abs((a - b).truncatingRemainder(dividingBy: 360))
        if d > 180 { d = 360 - d }
        return d
    }

    /// Shortest-angle lerp from `current` toward `target` — handles the 359°→0° wrap,
    /// so the compass needle never spins the long way round.
    static func smoothHeading(_ current: Double, toward target: Double, factor: Double) -> Double {
        var delta = (target - current).truncatingRemainder(dividingBy: 360)
        if delta > 180 { delta -= 360 } else if delta < -180 { delta += 360 }
        return (current + delta * factor + 360).truncatingRemainder(dividingBy: 360)
    }

    // MARK: Heading confidence

    /// Aim-confidence thresholds (degrees of `CLHeading.headingAccuracy`, lower = better).
    /// First estimates — kept as named constants so they can be tuned on-device.
    static let headingLowThreshold: Double = 20      // > this ⇒ degrading (low)
    static let headingInvalidThreshold: Double = 35  // > this ⇒ untrustworthy (invalid)
    static let headingConeMax: Double = 60           // widest the aim cone ever opens

    static func headingConfidence(accuracyDeg: Double?, calibrating: Bool) -> HeadingConfidence {
        guard let a = accuracyDeg, a >= 0 else { return .invalid }   // negative/nil ⇒ invalid
        if calibrating || a > headingInvalidThreshold { return .invalid }
        if a > headingLowThreshold { return .low }
        return .good
    }

    /// Aim-cone half-angle: floored at `base` (the honest lock cone), widening toward
    /// `max` as accuracy degrades; invalid/nil ⇒ fully open. The band VISIBLY widens as
    /// confidence drops — a real detector's confidence arc.
    static func coneHalfAngle(accuracyDeg: Double?, base: Double, max maxAngle: Double = headingConeMax) -> Double {
        guard let a = accuracyDeg, a >= 0 else { return maxAngle }
        return Swift.min(maxAngle, Swift.max(base, a))
    }

    /// Relative "contamination" bar: the median badness, clamped to [0.35, 0.6], so the
    /// radar surfaces the worst-nearby and is never empty when real ratings cluster high.
    static func contaminationFloor(badnesses: [Double]) -> Double {
        guard !badnesses.isEmpty else { return 0.4 }
        let sorted = badnesses.sorted()
        return max(0.35, min(0.6, sorted[sorted.count / 2]))
    }

    /// How hot a place reads: its `badness` sets the ceiling; aim (`headingError`) and
    /// proximity only swing the needle *within* that band — so a good place can never be
    /// made to read bad.
    static func intensity(badness: Double, distance: Double, headingError: Double, sensitivity: Double) -> Double {
        let prox = max(0.15, 1 - distance / 800)
        let face = (cos(headingError * .pi / 180) + 1) / 2
        let detection = prox * (0.4 + 0.6 * face)
        let value = badness * (0.62 + 0.38 * detection) * sensitivity
        return min(1, max(0, value))
    }

    /// Normalise `absolute` badness against the local spread (worst-nearby = 1, best = 0),
    /// with a gentle gamma to lift the mid. Degenerate spread (range ≤ 0.05) → returns
    /// `absolute` unchanged (never invents contrast from noise).
    static func relativeBadness(_ absolute: Double, localBadnesses: [Double]) -> Double {
        guard let lo = localBadnesses.min(), let hi = localBadnesses.max(),
              hi - lo > 0.05 else { return absolute }
        // Clamp BEFORE pow: an `absolute` outside [lo,hi] (e.g. a target beyond
        // localRadius via aim(at:)) yields a negative norm, and pow(negative, 0.75)
        // is NaN. Clamping first keeps in-range behaviour identical.
        let norm = min(1, max(0, (absolute - lo) / (hi - lo)))
        return pow(norm, 0.75)
    }

    /// Blend absolute and relative badness; `w` weights toward relative (≈0.6).
    static func readingBadness(absolute: Double, relative: Double, w: Double = 0.6) -> Double {
        min(1, max(0, absolute * (1 - w) + relative * w))
    }

    /// Distance (m) → 0.10…0.48 radial fraction of the scope / compass face.
    /// Shared by radarPins() and the detector face so the mapping never drifts.
    static func scopeRadiusFraction(distanceM: Double, maxM: Double = 560) -> Double {
        0.10 + min(1, distanceM / maxM) * 0.38
    }

    /// Greedy O(n²) spatial clustering (≤20 items expected). Items must arrive
    /// worst-first; the cluster seed (first encountered) becomes the representative.
    /// `position` maps an item to a planar point; `minSeparation` is in that same unit
    /// (≈0.08 scope-fraction for the radar, ≈25 m for the map).
    static func cluster<Item>(_ items: [Item],
                              position: (Item) -> CGPoint,
                              minSeparation: Double) -> [Cluster<Item>] {
        var used = [Bool](repeating: false, count: items.count)
        var result: [Cluster<Item>] = []
        for i in items.indices where !used[i] {
            used[i] = true
            var members = [items[i]]
            let pi = position(items[i])
            for j in (i + 1)..<items.count where !used[j] {
                let pj = position(items[j])
                if hypot(pj.x - pi.x, pj.y - pi.y) <= minSeparation {
                    used[j] = true
                    members.append(items[j])
                }
            }
            result.append(Cluster(representative: items[i], members: members))
        }
        return result
    }
}
