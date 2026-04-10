import UIKit
import ARKit
import CoreImage

final class CameraFrameExtractor {

    static let shared = CameraFrameExtractor()
    private let context = CIContext()

    private init() {}

    // MARK: - Preferred APIs: pass CVPixelBuffer, not ARFrame

    /// Convert CVPixelBuffer → UIImage (with orientation fix).
    /// Safe to call off-main as long as you don't touch UIKit beyond UIImage creation.
    func uiImage(from pixelBuffer: CVPixelBuffer) -> UIImage? {
        let ci = CIImage(cvPixelBuffer: pixelBuffer).oriented(.right) // AR portrait fix
        guard let cg = context.createCGImage(ci, from: ci.extent) else { return nil }
        return UIImage(cgImage: cg)
    }

    /// Synchronous CVPixelBuffer → downscaled JPEG.
    /// Prefer ARCameraFrameStreamer for async/background encoding.
    func jpeg(from pixelBuffer: CVPixelBuffer, targetWidth: CGFloat = 640, quality: CGFloat = 0.6) -> Data? {
        let ci = CIImage(cvPixelBuffer: pixelBuffer).oriented(.right)

        // Downscale (avoid upscaling if already small)
        let width = ci.extent.width
        let scale = min(1.0, targetWidth / width)
        let resized = ci.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        guard let cg = context.createCGImage(resized, from: resized.extent) else { return nil }
        return UIImage(cgImage: cg).jpegData(compressionQuality: quality)
    }

    // MARK: - Deprecated: avoid passing ARFrame around

    @available(*, deprecated, message: "Pass CVPixelBuffer instead; do not pass ARFrame outside didUpdate.")
    func uiImage(from frame: ARFrame) -> UIImage? {
        return uiImage(from: frame.capturedImage)
    }

    @available(*, deprecated, message: "Pass CVPixelBuffer instead; use ARCameraFrameStreamer for async JPEG.")
    func jpeg(from frame: ARFrame, scale: CGFloat = 0.33) -> Data? {
        // Keep behavior for compatibility, but delegate to pixelBuffer variant.
        let buffer = frame.capturedImage
        if scale != 0.33 {
            // If a custom scale was used, approximate via targetWidth
            let ci = CIImage(cvPixelBuffer: buffer).oriented(.right)
            let targetWidth = ci.extent.width * scale
            return jpeg(from: buffer, targetWidth: targetWidth, quality: 0.6)
        } else {
            return jpeg(from: buffer, targetWidth: 640, quality: 0.6)
        }
    }
}
