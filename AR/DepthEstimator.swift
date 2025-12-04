//
//  DepthEstimator.swift
//  WalkWithMe
//

import Foundation
import ARKit
import Vision
import UIKit

final class DepthEstimator {

    static let shared = DepthEstimator()

    private init() {}

    // Cached COPIES (safe)
    private var lastSceneDepthMap: CVPixelBuffer?
    private var lastCapturedImage: CVPixelBuffer?

    private let syncQueue = DispatchQueue(
        label: "com.walkwithme.depth.sync",
        qos: .userInitiated
    )

    // =========================================================
    // MARK: - UPDATE — SAFE BUFFER COPIES
    // =========================================================
    func update(depthMap: CVPixelBuffer?, capturedImage: CVPixelBuffer) {
        syncQueue.sync {
            // Deep copy both pixel buffers — prevents ARFrame retention
            if let d = depthMap {
                self.lastSceneDepthMap = DepthEstimator.copyPixelBuffer(d)
            } else {
                self.lastSceneDepthMap = nil
            }

            self.lastCapturedImage = DepthEstimator.copyPixelBuffer(capturedImage)
        }
    }

    // REMOVE THIS (dangerous)
    @available(*, deprecated)
    func update(frame: ARFrame) {
        // DO NOT USE — keeps ARFrame alive
    }

    // =========================================================
    // MARK: - COPY FUNCTION — CRITICAL PART
    // =========================================================
    private static func copyPixelBuffer(_ src: CVPixelBuffer) -> CVPixelBuffer {
        var dst: CVPixelBuffer?

        let width = CVPixelBufferGetWidth(src)
        let height = CVPixelBufferGetHeight(src)
        let pixelFormat = CVPixelBufferGetPixelFormatType(src)

        let attrs = [
            kCVPixelBufferIOSurfacePropertiesKey: [:]
        ] as CFDictionary

        CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            pixelFormat,
            attrs,
            &dst
        )

        guard let dst else { return src }

        CVPixelBufferLockBaseAddress(src, .readOnly)
        CVPixelBufferLockBaseAddress(dst, [])

        let srcBase = CVPixelBufferGetBaseAddress(src)!
        let dstBase = CVPixelBufferGetBaseAddress(dst)!
        let size = CVPixelBufferGetDataSize(src)
        memcpy(dstBase, srcBase, size)

        CVPixelBufferUnlockBaseAddress(dst, [])
        CVPixelBufferUnlockBaseAddress(src, .readOnly)

        return dst
    }

    // =========================================================
    // MARK: - PUBLIC API
    // =========================================================
    func distanceForHazard(bbox: CGRect?, label: String) -> Double? {

        let (map, img): (CVPixelBuffer?, CVPixelBuffer?) = syncQueue.sync {
            (self.lastSceneDepthMap, self.lastCapturedImage)
        }

        // 1) LiDAR
        if let map, let bbox {
            return lidarDepth(depthMap: map, bbox: bbox)
        }

        // 2) Vision Depth
        if let img, let bbox {
            return visionDepth(capturedImage: img, bbox: bbox)
        }

        // 3) YOLO fallback
        if let bbox {
            return bboxFallbackDistance(box: bbox, label: label)
        }

        return nil
    }

    // =========================================================
    // MARK: - Lidar Depth
    // =========================================================
    private func lidarDepth(depthMap: CVPixelBuffer, bbox: CGRect) -> Double? {

        let w = CVPixelBufferGetWidth(depthMap)
        let h = CVPixelBufferGetHeight(depthMap)

        let px = Int(CGFloat(w) * bbox.midX)
        let py = Int(CGFloat(h) * bbox.midY)

        guard px >= 0, px < w, py >= 0, py < h else { return nil }

        let distance = depthMap.floatChannel(at: px, y: py)
        if distance.isFinite, distance > 0 {
            return Double(distance)
        }
        return nil
    }

    // =========================================================
    // MARK: - Vision Depth (iOS 17+)
    // =========================================================
    private func visionDepth(capturedImage: CVPixelBuffer, bbox: CGRect) -> Double? {

        guard #available(iOS 17.0, *) else { return nil }

        let classNames = [
            "VNGenerateDepthFromMonocularImageRequest",
            "VNGenerateDepthImageRequest"
        ]

        guard let reqClass = classNames
            .compactMap({ NSClassFromString($0) as? NSObject.Type })
            .first else { return nil }

        let request = reqClass.init()

        let handler = VNImageRequestHandler(
            cvPixelBuffer: capturedImage,
            options: [:]
        )

        do { try handler.perform([request as! VNRequest]) }
        catch { return nil }

        guard
            let results = request.value(forKey: "results") as? [Any],
            let first = results.first as? NSObject,
            first.responds(to: NSSelectorFromString("depthMap"))
        else { return nil }

        let depthAny = first.value(forKey: "depthMap")
        guard let cfObj = depthAny as CFTypeRef?,
              CFGetTypeID(cfObj) == CVPixelBufferGetTypeID()
        else { return nil }

        let map = cfObj as! CVPixelBuffer

        let w = CVPixelBufferGetWidth(map)
        let h = CVPixelBufferGetHeight(map)

        let px = Int(CGFloat(w) * bbox.midX)
        let py = Int(CGFloat(h) * bbox.midY)

        guard px >= 0, px < w, py >= 0, py < h else { return nil }

        CVPixelBufferLockBaseAddress(map, .readOnly)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(map)
        let base = CVPixelBufferGetBaseAddress(map)!.assumingMemoryBound(to: UInt8.self)
        let rowPtr = base.advanced(by: py * bytesPerRow)
        let floatPtr = UnsafeRawPointer(rowPtr).assumingMemoryBound(to: Float32.self)
        let depthVal = floatPtr[px]
        CVPixelBufferUnlockBaseAddress(map, .readOnly)

        if depthVal.isFinite, depthVal > 0 {
            return Double(depthVal)
        }
        return nil
    }

    // =========================================================
    // MARK: - YOLO fallback distance
    // =========================================================
    private func bboxFallbackDistance(box: CGRect, label: String) -> Double {
        let size = (box.width + box.height) / 2.0
        switch label.lowercased() {
        case "person": return Double(1.0 / max(size, 0.05)) * 1.2
        case "dog": return Double(1.0 / max(size, 0.05)) * 0.8
        case "car", "truck", "bus": return Double(1.0 / max(size, 0.05)) * 3.0
        default: return Double(1.0 / max(size, 0.05)) * 2.0
        }
    }
}

// =========================================================
// MARK: - CVPixelBuffer float extraction helper
// =========================================================
private extension CVPixelBuffer {
    func floatChannel(at x: Int, y: Int) -> Float {
        CVPixelBufferLockBaseAddress(self, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(self, .readOnly) }

        let bytes = CVPixelBufferGetBytesPerRow(self)
        let base = CVPixelBufferGetBaseAddress(self)!.assumingMemoryBound(to: UInt8.self)
        let rowPtr = base.advanced(by: y * bytes)
        let floatRow = UnsafeRawPointer(rowPtr).assumingMemoryBound(to: Float32.self)
        return floatRow[x]
    }
}
