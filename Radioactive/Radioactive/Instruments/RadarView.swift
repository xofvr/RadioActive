import SwiftUI

/// Tactical radar scope: range rings, a rotating phosphor sweep, a pulsing "you"
/// at centre, and one pin per place placed by real bearing + distance. Each pin
/// is a NavigationLink that pushes the place's field report.
struct RadarView: View {
    var engine: DetectorEngine
    @State private var pulse = false

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            ZStack {
                rings(side)
                crosshairs(side)
                fieldGlow(side)
                sweep(side)
                northLabel(side)
                youMarker
                pins(side)
            }
            .frame(width: side, height: side)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
        .onAppear {
            withAnimation(.easeInOut(duration: 1).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }

    // MARK: Static scope furniture

    private func rings(_ s: CGFloat) -> some View {
        ZStack {
            Circle().stroke(Theme.phosphor.opacity(0.16), lineWidth: 1).frame(width: s, height: s)
            Circle().stroke(Theme.phosphor.opacity(0.13), lineWidth: 1).frame(width: s * 0.668, height: s * 0.668)
            Circle().stroke(Theme.phosphor.opacity(0.10), lineWidth: 1).frame(width: s * 0.334, height: s * 0.334)
        }
    }

    private func crosshairs(_ s: CGFloat) -> some View {
        ZStack {
            Rectangle().fill(Theme.phosphor.opacity(0.10)).frame(width: 1, height: s)
            Rectangle().fill(Theme.phosphor.opacity(0.10)).frame(width: s, height: 1)
        }
        .clipShape(Circle())
        .frame(width: s, height: s)
    }

    private func fieldGlow(_ s: CGFloat) -> some View {
        Circle()
            .fill(RadialGradient(
                colors: [Theme.phosphor.opacity(0.06), .clear],
                center: .center, startRadius: 0, endRadius: s * 0.36))
            .frame(width: s, height: s)
    }

    private func sweep(_ s: CGFloat) -> some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let angle = (t / 3.8).truncatingRemainder(dividingBy: 1) * 360
            Circle()
                .fill(AngularGradient(
                    stops: [
                        .init(color: Theme.phosphor.opacity(0.22), location: 0),
                        .init(color: .clear, location: 0.38),
                    ],
                    center: .center))
                .frame(width: s, height: s)
                .rotationEffect(.degrees(angle))
                .clipShape(Circle())
        }
    }

    private func northLabel(_ s: CGFloat) -> some View {
        Text("N")
            .font(Theme.mono(12))
            .foregroundStyle(Theme.phosphor.opacity(0.5))
            .offset(y: -(s / 2 - 10))
    }

    private var youMarker: some View {
        ZStack {
            Circle()
                .fill(Theme.phosphor.opacity(0.25))
                .frame(width: 28, height: 28)
                .scaleEffect(pulse ? 1.5 : 1)
                .opacity(pulse ? 0.35 : 0.9)
            Circle()
                .fill(Theme.phosphor)
                .frame(width: 12, height: 12)
                .phosphorGlow(Theme.phosphor, radius: 8)
        }
    }

    // MARK: Pins

    private func pins(_ s: CGFloat) -> some View {
        ForEach(engine.radarPins()) { pin in
            NavigationLink(value: pin.place) {
                pinView(pin)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(pin.place.name), \(pin.place.red) of 5 red stars")
            .position(x: pin.x * s, y: pin.y * s)
        }
    }

    private func pinView(_ pin: RadarPin) -> some View {
        let color = engine.color(pin.place.badness, 0.95)
        return VStack(spacing: 3) {
            ZStack {
                PingRing(color: engine.color(pin.place.badness, 0.5))
                Circle()
                    .fill(color)
                    .frame(width: 26, height: 26)
                    .overlay(Circle().stroke(Color.black.opacity(0.4), lineWidth: 2))
                    .overlay(
                        Text("\(pin.place.red)")
                            .font(.system(size: 12, weight: .heavy))
                            .foregroundStyle(Theme.bgDeep)
                    )
                    .shadow(color: .black.opacity(0.5), radius: 4, y: 2)
            }
            Text(pin.place.short)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(Capsule().fill(Color.black.opacity(0.55)))
                .fixedSize()
        }
    }
}

/// A single expanding "ping" ring behind a radar pin.
private struct PingRing: View {
    let color: Color
    @State private var expand = false

    var body: some View {
        Circle()
            .stroke(color, lineWidth: 2)
            .frame(width: 26, height: 26)
            .scaleEffect(expand ? 2.4 : 0.6)
            .opacity(expand ? 0 : 0.7)
            .onAppear {
                withAnimation(.easeOut(duration: 2.2).repeatForever(autoreverses: false)) {
                    expand = true
                }
            }
    }
}
