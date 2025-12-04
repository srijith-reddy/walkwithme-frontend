import Foundation
import CoreLocation

extension Route {
    // Returns (instruction text, distance in meters) if available.
    // Currently ignores userLocation; can be enhanced to pick the nearest step.
    func nextInstruction(from userLocation: CLLocationCoordinate2D) -> (text: String, distance: Double)? {
        // Prefer backend-provided nextTurn if present
        if let nt = nextTurn, let instr = nt.instruction, let dist = nt.distanceM {
            return (text: instr, distance: dist)
        }

        // Fallback to the first step (length is in kilometers per Valhalla)
        if let first = steps?.first {
            let meters = (first.length ?? 0) * 1000.0
            return (text: first.instruction, distance: meters)
        }

        return nil
    }
}
