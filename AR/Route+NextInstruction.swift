import Foundation
import CoreLocation

extension Route {
    // Returns (instruction text, distance in meters) if available.
    // Currently ignores userLocation; can be enhanced to pick the nearest step.
    func nextInstruction(from userLocation: CLLocationCoordinate2D) -> (text: String, distance: Double)? {
        // Prefer backend-provided nextTurn if present
        if let nt = nextTurn,
           let instr = nt.instruction?.trimmingCharacters(in: .whitespacesAndNewlines),
           !instr.isEmpty,
           let dist = nt.distanceM,
           dist > 8 {
            return (text: instr, distance: dist)
        }

        // Fallback to the first meaningful step (skip empty / zero-length startup instructions)
        if let step = steps?.first(where: {
            !$0.instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            (($0.length ?? 0) * 1000.0) > 8
        }) {
            let meters = max((step.length ?? 0) * 1000.0, 8)
            return (text: step.instruction, distance: meters)
        }

        // If all we have is the backend nextTurn, use it last.
        if let nt = nextTurn,
           let instr = nt.instruction?.trimmingCharacters(in: .whitespacesAndNewlines),
           !instr.isEmpty,
           let dist = nt.distanceM {
            return (text: instr, distance: max(dist, 0))
        }

        if let first = steps?.first,
           !first.instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let meters = max((first.length ?? 0) * 1000.0, 0)
            return (text: first.instruction, distance: meters)
        }

        return nil
    }
}
