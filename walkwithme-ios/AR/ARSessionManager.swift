import Foundation
import Combine
import RealityKit
import ARKit
import CoreLocation

// -----------------------------------------------------------
//  WALKWITHME - AR Session Manager (HUD + DEPTH + YOLO VERSION)
// -----------------------------------------------------------
final class ARSessionManager: NSObject, ObservableObject {

    static let shared = ARSessionManager()

    // -------------------------------------------------------
    // AR STATE
    // -------------------------------------------------------
    private(set) var arView: ARView?
    private var route: Route?

    /// First GPS fix → AR world origin
    private var originCoordinate: CLLocationCoordinate2D?

    private let alignment = ARAlignment()

    private struct ArrowNode {
        let coord: CLLocationCoordinate2D
        let anchor: AnchorEntity
        let arrow: ARArrowEntity
    }
    private var arrowNodes: [ArrowNode] = []

    private var lastUserLocation: CLLocationCoordinate2D?
    private var lastHeading: CLLocationDirection?

    private var lastVisionUpload = Date(timeIntervalSince1970: 0)

    // -------------------------------------------------------
    // PUBLISHERS
    // -------------------------------------------------------
    @Published private(set) var isReady: Bool = false
    @Published private(set) var debugText: String = ""

    private override init() {}
}

// -----------------------------------------------------------
// MARK: - Session Setup
// -----------------------------------------------------------
extension ARSessionManager {

    func configureSession(arView: ARView) {
        self.arView = arView

        // AR hazard icons
        HazardOverlayManager.shared.arView = arView

        // HUD layer
        ARHUDManager.shared.attach(to: arView)

        // Turn HUD layer (NEW)
        TurnHUDManager.shared.attach(to: arView)

        let config = ARWorldTrackingConfiguration()
        config.worldAlignment = .gravityAndHeading
        config.planeDetection = [.horizontal]
        config.frameSemantics = [.sceneDepth] // LiDAR

        arView.automaticallyConfigureSession = false
        arView.session.run(config)
        arView.session.delegate = self

        debug("AR Session configured.")
    }

    func loadRoute(_ route: Route) {
        self.route = route
        debug("Loaded route with \(route.coordinates.count) points.")
        attemptPlaceRouteIfPossible()
    }
}

// -----------------------------------------------------------
// MARK: - Route placement
// -----------------------------------------------------------
extension ARSessionManager {

    private func attemptPlaceRouteIfPossible() {
        guard let arView,
              let route,
              let userLoc = LocationManager.shared.userLocation else { return }

        if originCoordinate == nil {
            originCoordinate = userLoc
        }

        clearAnchors()
        placeRoute(route, relativeTo: originCoordinate!, in: arView)
        isReady = true
    }

    private func clearAnchors() {
        guard let arView else { return }
        arrowNodes.forEach { arView.scene.removeAnchor($0.anchor) }
        arrowNodes.removeAll()
    }

    private func placeRoute(
        _ route: Route,
        relativeTo origin: CLLocationCoordinate2D,
        in arView: ARView
    ) {
        let coords = route.coordinates.map {
            CLLocationCoordinate2D(latitude: $0[0], longitude: $0[1])
        }

        let slim = downsample(coords, step: 10)
        var placed: [ArrowNode] = []

        for c in slim {
            let localPos = alignment.localPosition(for: c, relativeTo: origin)
            let anchor = AnchorEntity(world: localPos)

            let arrow = ARArrowEntity()
            anchor.addChild(arrow)

            arView.scene.addAnchor(anchor)
            placed.append(ArrowNode(coord: c, anchor: anchor, arrow: arrow))
        }

        arrowNodes = placed
        debug("Placed \(placed.count) AR arrows.")
    }
}

// -----------------------------------------------------------
// MARK: - Arrow rotation
// -----------------------------------------------------------
extension ARSessionManager {

    func updateArrowDirection(
        userLocation: CLLocationCoordinate2D,
        heading: CLLocationDirection
    ) {
        guard !arrowNodes.isEmpty else { return }

        let closest = nearestNode(to: userLocation)
        let bearingDeg = bearing(from: userLocation, to: closest.coord)

        let deltaYaw = Float((bearingDeg - heading).degreesToRadians)
        closest.arrow.updateSmoothRotation(deltaYawRadians: deltaYaw)

        lastUserLocation = userLocation
        lastHeading = heading
    }

    private func nearestNode(to coord: CLLocationCoordinate2D) -> ArrowNode {
        arrowNodes.min { a, b in
            distance(a.coord, coord) < distance(b.coord, coord)
        }!
    }
}

// -----------------------------------------------------------
// MARK: - Vision Streaming + YOLO + Depth + Fusion
// -----------------------------------------------------------
extension ARSessionManager {

    private func uploadVisionFrame(_ frame: ARFrame) {

        let now = Date()
        guard now.timeIntervalSince(lastVisionUpload) >= 0.40 else { return }
        lastVisionUpload = now

        guard let heading = lastHeading,
              let userLoc = lastUserLocation,
              let route else { return }

        guard let b64 = ARCameraFrameStreamer.base64(from: frame) else { return }

        DepthEstimator.shared.update(frame: frame)
        let distToNext = computeDistToNextNode()

        VisionUploader.shared.send(
            frameB64: b64,
            detections: [],
            heading: heading,
            distanceToNext: distToNext
        ) { result in

            switch result {
            case .success(let backendJSON):

                YOLODetector.shared.detect(frame: frame) { localYOLO in

                    let fused = HazardFusion.fuse(
                        backendJSON: backendJSON,
                        yolo: localYOLO,
                        userLocation: userLoc,
                        userHeading: heading
                    )

                    HazardOverlayManager.shared.display(
                        hazards: fused,
                        userHeading: heading
                    )
                }

            case .failure(let err):
                print("[Vision] ERR:", err.localizedDescription)
            }
        }
    }

    private func computeDistToNextNode() -> Double {
        guard let user = lastUserLocation else { return 0 }
        let node = nearestNode(to: user)
        return distance(node.coord, user)
    }
}

// -----------------------------------------------------------
// MARK: - HUD Updates (Compass + MiniMap + Progress + Turns)
// -----------------------------------------------------------
extension ARSessionManager {

    private func updateHUD(
        userLocation: CLLocationCoordinate2D,
        heading: CLLocationDirection
    ) {
        guard let route else { return }

        // Compass
        ARHUDManager.shared.updateCompass(heading: heading)

        // MiniMap
        ARHUDManager.shared.updateMiniMap(
            userLocation: userLocation,
            route: route,
            heading: heading
        )

        // Progress bar
        let progress = computeRouteProgress(userLocation: userLocation, route: route)
        ARHUDManager.shared.updateProgress(percent: progress)

        // NEW: Turn-by-turn overlay
        if let turn = route.nextInstruction(from: userLocation) {
            TurnHUDManager.shared.updateTurn(
                instruction: turn.text,
                distanceMeters: turn.distance
            )
        } else {
            TurnHUDManager.shared.updateTurn(instruction: nil, distanceMeters: nil)
        }
    }

    private func computeRouteProgress(userLocation: CLLocationCoordinate2D, route: Route) -> Double {
        let coords = route.coordinates.map { CLLocationCoordinate2D(latitude: $0[0], longitude: $0[1]) }
        guard let first = coords.first, let last = coords.last else { return 0 }

        let total = distance(first, last)
        let done  = distance(first, userLocation)

        return max(0, min(1, done / total))
    }
}

// -----------------------------------------------------------
// MARK: - ARSessionDelegate
// -----------------------------------------------------------
extension ARSessionManager: ARSessionDelegate {

    func session(_ session: ARSession, didUpdate frame: ARFrame) {

        attemptPlaceRouteIfPossible()

        guard let userLoc = LocationManager.shared.userLocation,
              let heading = LocationManager.shared.heading?.trueHeading else { return }

        updateArrowDirection(userLocation: userLoc, heading: heading)

        updateHUD(userLocation: userLoc, heading: heading)

        uploadVisionFrame(frame)
    }
}

// -----------------------------------------------------------
// MARK: - Double helpers
// -----------------------------------------------------------
private extension Double {
    var radians: Double { self * .pi / 180 }
    var degrees: Double { self * 180 / .pi }
    var degreesToRadians: Double { self * .pi / 180 }
}
