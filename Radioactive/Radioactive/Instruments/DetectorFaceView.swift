import SwiftUI

/// The single, unified detector — TWO stacked instrument zones that read top-to-bottom
/// as one act: AIM, then READ.
///
///   • ZONE 1 — AIM (compass): the aimed business's name + absolute red-star verdict sit
///     ON TOP of a slim bearing ring; the forward reticle, the widening confidence cone,
///     and one blip per contaminant show DIRECTION. Nothing crowds the centre — it's a
///     clean radar you point with.
///   • ZONE 2 — READ (Geiger, the hero): the big bottom-hinged needle sweeps the danger
///     arc, with the live CPM, status word, proximity trend and oscilloscope trace reading
///     MAGNITUDE. This zone owns the screen — the counter is unmistakably the star.
///
/// The two zones fill one screen (no scroll): the compass is capped, the Geiger dial takes
/// the rest. HONESTY: the meter (needle / CPM / status / scope) and blip COLOUR are the
/// RELATIVE reading (`engine.rads` / `readingBadness`); the identity caption's
/// `RedStars(red:)` is the ABSOLUTE `Place.red`, never recoloured.
struct DetectorFaceView: View {
    var engine: DetectorEngine
    @Environment(AppSettings.self) private var settings

    /// Slow heartbeat driving the compass origin "ping" and the calibrate-chip pulse.
    @State private var pulse = false
    /// Fires the "CONTAMINANT LOGGED" stamp ONLY on an explicit quick-log ADD — never a
    /// NEXT / auto-snap onto an already-bookmarked place.
    @State private var logPulse = false

    private let cardinals: [(label: String, bearing: Double)] = [
        ("N", 0), ("E", 90), ("S", 180), ("W", 270),
    ]

    var body: some View {
        VStack(spacing: 10) {
            // Slim secondary controls — the honesty toggle + quick-log, kept out of the way.
            controlsRow

            // ── ZONE 1 · AIM ─────────────────────────────────────────────
            // The named verdict sits ON TOP of the compass, so you always see WHAT you're
            // pointing at while you aim.
            identityCaption
            compass
                .frame(maxWidth: .infinity, maxHeight: compassCap)
            aimCues

            zoneDivider

            // ── ZONE 2 · READ (hero) ─────────────────────────────────────
            geiger
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(16)
        // Curvy, genz housing that hugs the modern phone; the Geiger soul stays inside it.
        .instrumentPanel(cornerRadius: 22)
        // An explicit quick-log ADD flashes the stamp — not a target switch onto an
        // already-bookmarked place.
        .logStamp(trigger: logPulse)
        .onAppear {
            withAnimation(.easeInOut(duration: 1).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }

    /// The compass is the SECONDARY instrument, so it's capped — the Geiger dial below
    /// claims all remaining height and reads as the hero.
    private let compassCap: CGFloat = 250

    // MARK: Controls row

    /// RELATIVE reading toggle · (spacer) · quick-log bookmark. The old title / NEXT are
    /// gone — the hint line and the "+N MORE THIS WAY" pill carry that state without the
    /// standing chrome.
    private var controlsRow: some View {
        HStack(spacing: 10) {
            relativeToggle
            Spacer(minLength: 8)
            bookmarkButton
        }
    }

    /// RELATIVE reading toggle — normalises the live reading to the local field. Its
    /// filled-capsule active state doubles as the "RELATIVE" indicator.
    private var relativeToggle: some View {
        Button {
            settings.relativeReading.toggle()
        } label: {
            Text("RELATIVE")
                .font(Theme.mono(12))
                .tracking(0.5)
                .foregroundStyle(settings.relativeReading ? Theme.bgDeep : Theme.phosphor.opacity(0.8))
                .padding(.horizontal, 9)
                .padding(.vertical, 3)
                .background {
                    if settings.relativeReading {
                        Capsule().fill(Theme.phosphor)
                    } else {
                        Capsule().stroke(Theme.phosphor.opacity(0.35), lineWidth: 1)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Relative reading")
        .accessibilityValue(settings.relativeReading ? "On" : "Off")
    }

    /// Quick-log the active target without opening its report. Only an ADD
    /// (was-not-logged → now-logged) pulses the stamp; the pulse re-arms a moment later
    /// so the next add fires again.
    private var bookmarkButton: some View {
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
    }

    // MARK: Identity caption (absolute) — sits ON TOP of the compass

    /// The named-business verdict, floated above the compass so you read WHAT you're
    /// aiming at while you point. Name + ABSOLUTE red stars on one line; lock state +
    /// type·dist·bearing beneath. The whole caption pushes the full field report on tap.
    private var identityCaption: some View {
        let t = engine.target
        return NavigationLink(value: t) {
            VStack(spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(t.name)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Theme.inkBright)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Spacer(minLength: 8)
                    // ABSOLUTE verdict — frozen to Place.red, never the relative reading.
                    RedStars(red: t.red, size: 20, spacing: 2)
                }
                HStack(spacing: 6) {
                    Text(engine.locked ? "◉ ACQUIRED" : "SCANNING…")
                        .foregroundStyle(engine.locked ? Theme.phosphor : Theme.inkMuted)
                    Text("· \(t.type) · \(t.distLabel) · \(t.bearingLabel)")
                        .foregroundStyle(Theme.phosphor.opacity(0.55))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right")
                        .foregroundStyle(Theme.phosphor.opacity(0.45))
                }
                .font(Theme.mono(13))
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Aiming at \(t.name). \(t.red) of 5 red stars. \(engine.locked ? "Target acquired" : "Scanning"). Opens report.")
    }

    // MARK: Compass (direction)

    private var compass: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            ZStack {
                rimRing(side)
                cone(side)
                rotatingDial(side)
                originMarker(side)
                reticle(side)
                blips(side)
            }
            .frame(width: side, height: side)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    /// The slim bearing rim + a soft centre glow — the compass is a halo you point with,
    /// no longer a stack of radar circles competing with the meter.
    private func rimRing(_ s: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(RadialGradient(
                    colors: [Theme.phosphor.opacity(0.05), .clear],
                    center: .center, startRadius: 0, endRadius: s * 0.5))
                .frame(width: s, height: s)
            Circle()
                .stroke(Theme.phosphor.opacity(0.18), lineWidth: 1.5)
                .frame(width: s * 0.92, height: s * 0.92)
        }
    }

    /// The user's origin — a faint "you are here" dot at the centre with a slow radar
    /// ping expanding out of it, so the empty middle reads as a live scope, not a void.
    private func originMarker(_ s: CGFloat) -> some View {
        ZStack {
            Circle()
                .stroke(Theme.phosphor.opacity(0.14), lineWidth: 1)
                .frame(width: s * 0.12, height: s * 0.12)
                .scaleEffect(pulse ? 2.2 : 0.7)
                .opacity(pulse ? 0 : 0.6)
            Circle()
                .fill(Theme.phosphor.opacity(0.75))
                .frame(width: 6, height: 6)
                .phosphorGlow(Theme.phosphor, radius: 3)
        }
        .position(x: s / 2, y: s / 2)
    }

    /// Forward aim cone — a stroked arc ON THE RIM spanning ±half degrees, so it shows the
    /// aim spread without a wedge slicing across the face. Its half-angle is the live
    /// confidence cone: floored at `aimConeDegrees`, VISIBLY WIDENING toward `headingConeMax`
    /// as accuracy degrades (amber while not `.good`). Per-frame via TimelineView, mirroring
    /// rotatingDial — `headingAccuracyDeg` is ObservationIgnored, so `engine.frame` drives it.
    private func cone(_ s: CGFloat) -> some View {
        TimelineView(.animation) { _ in
            _ = engine.frame
            let good = engine.headingConfidence == .good
            // On the Simulator / no-compass demo sweep, deviceHeading == nil and
            // headingAccuracyDeg stays nil, so coneHalfAngle would yawn to its max (60°)
            // while confidence is still .good — a wide cone that looks "very unsure"
            // yet claims certainty. Pin the demo cone to the honest base width instead.
            let half = engine.deviceHeading == nil
                ? DetectorEngine.aimConeDegrees
                : DetectorMath.coneHalfAngle(accuracyDeg: engine.headingAccuracyDeg,
                                             base: DetectorEngine.aimConeDegrees)
            let tint = good ? Theme.phosphor : Theme.amber
            return RimCone(halfAngle: half, radiusFraction: 0.46)
                .stroke(tint.opacity(good ? 0.55 : 0.42),
                        style: StrokeStyle(lineWidth: max(4, s * 0.02), lineCap: .round))
                .frame(width: s, height: s)
                .phosphorGlow(tint, radius: 4)
        }
    }

    /// The cardinal ring, rotated so the dial is heading-up. Small marks just inside the
    /// rim — reference, not the hero. Wrapped in TimelineView(.animation) + `engine.frame`
    /// so it tracks the compass each tick (mirrors ScopeView's per-frame redraw).
    private func rotatingDial(_ s: CGFloat) -> some View {
        TimelineView(.animation) { _ in
            _ = engine.frame
            let heading = engine.heading
            let rr = s * 0.40
            return ZStack {
                ForEach(cardinals, id: \.label) { c in
                    let rad = (c.bearing - heading) * .pi / 180
                    Text(c.label)
                        .font(Theme.mono(c.label == "N" ? 15 : 12))
                        .foregroundStyle(c.label == "N"
                                         ? Theme.phosphorBright
                                         : Theme.phosphor.opacity(0.5))
                        .position(x: s / 2 + sin(rad) * rr, y: s / 2 - cos(rad) * rr)
                }
            }
            .frame(width: s, height: s)
        }
    }

    /// Forward reticle — a crisp chevron just OUTSIDE the rim at 12 o'clock, marking the
    /// exact aim direction. Amber while the signal is uncertain. It doesn't rotate:
    /// forward is always "up" on a heading-up dial.
    private func reticle(_ s: CGFloat) -> some View {
        let tint = engine.headingConfidence == .invalid ? Theme.amber : Theme.phosphorBright
        let cx = s / 2
        let tipY = s / 2 - s * 0.49
        let wing = s * 0.026
        let drop = s * 0.032
        return Path { p in
            p.move(to: CGPoint(x: cx - wing, y: tipY + drop))
            p.addLine(to: CGPoint(x: cx, y: tipY))
            p.addLine(to: CGPoint(x: cx + wing, y: tipY + drop))
        }
        .stroke(tint, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        .frame(width: s, height: s)
        .phosphorGlow(tint, radius: 4)
    }

    // MARK: Blips — contacts on the rim

    private func blips(_ s: CGFloat) -> some View {
        // On the rim at their bearing (distance reads as blip SIZE + brightness, not
        // radius), so a contact never collides with the centre of the scope.
        let rimFrac = 0.46
        // Skip the aimed target — the reticle + identity caption already mark it, so it
        // isn't also piled on the rim under the reticle (which read as clutter).
        return ForEach(engine.compassBlips().filter { !$0.isTarget }) { blip in
            let rad = (blip.bearing - engine.heading) * .pi / 180
            let x = (0.5 + sin(rad) * rimFrac) * s
            let y = (0.5 - cos(rad) * rimFrac) * s
            NavigationLink(value: blip.place) {
                blipView(blip)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(blip.place.name), \(blip.place.red) of 5 red stars")
            .position(x: x, y: y)
        }
    }

    private func blipView(_ blip: CompassBlip) -> some View {
        // Contacts are always NON-target here. COLOUR is RELATIVE (worst-nearby reads hot);
        // honesty-locked numbers live in the identity caption / detail screen, never
        // recoloured. SIZE + brightness read proximity (near = bigger/brighter) now that
        // radius is fixed to the rim.
        let color = engine.color(blip.readingBadness, 0.95)
        let near = 1 - min(1, blip.distance / 560)
        let dot = 9.0 + near * 5.0
        return ZStack {
            Circle()
                .fill(color)
                .frame(width: dot, height: dot)
                .overlay(Circle().stroke(Color.black.opacity(0.4), lineWidth: 1.5))
                .opacity(0.55 + near * 0.45)
                .phosphorGlow(color, radius: 3)

            // Cluster size — how many nearby contaminants collapsed into this contact.
            if blip.count > 1 {
                Text("+\(blip.count - 1)")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Color.black.opacity(0.7)))
                    .overlay(Capsule().stroke(color.opacity(0.8), lineWidth: 1))
                    .offset(x: 13, y: -12)
            }
        }
    }

    // MARK: Aim cues (below the compass)

    /// The conditional aiming cues, stacked tight beneath the compass: the demo/point
    /// hint, the calibrate chip, and the "dense bearing" NEXT pill. Only what's relevant
    /// shows, so the divider below never drifts far.
    private var aimCues: some View {
        VStack(spacing: 6) {
            hint
            calibrateChip
            densePill
        }
    }

    @ViewBuilder
    private var hint: some View {
        if engine.deviceHeading == nil {
            hintText("DEMO SWEEP — POINT ON A REAL DEVICE")
        } else if !engine.locked {
            hintText("POINT YOUR PHONE AT A PLACE.")
        }
    }

    private func hintText(_ s: String) -> some View {
        Text(s)
            .font(Theme.mono(13))
            .foregroundStyle(Theme.phosphor.opacity(0.5))
            .frame(maxWidth: .infinity)
    }

    /// Confidence chip — while a compass is present but uncertain, say so plainly and
    /// persistently (gentler than iOS's figure-8 HUD, which still performs the real recal).
    /// Amber capsule mirrors DetectorScreen.simBadge; pulses when invalid.
    @ViewBuilder
    private var calibrateChip: some View {
        if engine.deviceHeading != nil, engine.headingConfidence != .good {
            let invalid = engine.headingConfidence == .invalid
            HStack(spacing: 6) {
                Image(systemName: invalid ? "circle.dotted" : "wave.3.right")
                Text(invalid ? "◌ CALIBRATE · WAVE PHONE IN A FIGURE-8" : "LOW ACCURACY")
            }
            .font(Theme.mono(12))
            .tracking(0.5)
            .foregroundStyle(Theme.amber)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Capsule().fill(Theme.amber.opacity(0.12)))
            .overlay(Capsule().stroke(Theme.amber.opacity(0.40), lineWidth: 1))
            .opacity(invalid ? (pulse ? 0.6 : 1.0) : 0.9)
            .accessibilityLabel(invalid
                ? "Compass needs calibration. Wave the phone in a figure eight."
                : "Low compass accuracy.")
        }
    }

    /// "Dense bearing" pill — when several places stack inside the forward cone, tell the
    /// user there are more this way and let it cycle through them (the old NEXT button,
    /// now shown only when it has somewhere to go).
    @ViewBuilder
    private var densePill: some View {
        let count = engine.targetsInCone(engine.heading).count
        if count > 1 {
            Button(action: engine.cycleInCone) {
                HStack(spacing: 6) {
                    Image(systemName: "square.stack.3d.up")
                    Text("+\(count - 1) MORE THIS WAY")
                    Image(systemName: "arrow.right")
                }
                .font(Theme.mono(13))
                .tracking(0.5)
                .foregroundStyle(Theme.phosphor)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .liquidGlass(in: Capsule(), tint: Theme.phosphor.opacity(0.18))
                .overlay(Capsule().stroke(Theme.phosphor.opacity(0.3), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(count - 1) more places this way. Next.")
        }
    }

    // MARK: Zone divider

    /// A phosphor hairline seaming the AIM zone to the READ zone — one device face, two
    /// instrument sections.
    private var zoneDivider: some View {
        Rectangle()
            .fill(Theme.phosphor.opacity(0.16))
            .frame(height: 1)
            .padding(.vertical, 2)
    }

    // MARK: Geiger meter (magnitude) — the hero

    /// The Geiger METER — the hero, owning the lower half of the face. The big
    /// bottom-hinged needle sweeps the danger arc; the live CPM, status word, proximity
    /// trend and oscilloscope trace read beneath it. Not tappable — it's the meter, not a
    /// link. RELATIVE reading throughout.
    private var geiger: some View {
        VStack(spacing: 6) {
            CoreGaugeView(engine: engine)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            VStack(spacing: 1) {
                CPMReadout(engine: engine, size: 30)
                StatusWord(engine: engine, size: 15)
            }
            ProximityCue(engine: engine)
                .frame(maxWidth: .infinity)
            ScopeView(engine: engine)
        }
    }
}

/// A stroked arc on the compass rim, spanning ±`halfAngle` degrees around "up" (the
/// phone's forward direction) at `radiusFraction` of the face. The aim cone, drawn as a
/// rim band so it never slices across the scope.
private struct RimCone: Shape {
    let halfAngle: Double
    let radiusFraction: Double

    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        // radiusFraction is measured from centre as a fraction of the full side (to match
        // the blip / cardinal placement `(0.5 + sin·frac)·s`), NOT the half-dimension.
        let r = min(rect.width, rect.height) * radiusFraction
        var path = Path()
        var a = -halfAngle
        let step = 2.0
        var first = true
        while a <= halfAngle + 0.001 {
            let rad = a * .pi / 180
            let pt = CGPoint(x: c.x + sin(rad) * r, y: c.y - cos(rad) * r)
            if first { path.move(to: pt); first = false } else { path.addLine(to: pt) }
            a += step
        }
        return path
    }
}
