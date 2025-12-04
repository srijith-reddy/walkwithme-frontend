import Foundation
import RealityKit
import UIKit

/// Floating billboard hazard icon — procedural, no PNG assets needed.
final class ARHazardEntity: Entity, HasBillboard, HasOpacity, HasScale {

    private var icon: ModelEntity!
    private var fadeCancellable: Cancellable?

    init(label: String) {
        super.init()

        let symbol = Self.sfSymbol(for: label)
        let color  = Self.color(for: label)
        let texture = Self.symbolTexture(symbol: symbol, tint: color)

        self.icon = Self.makeBillboard(texture: texture)
        self.addChild(icon)

        // Always face user
        self.billboard = .init()

        // Natural scale
        self.scale = .init(repeating: 0.001)

        // Start invisible
        self.opacity = 0.0
    }

    required init() {
        fatalError("Use init(label:)")
    }

    // ------------------------------------------------------
    // MARK: - Animations
    // ------------------------------------------------------

    func appear() {
        fadeCancellable?.cancel()
        fadeCancellable = opacity.animate(
            to: 1.0,
            duration: 0.25,
            timingFunction: .easeInOut
        )
    }

    func disappear() {
        fadeCancellable?.cancel()
        fadeCancellable = opacity.animate(
            to: 0.0,
            duration: 0.25,
            timingFunction: .easeInOut
        )
    }

    /// Called by OverlayManager while repositioning
    /// Scales icon based on distance (closer = larger)
    func updateScale(forDistance dist: Float) {
        // clamp 0.7m to 6m
        let t = max(0.7, min(6.0, Double(dist)))
        let scaleFactor = Float(1.0 / t) * 1.4  // tuned visually
        self.scale = SIMD3<Float>(repeating: scaleFactor)
    }

    // ------------------------------------------------------
    // MARK: - Symbol Mapping
    // ------------------------------------------------------

    private static func sfSymbol(for label: String) -> UIImage {
        let name: String

        switch label.lowercased() {
        case "car", "truck", "bus":
            name = "car.fill"

        case "person", "people", "crowd":
            name = "figure.walk"

        case "dog":
            name = "pawprint.fill"

        case "bike", "bicycle":
            name = "bicycle"

        case "stop", "stop_sign":
            name = "hand.raised.fill"

        default:
            name = "exclamationmark.triangle.fill"
        }

        return UIImage(systemName: name)!
    }

    // ------------------------------------------------------
    // MARK: - Hazard Color Coding
    // ------------------------------------------------------

    private static func color(for label: String) -> UIColor {
        switch label.lowercased() {
        case "car", "truck", "bus": return .systemRed
        case "stop", "stop_sign":  return .systemRed
        case "bike", "bicycle":    return .systemOrange
        case "person", "people", "crowd": return .systemYellow
        case "dog":                return .systemBlue
        default:                   return .systemOrange
        }
    }

    // ------------------------------------------------------
    // MARK: - SF Symbol → Texture
    // ------------------------------------------------------

    private static func symbolTexture(symbol: UIImage, tint: UIColor)
        -> MaterialParameters.Texture {

        let config = UIImage.SymbolConfiguration(pointSize: 140, weight: .bold)

        let img = symbol.withConfiguration(config)
            .withTintColor(tint, renderingMode: .alwaysOriginal)

        let cg = img.cgImage!

        return try! MaterialParameters.Texture(.init(cgImage: cg))
    }

    // ------------------------------------------------------
    // MARK: - Billboard creation
    // ------------------------------------------------------
    private static func makeBillboard(texture: MaterialParameters.Texture) -> ModelEntity {

        var mat = UnlitMaterial()
        mat.color = .init(texture: texture)

        // Glow for outdoor visibility
        mat.tintColor = .init(tint: UIColor.white.withAlphaComponent(0.85))

        let mesh = MeshResource.generatePlane(width: 0.45, depth: 0.45)
        return ModelEntity(mesh: mesh, materials: [mat])
    }
}
