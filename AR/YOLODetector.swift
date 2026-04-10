import Foundation
import CoreML
import Vision
import UIKit
import CoreImage
import CoreGraphics

final class YOLODetector {

    static let shared = YOLODetector()
    private init() { loadModel() }

    private var visionModel: VNCoreMLModel?

    // Relevant hazard classes ONLY
    private let allowedClasses: Set<String> = [
        "person",
        "car", "truck", "bus",
        "bike", "bicycle", "motorcycle",
        "dog",
        "stop_sign", "traffic_light"
    ]

    // Tunables
    private let minConfidence: Float = 0.35          // base floor; per-class overrides below
    private let iouThreshold: CGFloat = 0.45         // keep NMS as-is

    // Rate limiting (tuned)
    private let baseMinInterval: TimeInterval = 0.30
    private var currentMinInterval: TimeInterval = 0.30

    // Adaptive timing (tuned)
    private var emaDetectMs: Double = 0
    private let emaAlpha: Double = 0.2
    private let slowThresholdMs: Double = 120
    private let fastThresholdMs: Double = 90
    private var lastRun = Date(timeIntervalSince1970: 0)

    // Vision queue
    private let queue = DispatchQueue(label: "com.walkwithme.yolo", qos: .userInitiated)
    private var isInFlight = false

    // Downscale settings
    private let targetMaxDimension: CGFloat = 640
    private var ciContext = CIContext()

    var forceCPUOnly: Bool = false
    var debugOverlayEnabled: Bool = false

    // ------------------------------------------------------------
    // Load YOLO model
    // ------------------------------------------------------------
    private func loadModel() {
        do {
            let cfg = MLModelConfiguration()
            cfg.computeUnits = .all

            let model = try yolo11n(configuration: cfg)
            visionModel = try VNCoreMLModel(for: model.model)

            print("🔥 YOLO model loaded.")
        } catch {
            print("❌ YOLO load fail:", error.localizedDescription)
        }
    }

    // ------------------------------------------------------------
    // Per-class confidence thresholds
    // ------------------------------------------------------------
    private func threshold(for label: String) -> Float {
        switch label.lowercased() {
        case "person":
            return 0.50
        case "car", "truck", "bus":
            return 0.55
        case "bicycle", "bike", "motorcycle":
            return 0.40
        case "dog":
            return 0.40
        case "traffic_light", "stop_sign":
            return 0.40
        default:
            return minConfidence
        }
    }

    // ------------------------------------------------------------
    // PUBLIC — detect hazards from CGImage
    // ------------------------------------------------------------
    func detect(cgImage: CGImage, completion: @escaping ([YOLODetection]) -> Void) {

        let now = Date()
        guard now.timeIntervalSince(lastRun) >= currentMinInterval else {
            completion([])
            return
        }
        guard !isInFlight else {
            completion([])
            return
        }

        lastRun = now
        isInFlight = true

        let resized = downscaleIfNeeded(cgImage)
        let start = CFAbsoluteTimeGetCurrent()

        runVision(on: resized) { [weak self] dets in
            guard let self else { return }

            // Adaptive throttle
            let ms = (CFAbsoluteTimeGetCurrent() - start) * 1000
            if self.emaDetectMs == 0 { self.emaDetectMs = ms }
            else { self.emaDetectMs = self.emaAlpha * ms + (1 - self.emaAlpha) * self.emaDetectMs }

            if self.emaDetectMs > self.slowThresholdMs {
                self.currentMinInterval = 0.45
            } else if self.emaDetectMs < self.fastThresholdMs {
                self.currentMinInterval = self.baseMinInterval
            }

            if self.debugOverlayEnabled {
                YOLODebugOverlay.shared.update(dets: dets)
            }

            completion(dets)
        }
    }

    // ------------------------------------------------------------
    // INTERNAL — Vision
    // ------------------------------------------------------------
    private func runVision(on image: CGImage,
                           completion: @escaping ([YOLODetection]) -> Void)
    {
        guard let model = visionModel else {
            isInFlight = false
            completion([])
            return
        }

        let request = VNCoreMLRequest(model: model) { [weak self] req, err in
            guard let self else { return }
            defer { self.isInFlight = false }

            if let err = err {
                print("YOLO error:", err.localizedDescription)
                completion([])
                return
            }

            let obs = (req.results as? [VNRecognizedObjectObservation]) ?? []

            // Map → YOLODetection
            let rawMapped: [YOLODetection] = obs.map { o in
                YOLODetection(
                    label: o.labels.first?.identifier.lowercased() ?? "unknown",
                    bbox: o.boundingBox,
                    confidence: o.confidence
                )
            }

            // FILTER 1: Hazard-relevant classes only
            let relevant = rawMapped.filter {
                self.allowedClasses.contains($0.label)
            }

            // FILTER 2: Per-class confidence thresholds
            let confident = relevant.filter { det in
                let t = self.threshold(for: det.label)
                return (det.confidence ?? 0) >= t
            }

            // FILTER 3: NMS (unchanged)
            let nms = self.nonMaxSuppression(confident, iouThreshold: self.iouThreshold)

            completion(nms)
        }

        request.imageCropAndScaleOption = .scaleFit

        queue.async {
            let handler = VNImageRequestHandler(cgImage: image, orientation: .up)
            do { try handler.perform([request]) }
            catch {
                print("YOLO Vision error:", error.localizedDescription)
                self.isInFlight = false
                completion([])
            }
        }
    }

    // ------------------------------------------------------------
    // Downscale
    // ------------------------------------------------------------
    private func downscaleIfNeeded(_ cg: CGImage) -> CGImage {
        let w = CGFloat(cg.width)
        let h = CGFloat(cg.height)
        let maxDim = max(w, h)

        if maxDim <= targetMaxDimension { return cg }

        let scale = targetMaxDimension / maxDim
        let newW = Int(w * scale)
        let newH = Int(h * scale)

        guard let ctx = CGContext(
            data: nil,
            width: newW,
            height: newH,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return cg }

        ctx.interpolationQuality = .low
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: CGFloat(newW), height: CGFloat(newH)))

        return ctx.makeImage() ?? cg
    }

    // ------------------------------------------------------------
    // NMS
    // ------------------------------------------------------------
    private func nonMaxSuppression(_ dets: [YOLODetection],
                                   iouThreshold: CGFloat) -> [YOLODetection] {

        let sorted = dets.sorted { ($0.confidence ?? 0) > ($1.confidence ?? 0) }
        var kept: [YOLODetection] = []

        for det in sorted {
            let overlap = kept.contains {
                labelsMatch($0.label, det.label) &&
                iou($0.bbox ?? .zero, det.bbox ?? .zero) > iouThreshold
            }
            if !overlap { kept.append(det) }
        }
        return kept
    }

    private func iou(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let inter = a.intersection(b)
        if inter.isNull { return 0 }
        let interArea = inter.width * inter.height
        let unionArea = a.width * a.height + b.width * b.height - interArea
        return unionArea <= 0 ? 0 : (interArea / unionArea)
    }

    private func labelsMatch(_ a: String, _ b: String) -> Bool {
        a.lowercased() == b.lowercased()
    }
}
