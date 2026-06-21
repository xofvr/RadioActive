import SwiftUI

// FROZEN SIGNATURE — implemented by the instruments workflow stage.
// Semicircular analog dose meter: coloured danger arc, ticks, jittering needle,
// hub, CLEAR/TOXIC end labels. Reads engine.rads / engine.frame / engine.dangerScale.
//
// The hero instrument. A top-half sweep (π → 2π) drawn entirely in a Canvas so the
// needle can jitter and glow every frame. DetectorScreen overlays the star row + CPM
// readout on top of this — GaugeView draws ONLY the meter.
struct GaugeView: View {
    var engine: DetectorEngine

    var body: some View {
        TimelineView(.animation) { _ in
            Canvas { ctx, size in
                draw(ctx: &ctx, size: size)
            }
        }
        .frame(height: 172)
        .frame(maxWidth: .infinity)
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
        let cy = h - 14
        let R = min(w / 2 - 14, h - 26)
        guard R > 0 else { return }
        let nLen = R - 6

        let start = Double.pi
        let end = 2 * Double.pi
        let span = end - start

        // 1) Track arc — faint base groove under the coloured band.
        ctx.stroke(
            arc(cx: cx, cy: cy, radius: R, a0: start, a1: end),
            with: .color(.white.opacity(0.06)),
            style: StrokeStyle(lineWidth: 11, lineCap: .round)
        )

        // 2) 60 coloured danger segments — calm → toxic along the sweep.
        let scale = engine.dangerScale
        for i in 0..<60 {
            let a0 = start + span * (Double(i) / 60)
            let a1 = start + span * (Double(i) + 1.04) / 60
            ctx.stroke(
                arc(cx: cx, cy: cy, radius: R, a0: a0, a1: a1),
                with: .color(scale.color(Double(i) / 60, 0.85)),
                style: StrokeStyle(lineWidth: 11, lineCap: .round)
            )
        }

        // 3) 9 graduation ticks across the dial.
        let r1 = R - 14
        let r2 = R - 22
        let tickColor = Color(.sRGB, red: 233.0 / 255, green: 239.0 / 255, blue: 233.0 / 255, opacity: 0.3)
        for i in 0..<9 {
            let a = start + span * (Double(i) / 8)
            let ca = cos(a)
            let sa = sin(a)
            var tick = Path()
            tick.move(to: CGPoint(x: cx + ca * r1, y: cy + sa * r1))
            tick.addLine(to: CGPoint(x: cx + ca * r2, y: cy + sa * r2))
            ctx.stroke(tick, with: .color(tickColor), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
        }

        // 4) Needle — jitters with the reading, glows in the active colour.
        let v = engine.rads
        let jitter = (Double.random(in: 0..<1) - 0.5) * (0.05 + v * 0.16)
        let ang = start + (v + jitter) * span
        let col = engine.color(v, 1)
        let ca = cos(ang)
        let sa = sin(ang)
        var needle = Path()
        needle.move(to: CGPoint(x: cx - ca * 14, y: cy - sa * 14))
        needle.addLine(to: CGPoint(x: cx + ca * nLen, y: cy + sa * nLen))

        var glowCtx = ctx
        glowCtx.addFilter(.shadow(color: col, radius: 16))
        glowCtx.stroke(needle, with: .color(col), style: StrokeStyle(lineWidth: 3.4, lineCap: .round))

        // 5) Hub — dark cap ringed in the needle colour.
        let hubRect = CGRect(x: cx - 9, y: cy - 9, width: 18, height: 18)
        let hub = Path(ellipseIn: hubRect)
        ctx.fill(hub, with: .color(Color(hex: 0x0A0B0A)))
        ctx.stroke(hub, with: .color(col), lineWidth: 2)

        // 6) End labels — CLEAR / TOXIC in the pixel font.
        let labelColor = Color(.sRGB, red: 233.0 / 255, green: 239.0 / 255, blue: 233.0 / 255, opacity: 0.35)
        let clear = Text("CLEAR").font(Theme.mono(13)).foregroundStyle(labelColor)
        let toxic = Text("TOXIC").font(Theme.mono(13)).foregroundStyle(labelColor)
        ctx.draw(clear, at: CGPoint(x: cx - R + 2, y: cy + 4), anchor: .leading)
        ctx.draw(toxic, at: CGPoint(x: cx + R - 2, y: cy + 4), anchor: .trailing)
    }
}
