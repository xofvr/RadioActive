import MapKit
import SwiftUI

/// Apple's NATIVE place card (iOS 26 `MKMapItemDetailViewController`) for a discovered
/// place — the app's "reality check". MapKit won't hand us a rating as *data*, but its
/// own card renders the REAL Apple Maps rating, photos, hours and reviews. We resolve
/// the `MKMapItem` from its stable identifier and present it in a sheet.
struct PlaceCardView: UIViewControllerRepresentable {
    let mapItemID: String
    var onFinish: () -> Void = {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    func makeUIViewController(context: Context) -> MKMapItemDetailViewController {
        // nil map item renders the card's built-in loading state until we resolve it.
        let controller = MKMapItemDetailViewController(mapItem: nil)
        controller.delegate = context.coordinator

        if let identifier = MKMapItem.Identifier(rawValue: mapItemID) {
            let request = MKMapItemRequest(mapItemIdentifier: identifier)
            // `request` is captured by the Task, keeping it alive until it resolves.
            Task { @MainActor in
                if let item = try? await request.mapItem {
                    controller.mapItem = item
                }
            }
        }
        return controller
    }

    func updateUIViewController(_ controller: MKMapItemDetailViewController, context: Context) {}

    final class Coordinator: NSObject, MKMapItemDetailViewControllerDelegate {
        let onFinish: () -> Void
        init(onFinish: @escaping () -> Void) { self.onFinish = onFinish }
        func mapItemDetailViewControllerDidFinish(_ controller: MKMapItemDetailViewController) {
            onFinish()
        }
    }
}
