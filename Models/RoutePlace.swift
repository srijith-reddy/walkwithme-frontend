import SwiftUI

struct NeighborhoodFlavor: Decodable {
    let label: String
    let emoji: String?
    let description: String?

    var displayText: String {
        let parts = [emoji, label].compactMap { value -> String? in
            guard let value, !value.isEmpty else { return nil }
            return value
        }
        return parts.joined(separator: " ")
    }
}

// MARK: - EnrichedPlace
// A single notable place returned inside the backend's enrichment block.
// Used by landmarks[], food[], and parks[] arrays.

struct EnrichedPlace: Decodable, Identifiable {
    let id = UUID()
    let name: String
    let lat: Double
    let lon: Double
    let category: String?           // "cafe", "bakery", "landmark", "park", etc.
    let rating: Double?
    let note: String?               // "featured in NYT", "viral on TikTok", etc.
    let distanceFromStartM: Double? // meters along route — nil for un-ordered places

    enum CodingKeys: String, CodingKey {
        case name, lat, lon, category, rating, note
        case distanceFromStartM = "distance_from_start_m"
        case distanceFromRouteM = "distance_from_route_m"
    }

    init(name: String, lat: Double, lon: Double, category: String?,
         rating: Double?, note: String?, distanceFromStartM: Double?) {
        self.name = name; self.lat = lat; self.lon = lon
        self.category = category; self.rating = rating
        self.note = note; self.distanceFromStartM = distanceFromStartM
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        lat = try container.decode(Double.self, forKey: .lat)
        lon = try container.decode(Double.self, forKey: .lon)
        category = try container.decodeIfPresent(String.self, forKey: .category)
        rating = try container.decodeIfPresent(Double.self, forKey: .rating)
        note = try container.decodeIfPresent(String.self, forKey: .note)
        distanceFromStartM =
            try container.decodeIfPresent(Double.self, forKey: .distanceFromStartM)
            ?? container.decodeIfPresent(Double.self, forKey: .distanceFromRouteM)
    }

    // MARK: Display helpers

    var icon: String {
        switch (category ?? "").lowercased() {
        case "cafe", "coffee":          return "cup.and.saucer.fill"
        case "bakery":                  return "birthday.cake.fill"
        case "restaurant", "food":      return "fork.knife"
        case "bar", "drinks":           return "wineglass.fill"
        case "park", "garden":          return "leaf.fill"
        case "landmark", "monument":    return "building.columns.fill"
        case "museum", "gallery", "art":return "photo.artframe"
        case "market":                  return "bag.fill"
        default:                        return "mappin.circle.fill"
        }
    }

    var accentColor: Color {
        switch (category ?? "").lowercased() {
        case "cafe", "coffee", "bakery":        return .orange
        case "restaurant", "food", "bar":       return Color(red: 0.9, green: 0.2, blue: 0.2)
        case "park", "garden":                  return .green
        case "landmark", "monument", "museum":  return .blue
        case "gallery", "art":                  return .purple
        case "market":                          return .yellow
        default:                                return .secondary
        }
    }
}

// MARK: - RouteEnrichment
// Top-level enrichment block returned by the backend when enrich=true is passed.
// Maps to: GET /route?...&enrich=true

struct RouteEnrichment: Decodable {
    /// One-paragraph human-readable walk summary — use as route card subtitle when present.
    let summary: String?

    /// Vibe / character of the neighborhood(s) traversed.
    let neighborhoodFlavor: NeighborhoodFlavor?

    /// Short highlight strings: "Passes by the Brooklyn Bridge", "Great bakeries on this block"
    let highlights: [String]?

    /// Historical / architectural landmarks along the route.
    let landmarks: [EnrichedPlace]?

    /// Cafes, bakeries, restaurants, bars worth stopping at.
    let food: [EnrichedPlace]?

    /// Green spaces and parks along the route.
    let parks: [EnrichedPlace]?

    enum CodingKeys: String, CodingKey {
        case summary
        case neighborhoodFlavor = "neighborhood_flavor"
        case highlights
        case landmarks
        case food
        case parks
    }

    /// All notable places from all categories, sorted by distance from start when available.
    var allPlaces: [EnrichedPlace] {
        let combined = (landmarks ?? []) + (food ?? []) + (parks ?? [])
        return combined.sorted {
            let a = $0.distanceFromStartM ?? Double.infinity
            let b = $1.distanceFromStartM ?? Double.infinity
            return a < b
        }
    }
}
