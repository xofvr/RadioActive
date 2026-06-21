import SwiftUI

/// The map tab. Toggles between the stylised **radar** scope and a real **Apple
/// Map** (MapKit) — both plot the same contaminants. A floating range chip + a
/// data-source readout sit up top; the hottest-signal card is pinned at the
/// bottom with a SCAN shortcut to the detector.
struct MapScreen: View {
    var engine: DetectorEngine
    var onScan: () -> Void
    var locationService: LocationService
    var placesProvider: PlacesProvider

    enum MapMode: String, CaseIterable, Identifiable {
        case radar = "RADAR", map = "MAP"
        var id: String { rawValue }
    }

    @State private var mode: MapMode = MapScreen.initialMode

    private static var initialMode: MapMode {
        #if DEBUG
        if UserDefaults.standard.string(forKey: "RAD_MAPMODE") == "map" { return .map }
        #endif
        return .radar
    }

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()

            Group {
                if mode == .radar {
                    RadarView(engine: engine)
                        .padding(.horizontal, 22)
                        .offset(y: -6)
                } else {
                    LiveMapView(engine: engine, base: locationService.coordinate)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(Theme.phosphor.opacity(0.25), lineWidth: 1)
                        )
                        .padding(.horizontal, 12)
                        .padding(.top, 116)
                        .padding(.bottom, 104)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Top stack — range chip, view toggle, source readout.
            VStack(spacing: 10) {
                rangeChip
                modeToggle
                Text(placesProvider.statusLabel)
                    .font(Theme.mono(11))
                    .tracking(1)
                    .foregroundStyle(Theme.phosphor.opacity(0.4))
                Spacer()
            }
            .padding(.top, 8)

            // Bottom summary card.
            VStack {
                Spacer()
                summaryCard
                    .padding(.horizontal, 14)
                    .padding(.bottom, 10)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    // MARK: View toggle

    private var modeToggle: some View {
        HStack(spacing: 0) {
            ForEach(MapMode.allCases) { m in
                Button {
                    withAnimation(.snappy(duration: 0.2)) { mode = m }
                } label: {
                    Text(m.rawValue)
                        .font(Theme.mono(15))
                        .tracking(1)
                        .foregroundStyle(mode == m ? Theme.bgDeep : Theme.phosphor)
                        .frame(width: 88, height: 30)
                        .background {
                            if mode == m { Capsule().fill(Theme.phosphor) }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .liquidGlass(in: Capsule())
        .overlay(Capsule().stroke(Theme.phosphor.opacity(0.3), lineWidth: 1))
        .accessibilityLabel("Map view mode")
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
            RoundedRectangle(cornerRadius: 9)
                .fill(engine.color(target.badness, 0.92))
                .frame(width: 44, height: 44)
                .overlay(
                    Text("\(target.red)")
                        .font(Theme.mono(30))
                        .foregroundStyle(Theme.bgDeep)
                )
                .phosphorGlow(engine.color(target.badness), radius: 7)

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
