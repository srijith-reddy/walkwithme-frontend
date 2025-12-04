import Foundation
import CoreML
import Vision
import UIKit
import ARKit

/// ------------------------------------------------------------
///  WALKWITHME — YOLODetector
/// ------------------------------------------------------------
/// Processes each ARFrame:
///   ARFrame → YOLO (CoreML/Vision) → [YOLODetection]
///
/// Distance is NOT computed here.
/// DepthEstimator handles that later.
/// ------------------------------------------------------------
final class YOLODetector {

    static let shared = YOLODetector()
    private init() { loadModel() }

    private var visionModel: VNCoreMLModel?

    // Prevent YOLO from running too fast
    private var lastRun = Date(timeIntervalSince1970: 0)
    private let minInterval: TimeInterval = 0.20   // 5 FPS YOLO

    // ------------------------------------------------------------
    // Load YOLO model
    // ------------------------------------------------------------
    private func loadModel() {
        do {
            // ⚠️ Replace "YOLOv8n" with your actual .mlmodel class name
            let model = try YOLOv8n(configuration: MLModelConfiguration())
            visionModel = try VNCoreMLModel(for: model.model)
            print("🔥 YOLO model loaded.")
        } catch {
            print("❌ Failed to load YOLO model:", error.localizedDescription)
        }
    }

    // ------------------------------------------------------------
    // MAIN API: Run YOLO on ARFrame
    // ------------------------------------------------------------
    func detect(
        frame: ARFrame,
        completion: @escaping ([YOLODetection]) -> Void
    ) {

        // Throttle YOLO calls
        let now = Date()
        guard now.timeIntervalSince(lastRun) >= minInterval else {
            completion([])
            return
        }
        lastRun = now

        guard let model = visionModel else {
            completion([])
            return
        }

        let request = VNCoreMLRequest(model: model) { req, err in
            if let err = err {
                print("YOLO error:", err.localizedDescription)
                completion([])
                return
            }

            guard let results = req.results as? [VNRecognizedObjectObservation] else {
                completion([])
                return
            }

            // Convert Vision detections → YOLODetection
            let mapped: [YOLODetection] = results.map { obs in
                let label = obs.labels.first?.identifier ?? "unknown"

                // bbox is already normalized (y-up coordinate system)
                let normBox = CGRect(
                    x: obs.boundingBox.origin.x,
                    y: obs.boundingBox.origin.y,
                    width: obs.boundingBox.size.width,
                    height: obs.boundingBox.size.height
                )

                return YOLODetection(
                    label: label,
                    bbox: normBox,
                    confidence: obs.confidence
                )
            }

            completion(mapped)
        }

        request.imageCropAndScaleOption = .scaleFill

        // Run YOLO in background
        let handler = VNImageRequestHandler(
            cvPixelBuffer: frame.capturedImage,
            orientation: .up,
            options: [:]
        )

        DispatchQueue.global(qos: .userInitiated).async {
            try? handler.perform([request])
        }
    }
}
