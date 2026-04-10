import Foundation
import RealityKit
import UIKit

/// Big, visible chevron billboard for route guidance.
/// Uses an unlit material so it stays bright regardless of lighting.
final class ARRouteChevronEntity: Entity {

    // Adjust these to taste
    private let planeHeight: Float = 1.2   // meters
    private let cornerRadius: Float = 0.12
    private let baseScale: Float = 1.0     // overall scale multiplier
    private let animationDuration: TimeInterval = 0.20

    private var model: ModelEntity!

    // MARK: - Init
    init(symbolName: String = "arrowtriangle.forward.fill", tint: UIColor = .systemBlue) {
        super.init()

        let img = ARRouteChevronEntity.renderSymbol(
            name: symbolName,
            color: tint,
            size: CGSize(width: 512, height: 512)
        )

        // Texture
        if let cg = img.cgImage,
           let tex = try? TextureResource.generate(from: cg, options: .init(semantic: .color)) {

            let w = Float(img.size.width)
            let h = Float(img.size.height)
            let aspect = (h > 0) ? (w / h) : 1.0

            let planeWidth: Float = max(0.4, planeHeight * aspect)

            // Generate a plane with rounded corners
            let mesh = MeshResource.generatePlane(
                width: planeWidth,
                height: planeHeight,
                cornerRadius: cornerRadius
            )

            var material = UnlitMaterial()
            material.color = .init(texture: .init(tex))

            let entity = ModelEntity(mesh: mesh, materials: [material])
            self.model = entity
            self.addChild(entity)

            self.scale = SIMD3<Float>(repeating: baseScale)
        } else {
            // Fallback solid plane if texture fails
            let mesh = MeshResource.generatePlane(
                width: 0.8,
                height: planeHeight,
                cornerRadius: cornerRadius
            )
            let material = SimpleMaterial(color: tint.withAlphaComponent(0.9), isMetallic: false)
            let entity = ModelEntity(mesh: mesh, materials: [material])
            self.model = entity
            self.addChild(entity)
            self.scale = SIMD3<Float>(repeating: baseScale)
        }
    }

    required init() {
        fatalError("Use init(symbolName:tint:)")
    }

    // MARK: - Rotation Helpers
    /// Rotate to an absolute yaw (radians) around Y axis with small safety checks.
    func safeRotate(to yaw: Float, animate: Bool = true) {
        guard yaw.isFinite else { return }

        let quat = simd_quatf(angle: normalized(yaw), axis: [0,1,0])
        guard quat.vector.x.isFinite,
              quat.vector.y.isFinite,
              quat.vector.z.isFinite,
              quat.vector.w.isFinite else { return }

        let t = Transform(
            scale: self.transform.scale,
            rotation: quat,
            translation: self.transform.translation
        )

        if animate {
            self.move(
                to: t,
                relativeTo: parent,
                duration: animationDuration,
                timingFunction: .easeInOut
            )
        } else {
            self.transform = t
        }
    }

    // MARK: - Symbol rendering
    private static func renderSymbol(name: String, color: UIColor, size: CGSize) -> UIImage {
        let config = UIImage.SymbolConfiguration(pointSize: min(size.width, size.height) * 0.7, weight: .bold)
        let base = UIImage(systemName: name, withConfiguration: config) ?? UIImage(systemName: "arrowtriangle.forward.fill")!

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        format.opaque = false

        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { ctx in
            let rect = CGRect(origin: .zero, size: size)
            UIColor.clear.setFill()
            ctx.fill(rect)

            let symbol = base.withTintColor(color, renderingMode: .alwaysOriginal)
            let s = symbol.size
            let scale = min(size.width / s.width, size.height / s.height) * 0.8
            let drawSize = CGSize(width: s.width * scale, height: s.height * scale)
            let drawOrigin = CGPoint(
                x: (size.width - drawSize.width) / 2.0,
                y: (size.height - drawSize.height) / 2.0
            )
            symbol.draw(in: CGRect(origin: drawOrigin, size: drawSize))
        }
    }

    // MARK: - Utils
    private func normalized(_ angle: Float) -> Float {
        var a = angle
        while a > .pi { a -= 2 * .pi }
        while a < -.pi { a += 2 * .pi }
        return a
    }
}
