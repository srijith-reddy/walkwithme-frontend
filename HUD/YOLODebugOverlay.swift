// YOLODebugOverlay.swift

import Foundation
import CoreGraphics
import Combine

final class YOLODebugOverlay: ObservableObject {

    static let shared = YOLODebugOverlay()
    private init() {}

    // SwiftUI-observable normalized boxes and labels (Vision coordinates: origin bottom-left)
    @Published var boxes: [CGRect] = []
    @Published var labels: [String] = []

    func clear() {
        DispatchQueue.main.async {
            self.boxes.removeAll()
            self.labels.removeAll()
        }
    }

    func update(dets: [YOLODetection]) {
        guard DebugSettings.showYOLOBoxes else { return }

        let newBoxes: [CGRect] = dets.compactMap { $0.bbox }
        let newLabels: [String] = dets.map { $0.label }

        DispatchQueue.main.async {
            self.boxes = newBoxes
            self.labels = newLabels
        }
    }
}
