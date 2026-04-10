import Foundation
import CoreLocation

// MARK: - Loop Origin

struct LoopOrigin: Decodable {
    let label: String
    let lat: Double
    let lon: Double
    /// "area" | "station" | "user_location" | "default"
    let originType: String?

    enum CodingKeys: String, CodingKey {
        case label, lat, lon
        case originType = "origin_type"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        label      = try c.decodeIfPresent(String.self, forKey: .label) ?? "Nearby"
        lat        = try c.decodeIfPresent(Double.self, forKey: .lat) ?? 0
        lon        = try c.decodeIfPresent(Double.self, forKey: .lon) ?? 0
        originType = try c.decodeIfPresent(String.self, forKey: .originType)
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
}

// MARK: - Loop Route Preview

/// Lightweight geometry preview returned by /loop_assistant.
/// Not used for navigation — navigation calls GET /route instead.
struct LoopRoutePreview: Decodable {
    let geometry: [[Double]]?
    let waypoints: [[Double]]?
}

// MARK: - Loop Option

struct LoopOption: Decodable, Identifiable {
    let id: String
    let title: String
    let subtitle: String
    /// Theme slug passed to GET /route as loop_theme= (e.g. "food", "scenic")
    let theme: String
    let routeStyle: String?
    let durationMin: Int
    let distanceMiles: Double
    /// Short human explanation of why this loop was selected
    let whyThis: String?
    let highlights: [String]
    let neighborhoodCharacter: String?
    let suggestedStops: [String]
    let routePreview: LoopRoutePreview?

    enum CodingKeys: String, CodingKey {
        case id, title, subtitle, theme, highlights
        case routeStyle            = "route_style"
        case durationMin           = "duration_min"
        case distanceMiles         = "distance_miles"
        case whyThis               = "why_this"
        case neighborhoodCharacter = "neighborhood_character"
        case suggestedStops        = "suggested_stops"
        case routePreview          = "route_preview"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        // Required-ish — fall back to safe defaults so one bad field
        // doesn't nuke the whole response.
        id       = try c.decodeIfPresent(String.self, forKey: .id)       ?? UUID().uuidString
        title    = try c.decodeIfPresent(String.self, forKey: .title)    ?? "Loop"
        subtitle = try c.decodeIfPresent(String.self, forKey: .subtitle) ?? ""
        theme    = try c.decodeIfPresent(String.self, forKey: .theme)    ?? "scenic"

        routeStyle            = try c.decodeIfPresent(String.self, forKey: .routeStyle)
        neighborhoodCharacter = try c.decodeIfPresent(String.self, forKey: .neighborhoodCharacter)
        whyThis               = try c.decodeIfPresent(String.self, forKey: .whyThis)
        routePreview          = try c.decodeIfPresent(LoopRoutePreview.self, forKey: .routePreview)

        // Numeric fields — backend might send Int or Double
        if let i = try? c.decode(Int.self, forKey: .durationMin) {
            durationMin = i
        } else if let d = try? c.decode(Double.self, forKey: .durationMin) {
            durationMin = Int(d)
        } else {
            durationMin = 30
        }

        if let d = try? c.decode(Double.self, forKey: .distanceMiles) {
            distanceMiles = d
        } else if let i = try? c.decode(Int.self, forKey: .distanceMiles) {
            distanceMiles = Double(i)
        } else {
            distanceMiles = 0
        }

        // Array fields — tolerate null or missing
        highlights    = (try? c.decodeIfPresent([String].self, forKey: .highlights))    ?? []
        suggestedStops = (try? c.decodeIfPresent([String].self, forKey: .suggestedStops)) ?? []
    }

    // MARK: Display helpers

    var durationText: String {
        durationMin < 60
            ? "\(durationMin) min"
            : "\(durationMin / 60) hr\(durationMin % 60 > 0 ? " \(durationMin % 60) min" : "")"
    }

    var distanceText: String {
        distanceMiles > 0 ? String(format: "%.1f mi", distanceMiles) : ""
    }

    func originLabel(from origin: LoopOrigin) -> String {
        "Starts and ends in \(origin.label)"
    }
}

// MARK: - Loop Assistant Response

struct LoopAssistantResponse: Decodable {
    let origin: LoopOrigin
    let assistantSummary: String?
    let options: [LoopOption]

    enum CodingKeys: String, CodingKey {
        case origin, options
        case assistantSummary = "assistant_summary"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        assistantSummary = try c.decodeIfPresent(String.self, forKey: .assistantSummary)

        // origin is required; if missing we build a placeholder so
        // we can still show whatever options the server returned.
        if let o = try? c.decode(LoopOrigin.self, forKey: .origin) {
            origin = o
        } else {
            origin = LoopOrigin(label: "Nearby", lat: 0, lon: 0, originType: nil)
        }

        options = (try? c.decodeIfPresent([LoopOption].self, forKey: .options)) ?? []
    }
}

// MARK: - Convenience inits (used by LoopFavoritesStore reconstruction)

extension LoopOrigin {
    init(label: String, lat: Double, lon: Double, originType: String? = nil) {
        self.label      = label
        self.lat        = lat
        self.lon        = lon
        self.originType = originType
    }
}

extension LoopOption {
    init(id: String, title: String, subtitle: String, theme: String,
         durationMin: Int, distanceMiles: Double, whyThis: String?,
         highlights: [String], suggestedStops: [String]) {
        self.id                    = id
        self.title                 = title
        self.subtitle              = subtitle
        self.theme                 = theme
        self.durationMin           = durationMin
        self.distanceMiles         = distanceMiles
        self.whyThis               = whyThis
        self.highlights            = highlights
        self.suggestedStops        = suggestedStops
        self.routeStyle            = nil
        self.neighborhoodCharacter = nil
        self.routePreview          = nil
    }
}
