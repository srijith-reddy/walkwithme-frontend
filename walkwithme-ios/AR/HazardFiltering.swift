import Foundation
import CoreLocation
import simd

/// ------------------------------------------------------------
/// SMART HAZARD FILTERING FOR WALKWITHME
/// ------------------------------------------------------------
/// - Input YOLO detections (label, bbox, optional distance)
/// - Filter → cluster → directional cone → score
/// - Output: **Top 3** hazards with severity
///
/// NYC-optimized: low spam, only things ahead of the user.
/// ------------------------------------------------------------

struct HazardInput {
    let label: String
    let bbox: CGRect     // YOLO 0–1 bbox
    let distance: Double?
}

struct HazardOutput {
    let label: String
    let severity: Double
    let why: String
}

final class HazardFiltering {

    // SHOW MAX 3 (updated)
    static let MAX_HAZARDS = 3

    // Users only care about things ahead
    static let FORWARD_CONE_DEGREES: Double = 70
    static let MAX_DISTANCE_M: Double = 25

    // If >=5 people → cluster into CROWD
    static let CROWD_THRESHOLD = 5

    // --------------------------------------------------------
    // MARK: - Main Filtering Pipeline
    // --------------------------------------------------------
    static func process(
        detections: [HazardInput],
        userHeading: CLLocationDirection
    ) -> [HazardOutput] {

        if detections.isEmpty { return [] }

        // 1. Only keep relevant labels
        let filtered = detections.filter { isRelevantLabel($0.label) }
        if filtered.isEmpty { return [] }

        // 2. NYC sidewalk → collapse >5 people into one crowd
        let clustered = clusterCrowd(filtered)

        // 3. Only keep things inside the forward cone
        let directional = clustered.filter {
            isInForwardCone(bbox: $0.bbox, userHeading: userHeading)
        }

        if directional.isEmpty { return [] }

        // 4. Compute severity ranking for each hazard
        let scored: [HazardOutput] = directional.map { hazard in
            HazardOutput(
                label: hazard.label == "crowd" ? "crowd" : hazard.label,
                severity: computeSeverity(for: hazard),
                why: reason(for: hazard)
            )
        }

        // 5. Sort by severity descending
        let sorted = scored.sorted { $0.severity > $1.severity }

        // 6. Return **top 3** hazards
        return Array(sorted.prefix(MAX_HAZARDS))
    }

    // --------------------------------------------------------
    // Step 1: Relevant classes
    // --------------------------------------------------------
    private static func isRelevantLabel(_ label: String) -> Bool {
        switch label.lowercased() {
        case "person", "people",
             "car", "truck", "bus",
             "bike", "bicycle", "motorcycle",
             "dog",
             "stop_sign", "traffic_light":
            return true
        default:
            return false
        }
    }

    // --------------------------------------------------------
    // Step 2: Cluster crowd
    // --------------------------------------------------------
    private static func clusterCrowd(_ dets: [HazardInput]) -> [HazardInput] {

        let persons = dets.filter { $0.label.lowercased() == "person" }

        if persons.count >= CROWD_THRESHOLD {

            // Replace people → 1 crowd hazard
            let centerBBox = averageBBox(of: persons)

            // keep everything else but people
            var others = dets.filter { $0.label.lowercased() != "person" }

            // Add crowd hazard
            others.append(HazardInput(
                label: "crowd",
                bbox: centerBBox,
                distance: nil
            ))
            return others
        }

        return dets
    }

    private static func averageBBox(of dets: [HazardInput]) -> CGRect {
        let xs = dets.map { $0.bbox.origin.x }
        let ys = dets.map { $0.bbox.origin.y }
        let ws = dets.map { $0.bbox.size.width }
        let hs = dets.map { $0.bbox.size.height }

        return CGRect(
            x: xs.reduce(0, +) / CGFloat(xs.count),
            y: ys.reduce(0, +) / CGFloat(ys.count),
            width: ws.reduce(0, +) / CGFloat(ws.count),
            height: hs.reduce(0, +) / CGFloat(hs.count)
        )
    }

    // --------------------------------------------------------
    // Step 3: Forward cone
    // --------------------------------------------------------
    private static func isInForwardCone(
        bbox: CGRect,
        userHeading: CLLocationDirection
    ) -> Bool {

        let centerX = bbox.midX

        // map x deviation to degrees
        let deviationDeg = abs(centerX - 0.5) * 180

        return deviationDeg < (FORWARD_CONE_DEGREES / 2)
    }

    // --------------------------------------------------------
    // Step 4: Severity Score
    // --------------------------------------------------------
    private static func computeSeverity(for h: HazardInput) -> Double {
        var score = 0.0

        // Base class score
        switch h.label.lowercased() {

        case "car", "truck", "bus":
            score += 70

        case "bike", "bicycle", "motorcycle":
            score += 55

        case "dog":
            score += 40

        case "crowd":
            score += 38  // slightly more than person

        case "person":
            score += 30

        default:
            break
        }

        // Distance boost
        if let d = h.distance {
            let closeness = max(0, (MAX_DISTANCE_M - d)) / MAX_DISTANCE_M
            score += closeness * 30
        } else {
            score += 10 // fallback depth
        }

        return score
    }

    // --------------------------------------------------------
    // Step 5: Explanation
    // --------------------------------------------------------
    private static func reason(for h: HazardInput) -> String {
        switch h.label.lowercased() {
        case "car", "truck", "bus": return "Vehicle ahead"
        case "bike", "bicycle": return "Bike approaching"
        case "crowd": return "Crowded path"
        case "dog": return "Dog near path"
        case "person": return "Person ahead"
        default: return "Possible hazard"
        }
    }
}
