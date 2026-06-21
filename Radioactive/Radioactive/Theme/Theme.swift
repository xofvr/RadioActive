import SwiftUI

/// Visual palette options. Phosphor (classic radium green) is the hero look;
/// Amber is a vintage CRT alternative, both taken verbatim from the source design.
enum Palette: String, CaseIterable, Identifiable {
    case phosphor = "Phosphor"
    case amber = "Amber"
    var id: String { rawValue }
}

/// Three-stop "danger gradient" — interpolates from calm → warning → toxic as a
/// 0...1 intensity climbs. Drives the gauge arc, needle, pins and rating colours.
struct DangerScale {
    let stops: [(Double, Double, Double)]

    static let phosphor = DangerScale(stops: [(69, 249, 166), (255, 194, 75), (255, 77, 67)])
    static let amber = DangerScale(stops: [(255, 209, 90), (255, 150, 46), (255, 77, 67)])

    static func forPalette(_ p: Palette) -> DangerScale { p == .amber ? .amber : .phosphor }

    func rgb(_ t: Double) -> (Double, Double, Double) {
        let tt = min(1, max(0, t))
        let a: (Double, Double, Double), b: (Double, Double, Double)
        let f: Double
        if tt < 0.5 { a = stops[0]; b = stops[1]; f = tt / 0.5 }
        else { a = stops[1]; b = stops[2]; f = (tt - 0.5) / 0.5 }
        return (a.0 + (b.0 - a.0) * f, a.1 + (b.1 - a.1) * f, a.2 + (b.2 - a.2) * f)
    }

    func color(_ t: Double, _ alpha: Double = 1) -> Color {
        let c = rgb(t)
        return Color(.sRGB, red: c.0 / 255, green: c.1 / 255, blue: c.2 / 255, opacity: alpha)
    }
}

/// Centralised tokens for the RADIOACTIVE look.
enum Theme {
    // Surfaces
    static let bg = Color(hex: 0x0A0B0A)
    static let bgDeep = Color(hex: 0x0D0E10)
    static let panelTop = Color(hex: 0x101E16)
    static let panelBottom = Color(hex: 0x070E0A)

    // Phosphor accents
    static let phosphor = Color(hex: 0x45F9A6)
    static let phosphorBright = Color(hex: 0x7DFFC4)
    static let phosphorDim = Color(hex: 0x45F9A6, alpha: 0.55)

    // Hazard
    static let danger = Color(hex: 0xFF4D43)
    static let dangerSoft = Color(hex: 0xFF7A72)
    static let amber = Color(hex: 0xFFC24B)

    // Text
    static let ink = Color(hex: 0xE9EFE9)
    static let inkBright = Color(hex: 0xEAFFF3)
    static let inkMuted = Color(hex: 0xE9EFE9, alpha: 0.45)

    /// Inset instrument-panel gradient used across cards.
    static var panel: LinearGradient {
        LinearGradient(
            colors: [panelTop.opacity(0.5), panelBottom.opacity(0.55)],
            startPoint: .top, endPoint: .bottom
        )
    }

    /// VT323 pixel font for instrument readouts/labels, with a graceful
    /// monospaced-system fallback if registration ever fails.
    static func mono(_ size: CGFloat) -> Font {
        FontRegistrar.vt323Available
            ? .custom("VT323", size: size, relativeTo: .body)
            : .system(size: size, weight: .regular, design: .monospaced)
    }
}

extension View {
    /// Soft phosphor/neon glow — the CRT bloom that defines the instrument.
    func phosphorGlow(_ color: Color, radius: CGFloat = 8) -> some View {
        shadow(color: color.opacity(0.55), radius: radius)
    }
}
