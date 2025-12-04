import UIKit
import ARKit
import CoreImage

final class CameraFrameExtractor {

    static let shared = CameraFrameExtractor()
    private let context = CIContext()

    private init() {}

    // Convert ARFrame → UIImage (with orientation fix)
    func uiImage(from frame: ARFrame) -> UIImage? {
        let buffer = frame.capturedImage
        let ci = CIImage(cvPixelBuffer: buffer)
        let oriented = ci.oriented(.right)  // fix 90° rotation

        guard let cg = context.createCGImage(oriented, from: oriented.extent) else {
            return nil
        }
        return UIImage(cgImage: cg)
    }

    // Convert ARFrame → downscaled JPEG
    func jpeg(from frame: ARFrame, scale: CGFloat = 0.33) -> Data? {
        guard let img = uiImage(from: frame) else { return nil }

        let newWidth = img.size.width * scale
        let newHeight = img.size.height * scale
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1.0

        let renderer = UIGraphicsImageRenderer(size: CGSize(width: newWidth, height: newHeight), format: format)

        let resized = renderer.image { _ in
            img.draw(in: CGRect(x: 0, y: 0, width: newWidth, height: newHeight))
        }

        return resized.jpegData(compressionQuality: 0.6)
    }
}
