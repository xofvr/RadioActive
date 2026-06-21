import SwiftUI

/// The full field report on one gloriously contaminated establishment — a pushed
/// dossier. Header readout, the big red-star verdict, three instrument stat cards,
/// a rating-breakdown histogram, field-report quotes, and the actions row that
/// either re-aims the detector here or files the place to the log.
struct DetailScreen: View {
    let place: Place
    var engine: DetectorEngine
    var onDetect: () -> Void

    /// Hazard colour for this place's badness, on the active palette.
    private var hazard: Color { engine.color(place.badness) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                verdict
                statsRow
                ratingBreakdown
                fieldReports
                actionsRow
            }
            .padding(18)
        }
        .background(Theme.bg)
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle(place.short)
        .toolbarBackground(.hidden, for: .navigationBar)
        // Reclaim the bottom for the primary actions — the tab bar would
        // otherwise sit over "DETECT FROM HERE".
        .toolbar(.hidden, for: .tabBar)
    }

    // MARK: 1 — Header

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("\(place.type) · \(place.distLabel)")
                    .font(Theme.mono(16))
                    .foregroundStyle(hazard)
                Text(place.name)
                    .font(.system(size: 29, weight: .bold))
                    .foregroundStyle(Theme.inkBright)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(engine.color(place.badness, 0.95))
                .frame(width: 58, height: 58)
                .overlay(
                    Text("\(place.red)")
                        .font(Theme.mono(34))
                        .foregroundStyle(Theme.bgDeep)
                )
                .phosphorGlow(hazard, radius: 18)
        }
    }

    // MARK: 2 — Red-star verdict

    private var verdict: some View {
        HStack(alignment: .center) {
            RedStars(red: place.red, size: 28)
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text("RED STARS")
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.inkMuted)
                Text("\(place.red) / 5")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(hazard)
            }
        }
    }

    // MARK: 3 — Instrument stat cards

    private var statsRow: some View {
        HStack(spacing: 10) {
            statCard(label: "PEAK CPM",
                     value: "\(place.peakCPM)",
                     valueColor: Theme.danger,
                     tint: Theme.danger)
            statCard(label: "REVIEWS",
                     value: "\(place.reviews)",
                     valueColor: Theme.phosphorBright,
                     tint: Theme.phosphor)
            statCard(label: "DAYS SINCE 5★",
                     value: "\(place.daysSinceGood)",
                     valueColor: Theme.phosphorBright,
                     tint: Theme.phosphor)
        }
    }

    private func statCard(label: String, value: String, valueColor: Color, tint: Color) -> some View {
        VStack(spacing: 6) {
            Text(label)
                .font(Theme.mono(14))
                .foregroundStyle(Theme.inkMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(value)
                .font(Theme.mono(34))
                .foregroundStyle(valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(tint.opacity(0.30), lineWidth: 1)
        )
    }

    // MARK: 4 — Rating breakdown

    private var ratingBreakdown: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("▮ RATING BREAKDOWN")
            VStack(spacing: 9) {
                ForEach(place.ratingBars) { bar in
                    HStack(spacing: 8) {
                        Text("\(bar.star)★")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.inkMuted)
                            .frame(width: 26, alignment: .leading)
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(Color.white.opacity(0.06))
                                Capsule()
                                    .fill(barColor(bar))
                                    .frame(width: max(0, geo.size.width * bar.pct))
                            }
                        }
                        .frame(height: 7)
                        Text("\(bar.count)")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.inkMuted)
                            .frame(width: 44, alignment: .trailing)
                    }
                }
            }
        }
        .padding(14)
        .instrumentPanel()
    }

    private func barColor(_ bar: RatingBar) -> Color {
        if bar.isHot { return Theme.danger }
        if bar.isMid { return Theme.amber }
        return Theme.ink.opacity(0.35)
    }

    // MARK: 5 — Field reports

    private var fieldReports: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("▮ FIELD REPORTS")
            ForEach(place.quotes) { quote in
                VStack(alignment: .leading, spacing: 8) {
                    QuoteStars(stars: quote.stars)
                    Text("“\(quote.text)”")
                        .font(.system(size: 14))
                        .italic()
                        .foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("— \(quote.author)")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.inkMuted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Theme.phosphor.opacity(0.22), lineWidth: 1)
                )
            }
        }
    }

    // MARK: 6 — Actions

    private var actionsRow: some View {
        HStack(spacing: 12) {
            Button(action: onDetect) {
                Text("▸ DETECT FROM HERE")
                    .font(Theme.mono(20))
                    .foregroundStyle(Theme.phosphorBright)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .liquidGlass(in: RoundedRectangle(cornerRadius: 14, style: .continuous),
                                 tint: Theme.phosphor.opacity(0.22),
                                 interactive: true)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Theme.phosphor.opacity(0.5), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)

            Button {
                engine.toggleLog(place)
            } label: {
                let logged = engine.isLogged(place)
                Image(systemName: logged ? "bookmark.fill" : "bookmark")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(logged ? Theme.phosphorBright : Theme.phosphor)
                    .frame(width: 54, height: 54)
                    .liquidGlass(in: RoundedRectangle(cornerRadius: 14, style: .continuous),
                                 tint: logged ? Theme.phosphor : nil,
                                 interactive: true)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(engine.isLogged(place) ? "Remove from log" : "Add to log")
        }
        .padding(.top, 4)
    }

    // MARK: Helpers

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(Theme.mono(15))
            .foregroundStyle(Theme.phosphor.opacity(0.6))
    }
}
