// MiniMapView.swift
import SwiftUI
import MapKit
import CoreLocation

struct MiniMapView: View {
    @State private var region = MKCoordinateRegion()
    @State private var routeOverlay: MKPolyline?

    let routeCoords: [CLLocationCoordinate2D]

    var body: some View {
        Map(coordinateRegion: $region,
            interactionModes: [],
            showsUserLocation: true)
        .overlay(RouteOverlay(routeCoords: routeCoords))
        .frame(width: 170, height: 170)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .shadow(radius: 8)
        .onAppear {
            updateRegion()
        }
    }

    private func updateRegion() {
        if let loc = LocationManager.shared.userLocation {
            region = MKCoordinateRegion(
                center: loc,
                span: MKCoordinateSpan(latitudeDelta: 0.002, longitudeDelta: 0.002)
            )
        }
    }
}

// Custom overlay for drawing polyline
struct RouteOverlay: UIViewRepresentable {
    let routeCoords: [CLLocationCoordinate2D]

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.isUserInteractionEnabled = false

        let polyline = MKPolyline(coordinates: routeCoords, count: routeCoords.count)
        map.addOverlay(polyline)

        map.delegate = context.coordinator
        return map
    }

    func updateUIView(_ uiView: MKMapView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator: NSObject, MKMapViewDelegate {
        func mapView(_ mapView: MKMapView,
                     rendererFor overlay: MKOverlay) -> MKOverlayRenderer {

            if let polyline = overlay as? MKPolyline {
                let renderer = MKPolylineRenderer(polyline: polyline)
                renderer.strokeColor = .systemBlue
                renderer.lineWidth = 4
                return renderer
            }
            return MKOverlayRenderer()
        }
    }
}
