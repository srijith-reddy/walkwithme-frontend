import Foundation
import CoreLocation
import Combine

@MainActor
final class NavigationManager: ObservableObject {
    @Published var currentRoute: Route?
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var mode: String = "shortest"

    /// For later: which step we're currently on
    @Published var currentStepIndex: Int = 0

    var nextTurnText: String {
        guard let steps = currentRoute?.steps, !steps.isEmpty else {
            return "Start walking"
        }
        let idx = min(currentStepIndex, steps.count - 1)
        return steps[idx].instruction
    }

    var distanceText: String {
        guard let meters = currentRoute?.distanceM ?? currentRoute?.summary?.length.map({ $0 * 1000 }) else {
            return "—"
        }
        if meters < 1000 {
            return String(format: "%.0f m", meters)
        } else {
            return String(format: "%.1f km", meters / 1000.0)
        }
    }

    func reset() {
        currentRoute = nil
        isLoading = false
        errorMessage = nil
        currentStepIndex = 0
    }

    func fetchRoute(start: CLLocationCoordinate2D,
                    end: CLLocationCoordinate2D?) async {

        isLoading = true
        errorMessage = nil

        do {
            let route = try await API.shared.fetchRoute(start: start, end: end, mode: mode)
            self.currentRoute = route
            self.currentStepIndex = 0
        } catch {
            self.errorMessage = error.localizedDescription
            self.currentRoute = nil
        }

        isLoading = false
    }
}
