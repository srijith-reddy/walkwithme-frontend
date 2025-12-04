import Foundation
import ARKit
import UIKit

final class ARCameraFrameStreamer: NSObject, ARSessionDelegate {

    static let shared = ARCameraFrameStreamer()

    private let context = CIContext()
    private var lastUpload = Date(timeIntervalSince1970: 0)

    /// Throttle: send max 2FPS to backend
    private let uploadInterval: TimeInterval = 0.5

    /// AR Nav metadata
    var distanceToNextStep: Double = 0
    var heading: CLLocationDirection = 0

    private override init() {}

    // MARK: - ARSessionDelegate

    func session(_ session: ARSession, didUpdate frame: ARFrame) {

        // 🔥 Throttle (don’t send every frame)
        let now = Date()
        if now.timeIntervalSince(lastUpload) < uploadInterval { return }
        lastUpload = now

        // 🔥 Convert AR frame to base64
        guard let b64 = self.base64(from: frame) else { return }

        // 🔥 Upload to backend
        VisionUploader.shared.send(
            frameB64: b64,
            detections: [],  // optional
            heading: heading,
            distanceToNext: distanceToNextStep
        ) { result in
            switch result {
            case .success(let json):
                self.handleVisionResponse(json)
            case .failure(let err):
                print("[Vision] Error:", err)
            }
        }
    }

    // MARK: - Conversion

    func base64(from frame: ARFrame) -> String? {
        guard let jpeg = jpegData(from: frame) else { return nil }
        return jpeg.base64EncodedString()
    }

    func jpegData(from frame: ARFrame) -> Data? {
        let pixelBuffer = frame.capturedImage
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)

        // 🔥 Fix orientation
        let oriented = ciImage.oriented(.right)

        // 🔥 Downscale for upload speed
        let scale = 640.0 / Double(oriented.extent.width)
        let resized = oriented.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        guard let cg = context.createCGImage(resized, from: resized.extent) else {
            return nil
        }

        let ui = UIImage(cgImage: cg)
        return ui.jpegData(compressionQuality: 0.6)
    }

    // MARK: - Hazard Response

    private func handleVisionResponse(_ json: [String: Any]) {
        print("[Vision] Hazard JSON received:", json)

        // TODO: convert hazards → ARHazardEntity overlays
        // let hazards = json["hazards"] as? [String] ?? []
    }
}
