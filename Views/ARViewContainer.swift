import SwiftUI
import RealityKit
import ARKit

struct ARViewContainer: UIViewRepresentable {

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)

        // Configure AR session; ARSessionManager will handle GPS origin and route anchors
        ARSessionManager.shared.configureSession(arView: arView)

        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {
        // Nothing to update per-frame from SwiftUI
    }
}
