import SwiftUI

/// The Pip-Boy device HOUSING — a fixed bezel that frames the whole screen so the app
/// reads as a handheld gadget, not a flat UI. A chunky dark frame catching a faint
/// phosphor glint on its inner bevel, four corner rivets, and a curved-glass edge
/// falloff that darkens the extreme edges like a bulging CRT.
///
/// Purely cosmetic; never intercepts touches. Pairs with `CRTOverlay` (scanlines +
/// vignette): the bezel is the housing, CRTOverlay is the glass over it.
struct PipBoyBezel: View {
    private let corner: CGFloat = 46

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // 0) Soft outer phosphor glow — the device edge catching CRT light.
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .stroke(Theme.phosphor.opacity(0.10), lineWidth: 3)
                    .blur(radius: 6)

                // 1) Curved-glass edge falloff — a soft dark inner border, heavier top &
                // bottom, like light rolling off a bulged CRT face.
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [.black.opacity(0.5), .black.opacity(0.12), .black.opacity(0.5)],
                            startPoint: .top, endPoint: .bottom),
                        lineWidth: 22)
                    .blur(radius: 9)

                // 2) The housing body — a chunky dark frame giving the bezel depth, with a
                // faintly-lit top edge so it reads as moulded plastic, not a flat line.
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [Color(hex: 0x141D17), Color(hex: 0x050706), Color(hex: 0x0B120D)],
                            startPoint: .top, endPoint: .bottom),
                        lineWidth: 9)

                // 3) Inner bevel highlight — the phosphor glint that says "glass set in a
                // frame": brighter at the top-left as if lit from above, with a warm amber
                // pool at the bottom-right (CRT warmth).
                RoundedRectangle(cornerRadius: corner - 3, style: .continuous)
                    .inset(by: 7)
                    .stroke(
                        LinearGradient(
                            colors: [Theme.phosphor.opacity(0.45), Theme.phosphor.opacity(0.08),
                                     Theme.amber.opacity(0.10), Theme.phosphor.opacity(0.14)],
                            startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: 1.5)

                // 4) Corner rivets — dark metal studs with a single phosphor glint.
                ForEach(Array(rivets(in: geo.size).enumerated()), id: \.offset) { _, p in
                    Circle()
                        .fill(RadialGradient(
                            colors: [Theme.phosphor.opacity(0.55), Color(hex: 0x0B0E0C)],
                            center: UnitPoint(x: 0.35, y: 0.32), startRadius: 0, endRadius: 7))
                        .frame(width: 10, height: 10)
                        .overlay(Circle().stroke(.black.opacity(0.6), lineWidth: 1))
                        .phosphorGlow(Theme.phosphor.opacity(0.5), radius: 3)
                        .position(p)
                }
            }
            .compositingGroup()
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }

    /// The four corner stud positions, tucked just inside the frame.
    private func rivets(in size: CGSize) -> [CGPoint] {
        let d: CGFloat = 26
        return [
            CGPoint(x: d, y: d),
            CGPoint(x: size.width - d, y: d),
            CGPoint(x: d, y: size.height - d),
            CGPoint(x: size.width - d, y: size.height - d),
        ]
    }
}
