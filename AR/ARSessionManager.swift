import Foundation
import Combine
import CoreLocation
import ARKit
import RealityKit
import CoreImage
import UIKit

// =====================================================
//  ARSessionManager.swift — FULL UPDATED VERSION
// =====================================================

final class ARSessionManager: NSObject, ObservableObject {

    let objectWillChange = ObservableObjectPublisher()
    static let shared = ARSessionManager()

    @Published private(set) var isReady = false

    private var arView: ARView?
    private var route: Route?
    private var origin: CLLocationCoordinate2D?

    // World anchor for entire route
    private var routeAnchor: AnchorEntity?

    private var startMarker: ARArrowEntity?
    private var endMarker: ARArrowEntity?

    private var chevrons: [(coord: CLLocationCoordinate2D, entity: ARRouteChevronEntity)] = []

    private let visionQueue = DispatchQueue(label: "com.walkwithme.vision", qos: .userInitiated)
    private let ciContext = CIContext()

    // Timers
    private var hudTimer: Timer?

    // Vision throttles
    private var lastYOLO = Date(timeIntervalSince1970: 0)
    private var lastUpload = Date(timeIntervalSince1970: 0)
    private var lastDepth = Date(timeIntervalSince1970: 0)
    private let depthInterval: TimeInterval = 0.10
    private let yoloInterval: TimeInterval = 0.45
    private let uploadInterval: TimeInterval = 1.0

    private var lastDetections: [YOLODetection] = []

    // Chevron rotation gating
    private var lastChevronUpdate = Date(timeIntervalSince1970: 0)
    private let minChevronUpdateInterval: TimeInterval = 0.12
    private var lastHeadingForChevrons: CLLocationDirection?
    private let maxChevronsPerTick = 5
    private let minAngleDeltaDeg: Double = 3.0

    private let chevronSpacingMeters: CLLocationDistance = 20

    private override init() { super.init() }
}

// =====================================================
//  CONFIGURE AR SESSION
// =====================================================

extension ARSessionManager {

    func configureSession(arView: ARView) {
        self.arView = arView

        LocationManager.shared.start()
        HazardOverlayManager.shared.arView = arView
        ARHUDManager.shared.attach(to: arView)
        TurnHUDManager.shared.attach(to: arView)
        FusionDebugOverlay.shared.arView = arView

        let config = ARWorldTrackingConfiguration()
        config.worldAlignment = .gravity
        config.planeDetection = [.horizontal]

        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            config.frameSemantics.insert(.sceneDepth)
        }

        if let f = ARWorldTrackingConfiguration.supportedVideoFormats
            .filter({ $0.imageResolution.width <= 1280 })
            .min(by: { $0.imageResolution.width < $1.imageResolution.width }) {
            config.videoFormat = f
        }

        arView.automaticallyConfigureSession = false
        arView.session.delegate = self
        arView.session.run(config)

        startTimers()
    }

    private func startTimers() {
        hudTimer?.invalidate()

        hudTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
            guard let self,
                  let route = self.route,
                  let loc = LocationManager.shared.userLocation,
                  let h = LocationManager.shared.heading?.trueHeading else { return }

            ARHUDManager.shared.updateCompass(heading: h)
            ARHUDManager.shared.updateMiniMap(userLocation: loc, route: route, heading: h)
            ARHUDManager.shared.updateProgress(percent: self.progress(loc: loc, route: route))

            if let t = route.nextInstruction(from: loc) {
                TurnHUDManager.shared.updateTurn(instruction: t.text, distanceMeters: t.distance)
            } else {
                TurnHUDManager.shared.updateTurn(instruction: nil, distanceMeters: nil)
            }
        }
    }
}

// =====================================================
//  ROUTE PLACEMENT
// =====================================================

extension ARSessionManager {

    func loadRoute(_ r: Route) {
        route = r
        origin = nil
        isReady = false
        clearAnchors()
        placeIfPossible()
    }

    private func placeIfPossible() {
        guard let arView,
              let route,
              LocationManager.shared.userLocation != nil else { return }
        guard !isReady else { return }

        if origin == nil {
            if let user = LocationManager.shared.userLocation {
                origin = user
            } else if let first = route.coordinates.first {
                origin = CLLocationCoordinate2D(latitude: first[0], longitude: first[1])
            }
        }
        guard let origin else { return }

        clearAnchors()

        let anchor = AnchorEntity(world: .zero)
        routeAnchor = anchor
        arView.scene.addAnchor(anchor)

        let aligner = ARAlignment()
        aligner.setOrigin(origin)

        // START marker
        if let first = route.coordinatePoints.first {
            let pos = aligner.localPosition(for: first, relativeTo: origin)
            let start = ARArrowEntity()
            start.scale = SIMD3<Float>(repeating: 1.2)
            start.position = pos
            anchor.addChild(start)
            startMarker = start
        }

        // END marker
        if let last = route.coordinatePoints.last {
            let pos = aligner.localPosition(for: last, relativeTo: origin)
            let end = ARArrowEntity()
            end.scale = SIMD3<Float>(repeating: 1.2)
            end.position = pos
            anchor.addChild(end)
            endMarker = end
        }

        // Chevrons
        let coords = route.coordinatePoints
        let sampled = sampleByDistance(coords: coords, spacingMeters: chevronSpacingMeters)
        chevrons.removeAll()

        for c in sampled {
            let wp = aligner.localPosition(for: c, relativeTo: origin)
            let chev = ARRouteChevronEntity(symbolName: "arrowtriangle.forward.fill", tint: .systemBlue)
            chev.position = wp
            chev.scale = SIMD3<Float>(repeating: 0.01)
            anchor.addChild(chev)

            chev.move(to: Transform(scale: SIMD3<Float>(repeating: 1.0),
                                    rotation: chev.transform.rotation,
                                    translation: chev.transform.translation),
                      relativeTo: chev.parent,
                      duration: 0.22,
                      timingFunction: .easeInOut)

            chevrons.append((c, chev))
        }

        isReady = true
    }

    private func clearAnchors() {
        guard let arView else { return }
        if let routeAnchor {
            arView.scene.removeAnchor(routeAnchor)
        }
        routeAnchor = nil
        startMarker = nil
        endMarker = nil
        chevrons.removeAll()
    }

    private func sampleByDistance(coords: [CLLocationCoordinate2D],
                                  spacingMeters: CLLocationDistance)
        -> [CLLocationCoordinate2D] {

        guard coords.count >= 2 else { return coords }

        var result: [CLLocationCoordinate2D] = []
        result.reserveCapacity(coords.count)

        var lastKept = coords[0]
        result.append(lastKept)
        var accumulated: CLLocationDistance = 0

        for i in 1..<coords.count {
            let cur = coords[i]
            let d = distance(lastKept, cur)
            accumulated += d

            if accumulated >= spacingMeters {
                result.append(cur)
                lastKept = cur
                accumulated = 0
            }
        }

        if let last = coords.last,
           last.latitude != result.last?.latitude ||
           last.longitude != result.last?.longitude {
            result.append(last)
        }

        return result
    }
}

// =====================================================
//  CHEVRON ROTATION
// =====================================================

extension ARSessionManager {

    private func updateChevronsIfNeeded(
        userLocation: CLLocationCoordinate2D,
        heading: CLLocationDirection
    ) {

        let now = Date()
        let timeOK = now.timeIntervalSince(lastChevronUpdate) >= minChevronUpdateInterval

        var angleOK = true
        if let lastH = lastHeadingForChevrons {
            var diff = abs(heading - lastH).truncatingRemainder(dividingBy: 360)
            if diff > 180 { diff = 360 - diff }
            angleOK = diff >= minAngleDeltaDeg
        }

        guard timeOK || angleOK else { return }
        guard !chevrons.isEmpty else { return }

        let sorted = chevrons.sorted {
            distance($0.coord, userLocation) < distance($1.coord, userLocation)
        }

        for item in sorted.prefix(maxChevronsPerTick) {
            let bearingDeg = bearing(from: userLocation, to: item.coord)
            let yaw = Float((bearingDeg - heading) * .pi / 180)

            let q = item.entity.transform.rotation
            let currentYaw = atan2f(
                2*(q.vector.y*q.vector.w + q.vector.x*q.vector.z),
                1 - 2*(q.vector.y*q.vector.y + q.vector.z*q.vector.z)
            )

            if abs(Double(yaw - currentYaw)) < (minAngleDeltaDeg * .pi / 180) {
                continue
            }

            item.entity.safeRotate(to: yaw, animate: true)
        }

        lastChevronUpdate = now
        lastHeadingForChevrons = heading
    }
}

// =====================================================
//  JPEG + YOLO RESIZE
// =====================================================

extension ARSessionManager {

    func encodeJPEGFast(_ cg: CGImage) -> Data? {
        let img = UIImage(cgImage: cg)
        return img.jpegData(compressionQuality: 0.55)
    }

    func resizeCGImage(_ img: CGImage, to size: CGSize) -> CGImage? {
        let width = Int(size.width)
        let height = Int(size.height)

        guard let ctx = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return nil }

        ctx.interpolationQuality = .high
        ctx.draw(img, in: CGRect(origin: .zero, size: size))

        return ctx.makeImage()
    }
}

// =====================================================
//  BACKEND UPLOAD
// =====================================================

extension ARSessionManager {

    func uploadHazards(yolo: [YOLODetection]) {
        VisionUploader.shared.send(
            yolo: yolo,
            heading: LocationManager.shared.heading?.trueHeading,
            distanceToNext: 0
        ) { res in

            if case .success(let json) = res {
                let obj = ARSessionManager.decodeBackend(json)

                let fused = HazardFusion.fuse(
                    backendJSON: obj,
                    yolo: yolo,
                    userLocation: LocationManager.shared.userLocation ?? .init(),
                    userHeading: LocationManager.shared.heading?.trueHeading ?? 0
                )

                DispatchQueue.main.async {
                    FusionDebugOverlay.shared.update(fused: fused)
                    HazardOverlayManager.shared.display(
                        fused: fused,
                        userHeading: LocationManager.shared.heading?.trueHeading
                    )
                }
            }
        }
    }
}

// =====================================================
//  JSON DECODE
// =====================================================

extension ARSessionManager {

    static func decodeBackend(_ json: [String: Any]) -> [String: Any] {
        if let s = json["analysis"] as? String,
           let data = s.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return obj
        }
        return json
    }

    private func progress(loc: CLLocationCoordinate2D, route: Route) -> Double {
        guard let first = route.coordinates.first,
              let last = route.coordinates.last else { return 0 }

        let start = CLLocationCoordinate2D(latitude: first[0], longitude: first[1])
        let end = CLLocationCoordinate2D(latitude: last[0], longitude: last[1])

        let total = max(distance(start, end), 0.001)
        let remaining = distance(loc, end)
        return max(0.0, min(1.0, 1.0 - (remaining / total)))
    }
}

// =====================================================
//  UPDATED — ARSessionDelegate WITH CONTEXT GATE
// =====================================================

extension ARSessionManager: ARSessionDelegate {

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        autoreleasepool {

            let now = Date()

            // ---------------------------------------------------
            // CONTEXT GATE (critical to reduce indoor spam)
            // ---------------------------------------------------
            let hasRoute = (route != nil)
            let gpsOK = LocationManager.shared.userLocation != nil
            let speed = LocationManager.shared.speed ?? 0
            let moving = speed > 0.35

            let allowVision =
                hasRoute &&
                gpsOK &&
                (moving || now.timeIntervalSince(lastYOLO) > 2.0)

            if !allowVision {
                return
            }

            // ---------------------------------------------------
            // TIMERS
            // ---------------------------------------------------
            let needYOLO = now.timeIntervalSince(lastYOLO) >= yoloInterval
            let needUpload = now.timeIntervalSince(lastUpload) >= uploadInterval
            let needDepth = now.timeIntervalSince(lastDepth) >= depthInterval

            // Always let chevrons move even if no YOLO
            if let loc = LocationManager.shared.userLocation,
               let h = LocationManager.shared.heading?.trueHeading {
                updateChevronsIfNeeded(userLocation: loc, heading: h)
            }

            guard needYOLO || needUpload || needDepth else { return }

            let pb = frame.capturedImage

            // ---------------------------------------------------
            // DEPTH
            // ---------------------------------------------------
            if needDepth {
                DepthEstimator.shared.update(
                    depthMap: frame.sceneDepth?.depthMap,
                    capturedImage: pb
                )
                lastDepth = now
            }

            // ---------------------------------------------------
            // YOLO + UPLOAD PIPELINE
            // ---------------------------------------------------
            if needYOLO || needUpload {

                let ci = CIImage(cvPixelBuffer: pb).oriented(.right)
                guard let originalCG = ciContext.createCGImage(ci, from: ci.extent) else { return }
                guard let cg = resizeCGImage(originalCG, to: CGSize(width: 640, height: 640)) else { return }

                visionQueue.async { [weak self] in
                    guard let self else { return }

                    let t = Date()
                    let runYOLO = t.timeIntervalSince(self.lastYOLO) >= self.yoloInterval
                    let runUpload = t.timeIntervalSince(self.lastUpload) >= self.uploadInterval

                    // -------- YOLO RUN --------
                    if runYOLO {
                        self.lastYOLO = t
                        YOLODetector.shared.detect(cgImage: cg) { dets in
                            self.lastDetections = dets

                            if runUpload {
                                self.lastUpload = t
                                self.uploadHazards(yolo: dets)
                            }
                        }
                    }

                    // -------- UPLOAD ONLY --------
                    else if runUpload {
                        self.lastUpload = t
                        self.uploadHazards(yolo: self.lastDetections)
                    }
                }
            }
        }
    }
}
