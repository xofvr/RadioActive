import Foundation

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
}
