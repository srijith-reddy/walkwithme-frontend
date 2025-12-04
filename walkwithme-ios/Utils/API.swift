import Foundation
import CoreLocation

enum APIError: Error, LocalizedError {
    case invalidURL
    case requestFailed
    case decodingFailed
    case server(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:       return "Invalid URL"
        case .requestFailed:    return "Network request failed"
        case .decodingFailed:   return "Failed to decode server response"
        case .server(let msg):  return msg
        }
    }
}

final class API {
    static let shared = API()

    /// ⚠️ change to your deployed backend
    private let baseURL = URL(string: "https://walkwithme-app-mw2xs.ondigitalocean.app")!

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 30
        return URLSession(configuration: config)
    }()

    private init() {}

    // MARK: - Route

    /// Calls /route?start=lat,lon&end=lat,lon&mode=...
    func fetchRoute(start: CLLocationCoordinate2D,
                    end: CLLocationCoordinate2D?,
                    mode: String = "shortest",
                    duration: Int = 20) async throws -> Route {

        var components = URLComponents(url: baseURL.appendingPathComponent("route"),
                                       resolvingAgainstBaseURL: false)
        var query: [URLQueryItem] = [
            .init(name: "start", value: "\(start.latitude),\(start.longitude)"),
            .init(name: "mode", value: mode),
            .init(name: "duration", value: "\(duration)")
        ]

        if let end = end {
            query.append(.init(name: "end", value: "\(end.latitude),\(end.longitude)"))
        }

        components?.queryItems = query

        guard let url = components?.url else {
            throw APIError.invalidURL
        }

        let (data, response) = try await session.data(from: url)

        guard let http = response as? HTTPURLResponse else {
            throw APIError.requestFailed
        }

        guard (200..<300).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown server error"
            throw APIError.server("HTTP \(http.statusCode): \(message)")
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        do {
            let route = try decoder.decode(Route.self, from: data)
            return route
        } catch {
            print("Decoding error:", error)
            throw APIError.decodingFailed
        }
    }
}
