import SwiftUI

/// Live contamination readout pill — colour + label track the engine, with a
/// blinking hazard dot. HOT SIGNAL / ELEVATED / FAINT TRACE (deliberately
/// non-defamatory — never a "CONTAMINATED" food-safety claim).
struct StatusPill: View {
    var engine: DetectorEngine
    @State private var blink = false

    var body: some View {
        let c = engine.statusColor
        HStack(spacing: 7) {
            Circle()
                .fill(c)
                .frame(width: 7, height: 7)
                .phosphorGlow(c, radius: 4)
                .opacity(blink ? 0.3 : 1)
            Text(engine.status.label)
                .font(Theme.mono(15))
                .foregroundStyle(c)
                .fixedSize()
        }
        .padding(.horizontal, 10)
        .frame(height: 26)
        .background(RoundedRectangle(cornerRadius: 3).fill(c.opacity(0.13)))
        .overlay(RoundedRectangle(cornerRadius: 3).stroke(c.opacity(0.34), lineWidth: 1))
        .onAppear {
            withAnimation(.easeInOut(duration: 0.55).repeatForever(autoreverses: true)) {
                blink = true
            }
        }
    }
}
