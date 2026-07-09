import SwiftUI

/// First-run onboarding + the always-reachable About/disclaimer. This is the App
/// Review shield and the defamation framing: it states plainly that the red stars are a
/// satirical inversion of public ratings, never a food-safety claim. On first run its
/// button primes the location prompt (so the system prompt arrives with context).
struct AboutSheet: View {
    var isFirstRun: Bool
    var onPrimary: () -> Void

    @Environment(AppSettings.self) private var settings

    private let contactEmail = "reports@radioactive.app"

    var body: some View {
        @Bindable var settings = settings
        return ZStack {
            Theme.bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    paragraph("RADIOACTIVE is a **novelty toy**. It finds nearby food & drink places and flips their public star ratings — the **lower** the rating, the **hotter** it reads here. Red stars, “rads” and Geiger clicks are an inverted re-score for entertainment.")
                    callout("This is NOT a food-safety, hygiene, or FSA rating, and makes no claim about the real quality, cleanliness, or safety of any business.")
                    if GooglePlacesConfig.isConfigured {
                        paragraph("Places are discovered via **Apple Maps (MapKit)** and scored from **Google** ratings. Where a place has a real Google rating the reading is real; any place without one stays **SIMULATED** — a deterministic stand-in, clearly flagged, never presented as a real rating.")
                        Toggle(isOn: $settings.liveRatings) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("LIVE DATA — real Google ratings")
                                    .font(Theme.mono(15))
                                    .foregroundStyle(Theme.phosphorBright)
                                Text("Off by default. Uses your Google quota only while on.")
                                    .font(.system(size: 13))
                                    .foregroundStyle(Theme.ink.opacity(0.7))
                            }
                        }
                        .tint(Theme.phosphor)
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.phosphor.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.phosphor.opacity(0.35), lineWidth: 1))
                        .accessibilityLabel("Live data, real Google ratings")
                        .accessibilityValue(settings.liveRatings ? "On" : "Off")
                    } else {
                        paragraph("Places are discovered via **Apple Maps (MapKit)**. Until a verified ratings source is connected, every reading is **SIMULATED** — a deterministic stand-in, clearly flagged, never presented as a real rating.")
                    }
                    Toggle(isOn: $settings.haptics) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("HAPTICS — tactile detection")
                                .font(Theme.mono(15))
                                .foregroundStyle(Theme.phosphorBright)
                            Text("Geiger clicks and the lock cue buzz — works with sound off.")
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.ink.opacity(0.7))
                        }
                    }
                    .tint(Theme.phosphor)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.phosphor.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.phosphor.opacity(0.35), lineWidth: 1))
                    .accessibilityLabel("Haptics, tactile detection")
                    .accessibilityValue(settings.haptics ? "On" : "Off")
                    paragraph("Found something wrong? Tap **Report / request removal** on any place, or email **\(contactEmail)** and we'll take it down.")
                    primaryButton
                }
                .padding(22)
            }
        }
        .presentationDragIndicator(.visible)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "dot.radiowaves.up.forward")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(Theme.phosphor)
                .phosphorGlow(Theme.phosphor, radius: 8)
            Text("RADIOACTIVE")
                .font(Theme.mono(28))
                .tracking(3)
                .foregroundStyle(Theme.phosphorBright)
                .phosphorGlow(Theme.phosphor, radius: 8)
        }
        .padding(.top, 8)
    }

    private func paragraph(_ markdown: LocalizedStringKey) -> some View {
        Text(markdown)
            .font(.system(size: 16))
            .foregroundStyle(Theme.ink)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func callout(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Theme.amber)
            .fixedSize(horizontal: false, vertical: true)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.amber.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.amber.opacity(0.4), lineWidth: 1))
    }

    private var primaryButton: some View {
        Button(action: onPrimary) {
            Text(isFirstRun ? "▸ BEGIN SCAN" : "DONE")
                .font(Theme.mono(22))
                .tracking(1)
                .foregroundStyle(Theme.bgDeep)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(Theme.phosphor, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .phosphorGlow(Theme.phosphor, radius: 10)
        }
        .buttonStyle(.plain)
        .padding(.top, 4)
        .accessibilityLabel(isFirstRun ? "Begin scan" : "Done")
    }
}
