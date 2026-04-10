import Foundation
import CoreLocation

struct RouteSummary: Decodable {
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

struct ElevationProfile: Decodable, Equatable, Hashable {
    let elevations: [Double]?
    let elevationGainM: Double?
    let elevationLossM: Double?
    let slopes: [Double]?
    let maxSlopePercent: Double?
    let difficulty: String?

    enum CodingKeys: String, CodingKey {
        case elevations
        case elevationGainM  = "elevation_gain_m"
        case elevationLossM  = "elevation_loss_m"
        case slopes
        case maxSlopePercent = "max_slope_percent"
        case difficulty
    }
}

struct NextTurn: Decodable {
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

struct Route: Identifiable, Decodable, Equatable {
    static func == (lhs: Route, rhs: Route) -> Bool { lhs.id == rhs.id }
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

    /// Route enrichment — landmarks, food, parks, highlights, neighborhood summary.
    /// Present when API is called with enrich=true. nil otherwise (degrades gracefully).
    let enrichment: RouteEnrichment?

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
        case enrichment
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

    var resolvedDistanceM: Double? {
        if let distanceM, distanceM > 0 { return distanceM }
        if let lengthKm = summary?.length, lengthKm > 0 { return lengthKm * 1000 }

        let points = coordinatePoints
        guard points.count >= 2 else { return nil }

        var total: CLLocationDistance = 0
        for index in 1..<points.count {
            total += CLLocation(latitude: points[index - 1].latitude, longitude: points[index - 1].longitude)
                .distance(from: CLLocation(latitude: points[index].latitude, longitude: points[index].longitude))
        }
        return total > 0 ? total : nil
    }

    var resolvedDurationS: Double? {
        if let durationS, durationS > 0 { return durationS }
        if let time = summary?.time, time > 0 { return time }
        if let distance = resolvedDistanceM, distance > 0 { return distance / 1.4 }
        return nil
    }
}

extension Route {
    nonisolated static func combined(from legs: [Route],
                                     mode: String,
                                     closesLoop: Bool) -> Route? {
        guard !legs.isEmpty else { return nil }

        let mergedCoordinates = mergeCoordinateArrays(legs.map(\.coordinates))
        let mergedWaypoints = mergeCoordinateArrays(legs.compactMap(\.waypoints))

        let distanceM = legs.reduce(0.0) { $0 + legDistanceMeters($1) }
        let durationS = legs.reduce(0.0) { $0 + legDurationSeconds($1) }

        let mergedSummary = buildSummary(from: legs,
                                         coordinates: mergedCoordinates,
                                         distanceM: distanceM,
                                         durationS: durationS)

        let mergedSteps = buildSteps(from: legs)
        let mergedElevation = buildElevation(from: legs)
        let mergedEnrichment = buildEnrichment(from: legs, closesLoop: closesLoop)

        let safetyScores = legs.compactMap(\.safetyScore)
        let scenicScores = legs.compactMap(\.scenicScore)
        let aiScores = legs.compactMap(\.aiBestScore)

        return Route(
            mode: mode,
            coordinates: mergedCoordinates,
            waypoints: mergedWaypoints.isEmpty ? nil : mergedWaypoints,
            distanceM: distanceM > 0 ? distanceM : nil,
            durationS: durationS > 0 ? durationS : nil,
            summary: mergedSummary,
            steps: mergedSteps.isEmpty ? nil : mergedSteps,
            elevation: mergedElevation,
            safetyScore: average(safetyScores),
            scenicScore: average(scenicScores),
            aiBestScore: average(aiScores),
            nextTurn: nil,
            enrichment: mergedEnrichment
        )
    }

    nonisolated private static func legDistanceMeters(_ leg: Route) -> Double {
        leg.resolvedDistanceM ?? 0
    }

    nonisolated private static func legDurationSeconds(_ leg: Route) -> Double {
        leg.resolvedDurationS ?? 0
    }

    nonisolated private static func mergeCoordinateArrays(_ arrays: [[[Double]]]) -> [[Double]] {
        var merged: [[Double]] = []

        for array in arrays where !array.isEmpty {
            if merged.isEmpty {
                merged.append(contentsOf: array)
            } else if let last = merged.last, let first = array.first, coordinatesEqual(last, first) {
                merged.append(contentsOf: array.dropFirst())
            } else {
                merged.append(contentsOf: array)
            }
        }

        return merged
    }

    nonisolated private static func coordinatesEqual(_ lhs: [Double], _ rhs: [Double]) -> Bool {
        guard lhs.count == 2, rhs.count == 2 else { return lhs == rhs }
        return abs(lhs[0] - rhs[0]) < 0.000001 && abs(lhs[1] - rhs[1]) < 0.000001
    }

    nonisolated private static func buildSummary(from legs: [Route],
                                                 coordinates: [[Double]],
                                                 distanceM: Double,
                                                 durationS: Double) -> RouteSummary? {
        guard !coordinates.isEmpty else { return nil }

        let lats = coordinates.compactMap { $0.count == 2 ? $0[0] : nil }
        let lons = coordinates.compactMap { $0.count == 2 ? $0[1] : nil }

        return RouteSummary(
            hasTimeRestrictions: legs.contains { $0.summary?.hasTimeRestrictions == true } ? true : nil,
            hasToll: legs.contains { $0.summary?.hasToll == true } ? true : nil,
            hasHighway: legs.contains { $0.summary?.hasHighway == true } ? true : nil,
            hasFerry: legs.contains { $0.summary?.hasFerry == true } ? true : nil,
            minLat: lats.min(),
            minLon: lons.min(),
            maxLat: lats.max(),
            maxLon: lons.max(),
            time: durationS > 0 ? durationS : nil,
            length: distanceM > 0 ? distanceM / 1000 : nil,
            cost: legs.compactMap { $0.summary?.cost }.reduce(0, +)
        )
    }

    nonisolated private static func buildSteps(from legs: [Route]) -> [Step] {
        var merged: [Step] = []

        for (index, leg) in legs.enumerated() {
            var legSteps = leg.steps ?? []
            if index < legs.count - 1 {
                legSteps.removeAll(where: isArrivalStep)
            }
            merged.append(contentsOf: legSteps.map {
                Step(instruction: $0.instruction,
                     type: $0.type,
                     length: $0.length,
                     beginLat: nil,
                     endLat: nil)
            })
        }

        return merged
    }

    nonisolated private static func isArrivalStep(_ step: Step) -> Bool {
        if step.type == 5 { return true }
        let lower = step.instruction.lowercased()
        return lower.contains("arrive") || lower.contains("destination")
    }

    nonisolated private static func buildElevation(from legs: [Route]) -> ElevationProfile? {
        let profiles = legs.compactMap(\.elevation)
        guard !profiles.isEmpty else { return nil }

        let mergedElevations = mergeSeries(profiles.compactMap(\.elevations))
        let mergedSlopes = mergeSeries(profiles.compactMap(\.slopes))

        return ElevationProfile(
            elevations: mergedElevations.isEmpty ? nil : mergedElevations,
            elevationGainM: profiles.compactMap(\.elevationGainM).reduce(0, +),
            elevationLossM: profiles.compactMap(\.elevationLossM).reduce(0, +),
            slopes: mergedSlopes.isEmpty ? nil : mergedSlopes,
            maxSlopePercent: profiles.compactMap(\.maxSlopePercent).max(),
            difficulty: hardestDifficulty(profiles.compactMap(\.difficulty))
        )
    }

    nonisolated private static func mergeSeries(_ arrays: [[Double]]) -> [Double] {
        var merged: [Double] = []

        for array in arrays where !array.isEmpty {
            if merged.isEmpty {
                merged.append(contentsOf: array)
            } else if let last = merged.last, let first = array.first, abs(last - first) < 0.0001 {
                merged.append(contentsOf: array.dropFirst())
            } else {
                merged.append(contentsOf: array)
            }
        }

        return merged
    }

    nonisolated private static func hardestDifficulty(_ values: [String]) -> String? {
        let rank: [String: Int] = [
            "easy": 0,
            "moderate": 1,
            "hard": 2,
            "very hard": 3
        ]

        return values.max {
            rank[$0.lowercased(), default: -1] < rank[$1.lowercased(), default: -1]
        }
    }

    nonisolated private static func buildEnrichment(from legs: [Route], closesLoop: Bool) -> RouteEnrichment? {
        let enrichments = legs.compactMap(\.enrichment)
        guard !enrichments.isEmpty else { return nil }

        var landmarks: [EnrichedPlace] = []
        var food: [EnrichedPlace] = []
        var parks: [EnrichedPlace] = []
        var highlights: [String] = []
        var seenPlaces = Set<String>()
        var seenHighlights = Set<String>()

        var distanceOffset = 0.0
        for leg in legs {
            if let enrichment = leg.enrichment {
                landmarks.append(contentsOf: shiftedUniquePlaces(enrichment.landmarks ?? [],
                                                                offset: distanceOffset,
                                                                seen: &seenPlaces))
                food.append(contentsOf: shiftedUniquePlaces(enrichment.food ?? [],
                                                           offset: distanceOffset,
                                                           seen: &seenPlaces))
                parks.append(contentsOf: shiftedUniquePlaces(enrichment.parks ?? [],
                                                            offset: distanceOffset,
                                                            seen: &seenPlaces))

                for highlight in enrichment.highlights ?? [] where seenHighlights.insert(highlight).inserted {
                    highlights.append(highlight)
                }
            }

            distanceOffset += legDistanceMeters(leg)
        }

        let stopCount = max(0, legs.count - 1)
        let generatedSummary: String? = stopCount > 0
            ? (closesLoop
               ? "Custom walking loop with \(stopCount) stop\(stopCount == 1 ? "" : "s")."
               : "Walk with \(stopCount) stop\(stopCount == 1 ? "" : "s") along the way.")
            : nil

        return RouteEnrichment(
            summary: generatedSummary ?? enrichments.compactMap(\.summary).first,
            neighborhoodFlavor: enrichments.compactMap(\.neighborhoodFlavor).first,
            highlights: highlights.isEmpty ? nil : Array(highlights.prefix(8)),
            landmarks: landmarks.isEmpty ? nil : landmarks,
            food: food.isEmpty ? nil : food,
            parks: parks.isEmpty ? nil : parks
        )
    }

    nonisolated private static func shiftedUniquePlaces(_ places: [EnrichedPlace],
                                                        offset: Double,
                                                        seen: inout Set<String>) -> [EnrichedPlace] {
        places.compactMap { place in
            let key = "\(place.name.lowercased())|\(place.lat)|\(place.lon)|\(place.category ?? "")"
            guard seen.insert(key).inserted else { return nil }
            return EnrichedPlace(
                name: place.name,
                lat: place.lat,
                lon: place.lon,
                category: place.category,
                rating: place.rating,
                note: place.note,
                distanceFromStartM: place.distanceFromStartM.map { $0 + offset }
            )
        }
    }

    nonisolated private static func average(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }
}
