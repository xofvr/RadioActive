import SwiftUI

/// The hero instrument screen: a handheld "review Geiger counter". A branded
/// header, the dose gauge with the target's red-star rating and live CPM readout,
/// the oscilloscope strip, an "aiming at" card that pushes the field report, and a
/// Liquid-Glass audio toggle that brings the crackle to life.
struct DetectorScreen: View {
    var engine: DetectorEngine

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                header
                gaugePanel
                aimingCard
                audioButton
            }
            .padding(16)
        }
        .background(Color.clear)
        .toolbar(.hidden, for: .navigationBar)
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center) {
            HStack(spacing: 10) {
                Image(systemName: "dot.radiowaves.up.forward")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Theme.phosphor)
                    .phosphorGlow(Theme.phosphor, radius: 8)
                Text("RADIOACTIVE")
                    .font(Theme.mono(20))
                    .tracking(3)
                    .foregroundStyle(Theme.phosphorBright)
                    .phosphorGlow(Theme.phosphor, radius: 8)
            }
            Spacer(minLength: 8)
            StatusPill(engine: engine)
        }
    }

    // MARK: Gauge panel

    private var gaugePanel: some View {
        VStack(spacing: 14) {
            HStack {
                Text("▮ RAD DETECTOR")
                    .font(Theme.mono(15))
                    .foregroundStyle(Theme.phosphor.opacity(0.7))
                Spacer()
                Button(action: engine.cycleTarget) {
                    HStack(spacing: 5) {
                        Text("NEXT")
                        Image(systemName: "arrow.clockwise")
                    }
                    .font(Theme.mono(14))
                    .foregroundStyle(Theme.phosphor.opacity(0.55))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Next target")
            }

            // The meter — arc, needle, hub. Kept clean: nothing overlaps it.
            GaugeView(engine: engine)

            // Hairline separating the instrument from its verdict.
            Rectangle()
                .fill(Theme.phosphor.opacity(0.14))
                .frame(height: 1)

            // HERO — the target's red-star rating: dead-centre, the biggest,
            // brightest thing on the panel. The needle moves with your aim; the
            // stars are the verdict everything else is in service of.
            RedStars(red: engine.target.red, size: 32, spacing: 8)
                .frame(maxWidth: .infinity)

            // Live dose readout — clearly secondary, in its own row so the needle
            // can never cross it. Isolated subview so only it redraws each frame.
            CPMReadout(engine: engine)

            ScopeView(engine: engine)
                .padding(.top, 2)
        }
        .padding(16)
        .instrumentPanel()
    }

    // MARK: Aiming-at card

    private var aimingCard: some View {
        NavigationLink(value: engine.target) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 0) {
                        Text("AIMING AT · ")
                            .foregroundStyle(Theme.phosphor.opacity(0.55))
                        Text(engine.locked ? "◉ TARGET ACQUIRED" : "SCANNING…")
                            .foregroundStyle(engine.locked ? Theme.phosphor : Theme.inkMuted)
                    }
                    .font(Theme.mono(13))

                    Text(engine.target.name)
                        .font(.system(size: 19, weight: .bold))
                        .foregroundStyle(Theme.inkBright)

                    Text("\(engine.target.type) · \(engine.target.distLabel) · \(engine.target.bearingLabel)")
                        .font(Theme.mono(15))
                        .foregroundStyle(Theme.phosphor.opacity(0.55))
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.phosphor.opacity(0.45))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .instrumentPanel()
        }
        .buttonStyle(.plain)
    }

    // MARK: Audio button

    private var audioButton: some View {
        Button(action: engine.toggleAudio) {
            HStack(spacing: 10) {
                Image(systemName: engine.audioOn ? "speaker.wave.2.fill" : "speaker.slash.fill")
                Text(engine.audioOn ? "Audio on — crackle live" : "Enable Geiger audio")
            }
            .font(Theme.mono(18))
            .foregroundStyle(engine.audioOn ? Theme.phosphorBright : Theme.phosphor.opacity(0.85))
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .liquidGlass(
                in: RoundedRectangle(cornerRadius: 12),
                tint: engine.audioOn ? Theme.phosphor.opacity(0.22) : nil,
                interactive: true
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Theme.phosphor.opacity(engine.audioOn ? 0.45 : 0.25), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

/// The live counts-per-minute readout. Pulled into its own view so that the
/// per-frame churn of `cpmDisplay`/`rads` invalidates only this small label —
/// not the whole detector screen — every display-link tick.
private struct CPMReadout: View {
    var engine: DetectorEngine

    var body: some View {
        let value = min(999, Int(engine.cpmDisplay))
        return HStack(spacing: 5) {
            Text(String(format: "%03d", value))
                .font(Theme.mono(26))
                .foregroundStyle(engine.color(engine.rads))
                .phosphorGlow(engine.color(engine.rads), radius: 6)
            Text("CPM")
                .font(Theme.mono(20))
                .foregroundStyle(Theme.phosphor.opacity(0.4))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(value) counts per minute")
    }
}
