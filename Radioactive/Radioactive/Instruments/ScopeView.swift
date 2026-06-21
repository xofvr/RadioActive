import SwiftUI

// Oscilloscope strip: a glowing waveform from engine.scope (150 samples),
// centre baseline, colour by engine.color(engine.rads).
struct ScopeView: View {
    var engine: DetectorEngine

    var body: some View {
        TimelineView(.animation) { _ in
            Canvas { ctx, size in
                // Touch the monotonic frame counter so the Canvas re-evaluates
                // every frame as the engine pushes new scope samples.
                _ = engine.frame

                let w = size.width
                let h = size.height
                let mid = h / 2

                // 1) Baseline.
                var baseline = Path()
                baseline.move(to: CGPoint(x: 0, y: mid))
                baseline.addLine(to: CGPoint(x: w, y: mid))
                ctx.stroke(baseline, with: .color(.white.opacity(0.05)), lineWidth: 1)

                // 2) Waveform from the 150-sample scope buffer.
                let samples = engine.scope
                let n = samples.count
                guard n > 1 else { return }

                let amp = mid - 3
                var wave = Path()
                for i in 0..<n {
                    let x = Double(i) / Double(n - 1) * w
                    let y = mid - samples[i] * amp
                    let pt = CGPoint(x: x, y: y)
                    if i == 0 { wave.move(to: pt) } else { wave.addLine(to: pt) }
                }

                let traceColor = engine.color(engine.rads, 0.95)
                ctx.addFilter(.shadow(color: traceColor.opacity(0.9), radius: 6))
                ctx.stroke(
                    wave,
                    with: .color(traceColor),
                    style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round)
                )
            }
        }
        .frame(height: 38)
        .frame(maxWidth: .infinity)
        .background(Color(hex: 0x0A0B0A, alpha: 0.6))
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .stroke(Theme.phosphor.opacity(0.18), lineWidth: 1)
        )
    }
}
