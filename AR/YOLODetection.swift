import Foundation
import CoreGraphics

/// Minimal detection model used across YOLO, fusion, velocity, and uploader.
struct YOLODetection: Equatable {
    let label: String
    let bbox: CGRect?          // Normalized [0,1] rect in Vision coordinate space
    let confidence: Float?     // 0.0 ... 1.0
}
