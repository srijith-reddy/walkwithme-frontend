import Foundation

struct Step: Identifiable, Codable {
    let id = UUID()

    /// e.g. "Walk south on the walkway."
    let instruction: String

    /// Valhalla maneuver type (3 = start, 10 = right, 15 = left, 5 = arrive, 28 ferry, etc.)
    let type: Int?

    /// Length of this step in **kilometers** (Valhalla sends km in `length`)
    let length: Double?

    /// Raw indices into the shape array (we can map to coordinates later if needed)
    let beginLat: Int?
    let endLat: Int?

    enum CodingKeys: String, CodingKey {
        case instruction
        case type
        case length
        case beginLat = "begin_lat"
        case endLat   = "end_lat"
    }
}
