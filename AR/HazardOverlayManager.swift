import Foundation
import RealityKit
import ARKit
import CoreLocation
import CoreGraphics

// ===========================================================
//  WALKWITHME — HazardOverlayManager (CAMERA-RELATIVE VERSION)
// ===========================================================
//
//  ✓ Hazards tied to camera (never disappear)
//  ✓ Offset ~2.0 meters in front
//  ✓ Downward offset so you see hazards near feet when tilting
//  ✓ Billboard (always face camera)
//  ✓ Smooth EMA for side/dist
//  ✓ Auto-cleanup
// ===========================================================

final class HazardOverlayManager {

    static let shared = HazardOverlayManager()
    private init() {}

    weak var arView: ARView?

    private struct ActiveHazard {
        let anchor: AnchorEntity
        let entity: ARHazardEntity
        var lastSeen: Date
        var side: Float
        var dist: Float   // not used for world, but still for smoothing
    }

    private var active: [String: ActiveHazard] = [:]

    // Smoothing
    private let sideEmaAlpha: Float = 0.25
    private let distEmaAlpha: Float = 0.25

    // Cleanup timing
    private let timeout: TimeInterval = 1.2

    // Update gating
    private var lastUpdate = Date(timeIntervalSince1970: 0)
    private let minUpdateInterval: TimeInterval = 0.20
    private var lastHeadingRad: Float?
    private let headingDeltaThresholdDeg: CLLocationDirection = 5

    // =======================================================
    // MARK: - MAIN ENTRY
    // =======================================================
    func display(fused: [FusedHazard],
                 userHeading: CLLocationDirection?) {

        guard let arView else { return }
        let now = Date()

        let yawRad: Float =
            cameraYawRadians(from: arView)
            ?? Float((userHeading ?? 0).degreesToRadians)

        let doUpdate = shouldUpdate(now: now, headingRad: yawRad)
        var seenIDs: Set<String> = []

        for hazard in fused.prefix(3) {
            let id = hazard.label.lowercased()
            seenIDs.insert(id)

            let targetSide = sideFromBBox(hazard.bbox)
            let targetDist = distFromHazard(hazard)

            if var entry = active[id] {
                entry.lastSeen = now

                entry.side = ema(current: entry.side,
                                 target: targetSide,
                                 alpha: sideEmaAlpha)

                entry.dist = ema(current: entry.dist,
                                 target: targetDist,
                                 alpha: distEmaAlpha)

                active[id] = entry

                if doUpdate {
                    reposition(anchor: entry.anchor,
                               side: entry.side,
                               dist: entry.dist,
                               arView: arView)
                }

            } else {
                // NEW hazard
                let anchor = AnchorEntity()
                let entity = ARHazardEntity(label: hazard.label)
                anchor.addChild(entity)

                let newEntry = ActiveHazard(
                    anchor: anchor,
                    entity: entity,
                    lastSeen: now,
                    side: targetSide,
                    dist: targetDist
                )

                active[id] = newEntry

                placeInitial(anchor: anchor,
                             side: targetSide,
                             dist: targetDist,
                             arView: arView)

                arView.scene.addAnchor(anchor)
                entity.appear()

                print("➕ Added hazard '\(id)' side=\(targetSide), dist=\(targetDist)")
            }
        }

        if doUpdate {
            lastUpdate = now
            lastHeadingRad = yawRad
        }

        cleanup(now: now, keep: seenIDs)
    }

    // =======================================================
    // MARK: - CAMERA-RELATIVE INITIAL PLACEMENT
    // =======================================================
    private func placeInitial(anchor: AnchorEntity,
                              side: Float,
                              dist: Float,
                              arView: ARView) {

        let cam = arView.cameraTransform.matrix

        let camPos = SIMD3<Float>(cam.columns.3.x,
                                  cam.columns.3.y,
                                  cam.columns.3.z)

        let right   = SIMD3<Float>(cam.columns.0.x,
                                   cam.columns.0.y,
                                   cam.columns.0.z)
        let up      = SIMD3<Float>(cam.columns.1.x,
                                   cam.columns.1.y,
                                   cam.columns.1.z)
        let forward = -SIMD3<Float>(cam.columns.2.x,
                                    cam.columns.2.y,
                                    cam.columns.2.z)

        // ⭐ FINAL PLACEMENT OFFSETS
        let forwardOffset: Float = 2.0     // ⇦ sits 2m in front
        let downOffset: Float    = -0.5    // ⇦ push slightly down (visible near feet)
        
        let pos = camPos
                + forward * forwardOffset
                + right   * side
                + up      * downOffset

        anchor.position = pos
        anchor.orientation = arView.cameraTransform.rotation   // face camera
    }

    // =======================================================
    // MARK: - CAMERA-RELATIVE REPOSITION
    // =======================================================
    private func reposition(anchor: AnchorEntity,
                            side: Float,
                            dist: Float,
                            arView: ARView) {

        let cam = arView.cameraTransform.matrix

        let camPos = SIMD3<Float>(cam.columns.3.x,
                                  cam.columns.3.y,
                                  cam.columns.3.z)

        let right   = SIMD3<Float>(cam.columns.0.x,
                                   cam.columns.0.y,
                                   cam.columns.0.z)
        let up      = SIMD3<Float>(cam.columns.1.x,
                                   cam.columns.1.y,
                                   cam.columns.1.z)
        let forward = -SIMD3<Float>(cam.columns.2.x,
                                    cam.columns.2.y,
                                    cam.columns.2.z)

        // Same offsets as initial placement
        let forwardOffset: Float = 2.0
        let downOffset: Float    = -0.5

        let pos = camPos
                + forward * forwardOffset
                + right   * side
                + up      * downOffset

        anchor.move(
            to: Transform(translation: pos),
            relativeTo: nil,
            duration: 0.15,
            timingFunction: .easeInOut
        )

        anchor.orientation = arView.cameraTransform.rotation
    }

    // =======================================================
    // MARK: - HELPERS
    // =======================================================

    private func sideFromBBox(_ bbox: CGRect) -> Float {
        let midX = Float(bbox.midX)
        // maps bbox mid to ±0.5 meters at 2m distance
        return max(-0.5, min(0.5, (midX - 0.5)))
    }

    private func distFromHazard(_ h: FusedHazard) -> Float {
        // smoothing dist still helps with animation, not world placement
        if let d = h.distance, d.isFinite {
            return max(1.0, min(Float(d), 4.0))
        }
        return 2.0
    }

    private func ema(current: Float,
                     target: Float,
                     alpha: Float) -> Float {
        return alpha * target + (1 - alpha) * current
    }

    private func shouldUpdate(now: Date,
                              headingRad: Float) -> Bool {

        let timeOK = now.timeIntervalSince(lastUpdate) >= minUpdateInterval

        let angleOK: Bool
        if let last = lastHeadingRad {
            let a = Double(last * 180 / .pi)
            let b = Double(headingRad * 180 / .pi)
            angleOK = angularDiffDegrees(a: a, b: b) >= headingDeltaThresholdDeg
        } else {
            angleOK = true
        }

        return timeOK || angleOK
    }

    private func angularDiffDegrees(a: CLLocationDirection,
                                    b: CLLocationDirection) -> CLLocationDirection {
        var d = abs(a - b).truncatingRemainder(dividingBy: 360)
        if d > 180 { d = 360 - d }
        return d
    }

    private func cleanup(now: Date, keep keepIDs: Set<String>) {
        guard let arView else { return }

        for (id, entry) in active {
            let expired = now.timeIntervalSince(entry.lastSeen) > timeout
            let removed = !keepIDs.contains(id)

            if expired || removed {
                entry.entity.disappear()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    arView.scene.removeAnchor(entry.anchor)
                }
                active.removeValue(forKey: id)
            }
        }
    }

    private func cameraYawRadians(from arView: ARView) -> Float? {
        let q = arView.cameraTransform.rotation
        let yaw = atan2f(
            2 * (q.imag.y * q.real + q.imag.x * q.imag.z),
            1 - 2 * (q.imag.y * q.imag.y + q.imag.z * q.imag.z)
        )
        return yaw.isFinite ? yaw : nil
    }
}

private extension CLLocationDirection {
    var degreesToRadians: Double { self * .pi / 180 }
}
