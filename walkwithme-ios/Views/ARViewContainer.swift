import SwiftUI
import RealityKit
import ARKit

struct ARViewContainer: UIViewRepresentable {

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)

        // Configure ARKit session
        ARSessionManager.shared.configureSession(arView: arView)

        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {}
}
