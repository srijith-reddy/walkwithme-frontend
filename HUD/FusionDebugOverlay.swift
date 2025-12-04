//
//  FusionDebugOverlay.swift
//  WalkWithMe
//

import UIKit
import RealityKit

/// ------------------------------------------------------------
///   DEBUG OVERLAY — POST-FUSION GREEN BOXES
/// ------------------------------------------------------------
/// This draws GREEN boxes on the ARView representing the
/// bounding boxes **after HazardFusion**.
/// Great for verifying the fusion logic is correct.
/// ------------------------------------------------------------
final class FusionDebugOverlay {

    static let shared = FusionDebugOverlay()
    private init() {}

    weak var arView: ARView?

    private var boxes: [UIView] = []

    func clear() {
        boxes.forEach { $0.removeFromSuperview() }
        boxes.removeAll()
    }

    func update(fused: [FusedHazard]) {
        guard DebugSettings.showFusionBoxes else { return }
        guard let arView else { return }

        clear()

        let screen = arView.bounds.size

        for hazard in fused {
            let b = hazard.bbox

            // ARKit uses normalized coords in YOLO space (0–1)
            let x = b.minX * screen.width
            let y = (1 - b.maxY) * screen.height
            let widthPx = b.width * screen.width
            let heightPx = b.height * screen.height

            let rect = CGRect(x: x, y: y, width: widthPx, height: heightPx)

            let view = UIView(frame: rect)
            view.layer.borderWidth = 2
            view.layer.borderColor = UIColor.green.cgColor
            view.backgroundColor = UIColor.clear

            let lbl = UILabel(frame: CGRect(x: 0, y: 0, width: widthPx, height: 14))
            lbl.font = .systemFont(ofSize: 11, weight: .semibold)
            lbl.text = "F: \(hazard.label)"
            lbl.textColor = .green
            view.addSubview(lbl)

            arView.addSubview(view)
            boxes.append(view)
        }
    }
}
