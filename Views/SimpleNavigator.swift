import SwiftUI
import MapKit
import CoreLocation
import Combine

@MainActor
final class SimpleNavigator: NSObject, ObservableObject,
                            CLLocationManagerDelegate, MKMapViewDelegate {

    // MARK: - Published UI
    @Published var instruction: String = ""
    @Published var distanceToNextText: String = ""
    @Published var etaText: String = ""
    @Published var isNavigating = false

    // MARK: - Internals
    private let lm = CLLocationManager()
    private var appleRoute: MKRoute?
    private var backendRoute: Route?
    private var usingBackend = false
    private var stepIndex = 0
    private var destination: MKMapItem?
    private var lastLocation: CLLocation?

    weak var mapView: MKMapView?

    override init() {
        super.init()
        lm.delegate = self
        lm.desiredAccuracy = kCLLocationAccuracyBest
        lm.activityType = .fitness
        lm.distanceFilter = 3
        lm.headingFilter = 3
    }

    // MARK: - Public API

    func start(to destination: MKMapItem) {
        self.destination = destination
        isNavigating = true
        StepCountManager.shared.beginSession()

        switch lm.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            lm.startUpdatingLocation()
            lm.startUpdatingHeading()
            if let loc = lm.location {
                computeRouteWithFallback(from: loc.coordinate, to: destination)
            } else {
                instruction = "Waiting for GPS…"
            }
        case .notDetermined:
            lm.requestWhenInUseAuthorization()
        default:
            instruction = "Location permission needed"
        }
    }

    func stop() {
        isNavigating = false
        lm.stopUpdatingLocation()
        lm.stopUpdatingHeading()
        if let mv = mapView {
            mv.removeOverlays(mv.overlays)
        }
        appleRoute = nil
        backendRoute = nil
        usingBackend = false
        stepIndex = 0
        instruction = ""
        distanceToNextText = ""
        etaText = ""
        StepCountManager.shared.endSession()
    }

    // MARK: - ROUTING (APPLE → BACKEND FALLBACK)

    private func computeRouteWithFallback(from source: CLLocationCoordinate2D,
                                          to destItem: MKMapItem) {
        computeAppleRoute(from: source, to: destItem) { [weak self] apple in
            guard let self else { return }

            if let apple {
                self.usingBackend = false
                self.appleRoute = apple
                self.stepIndex = 0
                self.updateAppleBanner()
                self.showAppleRoute(apple)
            } else {
                Task { await self.computeBackendRoute(from: source, to: destItem.placemark.coordinate) }
            }
        }
    }

    // MARK: - Apple Maps

    private func computeAppleRoute(from source: CLLocationCoordinate2D,
                                   to destItem: MKMapItem,
                                   completion: @escaping (MKRoute?) -> Void) {

        let req = MKDirections.Request()
        req.source = MKMapItem(placemark: MKPlacemark(coordinate: source))
        req.destination = destItem
        req.transportType = .walking
        req.requestsAlternateRoutes = false

        MKDirections(request: req).calculate { res, err in
            guard
                err == nil,
                let route = res?.routes.first,
                route.polyline.pointCount > 5,
                route.steps.count > 1,
                route.distance > 10
            else {
                completion(nil)
                return
            }
            completion(route)
        }
    }

    private func showAppleRoute(_ route: MKRoute) {
        guard let mv = mapView else { return }
        mv.removeOverlays(mv.overlays)
        mv.addOverlay(route.polyline)
        zoomToPolyline(route.polyline)
    }

    private func updateAppleBanner() {
        guard let route = appleRoute else { return }
        let idx = min(stepIndex, route.steps.count - 1)
        let step = route.steps[idx]
        instruction = step.instructions.isEmpty ? "Continue" : step.instructions
        distanceToNextText = LengthFormatter().string(fromMeters: step.distance)
        etaText = formatETA(route.expectedTravelTime)
    }

    // MARK: - Backend (Valhalla wrapper in your API)

    private func computeBackendRoute(from source: CLLocationCoordinate2D,
                                     to dest: CLLocationCoordinate2D) async {
        do {
            // Use user's selected mode if needed; here we pick "shortest" for walking-like
            let route = try await API.shared.fetchRoute(start: source, end: dest, mode: "shortest")

            usingBackend = true
            backendRoute = route
            stepIndex = 0

            // Draw polyline from provided coordinates
            let coords = route.coordinatePoints
            if coords.count >= 2 {
                let polyline = MKPolyline(coordinates: coords, count: coords.count)
                if let mv = mapView {
                    mv.removeOverlays(mv.overlays)
                    mv.addOverlay(polyline)
                    zoomToPolyline(polyline)
                }
            }

            updateBackendBanner()

        } catch {
            print("❌ Backend routing failed:", error)
            instruction = "Routing failed"
        }
    }

    private func updateBackendBanner() {
        guard let route = backendRoute else { return }

        // Instruction
        if let steps = route.steps, !steps.isEmpty {
            let idx = min(stepIndex, steps.count - 1)
            let s = steps[idx]
            instruction = s.instruction
            // Step.length is in kilometers
            let meters = (s.length ?? 0) * 1000.0
            distanceToNextText = meters > 0 ? String(format: "%.0f m", meters) : ""
        } else if let nt = route.nextTurn, let instr = nt.instruction, let d = nt.distanceM {
            instruction = instr
            distanceToNextText = String(format: "%.0f m", d)
        } else {
            instruction = "Start walking"
            distanceToNextText = ""
        }

        // ETA
        if let dur = route.durationS {
            etaText = formatETA(TimeInterval(dur))
        } else if let t = route.summary?.time {
            etaText = formatETA(TimeInterval(t))
        } else {
            etaText = ""
        }
    }

    // MARK: - Location updates

    func locationManager(_ manager: CLLocationManager,
                         didChangeAuthorization status: CLAuthorizationStatus) {
        if isNavigating,
           status == .authorizedAlways || status == .authorizedWhenInUse {
            lm.startUpdatingLocation()
            lm.startUpdatingHeading()
            if let loc = lm.location, let dest = destination {
                computeRouteWithFallback(from: loc.coordinate, to: dest)
            }
        }
    }

    func locationManager(_ manager: CLLocationManager,
                         didUpdateLocations locations: [CLLocation]) {
        guard isNavigating, let loc = locations.last else { return }
        lastLocation = loc

        followCamera(loc)

        if usingBackend {
            // Advance step index based on simple remaining distance to next step start
            if let route = backendRoute, let steps = route.steps, !steps.isEmpty {
                let idx = min(stepIndex, steps.count - 1)
                let step = steps[idx]
                // If Step has no geometry indices, approximate by total meters of this step
                let meters = (step.length ?? 0) * 1000.0
                // When we've covered most of this step, advance
                if meters <= 15 { // trivial steps
                    stepIndex = min(stepIndex + 1, steps.count - 1)
                } else {
                    // If user is close to the end of the polyline, also advance
                    if let end = backendRoute?.coordinatePoints.last {
                        let d = loc.distance(from: CLLocation(latitude: end.latitude, longitude: end.longitude))
                        if d < 20 {
                            stepIndex = min(stepIndex + 1, steps.count - 1)
                        }
                    }
                }
                updateBackendBanner()
            } else {
                // No steps — keep showing nextTurn if present
                updateBackendBanner()
            }
        } else if let route = appleRoute {
            if stepIndex < route.steps.count {
                let step = route.steps[stepIndex]
                // End coordinate of current step
                let end = step.polyline.lastCoordinate ?? route.polyline.lastCoordinate
                let d = loc.distance(from: CLLocation(latitude: end.latitude,
                                                      longitude: end.longitude))
                if d < 20 {
                    stepIndex = min(stepIndex + 1, route.steps.count - 1)
                    updateAppleBanner()
                }
            }
        }
    }

    // MARK: - Map

    func mapView(_ mapView: MKMapView,
                 rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
        if let poly = overlay as? MKPolyline {
            let r = MKPolylineRenderer(polyline: poly)
            r.strokeColor = .systemBlue
            r.lineWidth = 6
            r.lineJoin = .round
            r.lineCap = .round
            return r
        }
        return MKOverlayRenderer(overlay: overlay)
    }

    // MARK: - Helpers

    private func zoomToPolyline(_ poly: MKPolyline) {
        mapView?.setVisibleMapRect(
            poly.boundingMapRect,
            edgePadding: UIEdgeInsets(top: 120, left: 40, bottom: 160, right: 40),
            animated: true
        )
    }

    private func followCamera(_ loc: CLLocation) {
        guard let mv = mapView else { return }
        let cam = MKMapCamera(
            lookingAtCenter: loc.coordinate,
            fromDistance: max(200, mv.camera.centerCoordinateDistance),
            pitch: 60,
            heading: lm.heading?.trueHeading ?? mv.camera.heading
        )
        mv.setCamera(cam, animated: true)
    }

    private func formatETA(_ seconds: TimeInterval) -> String {
        let f = DateComponentsFormatter()
        f.allowedUnits = [.minute]
        f.unitsStyle = .short
        return f.string(from: seconds) ?? ""
    }
}

// MARK: - MKPolyline convenience

private extension MKPolyline {
    var lastCoordinate: CLLocationCoordinate2D {
        var c = CLLocationCoordinate2D()
        let count = Int(pointCount)
        if count > 0 {
            getCoordinates(&c, range: NSRange(location: count - 1, length: 1))
        }
        return c
    }
}
