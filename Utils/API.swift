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

struct PlaceSuggestion: Decodable, Identifiable, Hashable {
    let id = UUID()
    let label: String
    let lat: Double
    let lon: Double
}

// Rich POI result from /places_search (no photos)
struct PlaceSearchResult: Decodable, Identifiable, Hashable {
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
        case reviewCount = "review_count"
        case lat
        case lon
        case openNow     = "open_now"
        case distanceKm  = "distance_km"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        address = try container.decodeIfPresent(String.self, forKey: .address)
        rating = try container.decodeIfPresent(Double.self, forKey: .rating)
        reviews =
            try container.decodeIfPresent(Int.self, forKey: .reviews)
            ?? container.decodeIfPresent(Int.self, forKey: .reviewCount)
        lat = try container.decode(Double.self, forKey: .lat)
        lon = try container.decode(Double.self, forKey: .lon)
        openNow = try container.decodeIfPresent(Bool.self, forKey: .openNow)
        distanceKm = try container.decodeIfPresent(Double.self, forKey: .distanceKm)
    }
}

struct WalkPersona: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let emoji: String
    let tagline: String
    let routingBias: String?
    let highlightCategories: [String]?
    let timeOfDay: String?
    let weather: String?

    enum CodingKeys: String, CodingKey {
        case id, name, emoji, tagline, weather
        case routingBias = "routing_bias"
        case highlightCategories = "highlight_categories"
        case timeOfDay = "time_of_day"
    }
}

struct WalkTheme: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let emoji: String
    let tagline: String
    let description: String
    let loopTheme: String
    let suggestedDurationMin: Int
    let highlightCategories: [String]
    let tags: [String]

    enum CodingKeys: String, CodingKey {
        case id, name, emoji, tagline, description, tags
        case loopTheme = "loop_theme"
        case suggestedDurationMin = "suggested_duration_min"
        case highlightCategories = "highlight_categories"
    }
}

struct NearbyPlace: Decodable, Identifiable, Hashable {
    let id = UUID()
    let name: String
    let category: String?
    let emoji: String?
    let lat: Double
    let lon: Double
    let distanceFromYouM: Double?
    let distanceFromRouteM: Double?
    let cuisine: String?
    let openingHours: String?
    let website: String?

    enum CodingKeys: String, CodingKey {
        case name, category, emoji, lat, lon, cuisine, website
        case distanceFromYouM = "distance_from_you_m"
        case distanceFromRouteM = "distance_from_route_m"
        case openingHours = "opening_hours"
    }
}

struct DetourPlace: Decodable, Identifiable, Hashable {
    let id = UUID()
    let name: String
    let category: String?
    let emoji: String?
    let lat: Double
    let lon: Double
    let extraMinutes: Double?
    let worthItScore: Double?
    let label: String?

    enum CodingKeys: String, CodingKey {
        case name, category, emoji, lat, lon, label
        case extraMinutes = "extra_minutes"
        case worthItScore = "worth_it_score"
    }
}

struct DetoursResponse: Decodable, Hashable {
    let mode: String
    let distanceM: Double?
    let durationS: Double?
    let detourCount: Int
    let detours: [DetourPlace]

    enum CodingKeys: String, CodingKey {
        case mode, detours
        case distanceM = "distance_m"
        case durationS = "duration_s"
        case detourCount = "detour_count"
    }
}

struct WalkCoverage: Decodable, Hashable {
    let walkedCells: Int
    let totalCells: Int
    let coveragePct: Double
    let totalWalkedKm: Double
    let uniqueKm: Double
    let routeCount: Int

    enum CodingKeys: String, CodingKey {
        case walkedCells = "walked_cells"
        case totalCells = "total_cells"
        case coveragePct = "coverage_pct"
        case totalWalkedKm = "total_walked_km"
        case uniqueKm = "unique_km"
        case routeCount = "route_count"
    }
}

struct UnexploredSuggestion: Decodable, Identifiable, Hashable {
    let id = UUID()
    let lat: Double
    let lon: Double
    let distanceFromYouM: Double
    let direction: String
    let label: String

    enum CodingKeys: String, CodingKey {
        case lat, lon, direction, label
        case distanceFromYouM = "distance_from_you_m"
    }
}

struct WalkAnalysisResponse: Decodable, Hashable {
    let coverage: WalkCoverage
    let insight: String
    let unexploredSuggestions: [UnexploredSuggestion]

    enum CodingKeys: String, CodingKey {
        case coverage, insight
        case unexploredSuggestions = "unexplored_suggestions"
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

    /// Calls /route?start=lat,lon&end=lat,lon&mode=...&enrich=true&elevation=true&[loop_theme=...]
    func fetchRoute(start: CLLocationCoordinate2D,
                    end: CLLocationCoordinate2D?,
                    mode: String = "loop",
                    duration: Int = 30,
                    loopTheme: String? = nil) async throws -> Route {

        var components = URLComponents(url: baseURL.appendingPathComponent("route"),
                                       resolvingAgainstBaseURL: false)
        var query: [URLQueryItem] = [
            .init(name: "start",     value: "\(start.latitude),\(start.longitude)"),
            .init(name: "mode",      value: mode),
            .init(name: "duration",  value: "\(duration)"),
            .init(name: "enrich",    value: "true"),
            .init(name: "elevation", value: "true"),
        ]

        if let end {
            query.append(.init(name: "end", value: "\(end.latitude),\(end.longitude)"))
        }

        // loop_theme only makes sense for loop mode (e.g. "coffee", "scenic", "food")
        if mode == "loop", let theme = loopTheme, !theme.isEmpty {
            query.append(.init(name: "loop_theme", value: theme))
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

        struct Envelope: Decodable { let results: [PlaceSearchResult] }
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

    struct ImportGPXResponse: Decodable {
        let points: Int
        let coordinates: [[Double]]
        let elevation: ElevationProfile
    }

    // MARK: - Persona

    func fetchPersona(lat: Double, lon: Double) async throws -> WalkPersona {
        var components = URLComponents(url: baseURL.appendingPathComponent("persona"),
                                       resolvingAgainstBaseURL: false)
        components?.queryItems = [
            .init(name: "lat", value: "\(lat)"),
            .init(name: "lon", value: "\(lon)")
        ]

        guard let url = components?.url else { throw APIError.invalidURL }
        let (data, response) = try await session.data(from: url)
        try validate(response: response, data: data)
        return try JSONDecoder().decode(WalkPersona.self, from: data)
    }

    // MARK: - Themes

    func fetchThemes(tag: String? = nil) async throws -> [WalkTheme] {
        var components = URLComponents(url: baseURL.appendingPathComponent("themes"),
                                       resolvingAgainstBaseURL: false)
        if let tag, !tag.isEmpty {
            components?.queryItems = [.init(name: "tag", value: tag)]
        }

        guard let url = components?.url else { throw APIError.invalidURL }
        let (data, response) = try await session.data(from: url)
        try validate(response: response, data: data)

        struct Envelope: Decodable { let themes: [WalkTheme] }
        return try JSONDecoder().decode(Envelope.self, from: data).themes
    }

    func fetchThemeDetail(themeID: String) async throws -> WalkTheme {
        let url = baseURL.appendingPathComponent("themes").appendingPathComponent(themeID)
        let (data, response) = try await session.data(from: url)
        try validate(response: response, data: data)
        return try JSONDecoder().decode(WalkTheme.self, from: data)
    }

    // MARK: - Nearby

    func fetchNearby(lat: Double,
                     lon: Double,
                     radiusM: Int = 500,
                     category: String = "all") async throws -> [NearbyPlace] {
        var components = URLComponents(url: baseURL.appendingPathComponent("nearby"),
                                       resolvingAgainstBaseURL: false)
        components?.queryItems = [
            .init(name: "lat", value: "\(lat)"),
            .init(name: "lon", value: "\(lon)"),
            .init(name: "radius_m", value: "\(radiusM)"),
            .init(name: "category", value: category)
        ]

        guard let url = components?.url else { throw APIError.invalidURL }
        let (data, response) = try await session.data(from: url)
        try validate(response: response, data: data)

        struct Envelope: Decodable { let results: [NearbyPlace] }
        return try JSONDecoder().decode(Envelope.self, from: data).results
    }

    // MARK: - Detours

    func fetchDetours(start: CLLocationCoordinate2D,
                      end: CLLocationCoordinate2D,
                      mode: String,
                      maxDetourM: Int = 400,
                      topN: Int = 3) async throws -> DetoursResponse {
        var components = URLComponents(url: baseURL.appendingPathComponent("detours"),
                                       resolvingAgainstBaseURL: false)
        components?.queryItems = [
            .init(name: "start", value: "\(start.latitude),\(start.longitude)"),
            .init(name: "end", value: "\(end.latitude),\(end.longitude)"),
            .init(name: "mode", value: mode),
            .init(name: "max_detour_m", value: "\(maxDetourM)"),
            .init(name: "top_n", value: "\(topN)")
        ]

        guard let url = components?.url else { throw APIError.invalidURL }
        let (data, response) = try await session.data(from: url)
        try validate(response: response, data: data)
        return try JSONDecoder().decode(DetoursResponse.self, from: data)
    }

    // MARK: - Walk Analysis

    func analyzeWalks(routes: [[[Double]]],
                      centerLat: Double?,
                      centerLon: Double?,
                      suggestUnexplored: Bool = true,
                      radiusM: Int = 1500) async throws -> WalkAnalysisResponse {
        let url = baseURL.appendingPathComponent("walks").appendingPathComponent("analyze")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        struct Payload: Encodable {
            let routes: [[[Double]]]
            let centerLat: Double?
            let centerLon: Double?
            let suggestUnexplored: Bool
            let radiusM: Int

            enum CodingKeys: String, CodingKey {
                case routes
                case centerLat = "center_lat"
                case centerLon = "center_lon"
                case suggestUnexplored = "suggest_unexplored"
                case radiusM = "radius_m"
            }
        }

        let payload = Payload(
            routes: routes,
            centerLat: centerLat,
            centerLon: centerLon,
            suggestUnexplored: suggestUnexplored,
            radiusM: radiusM
        )

        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)
        return try JSONDecoder().decode(WalkAnalysisResponse.self, from: data)
    }

    // MARK: - Export GPX

    func exportGPX(start: CLLocationCoordinate2D,
                   end: CLLocationCoordinate2D?,
                   mode: String,
                   duration: Int = 30,
                   loopTheme: String? = nil,
                   name: String = "WalkWithMe Route") async throws -> URL {
        var components = URLComponents(url: baseURL.appendingPathComponent("export_gpx"),
                                       resolvingAgainstBaseURL: false)

        var query: [URLQueryItem] = [
            .init(name: "start", value: "\(start.latitude),\(start.longitude)"),
            .init(name: "mode", value: mode),
            .init(name: "duration", value: "\(duration)"),
            .init(name: "name", value: name)
        ]

        if let end {
            query.append(.init(name: "end", value: "\(end.latitude),\(end.longitude)"))
        }
        if let loopTheme, !loopTheme.isEmpty {
            query.append(.init(name: "loop_theme", value: loopTheme))
        }

        components?.queryItems = query
        guard let url = components?.url else { throw APIError.invalidURL }

        let (data, response) = try await session.data(from: url)
        try validate(response: response, data: data)

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("walkwithme-\(UUID().uuidString).gpx")
        try data.write(to: tempURL, options: .atomic)
        return tempURL
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

    // MARK: - Loop Assistant

    /// POST /loop_assistant — returns ranked loop options for natural-language query.
    /// Response is preview-only; navigation calls GET /route after selection.
    func fetchLoopOptions(query: String,
                          userLat: Double?,
                          userLon: Double?,
                          maxOptions: Int = 3) async throws -> LoopAssistantResponse {

        let url = baseURL.appendingPathComponent("loop_assistant")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        struct Payload: Encodable {
            let query: String
            let userLat: Double?
            let userLon: Double?
            let maxOptions: Int

            enum CodingKeys: String, CodingKey {
                case query
                case userLat    = "user_lat"
                case userLon    = "user_lon"
                case maxOptions = "max_options"
            }
        }

        let payload = Payload(
            query: query,
            userLat: userLat,
            userLon: userLon,
            maxOptions: maxOptions
        )
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)

        do {
            let decoder = JSONDecoder()
            return try decoder.decode(LoopAssistantResponse.self, from: data)
        } catch {
            // Log the raw payload so mismatches are easy to diagnose
            let raw = String(data: data, encoding: .utf8) ?? "<binary>"
            print("⚠️ LoopAssistant decoding error:", error)
            print("⚠️ Raw response:", raw)
            throw APIError.decodingFailed
        }
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw APIError.requestFailed
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown server error"
            throw APIError.server("HTTP \(http.statusCode): \(message)")
        }
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
