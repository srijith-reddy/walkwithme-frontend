import Foundation
import CoreGraphics

/// ------------------------------------------------------------
///  WALKWITHME — HazardVelocity
/// ------------------------------------------------------------
/// Tracks YOLO detections across frames and computes:
///    • pixel velocity
///    • direction of motion (toward / away / left / right)
///    • is object approaching user?
/// ------------------------------------------------------------
final class HazardVelocity {

    static let shared = HazardVelocity()

    /// Store last frame’s detections (indexed by label)
    private var last: [String: (bbox: CGRect, time: TimeInterval)] = [:]

    private init() {}

    // --------------------------------------------------------
    // PUBLIC: Compute velocity for each detection
    // --------------------------------------------------------
    func computeVelocity(detections: [YOLODetection]) -> [VelocityResult] {

        var results: [VelocityResult] = []
        let now = CACurrentMediaTime()

        for det in detections {
            let key = det.label.lowercased()

            if let prev = last[key] {
                let dt = now - prev.time
                guard dt > 0 else { continue }

                // Movement vector (bbox center difference)
                let dx = (det.bbox.midX - prev.bbox.midX) / CGFloat(dt)
                let dy = (det.bbox.midY - prev.bbox.midY) / CGFloat(dt)

                // Approach speed (vertical movement toward center)
                let approach = -dy    // YOLO Y-axis is inverted

                let vel = VelocityResult(
                    label: det.label,
                    dx: dx,
                    dy: dy,
                    approachSpeed: Double(approach),
                    isApproaching: approach > 0.015    // tuned threshold
                )

                results.append(vel)
            }

            // Update stored detection
            last[key] = (det.bbox, now)
        }

        return results
    }
}

/// ------------------------------------------------------------
/// Velocity result returned for each detection
/// ------------------------------------------------------------
struct VelocityResult {
    let label: String
    let dx: CGFloat
    let dy: CGFloat
    let approachSpeed: Double
    let isApproaching: Bool
}
