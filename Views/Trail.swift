// Trail.swift
import Foundation
import CoreLocation

struct Trail: Identifiable, Codable, Hashable {
    let id: String
    let name: String

    let centerLat: Double
    let centerLon: Double

    let lengthM: Double
    let distanceFromUserM: Double?
    let elevationGainM: Double?
    let difficultyLevel: String
    let difficultyScore: Double
    let scenicScore: Double
    let safetyScore: Double
    let estTimeMin: Int?

    let previewCoords: [[Double]]
    let geometryCoords: [[Double]]

    let use: String?
    let surface: String?
    let tags: [String]?

    enum CodingKeys: String, CodingKey {
        case id, name
        case centerLat = "center_lat"
        case centerLon = "center_lon"
        case lengthM = "length_m"
        case distanceFromUserM = "distance_from_user_m"
        case elevationGainM = "elevation_gain_m"
        case difficultyLevel = "difficulty_level"
        case difficultyScore = "difficulty_score"
        case scenicScore = "scenic_score"
        case safetyScore = "safety_score"
        case estTimeMin = "est_time_min"
        case previewCoords = "preview_coords"
        case geometryCoords = "geometry_coords"
        case use, surface, tags
    }

    var centerCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: centerLat, longitude: centerLon)
    }

    var previewPoints: [CLLocationCoordinate2D] {
        previewCoords.compactMap { pair in
            guard pair.count == 2 else { return nil }
            return CLLocationCoordinate2D(latitude: pair[0], longitude: pair[1])
        }
    }
}
