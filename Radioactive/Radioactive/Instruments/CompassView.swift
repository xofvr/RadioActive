import SwiftUI

/// The Pip-Boy compass hero — an alternative to the analog gauge. A heading-up dial:
/// range rings, a forward aim wedge (±`aimConeDegrees`) pinned to where the phone
/// points, a rotating cardinal ring, one blip per contaminant placed at its real
/// bearing relative to your heading, and a centre lock panel with the aimed place's
/// verdict + live reading. Tap a blip (or the panel) to push its field report.
///
/// HONESTY: blip COLOUR and the live CPM are the RELATIVE reading; the centre panel's
/// `RedStars(red:)` and the per-place number stay the ABSOLUTE `Place.red`.
struct CompassView: View {
    var engine: DetectorEngine
    @State private var pulse = false

    private let cardinals: [(label: String, bearing: Double)] = [
        ("N", 0), ("E", 90), ("S", 180), ("W", 270),
    ]

    var body: some View {
        VStack(spacing: 14) {
            header
            face
            hint
            densePill
            HStack(spacing: 12) {
                DosimeterChip(engine: engine)
                Spacer(minLength: 8)
                ProximityCue(engine: engine)
            }
        }
        .padding(16)
        .instrumentPanel()
        .onAppear {
            withAnimation(.easeInOut(duration: 1).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack {
            Text(engine.deviceHeading != nil ? "◎ POINT TO SCAN" : "▮ RAD COMPASS")
                .font(Theme.mono(15))
                .foregroundStyle(Theme.phosphor.opacity(0.7))
            Spacer()
            Button(action: engine.cycleInCone) {
                HStack(spacing: 5) {
                    Text("NEXT")
                    Image(systemName: "arrow.clockwise")
                }
                .font(Theme.mono(14))
                .foregroundStyle(Theme.phosphor.opacity(0.55))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Next target in cone")
        }
    }

    // MARK: Compass face

    private var face: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            ZStack {
                rings(side)
                cone(side)
                rotatingDial(side)
                blips(side)
                youMarker
                lockPanel(side)
            }
            .frame(width: side, height: side)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    // MARK: Static furniture

    private func rings(_ s: CGFloat) -> some View {
        ZStack {
            Circle().stroke(Theme.phosphor.opacity(0.16), lineWidth: 1).frame(width: s, height: s)
            Circle().stroke(Theme.phosphor.opacity(0.13), lineWidth: 1).frame(width: s * 0.668, height: s * 0.668)
            Circle().stroke(Theme.phosphor.opacity(0.10), lineWidth: 1).frame(width: s * 0.334, height: s * 0.334)
            Circle()
                .fill(RadialGradient(
                    colors: [Theme.phosphor.opacity(0.06), .clear],
                    center: .center, startRadius: 0, endRadius: s * 0.36))
                .frame(width: s, height: s)
        }
    }

    /// Forward aim wedge — pinned to "up" (where the phone points), ±aimConeDegrees.
    private func cone(_ s: CGFloat) -> some View {
        AimCone(halfAngle: DetectorEngine.aimConeDegrees)
            .fill(LinearGradient(
                colors: [Theme.phosphor.opacity(0.18), Theme.phosphor.opacity(0.02)],
                startPoint: .top, endPoint: .bottom))
            .frame(width: s, height: s)
            .overlay(
                AimCone(halfAngle: DetectorEngine.aimConeDegrees)
                    .stroke(Theme.phosphor.opacity(0.28), lineWidth: 1)
                    .frame(width: s, height: s)
            )
    }

    /// The cardinal ring + heading readout, rotated so the dial is heading-up. Wrapped
    /// in TimelineView(.animation) + `engine.frame` so it tracks the compass each tick
    /// (mirrors ScopeView's per-frame redraw).
    private func rotatingDial(_ s: CGFloat) -> some View {
        TimelineView(.animation) { _ in
            _ = engine.frame
            let heading = engine.heading
            let rr = s * 0.44
            return ZStack {
                ForEach(cardinals, id: \.label) { c in
                    let rad = (c.bearing - heading) * .pi / 180
                    Text(c.label)
                        .font(Theme.mono(c.label == "N" ? 16 : 13))
                        .foregroundStyle(c.label == "N"
                                         ? Theme.phosphorBright
                                         : Theme.phosphor.opacity(0.5))
                        .position(x: s / 2 + sin(rad) * rr, y: s / 2 - cos(rad) * rr)
                }
            }
            .frame(width: s, height: s)
        }
    }

    private var youMarker: some View {
        ZStack {
            Circle()
                .fill(Theme.phosphor.opacity(0.25))
                .frame(width: 22, height: 22)
                .scaleEffect(pulse ? 1.5 : 1)
                .opacity(pulse ? 0.35 : 0.9)
            Circle()
                .fill(Theme.phosphor)
                .frame(width: 9, height: 9)
                .phosphorGlow(Theme.phosphor, radius: 6)
        }
    }

    // MARK: Blips

    private func blips(_ s: CGFloat) -> some View {
        ForEach(engine.compassBlips()) { blip in
            let rad = (blip.bearing - engine.heading) * .pi / 180
            let rFrac = DetectorMath.scopeRadiusFraction(distanceM: blip.distance)
            let x = (0.5 + sin(rad) * rFrac) * s
            let y = (0.5 - cos(rad) * rFrac) * s
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
        // COLOUR is RELATIVE (worst-nearby reads hot); honesty-locked numbers live in
        // the centre panel / detail screen, never recoloured here.
        let color = engine.color(blip.readingBadness, 0.95)
        let dim = blip.distance / 560.0
        return ZStack {
            if blip.isTarget {
                Circle()
                    .stroke(color.opacity(0.7), lineWidth: 2)
                    .frame(width: 26, height: 26)
                    .scaleEffect(pulse ? 1.35 : 1)
                    .opacity(pulse ? 0.3 : 0.8)
            }
            Circle()
                .fill(color)
                .frame(width: blip.isTarget ? 18 : 12, height: blip.isTarget ? 18 : 12)
                .overlay(Circle().stroke(Color.black.opacity(0.4), lineWidth: 1.5))
                .opacity(1 - min(0.45, dim))
                .phosphorGlow(color, radius: blip.isTarget ? 6 : 3)
        }
    }

    // MARK: Centre lock panel

    private func lockPanel(_ s: CGFloat) -> some View {
        let t = engine.target
        return NavigationLink(value: t) {
            VStack(spacing: 4) {
                Text(engine.locked ? "◉ TARGET ACQUIRED" : "SCANNING…")
                    .font(Theme.mono(12))
                    .foregroundStyle(engine.locked ? Theme.phosphor : Theme.inkMuted)
                Text(t.name)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.inkBright)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                // ABSOLUTE verdict — frozen to Place.red, never the relative reading.
                RedStars(red: t.red, size: 15, spacing: 3)
                cpm
                Text("\(t.type) · \(t.distLabel) · \(t.bearingLabel)")
                    .font(Theme.mono(12))
                    .foregroundStyle(Theme.phosphor.opacity(0.55))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .padding(12)
            .frame(maxWidth: s * 0.66)
            .background(RoundedRectangle(cornerRadius: 8).fill(Theme.bg.opacity(0.74)))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.phosphor.opacity(0.25), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    /// Live counts-per-minute — RELATIVE reading colour (flows from `engine.rads`).
    private var cpm: some View {
        TimelineView(.animation) { _ in
            _ = engine.frame
            let value = min(999, Int(engine.cpmDisplay))
            return HStack(spacing: 4) {
                Text(String(format: "%03d", value))
                    .font(Theme.mono(22))
                    .foregroundStyle(engine.color(engine.rads))
                    .phosphorGlow(engine.color(engine.rads), radius: 5)
                Text("CPM")
                    .font(Theme.mono(16))
                    .foregroundStyle(Theme.phosphor.opacity(0.4))
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(value) counts per minute")
        }
    }

    // MARK: Below-face affordances

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

    /// "Dense bearing" pill — when several places stack inside the forward cone, tell
    /// the user there are more this way and let NEXT cycle through them.
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
}

/// A wedge fanning out from the centre toward "up" (the phone's forward direction),
/// spanning ±`halfAngle` degrees. Used as the compass aim cone.
private struct AimCone: Shape {
    let halfAngle: Double

    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let r = min(rect.width, rect.height) / 2
        var path = Path()
        path.move(to: c)
        let step = 2.0
        var a = -halfAngle
        while a <= halfAngle + 0.001 {
            let rad = a * .pi / 180
            path.addLine(to: CGPoint(x: c.x + sin(rad) * r, y: c.y - cos(rad) * r))
            a += step
        }
        path.closeSubpath()
        return path
    }
}
