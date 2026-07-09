import SwiftUI

/// The hero instrument screen: a handheld "review Geiger counter". A branded header,
/// the single unified detector face (point at a business to AIM, read the centre needle
/// / CPM / status for MAGNITUDE), and a Liquid-Glass audio toggle that brings the
/// crackle to life. The SIM disclaimer sits above the face, beside the named verdict.
struct DetectorScreen: View {
    var engine: DetectorEngine
    var placesProvider: PlacesProvider
    var onAbout: () -> Void = {}

    @Environment(AppSettings.self) private var settings

    var body: some View {
        // The detector is ONE fixed instrument screen (Apple's Compass / Level pattern):
        // the face fills the viewport so nothing — least of all the scope — hides below a
        // scroll. The ScrollView only ever engages as a safety valve at the very largest
        // Dynamic Type sizes; `minHeight: viewport` keeps it inert in normal use.
        GeometryReader { geo in
            ScrollView {
                VStack(spacing: 12) {
                    header
                    // Honesty: the explicit "SIMULATED · NOT A REAL RATING" disclaimer sits
                    // ABOVE the face so it stands beside the named-business star verdict in
                    // the identity caption.
                    if engine.target.ratingSource == .simulated {
                        simBadge
                    }
                    DetectorFaceView(engine: engine)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .padding(16)
                .frame(minHeight: geo.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .background(Color.clear)
        // The device status strip is PINNED above the tab bar as fixed housing chrome, so
        // the dosimeter + audio toggle are always visible and never scroll behind the bar.
        .safeAreaInset(edge: .bottom, spacing: 0) { deviceStatusStrip }
        .toolbar(.hidden, for: .navigationBar)
        // Keep the engine's relative-reading gate in lockstep with the setting (flipped
        // from the face's RELATIVE toggle), without the engine ever importing AppSettings.
        .onAppear { engine.relativeReadingEnabled = settings.relativeReading }
        .onChange(of: settings.relativeReading) {
            engine.relativeReadingEnabled = settings.relativeReading
        }
    }

    // MARK: Header

    /// The device's engraved label plate — the RADIOACTIVE wordmark + info + live pills
    /// recessed into a chrome panel, so the header reads as part of the housing rather
    /// than floating chrome on black.
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
            Button(action: onAbout) {
                Image(systemName: "info.circle")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.phosphor.opacity(0.7))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("About RADIOACTIVE")
            // SourcePill states the DATA SOURCE (absolute provenance). The READING verdict
            // that used to sit here (StatusPill) now reads out with the Geiger meter as
            // StatusWord, so the header stays quiet and un-duplicated.
            SourcePill(source: placesProvider.source, throttled: placesProvider.throttled)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            LinearGradient(colors: [Theme.panelBottom.opacity(0.9), Theme.bg.opacity(0.55)],
                           startPoint: .top, endPoint: .bottom),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Theme.phosphor.opacity(0.16), lineWidth: 1)
        )
    }

    /// "These stars are made up." The amber stand-in flag shown above the face when no
    /// real rating provider has matched the active (real) place yet.
    private var simBadge: some View {
        Text(placesProvider.throttled ? "QUOTA REACHED · STAND-IN READING"
                                      : "SIMULATED · NOT A REAL RATING")
            .font(Theme.mono(12))
            .tracking(0.5)
            .foregroundStyle(Theme.amber)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Capsule().fill(Theme.amber.opacity(0.12)))
            .overlay(Capsule().stroke(Theme.amber.opacity(0.40), lineWidth: 1))
            .accessibilityLabel("Simulated reading, not a real rating")
    }

    // MARK: Device status strip

    /// The housing's base chrome bar — the running dosimeter + discovered tally on the
    /// left, the Geiger-audio toggle on the right. Reads as the bottom of the device,
    /// distinct from the instrument face above it.
    private var deviceStatusStrip: some View {
        HStack(spacing: 12) {
            DosimeterChip(engine: engine)
            Spacer(minLength: 8)
            audioToggle
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(colors: [Theme.panelBottom, Theme.bgDeep],
                           startPoint: .top, endPoint: .bottom)
        )
        // A phosphor hairline seams it to the instrument above — the base of the device.
        .overlay(alignment: .top) {
            Rectangle().fill(Theme.phosphor.opacity(0.22)).frame(height: 1)
        }
    }

    /// Compact Geiger-audio toggle — the old full-width button distilled to a pill that
    /// fills phosphor when live, so it sits in the status strip without shouting.
    private var audioToggle: some View {
        Button(action: engine.toggleAudio) {
            HStack(spacing: 7) {
                Image(systemName: engine.audioOn ? "speaker.wave.2.fill" : "speaker.slash.fill")
                Text(engine.audioOn ? "AUDIO ON" : "AUDIO")
            }
            .font(Theme.mono(16))
            .tracking(0.5)
            .foregroundStyle(engine.audioOn ? Theme.bgDeep : Theme.phosphor.opacity(0.85))
            .padding(.horizontal, 14)
            .frame(height: 38)
            .background {
                Capsule().fill(engine.audioOn ? Theme.phosphor : Theme.phosphor.opacity(0.10))
            }
            .overlay(Capsule().stroke(Theme.phosphor.opacity(engine.audioOn ? 0.5 : 0.3), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(engine.audioOn ? "Geiger audio on, crackle live" : "Enable Geiger audio")
    }
}

/// The data-source provenance pill — the lone chip in the header, stating absolutely
/// where the roster came from (never the reading). Live green for a real ratings
/// provider, amber for a simulated stand-in, red when Google's quota threw us back
/// onto MapKit geometry.
private struct SourcePill: View {
    let source: PlacesProvider.Source
    let throttled: Bool

    private var label: String {
        if throttled { return "THROTTLED" }
        switch source {
        case .google, .tripAdvisor: return "LIVE"
        case .mapKit:               return "SIM"
        case .demo:                 return "DEMO"
        }
    }

    private var tint: Color {
        if throttled { return Theme.danger }
        switch source {
        case .google, .tripAdvisor: return Theme.phosphor
        case .mapKit, .demo:        return Theme.amber
        }
    }

    var body: some View {
        Text(label)
            .font(Theme.mono(12))
            .tracking(1)
            .foregroundStyle(tint)
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .background(Capsule().fill(tint.opacity(0.12)))
            .overlay(Capsule().stroke(tint.opacity(0.40), lineWidth: 1))
            .accessibilityLabel("Data source \(label)")
    }
}
