import SwiftUI
import RealityKit
import ARKit
import Combine

struct ARScreen: View {
    let route: Route
    
    @ObservedObject private var debug = YOLODebugOverlay.shared
    
    var body: some View {
        ZStack {

            // AR CAMERA FEED
            ARViewContainer()
                .ignoresSafeArea()

            // YOLO 2D BOUNDING BOXES
            GeometryReader { geo in
                ForEach(Array(debug.boxes.enumerated()), id: \.offset) { i, box in

                    let w = box.width * geo.size.width
                    let h = box.height * geo.size.height
                    let x = box.midX * geo.size.width
                    let y = (1 - box.midY) * geo.size.height

                    ZStack(alignment: .topLeading) {
                        Rectangle()
                            .stroke(Color.red, lineWidth: 2)
                            .frame(width: w, height: h)

                        if i < debug.labels.count {
                            Text(debug.labels[i])
                                .font(.caption2)
                                .bold()
                                .padding(4)
                                .background(Color.red.opacity(0.9))
                                .foregroundColor(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                                .offset(x: 2, y: 2)
                        }
                    }
                    .position(x: x, y: y)
                }
            }
            .allowsHitTesting(false)
        }
        .onAppear {
            startSession()
        }
    }
}


// MARK: - NO GPS WAIT. NO READINESS LOOP. JUST LOAD.
extension ARScreen {

    private func startSession() {
        // Enable YOLO overlays
        YOLODetector.shared.forceCPUOnly = true
        YOLODetector.shared.debugOverlayEnabled = true

        // 🚀 Route loads instantly once ARViewContainer finishes makeUIView
        ARSessionManager.shared.loadRoute(route)
    }
}
