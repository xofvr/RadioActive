import SwiftUI

/// Shared Phase-4 readouts, reused by BOTH hero instruments (the analog gauge and
/// the Pip-Boy compass). They read only the dosimeter / discovery / proximity-heat
/// state the engine accrues on its existing display-link tick — no new timers.

/// "Dosimeter" — the running session dose and the discovered-place tally. Both ride
/// the engine's `tick(dt:)`; this chip just surfaces them in the phosphor idiom.
struct DosimeterChip: View {
    var engine: DetectorEngine

    var body: some View {
        HStack(spacing: 14) {
            metric("RADS ABSORBED", String(format: "%.1f", engine.sessionRads))
            Rectangle()
                .fill(Theme.phosphor.opacity(0.18))
                .frame(width: 1, height: 22)
            metric("DISCOVERED", "\(engine.placesDiscovered)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 5).fill(Theme.bg.opacity(0.45)))
        .overlay(RoundedRectangle(cornerRadius: 5).stroke(Theme.phosphor.opacity(0.22), lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(String(format: "%.1f", engine.sessionRads)) rads absorbed, \(engine.placesDiscovered) places discovered")
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(Theme.mono(11))
                .tracking(0.5)
                .foregroundStyle(Theme.phosphor.opacity(0.45))
            Text(value)
                .font(Theme.mono(20))
                .foregroundStyle(Theme.phosphorBright)
                .phosphorGlow(Theme.phosphor, radius: 4)
        }
    }
}

/// Proximity heat — a "warmer / cooler" cue from the engine's fast-vs-slow rads EWMA.
/// Hidden-but-reserved (dim) when steady so the layout never jumps as you sweep.
struct ProximityCue: View {
    var engine: DetectorEngine

    var body: some View {
        Group {
            switch engine.radsTrend {
            case .warmer:
                cue(text: "GETTING HOTTER", systemImage: "arrow.right",
                    color: engine.color(0.85), trailingIcon: true)
            case .cooler:
                cue(text: "COOLER", systemImage: "arrow.left",
                    color: Theme.phosphor, trailingIcon: false)
            case .steady:
                cue(text: "STEADY", systemImage: nil,
                    color: Theme.phosphor.opacity(0.30), trailingIcon: false)
            }
        }
        .font(Theme.mono(14))
        .animation(.easeInOut(duration: 0.25), value: engine.radsTrend)
    }

    @ViewBuilder
    private func cue(text: String, systemImage: String?, color: Color, trailingIcon: Bool) -> some View {
        HStack(spacing: 5) {
            if let systemImage, !trailingIcon { Image(systemName: systemImage) }
            Text(text).tracking(0.5)
            if let systemImage, trailingIcon { Image(systemName: systemImage) }
        }
        .foregroundStyle(color)
    }
}
