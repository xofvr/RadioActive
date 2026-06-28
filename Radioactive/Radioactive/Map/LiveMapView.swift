import MapKit
import SwiftUI

/// A real Apple Map (dark) with a contaminant badge per place, placed by real
/// coordinate, and a phosphor "you" marker. Tapping a badge pushes its report.
struct LiveMapView: View {
    var engine: DetectorEngine
    var base: CLLocationCoordinate2D

    @State private var camera: MapCameraPosition = .automatic

    /// Contaminants clustered in geo-space (≈25 m). `members[0]` is the worst, so
    /// the representative's badge COLOUR/NUMBER stay ABSOLUTE per the honesty rules.
    private var clusters: [Cluster<Place>] {
        DetectorMath.cluster(engine.contaminants, position: { p in
            let c = p.coordinate(base: base)
            let dx = (c.longitude - base.longitude) * cos(base.latitude * .pi / 180) * 111_320
            let dy = (c.latitude - base.latitude) * 111_320
            return CGPoint(x: dx, y: dy)            // metres
        }, minSeparation: 25)
    }

    var body: some View {
        Map(position: $camera) {
            Annotation("You", coordinate: base, anchor: .center) {
                youMarker
            }
            ForEach(clusters, id: \.representative.id) { cluster in
                let place = cluster.representative
                Annotation(place.short, coordinate: place.coordinate(base: base), anchor: .bottom) {
                    NavigationLink(value: place) {
                        badge(place, count: cluster.count)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll, showsTraffic: false))
        .onAppear(perform: recenter)
        .onChange(of: base.latitude) { recenter() }
        .onChange(of: engine.contaminants.count) { recenter() }
    }

    private func recenter() {
        camera = .region(MKCoordinateRegion(
            center: base,
            span: MKCoordinateSpan(latitudeDelta: 0.016, longitudeDelta: 0.016)))
    }

    private var youMarker: some View {
        ZStack {
            Circle().fill(Theme.phosphor.opacity(0.25)).frame(width: 30, height: 30)
            Circle().fill(Theme.phosphor).frame(width: 14, height: 14)
                .overlay(Circle().stroke(.black.opacity(0.5), lineWidth: 2))
                .phosphorGlow(Theme.phosphor, radius: 8)
        }
        .accessibilityLabel("You are here")
    }

    private func badge(_ place: Place, count: Int) -> some View {
        // COLOUR + NUMBER are ABSOLUTE (place.badness / place.red) — never relative.
        let color = engine.color(place.badness, 0.95)
        let isTarget = place.id == engine.target.id
        return VStack(spacing: 2) {
            Circle()
                .fill(color)
                .frame(width: 30, height: 30)
                .overlay(Circle().stroke(.black.opacity(0.4), lineWidth: 2))
                .overlay(
                    Text("\(place.red)")
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundStyle(Theme.bgDeep)
                )
                .overlay(alignment: .topTrailing) {
                    if count > 1 {
                        Text("+\(count - 1)")
                            .font(.system(size: 10, weight: .heavy))
                            .foregroundStyle(Theme.bgDeep)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Theme.ink))
                            .overlay(Capsule().stroke(.black.opacity(0.4), lineWidth: 1))
                            .offset(x: 8, y: -6)
                    }
                }
                .shadow(color: .black.opacity(0.5), radius: 4, y: 2)
            if isTarget {
                Text(place.short)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(.black.opacity(0.6)))
                    .fixedSize()
            }
        }
        .frame(minWidth: 44, minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityLabel(
            count > 1
            ? "\(place.name), \(place.red) of 5 red stars, plus \(count - 1) more nearby"
            : "\(place.name), \(place.red) of 5 red stars")
    }
}
