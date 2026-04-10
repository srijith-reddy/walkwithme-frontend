import Foundation
import CoreLocation
import CoreGraphics

final class VisionUploader {

    static let shared = VisionUploader()
    private init() {}

    private var lastUploadTime = Date(timeIntervalSince1970: 0)

    private let uploadQueue = DispatchQueue(label: "com.walkwithme.vision.upload", qos: .utility)
    private var isUploading = false

    private func makeDetectionsPayload(from yolo: [YOLODetection]) -> [[String: Any]] {
        var out: [[String: Any]] = []
        out.reserveCapacity(yolo.count)

        for det in yolo {
            var d: [String: Any] = ["label": det.label]

            if let c = det.confidence {
                d["confidence"] = Double(c)
            }

            if let box = det.bbox {
                func r(_ v: CGFloat) -> Double {
                    Double((v * 10_000).rounded() / 10_000)
                }
                d["bbox"] = [
                    "x": r(box.origin.x),
                    "y": r(box.origin.y),
                    "w": r(box.size.width),
                    "h": r(box.size.height)
                ]
            }

            out.append(d)
        }
        return out
    }

    // Backward-compatible wrapper
    func upload(base64: String, detections: [YOLODetection]) {
        let payloadDetections = makeDetectionsPayload(from: detections)
        send(
            detections: payloadDetections,
            heading: nil,
            distanceToNext: nil,
            completion: { _ in }
        )
    }

    func send(yolo: [YOLODetection],
              heading: CLLocationDirection?,
              distanceToNext: Double?,
              completion: @escaping (Result<[String: Any], Error>) -> Void)
    {
        let payloadDetections = makeDetectionsPayload(from: yolo)
        send(
            detections: payloadDetections,
            heading: heading,
            distanceToNext: distanceToNext,
            completion: completion
        )
    }

    func send(detections: [[String: Any]] = [],
              heading: CLLocationDirection?,
              distanceToNext: Double?,
              completion: @escaping (Result<[String: Any], Error>) -> Void)
    {
        uploadQueue.async { [weak self] in
            guard let self = self else { return }

            let now = Date()
            if now.timeIntervalSince(self.lastUploadTime) < 0.75 || self.isUploading {
                return
            }
            self.lastUploadTime = now
            self.isUploading = true

            guard let url = URL(string: BackendConfig.baseURL + "/vision") else {
                self.isUploading = false
                completion(.failure(NSError(domain: "InvalidURL", code: -2)))
                return
            }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            request.addValue("application/json", forHTTPHeaderField: "Accept")
            request.timeoutInterval = 4.0

            let payload: [String: Any] = [
                "detections": detections,
                "heading": heading ?? 0,
                "distance_to_next": distanceToNext ?? 0
            ]

            guard let body = try? JSONSerialization.data(withJSONObject: payload) else {
                self.isUploading = false
                completion(.failure(NSError(domain: "JSONEncodeFail", code: -3)))
                return
            }
            request.httpBody = body

            URLSession.shared.dataTask(with: request) { data, resp, err in
                defer { self.isUploading = false }

                if let err = err {
                    completion(.failure(err))
                    return
                }

                guard let http = resp as? HTTPURLResponse else {
                    completion(.failure(NSError(domain: "NoHTTPResponse", code: -10)))
                    return
                }

                if !(200...299).contains(http.statusCode) {
                    let preview = data.flatMap { String(data: $0, encoding: .utf8) } ?? "<no body>"
                    let e = NSError(domain: "HTTPError", code: http.statusCode,
                                    userInfo: [NSLocalizedDescriptionKey: preview])
                    completion(.failure(e))
                    return
                }

                guard let data else {
                    let e = NSError(domain: "NoDataFromBackend", code: -4,
                                    userInfo: [NSLocalizedDescriptionKey: "Backend returned empty response"])
                    completion(.failure(e))
                    return
                }

                do {
                    let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                    completion(.success(json ?? [:]))
                } catch {
                    completion(.failure(error))
                }

            }.resume()
        }
    }
}
