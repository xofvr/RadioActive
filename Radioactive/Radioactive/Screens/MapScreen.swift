import SwiftUI

/// The tactical radar screen. A full-bleed `RadarView` sits at the centre with a
/// floating "contaminants in range" chip up top and a pinned summary card for the
/// hottest signal at the bottom — tap SCAN to jump to the detector.
struct MapScreen: View {
    var engine: DetectorEngine
    var onScan: () -> Void

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()

            // 1) Radar scope — square, self-sizing from the given width, lifted a
            // little above centre so the summary card has breathing room.
            RadarView(engine: engine)
                .padding(.horizontal, 22)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .offset(y: -28)

            // 2) Floating range chip, top-centre.
            VStack {
                rangeChip
                Spacer()
            }
            .padding(.top, 8)

            // 3) Bottom summary card, pinned near the bottom edge.
            VStack {
                Spacer()
                summaryCard
                    .padding(.horizontal, 14)
                    .padding(.bottom, 10)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    // MARK: Range chip

    private var rangeChip: some View {
        HStack(spacing: 9) {
            Circle()
                .fill(Theme.phosphor)
                .frame(width: 8, height: 8)
                .phosphorGlow(Theme.phosphor, radius: 6)

            Text("\(engine.mapCount) CONTAMINANTS IN RANGE")
                .font(Theme.mono(16))
                .foregroundStyle(Theme.phosphorBright)
                .tracking(0.5)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .liquidGlass(in: Capsule(), tint: Theme.phosphor.opacity(0.18))
        .overlay(
            Capsule().stroke(Theme.phosphor.opacity(0.30), lineWidth: 1)
        )
    }

    // MARK: Summary card

    private var summaryCard: some View {
        let target = engine.target
        return HStack(spacing: 14) {
            // Left — toxicity swatch with red-star count.
            RoundedRectangle(cornerRadius: 9)
                .fill(engine.color(target.badness, 0.92))
                .frame(width: 44, height: 44)
                .overlay(
                    Text("\(target.red)")
                        .font(Theme.mono(30))
                        .foregroundStyle(Theme.bgDeep)
                )
                .phosphorGlow(engine.color(target.badness), radius: 7)

            // Middle — hottest-signal readout.
            VStack(alignment: .leading, spacing: 1) {
                Text("HOTTEST SIGNAL")
                    .font(Theme.mono(13))
                    .foregroundStyle(Theme.phosphor.opacity(0.55))
                    .tracking(0.5)

                Text(target.name)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.inkBright)
                    .lineLimit(1)

                Text("\(target.distLabel) · \(target.ratingLabel)★")
                    .font(Theme.mono(15))
                    .foregroundStyle(Theme.phosphor.opacity(0.55))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Right — scan trigger.
            Button(action: onScan) {
                Text("▸ SCAN")
                    .font(Theme.mono(18))
                    .foregroundStyle(Theme.phosphor)
                    .tracking(0.5)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .liquidGlass(in: Capsule(), tint: Theme.phosphor.opacity(0.18), interactive: true)
                    .overlay(
                        Capsule().stroke(Theme.phosphor.opacity(0.45), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .instrumentPanel(cornerRadius: 12)
    }
}

#Preview {
    NavigationStack {
        MapScreen(engine: DetectorEngine(), onScan: {})
    }
    .preferredColorScheme(.dark)
}
