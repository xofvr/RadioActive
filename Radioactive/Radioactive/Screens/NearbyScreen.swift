import SwiftUI

/// The leaderboard of the worst places — a scannable, worst-first chart.
/// Filter chips ride on Liquid Glass; the ranked list lives inside a single
/// dark instrument panel, each row pushing the full contamination report.
struct NearbyScreen: View {
    var engine: DetectorEngine
    @State private var filter: NearbyFilter = .all

    private let hPad: CGFloat = 14

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                filterChips
                rankedList
            }
            .padding(.top, 4)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .background(Theme.bg)
        .navigationTitle("Hottest Nearby")
        .navigationBarTitleDisplayMode(.large)
    }

    // MARK: Filter chips

    private var filterChips: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 10) {
                ForEach(NearbyFilter.allCases) { f in
                    chip(f)
                }
            }
            .padding(.horizontal, hPad)
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
    }

    private func chip(_ f: NearbyFilter) -> some View {
        let active = f == filter
        return Button {
            withAnimation(.snappy(duration: 0.22)) { filter = f }
        } label: {
            Text(f.rawValue)
                .font(Theme.mono(17))
                .tracking(0.5)
                .foregroundStyle(active ? Theme.phosphorBright : Theme.inkMuted)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background {
                    if active {
                        Capsule().fill(Color.clear)
                            .liquidGlass(in: Capsule(), tint: Theme.phosphor.opacity(0.18), interactive: true)
                            .overlay(Capsule().stroke(Theme.phosphor.opacity(0.5), lineWidth: 1))
                    } else {
                        Capsule()
                            .stroke(Theme.phosphor.opacity(0.22), lineWidth: 1)
                    }
                }
                .phosphorGlow(active ? Theme.phosphor : .clear, radius: active ? 5 : 0)
        }
        .buttonStyle(.plain)
    }

    // MARK: Ranked list

    private var rankedList: some View {
        let places = engine.nearby(filter)
        return LazyVStack(spacing: 0) {
            ForEach(Array(places.enumerated()), id: \.element.id) { index, place in
                NavigationLink(value: place) {
                    row(index: index, place: place)
                }
                .buttonStyle(.plain)

                if index < places.count - 1 {
                    Divider()
                        .overlay(Color.white.opacity(0.05))
                        .padding(.leading, hPad)
                }
            }
        }
        .instrumentPanel(cornerRadius: 12)
        .padding(.horizontal, hPad)
    }

    private func row(index: Int, place: Place) -> some View {
        let danger = engine.color(place.badness, 0.92)
        return HStack(spacing: 12) {
            Text("\(index + 1)")
                .font(Theme.mono(26))
                .foregroundStyle(Theme.inkMuted)
                .frame(width: 26, alignment: .center)

            badge(place: place, danger: danger)

            VStack(alignment: .leading, spacing: 5) {
                Text(place.name)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.inkBright)
                    .lineLimit(1)

                Text("\(place.type) · \(place.distLabel) · \(place.ratingLabel)★")
                    .font(Theme.mono(15))
                    .foregroundStyle(Theme.phosphor.opacity(0.5))
                    .lineLimit(1)

                badnessBar(place: place, danger: danger)
                    .padding(.top, 1)
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.inkMuted)
        }
        .padding(.horizontal, hPad)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    private func badge(place: Place, danger: Color) -> some View {
        RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(danger)
            .frame(width: 40, height: 40)
            .overlay(
                Text("\(place.red)")
                    .font(Theme.mono(27))
                    .foregroundStyle(Theme.bgDeep)
            )
            .phosphorGlow(danger, radius: 5)
    }

    private func badnessBar(place: Place, danger: Color) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.07))
                Capsule()
                    .fill(danger)
                    .frame(width: max(0, geo.size.width * place.badness))
            }
        }
        .frame(height: 4)
    }
}
