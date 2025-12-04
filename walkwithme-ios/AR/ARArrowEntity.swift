import Foundation
import RealityKit
import simd

final class ARArrowEntity: Entity, HasModel, HasAnchoring {

    // MARK: - State

    private var usdzLoaded = false
    private var smoothingFactor: Float = 0.15   // rotation smoothing (Google-style)
    private var lastRotation: simd_quatf = simd_quatf(angle: 0, axis: [0,1,0])

    // MARK: - Init

    override init() {
        super.init()
        self.name = "ARArrowEntity"

        // Try loading Arrow.usdz from your bundle
        if loadUSDZModel() == false {
            buildProceduralArrow()
        }

        // Slight upward offset so arrow sits above the ground
        self.position.y = 0.05
    }

    required init(anchor: AnchorEntity) {
        fatalError("init(anchor:) has not been implemented")
    }

    // MARK: - USDZ Loader

    /// Attempts to load a .usdz model named "Arrow.usdz" from app bundle.
    /// Place Arrow.usdz inside the Xcode project (Copy to Bundle).
    private func loadUSDZModel() -> Bool {
        do {
            let entity = try Entity.load(named: "Arrow")    // Arrow.usdz
            self.model = entity.model
            usdzLoaded = true
            return true
        } catch {
            print("⚠️ [ARArrowEntity] Could not load Arrow.usdz, using procedural arrow.")
            return false
        }
    }

    // MARK: - Procedural Arrow (Fallback)

    private func buildProceduralArrow() {
        let shaftHeight: Float = 0.25
        let shaftRadius: Float = 0.02

        let coneHeight: Float = 0.12
        let coneRadius: Float = 0.06

        let shaft = ModelEntity(
            mesh: .generateCylinder(height: shaftHeight, radius: shaftRadius),
            materials: [SimpleMaterial(color: .blue, isMetallic: true)]
        )

        let cone = ModelEntity(
            mesh: .generateCone(height: coneHeight, radius: coneRadius),
            materials: [SimpleMaterial(color: .blue, isMetallic: true)]
        )

        // Position the parts to form an upward arrow
        shaft.position = [0, shaftHeight/2, 0]
        cone.position  = [0, shaftHeight + coneHeight/2, 0]

        self.children.append(shaft)
        self.children.append(cone)
    }

    // MARK: - Rotation Update (Smooth)

    /// Updates arrow rotation to match navigation heading (AR world space).
    /// - parameter deltaRadians: arrow rotation in radians relative to camera heading
    func updateRotation(_ deltaRadians: Float) {

        // The arrow should rotate around the Y-axis.
        let target = simd_quatf(angle: deltaRadians, axis: SIMD3<Float>(0, 1, 0))

        // Smooth interpolation (LERP in quaternion space)
        lastRotation = simd_slerp(lastRotation, target, smoothingFactor)

        self.orientation = lastRotation
    }

    // MARK: - Animated Scaling (optional)

    /// Pulse animation when near a turn
    func pulse() {
        let anim = FromToByAnimation<Transform>(
            name: "pulse",
            duration: 0.4,
            curve: .easeInOut,
            from: self.transform,
            to: Transform(scale: SIMD3<Float>(1.3, 1.3, 1.3),
                          rotation: self.orientation,
                          translation: self.position)
        )

        self.playAnimation(anim)
    }
}
