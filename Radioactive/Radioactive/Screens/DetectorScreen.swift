import SwiftUI

/// The hero instrument screen: a handheld "review Geiger counter". A branded
/// header, the dose gauge with the target's red-star rating and live CPM readout,
/// the oscilloscope strip, an "aiming at" card that pushes the field report, and a
/// Liquid-Glass audio toggle that brings the crackle to life.
struct DetectorScreen: View {
    var engine: DetectorEngine
    var placesProvider: PlacesProvider
    var onAbout: () -> Void = {}

    @Environment(AppSettings.self) private var settings

    /// Fires the "CONTAMINANT LOGGED" stamp ONLY on an explicit quick-log ADD.
    /// Driving the stamp off `isLogged(target)` would mis-fire when NEXT / compass
    /// auto-snap lands on an already-bookmarked place.
    @State private var logPulse = false

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                header
                heroToggle
                // Honesty: the explicit "SIMULATED · NOT A REAL RATING" disclaimer
                // sits ABOVE the hero so it stands beside the named-business star
                // verdict in BOTH gauge and compass modes (the compass RedStars lock
                // panel otherwise carried only the terse SIM SourcePill).
                if engine.target.ratingSource == .simulated {
                    simBadge
                }
                if settings.useCompass {
                    CompassView(engine: engine)
                } else {
                    gaugePanel
                }
                aimingCard
                audioButton
            }
            .padding(16)
        }
        .background(Color.clear)
        .toolbar(.hidden, for: .navigationBar)
        // Keep the engine's relative-reading gate in lockstep with the setting,
        // without the engine ever importing AppSettings.
        .onAppear { engine.relativeReadingEnabled = settings.relativeReading }
        .onChange(of: settings.relativeReading) {
            engine.relativeReadingEnabled = settings.relativeReading
        }
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
            Button(action: onAbout) {
                Image(systemName: "info.circle")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.phosphor.opacity(0.7))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("About RADIOACTIVE")
            // StatusPill describes the READING (relative); SourcePill describes the
            // DATA SOURCE (absolute provenance). They sit side by side, distinct jobs.
            SourcePill(source: placesProvider.source, throttled: placesProvider.throttled)
            StatusPill(engine: engine)
        }
    }

    // MARK: Hero + reading toggles

    /// GAUGE | COMPASS hero selector with a RELATIVE reading toggle riding alongside.
    /// Replicates MapScreen's capsule styling (no shared component exists).
    private var heroToggle: some View {
        HStack(spacing: 10) {
            HStack(spacing: 0) {
                segment("GAUGE", active: !settings.useCompass) { settings.useCompass = false }
                segment("COMPASS", active: settings.useCompass) { settings.useCompass = true }
            }
            .padding(3)
            .liquidGlass(in: Capsule())
            .overlay(Capsule().stroke(Theme.phosphor.opacity(0.3), lineWidth: 1))
            .accessibilityLabel("Hero instrument")

            Spacer(minLength: 0)

            // RELATIVE reading toggle — normalises the live reading to the local field.
            Button {
                settings.relativeReading.toggle()
            } label: {
                Text("RELATIVE")
                    .font(Theme.mono(13))
                    .tracking(1)
                    .foregroundStyle(settings.relativeReading ? Theme.bgDeep : Theme.phosphor)
                    .padding(.horizontal, 12)
                    .frame(height: 30)
                    .background {
                        if settings.relativeReading { Capsule().fill(Theme.phosphor) }
                    }
                    .padding(3)
                    .liquidGlass(in: Capsule())
                    .overlay(Capsule().stroke(Theme.phosphor.opacity(0.3), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Relative reading")
            .accessibilityValue(settings.relativeReading ? "On" : "Off")
        }
    }

    private func segment(_ title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.snappy(duration: 0.2)) { action() }
        } label: {
            Text(title)
                .font(Theme.mono(15))
                .tracking(1)
                .foregroundStyle(active ? Theme.bgDeep : Theme.phosphor)
                .frame(width: 88, height: 30)
                .background {
                    if active { Capsule().fill(Theme.phosphor) }
                }
        }
        .buttonStyle(.plain)
    }

    // MARK: Gauge panel

    private var gaugePanel: some View {
        VStack(spacing: 14) {
            HStack(spacing: 8) {
                Text(engine.deviceHeading != nil ? "◎ POINT TO SCAN" : "▮ RAD DETECTOR")
                    .font(Theme.mono(15))
                    .foregroundStyle(Theme.phosphor.opacity(0.7))
                // The reading is normalised to the local field — flag it honestly.
                if engine.relativeReadingEnabled {
                    Text("RELATIVE")
                        .font(Theme.mono(11))
                        .tracking(1)
                        .foregroundStyle(Theme.phosphor.opacity(0.7))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .overlay(Capsule().stroke(Theme.phosphor.opacity(0.35), lineWidth: 1))
                }
                Spacer()
                // Quick-log the active target without opening its report. Only an
                // ADD (was-not-logged → now-logged) pulses the stamp; the pulse
                // re-arms a moment later so the next add fires again.
                Button {
                    let wasLogged = engine.isLogged(engine.target)
                    engine.toggleLog(engine.target)
                    if !wasLogged && engine.isLogged(engine.target) {
                        logPulse = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { logPulse = false }
                    }
                } label: {
                    Image(systemName: engine.isLogged(engine.target) ? "bookmark.fill" : "bookmark")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(engine.isLogged(engine.target) ? Theme.phosphorBright : Theme.phosphor.opacity(0.55))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(engine.isLogged(engine.target) ? "Remove from log" : "Add to log")
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

            // Field-survey readouts — shared with the compass hero (HeroReadouts).
            HStack {
                DosimeterChip(engine: engine)
                Spacer()
                ProximityCue(engine: engine)
            }
        }
        .padding(16)
        .instrumentPanel()
        // An explicit quick-log ADD flashes the "CONTAMINANT LOGGED" stamp — not a
        // target switch onto an already-bookmarked place.
        .logStamp(trigger: logPulse)
    }

    /// "These stars are made up." The amber stand-in flag shown under the hero when no
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

/// The data-source provenance pill — sits beside `StatusPill` in the header and
/// states, absolutely, where the roster came from (never the reading). Live green
/// for a real ratings provider, amber for a simulated stand-in, red when Google's
/// quota threw us back onto MapKit geometry.
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
