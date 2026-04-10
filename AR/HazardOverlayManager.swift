import Foundation
import RealityKit
import CoreLocation
import Combine
import CoreGraphics

// ===========================================================
//  WALKWITHME — HazardOverlayManager
// ===========================================================
//  Tracks fused hazards from the YOLO pipeline and publishes
//  their normalised screen-X positions (0 = left, 1 = right)
//  for the 2-D SwiftUI HazardEdgeView overlay.
//
//  No RealityKit entities are added to the AR scene —
//  visual feedback is handled entirely in SwiftUI for lower
//  CPU/GPU overhead and a cleaner look.
// ===========================================================

final class HazardOverlayManager: ObservableObject {

    static let shared = HazardOverlayManager()
    private init() {}

    /// AR view reference kept for API compatibility; not used for rendering.
    weak var arView: ARView?

    // Published to ARScreen so SwiftUI can render HazardEdgeView.
    @Published var activeHazardPositions: [(label: String, normalizedX: Float)] = []

    // MARK: - Internal tracking

    private struct TrackedHazard {
        var lastSeen: Date
        var normalizedX: Float   // EMA-smoothed bbox midX (0–1)
    }

    private var tracked: [String: TrackedHazard] = [:]

    private let emaAlpha:  Float        = 0.28
    private let timeout:   TimeInterval = 1.2

    // MARK: - Main entry (called on main thread from ARSessionManager)

    func display(fused: [FusedHazard],
                 userHeading: CLLocationDirection?) {

        let now = Date()
        var seenIDs: Set<String> = []

        for hazard in fused.prefix(3) {
            let id = hazard.label.lowercased()
            seenIDs.insert(id)
            let targetX = Float(hazard.bbox.midX)

            if var entry = tracked[id] {
                entry.lastSeen   = now
                entry.normalizedX = emaAlpha * targetX + (1 - emaAlpha) * entry.normalizedX
                tracked[id] = entry
            } else {
                tracked[id] = TrackedHazard(lastSeen: now, normalizedX: targetX)
            }
        }

        cleanup(now: now, keep: seenIDs)

        activeHazardPositions = tracked.map { (label: $0.key, normalizedX: $0.value.normalizedX) }
    }

    // MARK: - Cleanup expired / removed hazards

    private func cleanup(now: Date, keep keepIDs: Set<String>) {
        for (id, entry) in tracked {
            let expired = now.timeIntervalSince(entry.lastSeen) > timeout
            if expired || !keepIDs.contains(id) {
                tracked.removeValue(forKey: id)
            }
        }
    }
}
