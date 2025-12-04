import SwiftUI
import MapKit
import CoreLocation
import Combine

@MainActor
final class SimpleNavigator: NSObject, ObservableObject, CLLocationManagerDelegate, MKMapViewDelegate {

    // Published UI state
    @Published var instruction: String = ""
    @Published var distanceToNextText: String = ""
    @Published var etaText: String = ""
    @Published var isNavigating = false

    // Internals
    private let lm = CLLocationManager()
    private var route: MKRoute?
    private var stepIndex: Int = 0
    private var destination: MKMapItem?
    private var lastLocation: CLLocation?
    weak var mapView: MKMapView?

    override init() {
        super.init()
        lm.delegate = self
        lm.desiredAccuracy = kCLLocationAccuracyBest
        lm.activityType = .fitness
        lm.distanceFilter = 3 // meters
        lm.headingFilter = 3  // degrees
    }

    func start(to destination: MKMapItem) {
        self.destination = destination
        isNavigating = true

        // Begin a step-counting session
        StepCountManager.shared.beginSession()

        switch lm.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            lm.startUpdatingLocation()
            lm.startUpdatingHeading()
            if let loc = lm.location {
                computeRoute(from: loc.coordinate, to: destination)
            }
        case .notDetermined:
            lm.requestWhenInUseAuthorization()
        default:
            break
        }
    }

    func stop() {
        isNavigating = false
        lm.stopUpdatingLocation()
        lm.stopUpdatingHeading()
        if let mv = mapView {
            mv.removeOverlays(mv.overlays)
        }
        route = nil
        stepIndex = 0
        instruction = ""
        distanceToNextText = ""
        etaText = ""

        // End session step counting (HealthKit background still active)
        StepCountManager.shared.endSession()
    }

    private func computeRoute(from source: CLLocationCoordinate2D, to destItem: MKMapItem) {
        let req = MKDirections.Request()
        req.source = MKMapItem(placemark: MKPlacemark(coordinate: source))
        req.destination = destItem
        req.transportType = .walking
        req.requestsAlternateRoutes = false

        MKDirections(request: req).calculate { [weak self] res, err in
            guard let self else { return }
            guard let route = res?.routes.first, err == nil else { return }
            self.route = route
            self.stepIndex = 0
            self.updateBannerTexts()
            self.showRouteOnMap(route)
        }
    }

    private func showRouteOnMap(_ route: MKRoute) {
        guard let mv = mapView else { return }
        mv.removeOverlays(mv.overlays)
        mv.addOverlay(route.polyline)

        let pad = UIEdgeInsets(top: 120, left: 40, bottom: 160, right: 40)
        mv.setVisibleMapRect(route.polyline.boundingMapRect, edgePadding: pad, animated: true)

        if #available(iOS 16.0, *) {
            mv.preferredConfiguration = MKImageryMapConfiguration(elevationStyle: .realistic)
        }
        mv.showsBuildings = true
        mv.camera.pitch = 60
    }

    // MARK: - CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if isNavigating,
           manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways {
            manager.startUpdatingLocation()
            manager.startUpdatingHeading()
            if let loc = manager.location, let dest = destination {
                computeRoute(from: loc.coordinate, to: dest)
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        guard let mv = mapView, let loc = manager.location else { return }
        let cam = MKMapCamera(lookingAtCenter: loc.coordinate,
                              fromDistance: max(250, mv.camera.centerCoordinateDistance),
                              pitch: 60,
                              heading: newHeading.trueHeading)
        mv.setCamera(cam, animated: true)
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard isNavigating, let loc = locations.last else { return }
        lastLocation = loc

        // Follow with heading
        if let mv = mapView {
            let cam = MKMapCamera(lookingAtCenter: loc.coordinate,
                                  fromDistance: max(200, mv.camera.centerCoordinateDistance),
                                  pitch: 60,
                                  heading: manager.heading?.trueHeading ?? mv.camera.heading)
            mv.setCamera(cam, animated: true)
        }

        guard let route else { return }

        // Advance step if close to its end
        if stepIndex < route.steps.count {
            let step = route.steps[stepIndex]
            let end = step.polyline.lastCoordinate ?? route.polyline.lastCoordinate ?? step.polyline.firstCoordinate
            let d = loc.distance(from: CLLocation(latitude: end.latitude, longitude: end.longitude))
            updateDistanceText(currentDistanceMeters: d, defaultStepDistance: step.distance)
            if d < 20 { // meters threshold
                stepIndex = min(stepIndex + 1, route.steps.count - 1)
                self.updateBannerTexts()
            }
        } else {
            instruction = "Arrived"
            distanceToNextText = "0 ft"
        }

        // Simple re-route if far from polyline
        if let distToRoute = nearestDistance(to: route.polyline, from: loc.coordinate),
           distToRoute > 60, let dest = destination {
            computeRoute(from: loc.coordinate, to: dest)
        }
    }

    // MARK: - MKMapViewDelegate

    func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
        if let poly = overlay as? MKPolyline {
            let r = MKPolylineRenderer(polyline: poly)
            r.strokeColor = UIColor.systemBlue
            r.lineWidth = 6
            r.lineJoin = .round
            r.lineCap = .round
            return r
        }
        return MKOverlayRenderer(overlay: overlay)
    }

    // MARK: - Helpers

    private func updateBannerTexts() {
        guard let route else { return }
        let step = route.steps[min(stepIndex, route.steps.count - 1)]
        instruction = step.instructions.isEmpty ? "Continue" : step.instructions

        let lf = LengthFormatter()
        lf.unitStyle = .short
        distanceToNextText = lf.string(fromMeters: step.distance)

        let eta = route.expectedTravelTime
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.minute]
        formatter.unitsStyle = .short
        etaText = formatter.string(from: eta) ?? ""
    }

    private func updateDistanceText(currentDistanceMeters: CLLocationDistance, defaultStepDistance: CLLocationDistance) {
        let meters = max(0, min(defaultStepDistance, currentDistanceMeters))
        let lf = LengthFormatter()
        lf.unitStyle = .short
        distanceToNextText = lf.string(fromMeters: meters)
    }

    private func nearestDistance(to polyline: MKPolyline, from coord: CLLocationCoordinate2D) -> CLLocationDistance? {
        guard polyline.pointCount >= 2 else { return nil }
        var coords = [CLLocationCoordinate2D](repeating: kCLLocationCoordinate2DInvalid, count: polyline.pointCount)
        polyline.getCoordinates(&coords, range: NSRange(location: 0, length: polyline.pointCount))

        let p = MKMapPoint(coord)
        var minDist = CLLocationDistance.greatestFiniteMagnitude

        for i in 0..<(coords.count - 1) {
            let a = MKMapPoint(coords[i])
            let b = MKMapPoint(coords[i + 1])
            let ab = CGPoint(x: b.x - a.x, y: b.y - a.y)
            let ap = CGPoint(x: p.x - a.x, y: p.y - a.y)
            let abLen2 = ab.x*ab.x + ab.y*ab.y
            let t = max(0.0, min(1.0, (abLen2 > 0) ? ((ap.x*ab.x + ap.y*ab.y)/abLen2) : 0))
            let proj = MKMapPoint(x: a.x + t*ab.x, y: a.y + t*ab.y)
            let d = p.distance(to: proj)
            minDist = min(minDist, d)
        }
        return minDist
    }
}

private extension MKPolyline {
    var firstCoordinate: CLLocationCoordinate2D {
        var c = [CLLocationCoordinate2D](repeating: kCLLocationCoordinate2DInvalid, count: 1)
        getCoordinates(&c, range: NSRange(location: 0, length: 1))
        return c[0]
    }
    var lastCoordinate: CLLocationCoordinate2D? {
        guard pointCount > 0 else { return nil }
        var c = [CLLocationCoordinate2D](repeating: kCLLocationCoordinate2DInvalid, count: 1)
        getCoordinates(&c, range: NSRange(location: pointCount - 1, length: 1))
        return c[0]
    }
}

struct NavMapView: UIViewRepresentable {
    @ObservedObject var navigator: SimpleNavigator

    func makeUIView(context: Context) -> MKMapView {
        let mv = MKMapView(frame: .zero)
        mv.delegate = navigator
        mv.showsUserLocation = true
        mv.userTrackingMode = .followWithHeading
        mv.showsCompass = false
        mv.isRotateEnabled = true
        mv.isPitchEnabled = true
        mv.pointOfInterestFilter = .includingAll
        if #available(iOS 16.0, *) {
            mv.preferredConfiguration = MKImageryMapConfiguration(elevationStyle: .realistic)
        }
        navigator.mapView = mv
        return mv
    }

    func updateUIView(_ uiView: MKMapView, context: Context) {}
}

struct SimpleNavigationView: View {
    let destination: MKMapItem
    @StateObject private var nav = SimpleNavigator()
    @ObservedObject private var steps = StepCountManager.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            NavMapView(navigator: nav)
                .ignoresSafeArea()

            VStack(spacing: 12) {
                if !nav.instruction.isEmpty {
                    HStack(spacing: 12) {
                        Image(systemName: "arrow.up")
                            .font(.title2).bold()
                        VStack(alignment: .leading) {
                            Text(nav.instruction).font(.headline).lineLimit(2)
                            if !nav.distanceToNextText.isEmpty {
                                Text(nav.distanceToNextText).font(.subheadline).opacity(0.8)
                            }
                        }
                        Spacer()
                        Button {
                            dismiss()
                            nav.stop()
                        } label: {
                            Image(systemName: "xmark.circle.fill").font(.title2)
                        }
                    }
                    .foregroundColor(.white)
                    .padding()
                    .background(Color.green)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .shadow(radius: 6)
                    .padding(.horizontal)
                    .padding(.top, 12)
                }

                Spacer()

                HStack(spacing: 12) {
                    Image(systemName: "figure.walk").foregroundColor(.blue)
                    Text(nav.etaText.isEmpty ? "Walking" : "ETA \(nav.etaText)")

                    Divider().frame(height: 18)

                    Image(systemName: "shoeprints.fill").foregroundColor(.purple)
                    Text("\(steps.sessionSteps) steps")
                        .monospacedDigit()

                    Spacer()
                }
                .padding()
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding(.horizontal)
                .padding(.bottom, 20)
            }
        }
        .onAppear { nav.start(to: destination) }
        .onDisappear { nav.stop() }
    }
}
