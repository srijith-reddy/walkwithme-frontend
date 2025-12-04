import Foundation
import CoreLocation
import UIKit

/// ------------------------------------------------------------
///  WALKWITHME — HazardFusion (TOP-3, VELOCITY + DEPTH READY)
/// ------------------------------------------------------------
/// Combines:
///   • Backend semantic hazards
///   • Local YOLO detections (bbox only)
///   • DepthEstimator (LiDAR → fallback Vision Depth)
///   • HazardVelocity (approaching / crossing path)
///   • HazardFiltering (NYC-safe, TOP 3 only)
///
/// OUTPUT → Top 3 hazards ready for AROverlayManager
/// ------------------------------------------------------------
final class HazardFusion {

    // --------------------------------------------------------
    // MAIN ENTRY
    // --------------------------------------------------------
    static func fuse(
        backendJSON: [String: Any],
        yolo: [YOLODetection],
        userLocation: CLLocationCoordinate2D?,
        userHeading: CLLocationDirection?
    ) -> [FusedHazard] {

        guard let userHeading else { return [] }

        // ----------------------------------------------------
        // 1. Convert YOLO → HazardInput (no depth yet)
        // ----------------------------------------------------
        let yoloInputs: [HazardInput] = yolo.map {
            HazardInput(
                label: $0.label,
                bbox: $0.bbox ?? .zero,
                distance: nil        // depth added later
            )
        }

        // ----------------------------------------------------
        // 2. Convert backend → HazardInput
        // ----------------------------------------------------
        let backendInputs = parseBackendHazards(backendJSON)

        // ----------------------------------------------------
        // 3. Merge backend + YOLO (class matching)
        // ----------------------------------------------------
        let merged = mergeHazards(
            backend: backendInputs,
            localYOLO: yoloInputs
        )

        // ----------------------------------------------------
        // 4. Apply DEPTH (LiDAR → Vision depth)
        // ----------------------------------------------------
        let withDepth = merged.map { hazard in
            let dist = DepthEstimator.shared.distanceForHazard(bbox: hazard.bbox)
            return HazardInput(
                label: hazard.label,
                bbox: hazard.bbox,
                distance: dist
            )
        }

        // ----------------------------------------------------
        // 5. Apply VELOCITY (Option A)
        // ----------------------------------------------------
        let velocities = HazardVelocity.shared.computeVelocity(detections: yolo)

        // ----------------------------------------------------
        // 6. NYC-smart filtering → top 3 hazards
        // ----------------------------------------------------
        let filteredTop3 = HazardFiltering.process(
            detections: withDepth,
            userHeading: userHeading
        )

        // ----------------------------------------------------
        // 7. Convert → AR-ready FusedHazard
        // ----------------------------------------------------
        return filteredTop3.map {
            convertToFusedHazard(
                label: $0.label,
                severity: $0.severity,
                why: $0.why,
                from: withDepth,
                velocities: velocities
            )
        }
    }

    // --------------------------------------------------------
    // Parse backend hazards
    // --------------------------------------------------------
    private static func parseBackendHazards(_ json: [String: Any]) -> [HazardInput] {

        let raw = json["hazards"] as? [String] ?? []

        return raw.map {
            HazardInput(
                label: $0,
                bbox: CGRect(x: 0.48, y: 0.48, width: 0.1, height: 0.1),
                distance: nil
            )
        }
    }

    // --------------------------------------------------------
    // Merge backend + YOLO
    // --------------------------------------------------------
    private static func mergeHazards(
        backend: [HazardInput],
        localYOLO: [HazardInput]
    ) -> [HazardInput] {

        var result: [HazardInput] = []
        var usedLocal = Set<Int>()

        for b in backend {
            var matched = false

            for (i, y) in localYOLO.enumerated() where !usedLocal.contains(i) {
                if labelsMatch(b.label, y.label) {

                    result.append(
                        HazardInput(
                            label: y.label,
                            bbox: y.bbox,
                            distance: nil
                        )
                    )

                    usedLocal.insert(i)
                    matched = true
                    break
                }
            }

            if !matched {
                result.append(b)
            }
        }

        for (i, y) in localYOLO.enumerated() where !usedLocal.contains(i) {
            result.append(y)
        }

        return result
    }

    private static func labelsMatch(_ a: String, _ b: String) -> Bool {
        let A = a.lowercased()
        let B = b.lowercased()

        if A.contains("bike") && B.contains("bike") { return true }
        if A.contains("car")  && B == "car"        { return true }
        if A.contains("bus")  && B == "bus"        { return true }
        if A.contains("truck") && B == "truck"     { return true }
        if A.contains("person") && B == "person"   { return true }
        if A.contains("crowd") && B == "person"    { return true }
        if A.contains("dog")   && B == "dog"       { return true }

        return A == B
    }

    // --------------------------------------------------------
    // 8. Convert hazard into AR overlay object (Velocity + Depth)
    // --------------------------------------------------------
    private static func convertToFusedHazard(
        label: String,
        severity: Double,
        why: String,
        from hazards: [HazardInput],
        velocities: [VelocityResult]
    ) -> FusedHazard {

        let src = hazards.first { labelsMatch(label, $0.label) }

        var finalSeverity = severity
        var explanation = why

        // ----------------------------
        // VELOCITY BOOST
        // ----------------------------
        if let v = velocities.first(where: { $0.label.lowercased() == label.lowercased() }) {

            if v.isApproaching {
                finalSeverity += 40
                explanation = "\(why) — approaching fast"
            } else if abs(v.dx) > 0.015 {
                finalSeverity += 5
                explanation = "\(why) — moving across path"
            }
        }

        return FusedHazard(
            label: label,
            severity: finalSeverity,
            explanation: explanation,
            bbox: src?.bbox ?? CGRect(x: 0.48, y: 0.48, width: 0.1, height: 0.1),
            distance: src?.distance
        )
    }
}

// ------------------------------------------------------------
// MARK: - Supporting Models
// ------------------------------------------------------------
struct YOLODetection {
    let label: String
    let bbox: CGRect?
    let confidence: Float?
}

struct HazardInput {
    let label: String
    let bbox: CGRect
    let distance: Double?
}

struct FusedHazard {
    let label: String
    let severity: Double
    let explanation: String
    let bbox: CGRect
    let distance: Double?
}
