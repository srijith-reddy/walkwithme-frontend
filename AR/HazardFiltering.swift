import Foundation
import CoreLocation
import simd
import CoreGraphics

// ------------------------------------------------------------
// HAZARD FILTERING (ANTI-SPAM VERSION)
// ------------------------------------------------------------
// Applies:
//  • Relevant-label filtering
//  • Tiny-box suppression (mirror/artifacts)
//  • Near-person suppression when standing
//  • Crowd clustering
//  • Forward cone filtering
//  • Severity scoring
//
// Output: Top 3 highest-priority hazards
// ------------------------------------------------------------

struct HazardInput {
    let label: String
    let bbox: CGRect     // YOLO bbox normalized 0–1
    let distance: Double?  // meters from DepthEstimator
}

struct HazardOutput {
    let label: String
    let severity: Double
    let why: String
}

final class HazardFiltering {

    // --------------------------------------------------------
    // CONFIG (ANTI-SPAM)
    // --------------------------------------------------------
    static let MIN_BOX_AREA: CGFloat = 0.010      // suppress tiny reflections
    static let MIN_BOX_SIZE: CGFloat = 0.05       // min width & height 5%
    static let NEAR_PERSON_IGNORE: Double = 0.7   // ignore <0.7m if standing
    static let FORWARD_CONE_DEGREES: Double = 60  // narrower = fewer sides
    static let MAX_DISTANCE_M: Double = 25        // for severity
    static let CROWD_THRESHOLD = 5                // cluster 5+ persons
    static let MAX_HAZARDS = 3

    // --------------------------------------------------------
    // MAIN PIPELINE
    // --------------------------------------------------------
    static func process(
        detections: [HazardInput],
        userHeading: CLLocationDirection
    ) -> [HazardOutput] {

        let speed = LocationManager.shared.speed ?? 0   // m/s

        // 1. Relevant classes only
        let relevant = detections.filter { isRelevantLabel($0.label) }
        if relevant.isEmpty { return [] }

        // 2. Min bbox size + area filtering
        let sized = relevant.filter {
            let area = $0.bbox.width * $0.bbox.height
            return area >= MIN_BOX_AREA &&
                   $0.bbox.width >= MIN_BOX_SIZE &&
                   $0.bbox.height >= MIN_BOX_SIZE
        }

        if sized.isEmpty { return [] }

        // 3. Suppress very-near person when standing still
        let nearFiltered = sized.filter {
            if speed < 0.3 && $0.label.lowercased() == "person" {
                if let d = $0.distance, d < NEAR_PERSON_IGNORE { return false }
            }
            return true
        }

        if nearFiltered.isEmpty { return [] }

        // 4. Crowd clustering (merge many persons → 1 crowd)
        let clustered = clusterCrowd(nearFiltered)

        // 5. Forward cone (only ahead, avoid side detections)
        let forward = clustered.filter {
            isInForwardCone(bbox: $0.bbox, userHeading: userHeading)
        }

        if forward.isEmpty { return [] }

        // 6. Score & sort
        let scored = forward.map {
            HazardOutput(label: $0.label,
                         severity: computeSeverity(for: $0),
                         why: reason(for: $0))
        }

        return Array(scored.sorted { $0.severity > $1.severity }.prefix(MAX_HAZARDS))
    }

    // --------------------------------------------------------
    // Relevant label filtering
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
    // CROWD CLUSTERING
    // --------------------------------------------------------
    private static func clusterCrowd(_ dets: [HazardInput]) -> [HazardInput] {

        let persons = dets.filter { $0.label.lowercased() == "person" }

        // If many → collapse into crowd
        if persons.count >= CROWD_THRESHOLD {
            let center = averageBBox(of: persons)

            // keep everything except persons
            var others = dets.filter { $0.label.lowercased() != "person" }

            // add one CROWD hazard
            others.append(HazardInput(
                label: "crowd",
                bbox: center,
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
    // FORWARD CONE
    // --------------------------------------------------------
    private static func isInForwardCone(
        bbox: CGRect,
        userHeading: CLLocationDirection
    ) -> Bool {

        // Bbox center X → deviation from screen center (0.5)
        let centerX = bbox.midX
        let deviationDeg = abs(centerX - 0.5) * 180   // convert normalized to degrees

        return deviationDeg < (FORWARD_CONE_DEGREES / 2)
    }

    // --------------------------------------------------------
    // SEVERITY SCORE
    // --------------------------------------------------------
    private static func computeSeverity(for h: HazardInput) -> Double {
        var score = 0.0

        switch h.label.lowercased() {

        case "car", "truck", "bus":
            score += 70

        case "bike", "bicycle", "motorcycle":
            score += 55

        case "dog":
            score += 40

        case "crowd":
            score += 38

        case "person":
            score += 30

        default:
            break
        }

        // Distance scaling
        if let d = h.distance {
            let closeness = max(0, (MAX_DISTANCE_M - d)) / MAX_DISTANCE_M
            score += closeness * 30
        } else {
            score += 10 // unknown depth → mild boost
        }

        return score
    }

    // --------------------------------------------------------
    // Explanation strings
    // --------------------------------------------------------
    private static func reason(for h: HazardInput) -> String {
        switch h.label.lowercased() {
        case "car", "truck", "bus": return "Vehicle ahead"
        case "bike", "bicycle":     return "Bike approaching"
        case "crowd":               return "Crowded path"
        case "dog":                 return "Dog near path"
        case "person":              return "Person ahead"
        default:                    return "Possible hazard"
        }
    }
}
