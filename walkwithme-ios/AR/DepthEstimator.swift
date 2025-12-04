import Foundation
import ARKit
import Vision
import UIKit

final class DepthEstimator {

    static let shared = DepthEstimator()

    private init() {}

    // ---------------------------------------------------------
    // MAIN API
    // ---------------------------------------------------------
    /// Returns: real-world distance (meters) for the object center.
    /// Priority:
    ///    1) LiDAR
    ///    2) Apple Vision Depth
    ///    3) YOLO BBox fallback
    func estimateDistance(
        frame: ARFrame,
        bbox: CGRect?,          // YOLO bbox in 0–1 normalized
        label: String
    ) -> Double? {

        // 1) LiDAR depth (best)
        if let lidar = lidarDepth(frame: frame, bbox: bbox) {
            return lidar
        }

        // 2) Vision Depth API
        if let depth = visionDepth(frame: frame, bbox: bbox) {
            return depth
        }

        // 3) Fallback: YOLO bbox → approximate distance
        if let box = bbox {
            return bboxFallbackDistance(box: box, label: label)
        }

        return nil
    }

    // ---------------------------------------------------------
    // 1) LiDAR—SceneDepth
    // ---------------------------------------------------------
    private func lidarDepth(frame: ARFrame, bbox: CGRect?) -> Double? {
        guard let depthMap = frame.sceneDepth?.depthMap else {
            return nil
        }

        guard let bbox else { return nil }

        // Sample center pixel
        let w = depthMap.width
        let h = depthMap.height
        let px = Int(CGFloat(w) * bbox.midX)
        let py = Int(CGFloat(h) * bbox.midY)

        guard px >= 0, px < w, py >= 0, py < h else { return nil }

        let distance = depthMap.floatChannel(at: px, y: py)
        if distance.isFinite, distance > 0 {
            return Double(distance)
        }

        return nil
    }

    // ---------------------------------------------------------
    // 2) Vision Depth (iOS 17+)
    // ---------------------------------------------------------
    private func visionDepth(frame: ARFrame, bbox: CGRect?) -> Double? {
        guard #available(iOS 17.0, *),
              let bbox else { return nil }

        let request = VNGenerateDepthImageRequest()
        let handler = VNImageRequestHandler(
            cvPixelBuffer: frame.capturedImage,
            options: [:]
        )

        do {
            try handler.perform([request])
            guard let depth = request.results?.first else { return nil }

            let map = depth.depthMap

            let w = CVPixelBufferGetWidth(map)
            let h = CVPixelBufferGetHeight(map)

            let px = Int(CGFloat(w) * bbox.midX)
            let py = Int(CGFloat(h) * bbox.midY)

            CVPixelBufferLockBaseAddress(map, .readOnly)
            let row = CVPixelBufferGetBaseAddress(map)! + py * CVPixelBufferGetBytesPerRow(map)
            let depthVal = row.assumingMemoryBound(to: Float32.self)[px]
            CVPixelBufferUnlockBaseAddress(map, .readOnly)

            if depthVal.isFinite, depthVal > 0 {
                return Double(depthVal)
            }
        } catch {
            return nil
        }

        return nil
    }

    // ---------------------------------------------------------
    // 3) Fallback: YOLO bbox → distance approximation
    // ---------------------------------------------------------
    private func bboxFallbackDistance(box: CGRect, label: String) -> Double {

        let size = (box.width + box.height) / 2.0   // normalized (0–1)

        // Tuned heuristics (good enough)
        switch label.lowercased() {

        case "person", "people":
            return Double(1.0 / max(size, 0.05)) * 1.2   // people often close

        case "dog":
            return Double(1.0 / max(size, 0.05)) * 0.8

        case "car", "truck", "bus":
            return Double(1.0 / max(size, 0.05)) * 3.0

        default:
            return Double(1.0 / max(size, 0.05)) * 2.0
        }
    }
}

private extension CVPixelBuffer {
    func floatChannel(at x: Int, y: Int) -> Float {
        CVPixelBufferLockBaseAddress(self, .readOnly)
        let row = CVPixelBufferGetBaseAddress(self)! + y * CVPixelBufferGetBytesPerRow(self)
        let val = row.assumingMemoryBound(to: Float32.self)[x]
        CVPixelBufferUnlockBaseAddress(self, .readOnly)
        return val
    }
}
