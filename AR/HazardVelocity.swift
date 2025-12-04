import Foundation
import CoreGraphics
import QuartzCore   // Needed for CACurrentMediaTime()


/// ------------------------------------------------------------
///  WALKWITHME — HazardVelocity
/// ------------------------------------------------------------
/// Tracks YOLO detections across frames and computes:
///    • pixel velocity per axis
///    • direction
///    • approach speed (is object moving toward camera?)
/// ------------------------------------------------------------
final class HazardVelocity {

    static let shared = HazardVelocity()

    /// Stores last frame’s bbox + timestamp for each label
    /// (bbox is non-optional now, so no mismatch errors)
    private var last: [String: (bbox: CGRect, time: TimeInterval)] = [:]

    private init() {}

    // --------------------------------------------------------
    // PUBLIC — Compute velocity for each detection
    // --------------------------------------------------------
    func computeVelocity(detections: [YOLODetection]) -> [VelocityResult] {

        var results: [VelocityResult] = []
        let now = CACurrentMediaTime()

        for det in detections {
            let key = det.label.lowercased()

            guard let curBox = det.bbox else { continue }

            if let prev = last[key] {
                let dt = now - prev.time
                guard dt > 0 else { continue }

                // Pixel velocity (center difference / time)
                let dx = (curBox.midX - prev.bbox.midX) / CGFloat(dt)
                let dy = (curBox.midY - prev.bbox.midY) / CGFloat(dt)

                // Positive dy (down) in YOLO → invert to get "approach"
                let approach = -dy

                let vel = VelocityResult(
                    label: det.label,
                    dx: dx,
                    dy: dy,
                    approachSpeed: Double(approach),
                    isApproaching: approach > 0.015   // tweak threshold
                )

                results.append(vel)
            }

            // Store latest box for next frame
            last[key] = (bbox: curBox, time: now)
        }

        return results
    }
}


/// ------------------------------------------------------------
/// Returned velocity info
/// ------------------------------------------------------------
struct VelocityResult {
    let label: String
    let dx: CGFloat        // horizontal pixels/sec
    let dy: CGFloat        // vertical pixels/sec
    let approachSpeed: Double
    let isApproaching: Bool
}
