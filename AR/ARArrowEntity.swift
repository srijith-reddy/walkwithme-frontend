import Foundation
import RealityKit
import UIKit

// Removed HasAnchoring — arrow should NOT anchor itself.
// You will anchor it externally using AnchorEntity(world: ...)
final class ARArrowEntity: Entity, HasModel {

    // -----------------------------------------------------------
    // MARK: Init
    // -----------------------------------------------------------
    required init() {
        super.init()

        self.model = ModelComponent(
            mesh: .generateArrowMesh(),
            materials: [SimpleMaterial(color: .cyan, isMetallic: false)]
        )

        // Base size
        self.scale = SIMD3<Float>(repeating: 1.0)
    }

    // -----------------------------------------------------------
    // MARK: SAFETY HELPERS (NO MORE NaNs)
    // -----------------------------------------------------------
    private func safeTransform(_ t: Transform) -> Transform? {
        let m = t.matrix

        let finite =
            m.columns.0.x.isFinite &&
            m.columns.0.y.isFinite &&
            m.columns.0.z.isFinite &&
            m.columns.3.x.isFinite &&
            m.columns.3.y.isFinite &&
            m.columns.3.z.isFinite

        return finite ? t : nil
    }

    private func safeYaw(_ yaw: Float) -> Float? {
        guard yaw.isFinite, !yaw.isNaN else { return nil }
        return yaw
    }

    /// Clamp angle to [-π, π]
    private func normalized(_ angle: Float) -> Float {
        var a = angle
        while a > .pi { a -= 2 * .pi }
        while a < -.pi { a += 2 * .pi }
        return a
    }

    // -----------------------------------------------------------
    // MARK: SAFE MOVE WRAPPER (cannot override RealityKit's move)
    // -----------------------------------------------------------
    private func safeMove(
        to transform: Transform,
        relativeTo: Entity?,
        duration: TimeInterval,
        timingFunction: AnimationTimingFunction)
    {
        guard let clean = safeTransform(transform) else {
            print("⚠️ ARArrowEntity: blocked NaN transform")
            return
        }

        self.move(
            to: clean,
            relativeTo: relativeTo,
            duration: duration,
            timingFunction: timingFunction
        )
    }

    // -----------------------------------------------------------
    // MARK: SAFE ROTATION APIs
    // -----------------------------------------------------------
    func safeRotate(to absoluteYaw: Float) {
        guard let y = safeYaw(absoluteYaw) else { return }

        let yaw = normalized(y)
        let quat = simd_quatf(angle: yaw, axis: [0,1,0])

        guard quat.vector.x.isFinite,
              quat.vector.y.isFinite,
              quat.vector.z.isFinite,
              quat.vector.w.isFinite
        else {
            print("⚠️ Quaternion contained NaN; blocked")
            return
        }

        let t = Transform(
            scale: self.transform.scale,
            rotation: quat,
            translation: self.transform.translation
        )

        guard let safeT = safeTransform(t) else { return }

        safeMove(
            to: safeT,
            relativeTo: parent,
            duration: 0.25,
            timingFunction: .easeInOut
        )
    }

    func safeDeltaRotate(delta: Float) {
        guard delta.isFinite else { return }

        let q = self.transform.rotation
        let currentYaw = atan2f(
            2*(q.vector.y*q.vector.w + q.vector.x*q.vector.z),
            1 - 2*(q.vector.y*q.vector.y + q.vector.z*q.vector.z)
        )

        guard currentYaw.isFinite else { return }

        safeRotate(to: currentYaw + delta)
    }

    // -----------------------------------------------------------
    // MARK: Pulse Animation
    // -----------------------------------------------------------
    func startPulse() {

        let small = Transform(
            scale: .init(repeating: 0.25),
            rotation: self.transform.rotation,
            translation: self.transform.translation
        )

        let big = Transform(
            scale: .init(repeating: 0.33),
            rotation: self.transform.rotation,
            translation: self.transform.translation
        )

        pulseLoop(small: small, big: big)
    }

    private func pulseLoop(small: Transform, big: Transform) {

        self.safeMove(
            to: big,
            relativeTo: parent,
            duration: 0.40,
            timingFunction: .easeInOut
        )

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.40) { [weak self] in
            guard let self else { return }

            self.safeMove(
                to: small,
                relativeTo: self.parent,
                duration: 0.40,
                timingFunction: .easeInOut
            )

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.40) {
                self.pulseLoop(small: small, big: big)
            }
        }
    }
}

// -----------------------------------------------------------
// MARK: Arrow Mesh
// -----------------------------------------------------------
extension MeshResource {
    static func generateArrowMesh() -> MeshResource {
        // A long rectangular prism that looks like a pointer
        // width = 0.12 m, height = 0.12 m, length = 0.50 m
        return MeshResource.generateBox(size: [0.12, 0.12, 0.50])
    }
}

