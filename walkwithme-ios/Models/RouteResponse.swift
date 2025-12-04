import Foundation
import CoreLocation

struct RouteSummary: Codable {
    let hasTimeRestrictions: Bool?
    let hasToll: Bool?
    let hasHighway: Bool?
    let hasFerry: Bool?
    let minLat: Double?
    let minLon: Double?
    let maxLat: Double?
    let maxLon: Double?
    let time: Double?     // seconds
    let length: Double?   // km
    let cost: Double?

    enum CodingKeys: String, CodingKey {
        case hasTimeRestrictions = "has_time_restrictions"
        case hasToll              = "has_toll"
        case hasHighway           = "has_highway"
        case hasFerry             = "has_ferry"
        case minLat               = "min_lat"
        case minLon               = "min_lon"
        case maxLat               = "max_lat"
        case maxLon               = "max_lon"
        case time, length, cost
    }
}

struct ElevationProfile: Codable {
    let elevations: [Double]
    let elevationGainM: Double
    let elevationLossM: Double
    let slopes: [Double]
    let maxSlopePercent: Double
    let difficulty: String

    enum CodingKeys: String, CodingKey {
        case elevations
        case elevationGainM  = "elevation_gain_m"
        case elevationLossM  = "elevation_loss_m"
        case slopes
        case maxSlopePercent = "max_slope_percent"
        case difficulty
    }
}

struct NextTurn: Codable {
    let type: Int?
    let instruction: String?
    let distanceM: Double?
    let degrees: Double?

    enum CodingKeys: String, CodingKey {
        case type
        case instruction
        case distanceM = "distance_m"
        case degrees
    }
}

struct Route: Identifiable, Codable {
    let id = UUID()

    let mode: String

    /// Full polyline decoded from Valhalla: [[lat, lon]]
    let coordinates: [[Double]]

    /// Simplified nodes for AR (may be nil for some modes)
    let waypoints: [[Double]]?

    /// Distance in meters (we compute from `summary.length` if needed)
    let distanceM: Double?
    /// Duration in seconds
    let durationS: Double?

    let summary: RouteSummary?

    /// Turn-by-turn steps (optional)
    let steps: [Step]?

    /// Elevation analysis from /route wrapper
    let elevation: ElevationProfile?

    /// AI helper fields (only present for some modes)
    let safetyScore: Double?
    let scenicScore: Double?
    let aiBestScore: Double?

    let nextTurn: NextTurn?

    enum CodingKeys: String, CodingKey {
        case mode
        case coordinates
        case waypoints
        case distanceM  = "distance_m"
        case durationS  = "duration_s"
        case summary
        case steps
        case elevation
        case safetyScore = "safety_score"
        case scenicScore = "scenic_score"
        case aiBestScore = "ai_best_score"
        case nextTurn    = "next_turn"
    }

    /// Convenience: convert to CLLocationCoordinate2D for Map / AR
    var coordinatePoints: [CLLocationCoordinate2D] {
        coordinates.compactMap { pair in
            guard pair.count == 2 else { return nil }
            return CLLocationCoordinate2D(latitude: pair[0], longitude: pair[1])
        }
    }

    var waypointPoints: [CLLocationCoordinate2D] {
        (waypoints ?? []).compactMap { pair in
            guard pair.count == 2 else { return nil }
            return CLLocationCoordinate2D(latitude: pair[0], longitude: pair[1])
        }
    }
}
