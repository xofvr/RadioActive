import SwiftUI

/// The field log — every contaminant you've personally bookmarked, kept as durable
/// `LoggedEntry` snapshots so the list survives even when a place drifts out of range
/// or off the current roster. Each row's red stars are FROZEN at log time (absolute);
/// rows whose place is still live push the full report, the rest sit as plain records.
struct LogbookScreen: View {
    var engine: DetectorEngine

    private let hPad: CGFloat = 14

    /// Newest first — a logbook reads like a journal, most recent entry on top.
    private var entries: [LoggedEntry] {
        engine.loggedEntries.sorted { $0.date > $1.date }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if entries.isEmpty {
                    emptyState
                } else {
                    loggedList
                }
            }
            .padding(.top, 4)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .background(Theme.bg)
        .navigationTitle("Field Log")
        .navigationBarTitleDisplayMode(.large)
    }

    // MARK: Empty state

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "books.vertical")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(Theme.phosphor.opacity(0.5))
                .phosphorGlow(Theme.phosphor, radius: 6)
            Text("NO CONTAMINANTS LOGGED")
                .font(Theme.mono(16))
                .tracking(1)
                .foregroundStyle(Theme.phosphorBright)
            Text("Bookmark a place from the detector or its report to file it here.")
                .font(.system(size: 14))
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
        .padding(.horizontal, 28)
    }

    // MARK: Logged list

    private var loggedList: some View {
        let items = entries
        return LazyVStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, entry in
                // Push the live report only if the place is still on the roster;
                // out-of-range snapshots render as plain (non-pushing) records.
                if let live = engine.places.first(where: { $0.logKey == entry.logKey }) {
                    NavigationLink(value: live) {
                        row(index: index, entry: entry, isLive: true)
                    }
                    .buttonStyle(.plain)
                } else {
                    row(index: index, entry: entry, isLive: false)
                }

                if index < items.count - 1 {
                    Divider()
                        .overlay(Color.white.opacity(0.05))
                        .padding(.leading, hPad)
                }
            }
        }
        .instrumentPanel(cornerRadius: 12)
        .padding(.horizontal, hPad)
    }

    private func row(index: Int, entry: LoggedEntry, isLive: Bool) -> some View {
        // Colour derives ONLY from the frozen red — absolute, never the local field.
        let danger = engine.color(Double(entry.red) / 5.0, 0.92)
        return HStack(spacing: 12) {
            Text("\(index + 1)")
                .font(Theme.mono(26))
                .foregroundStyle(Theme.inkMuted)
                .frame(width: 26, alignment: .center)

            badge(entry: entry, danger: danger)

            VStack(alignment: .leading, spacing: 5) {
                Text(entry.name)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.inkBright)
                    .lineLimit(1)

                Text("\(entry.type) · \(dateLabel(entry.date))")
                    .font(Theme.mono(15))
                    .foregroundStyle(Theme.phosphor.opacity(0.5))
                    .lineLimit(1)

                HStack(spacing: 8) {
                    RedStars(red: entry.red, size: 13, spacing: 3, showGlow: false)
                    if entry.ratingSource == "simulated" { simTag }
                }
                .padding(.top, 1)
            }

            Spacer(minLength: 8)

            if isLive {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.inkMuted)
            }
        }
        .padding(.horizontal, hPad)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    private func badge(entry: LoggedEntry, danger: Color) -> some View {
        RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(danger)
            .frame(width: 40, height: 40)
            .overlay(
                Text("\(entry.red)")
                    .font(Theme.mono(27))
                    .foregroundStyle(Theme.bgDeep)
            )
            .phosphorGlow(danger, radius: 5)
    }

    /// Amber honesty flag — this entry's stars were a deterministic stand-in.
    private var simTag: some View {
        Text("SIMULATED")
            .font(Theme.mono(11))
            .tracking(0.5)
            .foregroundStyle(Theme.amber)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Capsule().fill(Theme.amber.opacity(0.12)))
            .overlay(Capsule().stroke(Theme.amber.opacity(0.40), lineWidth: 1))
    }

    private func dateLabel(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }
}
