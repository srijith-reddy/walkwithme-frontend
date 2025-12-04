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

struct PlaceSuggestion: Codable, Identifiable, Hashable {
    let id = UUID()
    let label: String
    let lat: Double
    let lon: Double
}

// Rich POI result from /places_search (no photos)
struct PlaceSearchResult: Codable, Identifiable, Hashable {
    let id = UUID()
    let name: String
    let address: String?
    let rating: Double?
    let reviews: Int?
    let lat: Double
    let lon: Double
    let openNow: Bool?
    let distanceKm: Double?

    enum CodingKeys: String, CodingKey {
        case name
        case address
        case rating
        case reviews
        case lat
        case lon
        case openNow     = "open_now"
        case distanceKm  = "distance_km"
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

    // MARK: - Autocomplete (address-like)

    /// Calls /autocomplete?q=...&user_lat=...&user_lon=...&limit=...
    func fetchAutocomplete(q: String,
                           userLat: Double?,
                           userLon: Double?,
                           limit: Int = 7) async throws -> [PlaceSuggestion] {

        var components = URLComponents(url: baseURL.appendingPathComponent("autocomplete"),
                                       resolvingAgainstBaseURL: false)
        var items: [URLQueryItem] = [
            .init(name: "q", value: q),
            .init(name: "limit", value: "\(limit)")
        ]
        if let userLat = userLat, let userLon = userLon {
            items.append(.init(name: "user_lat", value: "\(userLat)"))
            items.append(.init(name: "user_lon", value: "\(userLon)"))
        }
        components?.queryItems = items

        guard let url = components?.url else { throw APIError.invalidURL }

        let (data, response) = try await session.data(from: url)

        guard let http = response as? HTTPURLResponse else {
            throw APIError.requestFailed
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown server error"
            throw APIError.server("HTTP \(http.statusCode): \(message)")
        }

        do {
            // Backend returns array of { label, lat, lon }
            let decoder = JSONDecoder()
            let raw = try decoder.decode([[String: CodableValue]].self, from: data)

            // Map into PlaceSuggestion
            let suggestions: [PlaceSuggestion] = raw.compactMap { dict in
                guard
                    let label = dict["label"]?.stringValue,
                    let lat = dict["lat"]?.doubleValue,
                    let lon = dict["lon"]?.doubleValue
                else { return nil }
                return PlaceSuggestion(label: label, lat: lat, lon: lon)
            }
            return suggestions
        } catch {
            // Fallback: try direct decode to [PlaceSuggestion] if keys/types match exactly
            if let suggestions = try? JSONDecoder().decode([PlaceSuggestion].self, from: data) {
                return suggestions
            }
            throw APIError.decodingFailed
        }
    }

    // MARK: - Places Search (POI with ratings)

    /// Calls /places_search?q=...&user_lat=...&user_lon=...
    func fetchPlacesSearch(q: String,
                           userLat: Double?,
                           userLon: Double?) async throws -> [PlaceSearchResult] {
        var components = URLComponents(url: baseURL.appendingPathComponent("places_search"),
                                       resolvingAgainstBaseURL: false)
        var items: [URLQueryItem] = [
            .init(name: "q", value: q)
        ]
        if let userLat, let userLon {
            items.append(.init(name: "user_lat", value: "\(userLat)"))
            items.append(.init(name: "user_lon", value: "\(userLon)"))
        }
        components?.queryItems = items

        guard let url = components?.url else { throw APIError.invalidURL }

        let (data, response) = try await session.data(from: url)

        guard let http = response as? HTTPURLResponse else {
            throw APIError.requestFailed
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown server error"
            throw APIError.server("HTTP \(http.statusCode): \(message)")
        }

        struct Envelope: Codable { let results: [PlaceSearchResult] }
        do {
            let env = try JSONDecoder().decode(Envelope.self, from: data)
            return env.results
        } catch {
            throw APIError.decodingFailed
        }
    }

    // MARK: - Reverse Geocode

    /// Calls /reverse_geocode?coords=lat,lon → { "address": "..." }
    func reverseGeocode(coords: CLLocationCoordinate2D) async throws -> String {
        var components = URLComponents(url: baseURL.appendingPathComponent("reverse_geocode"),
                                       resolvingAgainstBaseURL: false)
        components?.queryItems = [
            .init(name: "coords", value: "\(coords.latitude),\(coords.longitude)")
        ]

        guard let url = components?.url else { throw APIError.invalidURL }

        let (data, response) = try await session.data(from: url)

        guard let http = response as? HTTPURLResponse else {
            throw APIError.requestFailed
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown server error"
            throw APIError.server("HTTP \(http.statusCode): \(message)")
        }

        do {
            let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let address = obj?["address"] as? String ?? ""
            return address
        } catch {
            throw APIError.decodingFailed
        }
    }

    // MARK: - Import GPX

    struct ImportGPXResponse: Codable, Hashable {
        let points: Int
        let coordinates: [[Double]]
        let elevation: ElevationProfile
    }

    /// Uploads a GPX file as multipart/form-data to /import_gpx and returns decoded coordinates + elevation.
    func importGPX(data: Data, filename: String = "route.gpx") async throws -> ImportGPXResponse {
        let url = baseURL.appendingPathComponent("import_gpx")

        var req = URLRequest(url: url)
        req.httpMethod = "POST"

        let boundary = "Boundary-\(UUID().uuidString)"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        // Build multipart body
        var body = Data()

        // --boundary
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        // Content-Disposition with field name "file" (FastAPI expects this)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: application/gpx+xml\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n".data(using: .utf8)!)

        // --boundary--
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        req.httpBody = body

        let (respData, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.requestFailed
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = String(data: respData, encoding: .utf8) ?? "Unknown server error"
            throw APIError.server("HTTP \(http.statusCode): \(message)")
        }

        do {
            let decoded = try JSONDecoder().decode(ImportGPXResponse.self, from: respData)
            return decoded
        } catch {
            throw APIError.decodingFailed
        }
    }

    /// Convenience overload: read a local GPX file URL and upload it.
    func importGPX(fileURL: URL) async throws -> ImportGPXResponse {
        let data = try Data(contentsOf: fileURL)
        return try await importGPX(data: data, filename: fileURL.lastPathComponent)
    }
}

// Utility to decode loosely typed JSON dictionaries
private struct CodableValue: Codable, Hashable {
    let value: AnyHashable?

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let s = try? container.decode(String.self) { value = s }
        else if let d = try? container.decode(Double.self) { value = d }
        else if let i = try? container.decode(Int.self) { value = i }
        else if let b = try? container.decode(Bool.self) { value = b }
        else { value = nil }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let s = value as? String { try container.encode(s) }
        else if let d = value as? Double { try container.encode(d) }
        else if let i = value as? Int { try container.encode(i) }
        else if let b = value as? Bool { try container.encode(b) }
        else { try container.encodeNil() }
    }

    var stringValue: String? { value as? String }
    var doubleValue: Double? {
        if let d = value as? Double { return d }
        if let i = value as? Int { return Double(i) }
        return nil
    }
}
