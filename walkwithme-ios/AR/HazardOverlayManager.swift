import Foundation
import RealityKit
import ARKit
import CoreLocation

/// -----------------------------------------------------------
///  WALKWITHME — HazardOverlayManager (TOP-3 VERSION)
/// -----------------------------------------------------------
/// Responsibilities:
///   ✓ Receives final fused hazards (up to 3)
///   ✓ Creates ARHazardEntity icons
///   ✓ Places them 3–6 meters ahead with stable offsets
///   ✓ Smooth motion as user turns / walks
///   ✓ Removes stale hazards
/// -----------------------------------------------------------
final class HazardOverlayManager {

    static let shared = HazardOverlayManager()
    private init() {}

    weak var arView: ARView?

    /// Currently visible AR hazards
    private var active: [String: (entity: ARHazardEntity, lastSeen: Date)] = [:]

    /// Placement tuning
    private let baseDistance: Float = 3.0
    private let maxDistance: Float  = 6.2
    private let sideOffset: Float   = 1.0

    /// Remove hazards if they don’t appear for 1.2s
    private let timeout: TimeInterval = 1.2

    // ---------------------------------------------------------
    // MARK: - Public API
    // ---------------------------------------------------------
    /// Called by ARSessionManager after hazard fusion
    func display(fused: [FusedHazard],
                 userHeading: CLLocationDirection?) {

        guard let arView else { return }
        guard let userHeading else { return }

        let now = Date()

        // stable placement per index (left, center, right)
        let indexed = Array(fused.prefix(3)).enumerated()

        var seenIDs: Set<String> = []

        for (i, hazard) in indexed {

            let hazardID = hazard.label.lowercased()

            seenIDs.insert(hazardID)

            if let entry = active[hazardID] {
                // Exists → update position
                active[hazardID]?.lastSeen = now
                reposition(entry.entity, index: i, heading: userHeading)
            } else {
                // New hazard → create
                let entity = ARHazardEntity(label: hazard.label)
                active[hazardID] = (entity, now)

                placeInitial(entity,
                             index: i,
                             heading: userHeading)

                arView.scene.addAnchor(entity)
                entity.appear()
            }
        }

        // Remove old hazards not in current frame
        cleanup(now: now, keep: seenIDs)
    }

    // ---------------------------------------------------------
    // MARK: - Placement
    // ---------------------------------------------------------

    /// Initial placement when entity spawns
    private func placeInitial(_ entity: ARHazardEntity,
                              index: Int,
                              heading: CLLocationDirection) {

        let yaw = Float(heading.degreesToRadians)

        let forward = SIMD3<Float>(-sin(yaw), 0, -cos(yaw))
        let right   = SIMD3<Float>(cos(yaw), 0, -sin(yaw))

        // Assign left/center/right offsets by index
        let side = offsetForIndex(index)

        let dist = Float.random(in: baseDistance...(baseDistance + 1.2))
        let pos = forward * dist + right * side

        entity.position = [pos.x, 0.55, pos.z]
    }

    /// Smooth reposition for each frame update
    private func reposition(_ entity: ARHazardEntity,
                            index: Int,
                            heading: CLLocationDirection) {

        let yaw = Float(heading.degreesToRadians)

        let forward = SIMD3<Float>(-sin(yaw), 0, -cos(yaw))
        let right   = SIMD3<Float>(cos(yaw), 0, -sin(yaw))

        let side = offsetForIndex(index)
        let dist = Float.random(in: baseDistance...maxDistance)

        let newPos = forward * dist + right * side

        entity.move(
            to: Transform(translation: SIMD3<Float>(newPos.x, 0.55, newPos.z)),
            relativeTo: nil,
            duration: 0.35,
            timingFunction: .easeInOut
        )
    }

    /// Left = -offset, Center = 0, Right = +offset
    private func offsetForIndex(_ index: Int) -> Float {
        switch index {
        case 0: return -sideOffset     // left
        case 1: return 0               // center
        case 2: return sideOffset      // right
        default: return 0
        }
    }

    // ---------------------------------------------------------
    // MARK: - Cleanup
    // ---------------------------------------------------------
    private func cleanup(now: Date, keep keepIDs: Set<String>) {

        guard let arView else { return }

        for (id, entry) in active {
            let expired = now.timeIntervalSince(entry.lastSeen) > timeout
            let removed = !keepIDs.contains(id)

            if expired || removed {

                entry.entity.disappear()

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    arView.scene.removeAnchor(entry.entity)
                }

                active.removeValue(forKey: id)
            }
        }
    }
}

// ---------------------------------------------------------
// MARK: - Helpers
// ---------------------------------------------------------
private extension CLLocationDirection {
    var degreesToRadians: Double { self * .pi / 180 }
}
