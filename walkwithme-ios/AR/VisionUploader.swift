import Foundation
import CoreLocation

final class VisionUploader {

    static let shared = VisionUploader()
    private init() {}

    private var lastUploadTime = Date(timeIntervalSince1970: 0)

    /// Sends compressed AR camera frames + optional YOLO detections to backend
    func send(frameB64: String,
              detections: [[String: Any]] = [],
              heading: CLLocationDirection?,
              distanceToNext: Double?,
              completion: @escaping (Result<[String: Any], Error>) -> Void)
    {
        // --------------------------
        // Throttle to 2 FPS
        // --------------------------
        let now = Date()
        if now.timeIntervalSince(lastUploadTime) < 0.5 {
            return   // skip this frame
        }
        lastUploadTime = now

        // --------------------------
        // URL
        // --------------------------
        guard let url = URL(string: BackendConfig.baseURL + "/vision") else {
            completion(.failure(NSError(domain: "InvalidURL", code: -2)))
            return
        }

        // --------------------------
        // Request
        // --------------------------
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 4.0

        let payload: [String: Any] = [
            "image_b64": frameB64,
            "detections": detections,
            "heading": heading ?? 0,
            "distance_to_next": distanceToNext ?? 0
        ]

        guard let body = try? JSONSerialization.data(withJSONObject: payload) else {
            completion(.failure(NSError(domain: "JSONEncodeFail", code: -3)))
            return
        }
        request.httpBody = body

        // --------------------------
        // Network call
        // --------------------------
        URLSession.shared.dataTask(with: request) { data, resp, err in

            if let err = err {
                completion(.failure(err))
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
