import Foundation
import RealityKit
import UIKit

/// Billboard-style hazard icon using SF Symbols rendered into a texture (unlit for visibility).
final class ARHazardEntity: Entity {

    private var icon: ModelEntity!
    private let baseScale: Float = 0.001   // tiny default size (we multiply up on appear)

    // ------------------------------------------------------
    // MARK: - Init
    // ------------------------------------------------------
    init(label: String) {
        super.init()

        // Build a textured billboard from an SF Symbol mapped by label
        let (symbolName, tint) = ARHazardEntity.symbol(for: label)
        self.icon = ARHazardEntity.makeBillboard(symbolName: symbolName, color: tint)
        self.addChild(icon)

        // Start tiny and hidden; appear() will scale it up
        self.scale = SIMD3<Float>(repeating: baseScale)
        self.isEnabled = false
    }

    required init() {
        fatalError("Use init(label:)")
    }

    // ------------------------------------------------------
    // MARK: - Appear / Disappear via scale
    // ------------------------------------------------------
    func appear() {
        self.isEnabled = true

        // Reasonable default size on screen; tweak multiplier to taste
        let targetScale: Float = baseScale * 350.0
        let target = Transform(
            scale: SIMD3<Float>(repeating: targetScale),
            rotation: transform.rotation,
            translation: transform.translation
        )

        self.move(
            to: target,
            relativeTo: self.parent,
            duration: 0.20,
            timingFunction: .easeInOut
        )
    }

    func disappear() {
        let small = Transform(
            scale: SIMD3<Float>(repeating: baseScale),
            rotation: transform.rotation,
            translation: transform.translation
        )

        self.move(
            to: small,
            relativeTo: self.parent,
            duration: 0.15,
            timingFunction: .easeInOut
        )

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.isEnabled = false
        }
    }

    // ------------------------------------------------------
    // MARK: - Scale based on distance (optional)
    // ------------------------------------------------------
    func updateScale(forDistance dist: Float) {
        let d = max(0.7, min(6.0, Double(dist)))
        let factor = Float(1.0 / d) * 2.0  // slightly larger factor for visibility
        self.scale = SIMD3<Float>(repeating: factor)
    }

    // ------------------------------------------------------
    // MARK: - Label → SF Symbol mapping
    // ------------------------------------------------------
    private static func symbol(for label: String) -> (name: String, color: UIColor) {
        switch label.lowercased() {
        case "car":             return ("car.fill", .systemRed)
        case "truck":           return ("box.truck.fill", .systemRed)
        case "bus":             return ("bus.fill", .systemRed)
        case "bike", "bicycle": return ("bicycle", .systemOrange)
        case "motorcycle":      return ("motorcycle", .systemOrange)
        case "person", "people":return ("figure.walk", .systemYellow)
        case "crowd":           return ("person.3.sequence.fill", .systemYellow)
        case "dog":             return ("pawprint.fill", .systemBlue)
        case "stop", "stop_sign":
            return ("octagon.fill", .systemRed)
        case "traffic_light":
            return ("trafficlight", .systemGreen)
        default:
            return ("exclamationmark.triangle.fill", .systemOrange)
        }
    }

    // ------------------------------------------------------
    // MARK: - Billboard with SF Symbol texture (unlit)
    // ------------------------------------------------------
    private static func makeBillboard(symbolName: String, color: UIColor) -> ModelEntity {
        // 1) Render SF Symbol into a UIImage
        let imageSize = CGSize(width: 512, height: 512) // high-res to keep crisp in AR
        let img = renderSymbol(name: symbolName, color: color, size: imageSize)

        // 2) Create TextureResource
        if let cg = img.cgImage,
           let tex = try? TextureResource.generate(from: cg, options: .init(semantic: .color)) {

            // Maintain aspect ratio (square symbol image here, but code is robust)
            let w = Float(img.size.width)
            let h = Float(img.size.height)
            let aspect = (h > 0) ? (w / h) : 1.0

            // Choose a base height in meters, width follows aspect
            let planeHeight: Float = 1.0
            let planeWidth: Float = max(0.2, planeHeight * aspect)

            // Use overload without cornerSegments for broader SDK compatibility
            let mesh = MeshResource.generatePlane(width: planeWidth, height: planeHeight, cornerRadius: 0.10)

            var material = UnlitMaterial()
            material.color = .init(texture: .init(tex))

            let entity = ModelEntity(mesh: mesh, materials: [material])
            return entity
        }

        // 3) Fallback: colored plane if texture creation failed
        let material = SimpleMaterial(color: color.withAlphaComponent(0.9), isMetallic: false)
        let mesh = MeshResource.generatePlane(width: 1.0, height: 1.0, cornerRadius: 0.12)
        return ModelEntity(mesh: mesh, materials: [material])
    }

    // ------------------------------------------------------
    // MARK: - Symbol rendering helper
    // ------------------------------------------------------
    private static func renderSymbol(name: String, color: UIColor, size: CGSize) -> UIImage {
        let config = UIImage.SymbolConfiguration(pointSize: min(size.width, size.height) * 0.6, weight: .bold)
        let base = UIImage(systemName: name, withConfiguration: config) ?? UIImage(systemName: "questionmark")!

        // Render centered on a transparent canvas
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        format.opaque = false

        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { ctx in
            let rect = CGRect(origin: .zero, size: size)
            UIColor.clear.setFill()
            ctx.fill(rect)

            let symbol = base.withTintColor(color, renderingMode: .alwaysOriginal)

            // Aspect-fit into canvas
            let s = symbol.size
            let scale = min(size.width / s.width, size.height / s.height) * 0.8
            let drawSize = CGSize(width: s.width * scale, height: s.height * scale)
            let drawOrigin = CGPoint(x: (size.width - drawSize.width) / 2.0,
                                     y: (size.height - drawSize.height) / 2.0)
            symbol.draw(in: CGRect(origin: drawOrigin, size: drawSize))
        }
    }
}
