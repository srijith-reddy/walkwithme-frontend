import Foundation
import CoreLocation
import UIKit

// ------------------------------------------------------------
// MARK: - Public FusedHazard (AR-ready)
// ------------------------------------------------------------
struct FusedHazard {
    let id: String
    let label: String
    let source: String       // "yolo" (backend has no bbox → not used as source)
    let severity: Double
    let explanation: String
    let bbox: CGRect         // MUST come from YOLO
    let distance: Double?
}

// ------------------------------------------------------------
// MARK: - Internal TaggedHazardInput
// ------------------------------------------------------------
private struct TaggedHazardInput {
    let label: String
    let bbox: CGRect?        // YOLO only
    let distance: Double?
    let source: String       // "yolo" only in final system
}

// ------------------------------------------------------------
// MARK: - FINAL HAZARD FUSION PIPELINE
// ------------------------------------------------------------
final class HazardFusion {

    // ============================================================
    // MAIN ENTRY POINT
    // ============================================================
    static func fuse(
        backendJSON: [String: Any],
        yolo: [YOLODetection],
        userLocation: CLLocationCoordinate2D?,
        userHeading: CLLocationDirection?
    ) -> [FusedHazard] {

        guard let userHeading else { return [] }

        // --------------------------------------------------------
        // 1. YOLO detections → TaggedHazardInput
        // --------------------------------------------------------
        let yoloInputs: [TaggedHazardInput] = yolo.compactMap {
            guard let box = $0.bbox else { return nil }
            return TaggedHazardInput(
                label: $0.label,
                bbox: box,
                distance: nil,
                source: "yolo"
            )
        }

        // --------------------------------------------------------
        // 2. Backend hazards → labels only (no bounding boxes)
        // --------------------------------------------------------
        let backendLabels = parseBackendLabels(backendJSON)

        // --------------------------------------------------------
        // 3. Depth inference for each YOLO box
        // --------------------------------------------------------
        let withDepth: [TaggedHazardInput] = yoloInputs.map { h in
            let dist = DepthEstimator.shared.distanceForHazard(bbox: h.bbox!, label: h.label)
            return TaggedHazardInput(
                label: h.label,
                bbox: h.bbox,
                distance: dist,
                source: h.source
            )
        }

        // --------------------------------------------------------
        // 4. Velocity
        // --------------------------------------------------------
        let velocities = HazardVelocity.shared.computeVelocity(detections: yolo)

        // --------------------------------------------------------
        // 5. Filtering & Top-3 selection
        // --------------------------------------------------------
        let filtered = HazardFiltering.process(
            detections: withDepth.map {
                HazardInput(label: $0.label, bbox: $0.bbox!, distance: $0.distance)
            },
            userHeading: userHeading
        )

        // --------------------------------------------------------
        // 6. Convert → FusedHazard
        // --------------------------------------------------------
        return filtered.compactMap { out in
            convertToFused(
                out: out,
                yoloTagged: withDepth,
                backendBoost: backendLabels,
                velocities: velocities
            )
        }
    }

    // ============================================================
    // Backend → label set
    // ============================================================
    private static func parseBackendLabels(_ json: [String: Any]) -> Set<String> {
        let arr = json["hazards"] as? [String] ?? []
        return Set(arr.map { $0.lowercased() })
    }

    // ============================================================
    // Convert HazardOutput → AR-ready FusedHazard
    // ============================================================
    private static func convertToFused(
        out: HazardOutput,
        yoloTagged: [TaggedHazardInput],
        backendBoost: Set<String>,
        velocities: [VelocityResult]
    ) -> FusedHazard? {

        // Must match YOLO class to get bbox + depth
        guard let src = yoloTagged.first(where: {
            $0.label.lowercased() == out.label.lowercased()
        }) else {
            return nil
        }

        guard let bbox = src.bbox else { return nil }

        var severity = out.severity
        var explanation = out.why

        // --------------------------------------------------------
        // A. Backend semantic confirmation → boost
        // --------------------------------------------------------
        if backendBoost.contains(out.label.lowercased()) {
            severity += 8
            explanation += " — confirmed by backend"
        }

        // --------------------------------------------------------
        // B. Velocity-based boosts
        // --------------------------------------------------------
        if let vel = velocities.first(where: {
            $0.label.lowercased() == out.label.lowercased()
        }) {
            if vel.isApproaching {
                severity += 40
                explanation += " — approaching fast"
            } else if abs(vel.dx) > 0.015 {
                severity += 5
                explanation += " — moving across path"
            }
        }

        // --------------------------------------------------------
        // Final fused hazard
        // --------------------------------------------------------
        return FusedHazard(
            id: "yolo-\(out.label.lowercased())",
            label: src.label,
            source: "yolo",          // backend has no bbox → cannot be a source
            severity: severity,
            explanation: explanation,
            bbox: bbox,
            distance: src.distance
        )
    }
}
