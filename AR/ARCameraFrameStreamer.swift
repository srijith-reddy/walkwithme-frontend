import Foundation
import ARKit
import UIKit
import CoreImage

final class ARCameraFrameStreamer: NSObject {

    static let shared = ARCameraFrameStreamer()

    private let context = CIContext()
    private let encodeQueue = DispatchQueue(label: "com.walkwithme.camera.encode", qos: .userInitiated)

    // Tunables
    private let targetWidth: CGFloat = 384   // smaller cuts CPU/bandwidth further
    private let jpegQuality: CGFloat = 0.6

    private override init() {
        super.init()
    }

    // MARK: - Async Conversion (preferred, CVPixelBuffer only)

    func base64(from pixelBuffer: CVPixelBuffer) async -> String? {
        guard let jpeg = await jpegData(from: pixelBuffer) else { return nil }
        return jpeg.base64EncodedString()
    }

    func jpegData(from pixelBuffer: CVPixelBuffer) async -> Data? {
        await withCheckedContinuation { (continuation: CheckedContinuation<Data?, Never>) in
            encodeQueue.async { [context, targetWidth, jpegQuality] in
                autoreleasepool {
                    let ciImage = CIImage(cvPixelBuffer: pixelBuffer).oriented(.right)

                    let width = ciImage.extent.width
                    let scale = min(1.0, targetWidth / width)
                    let resized = ciImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

                    guard let cg = context.createCGImage(resized, from: resized.extent) else {
                        continuation.resume(returning: nil)
                        return
                    }

                    let ui = UIImage(cgImage: cg)
                    let data = ui.jpegData(compressionQuality: jpegQuality)
                    continuation.resume(returning: data)
                }
            }
        }
    }
}
