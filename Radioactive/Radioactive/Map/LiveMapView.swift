import MapKit
import SwiftUI

/// A real Apple Map (dark) with a contaminant badge per place, placed by real
/// coordinate, and a phosphor "you" marker. Tapping a badge pushes its report.
struct LiveMapView: View {
    var engine: DetectorEngine
    var base: CLLocationCoordinate2D

    @State private var camera: MapCameraPosition = .automatic

    var body: some View {
        Map(position: $camera) {
            Annotation("You", coordinate: base, anchor: .center) {
                youMarker
            }
            ForEach(engine.contaminants) { place in
                Annotation(place.short, coordinate: place.coordinate(base: base), anchor: .bottom) {
                    NavigationLink(value: place) {
                        badge(place)
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

    private func badge(_ place: Place) -> some View {
        let color = engine.color(place.badness, 0.95)
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
                .shadow(color: .black.opacity(0.5), radius: 4, y: 2)
            Text(place.short)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(Capsule().fill(.black.opacity(0.6)))
                .fixedSize()
        }
        .frame(minWidth: 44, minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityLabel("\(place.name), \(place.red) of 5 red stars")
    }
}
