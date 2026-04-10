import SwiftUI
import MapKit
import CoreLocation
import Combine

@MainActor
final class SimpleNavigator: NSObject, ObservableObject, CLLocationManagerDelegate, MKMapViewDelegate {

    @Published var isFollowingUser = false
    @Published var primaryTurnIcon = "arrow.up"
    @Published var primaryPrefixText = "Getting ready"
    @Published var primaryTitleText = "Waiting for GPS"
    @Published var distanceToNextTurnText: String = ""
    @Published var secondaryInstruction: String?
    @Published var secondaryTurnIcon = "arrow.turn.up.right"
    @Published var tripTimeText = "0 min"
    @Published var tripMetaText = "Waiting for location"

    private let locationManager = CLLocationManager()
    private var route: Route?
    private var stopCoordinates: [CLLocationCoordinate2D] = []
    private var routeCoordinates: [CLLocationCoordinate2D] = []
    private var routeLocations: [CLLocation] = []
    private var cumulativeDistances: [CLLocationDistance] = []
    private var stepEndIndices: [Int] = []
    private var currentProgressIndex = 0
    private var currentStepIndex = 0
    private var lastLocation: CLLocation?
    private var isProgrammaticCameraChange = false
    private var hasCenteredInitialOverview = false

    weak var mapView: MKMapView? {
        didSet {
            configureMapIfNeeded()
            renderRoute()
        }
    }

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.activityType = .fitness
        locationManager.distanceFilter = 3
        locationManager.headingFilter = 3
    }

    func start(route: Route, stopCoordinates: [CLLocationCoordinate2D]) {
        self.route = route
        self.stopCoordinates = stopCoordinates
        self.routeCoordinates = route.coordinatePoints
        self.routeLocations = routeCoordinates.map { CLLocation(latitude: $0.latitude, longitude: $0.longitude) }
        self.cumulativeDistances = Self.buildCumulativeDistances(for: routeLocations)
        self.stepEndIndices = Self.buildStepEndIndices(for: route, coordinateCount: routeCoordinates.count, cumulativeDistances: cumulativeDistances)
        self.currentProgressIndex = 0
        self.currentStepIndex = 0
        self.hasCenteredInitialOverview = false

        renderRoute()
        updateInstructionState()
        StepCountManager.shared.beginSession()
        requestLocationUpdatesIfNeeded()
    }

    func stop() {
        if let route {
            WalkHistoryStore.shared.record(route: route)
        }
        isFollowingUser = false
        lastLocation = nil
        locationManager.stopUpdatingLocation()
        locationManager.stopUpdatingHeading()
        if let mapView {
            mapView.removeOverlays(mapView.overlays)
            let removable = mapView.annotations.filter { !($0 is MKUserLocation) }
            mapView.removeAnnotations(removable)
        }
        route = nil
        routeCoordinates = []
        routeLocations = []
        cumulativeDistances = []
        stepEndIndices = []
        secondaryInstruction = nil
        tripTimeText = "0 min"
        tripMetaText = "Trip ended"
        StepCountManager.shared.endSession()
    }

    func recenter() {
        guard let lastLocation else { return }
        isFollowingUser = true
        followCamera(to: lastLocation, animated: true)
    }

    func showOverview() {
        guard let mapView, let polyline = currentPolyline else { return }
        isFollowingUser = false
        isProgrammaticCameraChange = true
        mapView.setVisibleMapRect(
            polyline.boundingMapRect,
            edgePadding: UIEdgeInsets(top: 180, left: 44, bottom: 220, right: 44),
            animated: true
        )
        releaseProgrammaticCameraFlag(after: 0.55)
    }

    private var currentPolyline: MKPolyline? {
        guard routeCoordinates.count >= 2 else { return nil }
        return MKPolyline(coordinates: routeCoordinates, count: routeCoordinates.count)
    }

    private func configureMapIfNeeded() {
        guard let mapView else { return }
        mapView.showsUserLocation = true
        mapView.showsCompass = false
        mapView.showsScale = false
        mapView.isPitchEnabled = true
        mapView.isRotateEnabled = true
        mapView.pointOfInterestFilter = .includingAll
        if #available(iOS 16.0, *) {
            let config = MKHybridMapConfiguration(elevationStyle: .realistic)
            config.showsTraffic = false
            mapView.preferredConfiguration = config
        }
    }

    private func requestLocationUpdatesIfNeeded() {
        switch locationManager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            locationManager.startUpdatingLocation()
            if CLLocationManager.headingAvailable() {
                locationManager.startUpdatingHeading()
            }
            if let location = locationManager.location {
                lastLocation = location
                if !hasCenteredInitialOverview {
                    isFollowingUser = true
                    followCamera(to: location, animated: false)
                }
                updateProgress(using: location)
            } else if !hasCenteredInitialOverview {
                showOverview()
                hasCenteredInitialOverview = true
            }
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        default:
            if !hasCenteredInitialOverview {
                showOverview()
                hasCenteredInitialOverview = true
            }
            primaryPrefixText = "Location permission needed"
            primaryTitleText = "Enable GPS to follow your walk"
            tripMetaText = "You can still preview the route"
        }
    }

    private func renderRoute() {
        guard let mapView else { return }

        mapView.removeOverlays(mapView.overlays)
        let removable = mapView.annotations.filter { !($0 is MKUserLocation) }
        mapView.removeAnnotations(removable)

        guard let route else { return }

        if routeCoordinates.count >= 2 {
            let polyline = MKPolyline(coordinates: routeCoordinates, count: routeCoordinates.count)
            mapView.addOverlay(polyline)
            if !hasCenteredInitialOverview {
                hasCenteredInitialOverview = true
                showOverview()
            }
        }

        var annotations: [TripMarkerAnnotation] = []
        if let start = routeCoordinates.first {
            annotations.append(.init(coordinate: start, kind: .start))
        }

        for (index, coordinate) in stopCoordinates.enumerated() {
            annotations.append(.init(coordinate: coordinate, kind: .stop(index + 1)))
        }

        if let end = routeCoordinates.last,
           let start = routeCoordinates.first,
           !route.mode.lowercased().contains("loop") || Self.distance(from: start, to: end) > 5 {
            annotations.append(.init(coordinate: end, kind: .finish))
        }

        mapView.addAnnotations(annotations)
    }

    private func updateProgress(using location: CLLocation) {
        guard !routeLocations.isEmpty else {
            updateInstructionState()
            return
        }

        let localIndex = Self.nearestCoordinateIndex(
            to: location,
            in: routeLocations,
            startingAt: max(0, currentProgressIndex - 6)
        )
        currentProgressIndex = max(currentProgressIndex, localIndex)

        if currentProgressIndex >= routeLocations.count - 1 || remainingDistance(from: location) < 12 {
            currentStepIndex = max(0, (route?.steps?.count ?? 1) - 1)
        } else if !stepEndIndices.isEmpty {
            if let nextIndex = stepEndIndices.firstIndex(where: { $0 > currentProgressIndex + 1 }) {
                currentStepIndex = nextIndex
            } else {
                currentStepIndex = max(0, stepEndIndices.count - 1)
            }
        }

        updateInstructionState(using: location)
    }

    private func updateInstructionState(using location: CLLocation? = nil) {
        let activeLocation = location ?? lastLocation
        let steps = route?.steps ?? []
        let activeStep = steps.isEmpty ? nil : steps[min(currentStepIndex, steps.count - 1)]
        let nextStep = nextUsableStep(after: currentStepIndex, in: steps)

        if remainingDistance(from: activeLocation) < 12 {
            primaryTurnIcon = "flag.checkered"
            primaryPrefixText = route?.mode.lowercased() == "loop" ? "Loop complete" : "You made it"
            primaryTitleText = route?.mode.lowercased() == "loop" ? "Back at the start" : "Destination ahead"
            distanceToNextTurnText = ""
            secondaryInstruction = nil
            tripTimeText = "0 min"
            tripMetaText = "Arrived"
            return
        }

        if let activeStep {
            let presentation = StepPresentation(step: activeStep)
            primaryTurnIcon = presentation.icon
            primaryPrefixText = presentation.prefix
            primaryTitleText = presentation.title
        } else {
            primaryTurnIcon = "arrow.up"
            primaryPrefixText = "Keep going"
            primaryTitleText = "Follow the route"
        }

        if let nextStep {
            let nextPresentation = StepPresentation(step: nextStep)
            secondaryTurnIcon = nextPresentation.icon
            secondaryInstruction = nextPresentation.compactTitle
        } else {
            secondaryInstruction = nil
        }

        let remainingMeters = remainingDistance(from: activeLocation)
        let remainingSeconds = remainingTime(fromDistanceMeters: remainingMeters)
        tripTimeText = Self.formatDurationText(remainingSeconds)
        tripMetaText = Self.formatMetaText(distanceMeters: remainingMeters, arrivalDate: Date().addingTimeInterval(remainingSeconds))

        // Distance to next turn
        if let turnDist = distanceToNextTurn(from: activeLocation), turnDist >= 12 {
            distanceToNextTurnText = turnDist < 1000
                ? String(format: "in %.0f m", turnDist)
                : String(format: "in %.1f km", turnDist / 1000)
        } else {
            distanceToNextTurnText = ""
        }
    }

    private func nextUsableStep(after index: Int, in steps: [Step]) -> Step? {
        guard !steps.isEmpty else { return nil }
        let start = min(index + 1, steps.count - 1)
        for offset in start..<steps.count {
            let step = steps[offset]
            if !Self.isArrival(step) {
                return step
            }
        }
        return nil
    }

    private func distanceToNextTurn(from location: CLLocation?) -> CLLocationDistance? {
        guard route?.steps?.isEmpty == false,
              !stepEndIndices.isEmpty, !cumulativeDistances.isEmpty else { return nil }
        let safeStep = min(currentStepIndex, stepEndIndices.count - 1)
        let stepEndIdx = min(stepEndIndices[safeStep], cumulativeDistances.count - 1)
        let clampedProgress = min(currentProgressIndex, cumulativeDistances.count - 1)
        let stepRemaining = max(0, cumulativeDistances[stepEndIdx] - cumulativeDistances[clampedProgress])
        guard let location, clampedProgress < routeLocations.count else { return stepRemaining }
        let snapDist = location.distance(from: routeLocations[clampedProgress])
        return max(0, stepRemaining + snapDist)
    }

    private func remainingDistance(from location: CLLocation?) -> CLLocationDistance {
        guard !routeLocations.isEmpty else { return 0 }
        let clampedIndex = min(currentProgressIndex, max(routeLocations.count - 1, 0))
        let routeRemaining = (cumulativeDistances.last ?? 0) - (cumulativeDistances[safe: clampedIndex] ?? 0)
        guard let location else { return max(routeRemaining, 0) }
        let snapDistance = location.distance(from: routeLocations[clampedIndex])
        return max(0, routeRemaining + snapDistance)
    }

    private func remainingTime(fromDistanceMeters meters: CLLocationDistance) -> TimeInterval {
        if let duration = route?.durationS,
           let total = cumulativeDistances.last,
           total > 1 {
            return max(0, duration * (meters / total))
        }
        return max(0, meters / 1.35)
    }

    private func followCamera(to location: CLLocation, animated: Bool) {
        guard let mapView else { return }
        let heading = currentHeading()
        let distance = max(180, min(320, remainingDistance(from: location) * 0.65))
        let camera = MKMapCamera(
            lookingAtCenter: location.coordinate,
            fromDistance: distance,
            pitch: 58,
            heading: heading
        )

        isProgrammaticCameraChange = true
        mapView.setCamera(camera, animated: animated)
        releaseProgrammaticCameraFlag(after: animated ? 0.35 : 0.05)
    }

    private func currentHeading() -> CLLocationDirection {
        if let course = lastLocation?.course, course >= 0 {
            return course
        }
        if let heading = locationManager.heading?.trueHeading, heading >= 0 {
            return heading
        }
        return mapView?.camera.heading ?? 0
    }

    private func releaseProgrammaticCameraFlag(after delay: TimeInterval) {
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            self?.isProgrammaticCameraChange = false
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        requestLocationUpdatesIfNeeded()
    }

    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        requestLocationUpdatesIfNeeded()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        lastLocation = location
        updateProgress(using: location)
        if isFollowingUser {
            followCamera(to: location, animated: true)
        }
    }

    func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
        guard let polyline = overlay as? MKPolyline else {
            return MKOverlayRenderer(overlay: overlay)
        }

        let renderer = MKPolylineRenderer(polyline: polyline)
        renderer.strokeColor = UIColor.systemBlue
        renderer.lineWidth = 7
        renderer.lineCap = .round
        renderer.lineJoin = .round
        return renderer
    }

    func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        guard let marker = annotation as? TripMarkerAnnotation else { return nil }

        let view = (mapView.dequeueReusableAnnotationView(withIdentifier: TripMarkerAnnotation.reuseID) as? MKMarkerAnnotationView)
            ?? MKMarkerAnnotationView(annotation: marker, reuseIdentifier: TripMarkerAnnotation.reuseID)

        view.annotation = marker
        view.canShowCallout = false
        view.titleVisibility = .hidden
        view.subtitleVisibility = .hidden

        switch marker.kind {
        case .start:
            view.markerTintColor = .systemGreen
            view.glyphText = "S"
            view.glyphTintColor = .white
        case .finish:
            view.markerTintColor = .systemRed
            view.glyphText = "E"
            view.glyphTintColor = .white
        case .stop(let index):
            view.markerTintColor = .systemOrange
            view.glyphText = "\(index)"
            view.glyphTintColor = .white
        }

        return view
    }

    func mapView(_ mapView: MKMapView, regionWillChangeAnimated animated: Bool) {
        guard !isProgrammaticCameraChange, mapView.isUserInteracting else { return }
        isFollowingUser = false
    }

    private static func buildCumulativeDistances(for locations: [CLLocation]) -> [CLLocationDistance] {
        guard !locations.isEmpty else { return [] }
        var output: [CLLocationDistance] = [0]
        for index in 1..<locations.count {
            output.append(output[index - 1] + locations[index].distance(from: locations[index - 1]))
        }
        return output
    }

    private static func buildStepEndIndices(for route: Route,
                                            coordinateCount: Int,
                                            cumulativeDistances: [CLLocationDistance]) -> [Int] {
        let steps = route.steps ?? []
        guard !steps.isEmpty, coordinateCount > 0 else { return [] }

        let rawIndices = steps.compactMap(\.endLat)
        if rawIndices.count == steps.count {
            return rawIndices.map { min(max($0, 0), coordinateCount - 1) }
        }

        let totalDistance = cumulativeDistances.last ?? 0
        guard totalDistance > 0 else {
            return steps.enumerated().map { index, _ in
                min(coordinateCount - 1, Int((Double(index + 1) / Double(max(steps.count, 1))) * Double(coordinateCount - 1)))
            }
        }

        var runningDistance: CLLocationDistance = 0
        return steps.enumerated().map { index, step in
            if index == steps.count - 1 { return coordinateCount - 1 }
            runningDistance += max(0, (step.length ?? 0) * 1000)
            return firstIndex(for: runningDistance, in: cumulativeDistances)
        }
    }

    private static func firstIndex(for distance: CLLocationDistance, in cumulativeDistances: [CLLocationDistance]) -> Int {
        guard !cumulativeDistances.isEmpty else { return 0 }
        if let index = cumulativeDistances.firstIndex(where: { $0 >= distance }) {
            return index
        }
        return cumulativeDistances.count - 1
    }

    private static func nearestCoordinateIndex(to location: CLLocation,
                                               in routeLocations: [CLLocation],
                                               startingAt startIndex: Int) -> Int {
        guard !routeLocations.isEmpty else { return 0 }

        var bestIndex = min(max(startIndex, 0), routeLocations.count - 1)
        var bestDistance = CLLocationDistance.greatestFiniteMagnitude

        let start = min(max(startIndex, 0), routeLocations.count - 1)
        let end = routeLocations.count - 1
        for index in start...end {
            let distance = location.distance(from: routeLocations[index])
            if distance <= bestDistance {
                bestDistance = distance
                bestIndex = index
            } else if index > start + 20, distance > bestDistance * 1.6 {
                break
            }
        }

        if bestDistance < 90 {
            return bestIndex
        }

        for index in 0..<routeLocations.count {
            let distance = location.distance(from: routeLocations[index])
            if distance < bestDistance {
                bestDistance = distance
                bestIndex = index
            }
        }

        return bestIndex
    }

    private static func formatDurationText(_ seconds: TimeInterval) -> String {
        if seconds < 45 { return "Now" }
        let minutes = max(1, Int(round(seconds / 60)))
        return "\(minutes) min"
    }

    private static func formatMetaText(distanceMeters: CLLocationDistance, arrivalDate: Date) -> String {
        let distanceText = MKDistanceFormatter().string(fromDistance: distanceMeters)
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return "\(distanceText) · \(formatter.string(from: arrivalDate))"
    }

    private static func isArrival(_ step: Step) -> Bool {
        if step.type == 5 { return true }
        let lower = step.instruction.lowercased()
        return lower.contains("arrive") || lower.contains("destination")
    }

    private static func distance(from lhs: CLLocationCoordinate2D, to rhs: CLLocationCoordinate2D) -> CLLocationDistance {
        CLLocation(latitude: lhs.latitude, longitude: lhs.longitude)
            .distance(from: CLLocation(latitude: rhs.latitude, longitude: rhs.longitude))
    }
}

private struct StepPresentation {
    let icon: String
    let prefix: String
    let title: String
    let compactTitle: String

    init(step: Step) {
        let instruction = step.instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = instruction.lowercased()
        let street = Self.extractStreet(from: instruction)

        if lower.contains("arrive") || lower.contains("destination") {
            icon = "flag.checkered"
            prefix = "Almost there"
            title = "Destination ahead"
            compactTitle = "Arrive at your destination"
            return
        }

        if lower.contains("right") {
            icon = "arrow.turn.up.right"
            prefix = "Turn right"
            title = street ?? "ahead"
            compactTitle = street.map { "onto \($0)" } ?? "turn right"
            return
        }

        if lower.contains("left") {
            icon = "arrow.turn.up.left"
            prefix = "Turn left"
            title = street ?? "ahead"
            compactTitle = street.map { "onto \($0)" } ?? "turn left"
            return
        }

        if lower.contains("continue") || lower.contains("head") || lower.contains("walk") || lower.contains("proceed") {
            icon = "arrow.up"
            prefix = "toward"
            title = street ?? Self.cleanInstruction(instruction)
            compactTitle = street ?? Self.cleanInstruction(instruction)
            return
        }

        icon = Self.icon(for: step.type)
        prefix = "Next"
        title = street ?? Self.cleanInstruction(instruction)
        compactTitle = Self.cleanInstruction(instruction)
    }

    private static func icon(for type: Int?) -> String {
        switch type {
        case 10, 11, 12, 13: return "arrow.turn.up.right"
        case 14, 15, 16, 17: return "arrow.turn.up.left"
        case 5: return "flag.checkered"
        default: return "arrow.up"
        }
    }

    private static func cleanInstruction(_ instruction: String) -> String {
        instruction
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: "Walk ", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "Head ", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "Continue ", with: "", options: .caseInsensitive)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func extractStreet(from instruction: String) -> String? {
        let lowered = instruction.lowercased()
        let tokens = [" onto ", " on ", " toward ", " towards "]

        for token in tokens {
            guard let range = lowered.range(of: token) else { continue }
            let remainder = instruction[range.upperBound...]
                .trimmingCharacters(in: .whitespacesAndNewlines)

            let cleaned = remainder
                .split(whereSeparator: { [",", ".", ";"].contains($0) })
                .first
                .map(String.init)?
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if let cleaned, !cleaned.isEmpty {
                return cleaned
            }
        }

        return nil
    }
}

private final class TripMarkerAnnotation: NSObject, MKAnnotation {
    enum Kind {
        case start
        case stop(Int)
        case finish
    }

    static let reuseID = "trip-marker"

    let coordinate: CLLocationCoordinate2D
    let kind: Kind

    init(coordinate: CLLocationCoordinate2D, kind: Kind) {
        self.coordinate = coordinate
        self.kind = kind
    }
}

private extension MKMapView {
    var isUserInteracting: Bool {
        gestureRecognizers?.contains(where: { recognizer in
            switch recognizer.state {
            case .began, .changed:
                return true
            default:
                return false
            }
        }) ?? false
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
