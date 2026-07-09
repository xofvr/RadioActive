import SwiftUI

/// The beloved Geiger needle — the HERO of the detector face. A bottom-hinged upward
/// semicircle (π → 2π) drawn entirely in a Canvas so the needle can jitter and glow
/// every frame: 60 danger segments (`engine.dangerScale`), graduation ticks, and a live
/// needle keyed to `engine.rads`.
///
/// Everything SIZES TO ITS FRAME (stroke, ticks, hub) rather than a fixed height, so the
/// face can mount it big as the hero while it still degrades gracefully at small sizes
/// (ticks drop when the stroke gets thin). No CLEAR/TOXIC end labels — the housing plate
/// carries those. RELATIVE reading: the arc + needle colour flow from `engine.rads`,
/// never the absolute `Place.red`.
struct CoreGaugeView: View {
    var engine: DetectorEngine

    var body: some View {
        TimelineView(.animation) { _ in
            Canvas { ctx, size in
                // Touch the monotonic frame counter so the Canvas re-evaluates every
                // display-link tick as the reading (and its jitter) moves.
                _ = engine.frame
                draw(ctx: &ctx, size: size)
            }
        }
    }

    /// Builds a centred arc Path from `a0` to `a1` (radians) at `radius`.
    private func arc(cx: Double, cy: Double, radius: Double, a0: Double, a1: Double) -> Path {
        var path = Path()
        path.addArc(
            center: CGPoint(x: cx, y: cy),
            radius: radius,
            startAngle: .radians(a0),
            endAngle: .radians(a1),
            clockwise: false
        )
        return path
    }

    private func draw(ctx: inout GraphicsContext, size: CGSize) {
        let w = size.width
        let h = size.height
        let cx = w / 2
        // Hinge near the bottom of the frame; the semicircle sweeps up out of it.
        let cy = h - h * 0.08
        // Stroke width + hub scale with the frame so the meter reads clean at any size.
        let lineW = max(4, h * 0.09)
        let R = min(w / 2 - lineW, h - lineW * 1.4)
        guard R > 0 else { return }
        let nLen = R - lineW * 0.6

        let start = Double.pi
        let end = 2 * Double.pi
        let span = end - start

        // 1) Track arc — faint base groove under the coloured band.
        ctx.stroke(
            arc(cx: cx, cy: cy, radius: R, a0: start, a1: end),
            with: .color(.white.opacity(0.06)),
            style: StrokeStyle(lineWidth: lineW, lineCap: .round)
        )

        // 2) 60 coloured danger segments — calm → toxic along the sweep.
        let scale = engine.dangerScale
        for i in 0..<60 {
            let a0 = start + span * (Double(i) / 60)
            let a1 = start + span * (Double(i) + 1.04) / 60
            ctx.stroke(
                arc(cx: cx, cy: cy, radius: R, a0: a0, a1: a1),
                with: .color(scale.color(Double(i) / 60, 0.85)),
                style: StrokeStyle(lineWidth: lineW, lineCap: .round)
            )
        }

        // 3) Graduation ticks across the dial — the analog-meter detail that reads the
        // needle as a real Geiger counter (scaled to the frame; dropped when tiny).
        if lineW >= 5 {
            let r1 = R - lineW * 1.2
            let r2 = R - lineW * 2.1
            let tickColor = Color(.sRGB, red: 233.0 / 255, green: 239.0 / 255, blue: 233.0 / 255, opacity: 0.28)
            for i in 0..<9 {
                let a = start + span * (Double(i) / 8)
                let ca = cos(a)
                let sa = sin(a)
                var tick = Path()
                tick.move(to: CGPoint(x: cx + ca * r1, y: cy + sa * r1))
                tick.addLine(to: CGPoint(x: cx + ca * r2, y: cy + sa * r2))
                ctx.stroke(tick, with: .color(tickColor), style: StrokeStyle(lineWidth: max(1, lineW * 0.16), lineCap: .round))
            }
        }

        // 4) Needle — jitters with the reading, glows in the active colour.
        let v = engine.rads
        let jitter = (Double.random(in: 0..<1) - 0.5) * (0.05 + v * 0.16)
        let ang = start + (v + jitter) * span
        let col = engine.color(v, 1)
        let ca = cos(ang)
        let sa = sin(ang)
        var needle = Path()
        needle.move(to: CGPoint(x: cx - ca * lineW, y: cy - sa * lineW))
        needle.addLine(to: CGPoint(x: cx + ca * nLen, y: cy + sa * nLen))

        var glowCtx = ctx
        glowCtx.addFilter(.shadow(color: col, radius: lineW * 2.4))
        glowCtx.stroke(needle, with: .color(col), style: StrokeStyle(lineWidth: max(2, lineW * 0.55), lineCap: .round))

        // 5) Hub — dark cap ringed in the needle colour.
        let hubR = lineW * 0.9
        let hubRect = CGRect(x: cx - hubR, y: cy - hubR, width: hubR * 2, height: hubR * 2)
        let hub = Path(ellipseIn: hubRect)
        ctx.fill(hub, with: .color(Theme.bg))
        ctx.stroke(hub, with: .color(col), lineWidth: max(1.5, lineW * 0.22))
    }
}
