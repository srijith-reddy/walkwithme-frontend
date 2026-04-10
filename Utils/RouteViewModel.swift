import SwiftUI
import Foundation
import CoreLocation
import Combine

// MARK: - Walk Prompt

struct WalkPrompt: Identifiable {
    let id = UUID()
    let emoji: String
    let label: String
    let mode: String
    let duration: Int       // minutes to pass to /route as duration=
    let loopTheme: String?  // passed as loop_theme= when mode == "loop"
}

let walkPrompts: [WalkPrompt] = [
    .init(emoji: "✨", label: "AI best route",   mode: "best",      duration: 30, loopTheme: nil),
    .init(emoji: "🌿", label: "Scenic route",    mode: "scenic",    duration: 35, loopTheme: nil),
    .init(emoji: "🏔", label: "Go hilly",        mode: "elevation", duration: 40, loopTheme: nil),
    .init(emoji: "🛡", label: "Safe streets",    mode: "safe",      duration: 25, loopTheme: nil),
]

// MARK: - RouteViewModel

@MainActor
final class RouteViewModel: ObservableObject {

    // Route state
    @Published var currentRoute: Route?
    @Published var isLoading = false
    @Published var mode = "loop"

    // Toast
    @Published var toastMessage: String?
    @Published var toastIsError = true
    private var toastTask: Task<Void, Never>?

    // MARK: - Loop Assistant state

    @Published var loopQuery        = ""
    @Published var loopOptions:     [LoopOption] = []
    @Published var isLoadingLoops   = false
    @Published var selectedLoop:    LoopOption?
    @Published var loopOrigin:      LoopOrigin?
    @Published var loopSummary:     String?
    @Published var loopError:       String?

    // MARK: - Derived text

    var distanceText: String {
        guard let meters = currentRoute?.resolvedDistanceM else {
            return "—"
        }
        return meters < 1000
            ? String(format: "%.0f m", meters)
            : String(format: "%.1f km", meters / 1000.0)
    }

    var durationText: String? {
        guard let route = currentRoute else { return nil }
        guard let secs = route.resolvedDurationS else { return nil }
        let mins = Int(secs / 60)
        guard mins > 0 else { return nil }
        if mins < 60 { return "~\(mins) min" }
        let h = mins / 60, m = mins % 60
        return m == 0 ? "\(h) hr" : "\(h) hr \(m) min"
    }

    var estimatedStepsText: String? {
        guard let dist = currentRoute?.resolvedDistanceM, dist > 0 else { return nil }
        let steps = Int(dist / 0.762)
        return "~\(steps.formatted()) steps"
    }

    /// Normalized elevation values (0–1) downsampled to ≤60 points for the sparkline.
    var sparklineElevations: [Double]? {
        guard let elevs = currentRoute?.elevation?.elevations, elevs.count >= 4 else { return nil }
        let sampled = downsampleDoubles(elevs, to: 60)
        let mn = sampled.min()!, mx = sampled.max()!
        let range = mx - mn
        guard range > 1.0 else { return nil } // flat — not visually interesting
        return sampled.map { ($0 - mn) / range }
    }

    // MARK: - Actions

    /// Fire route request from a quick-start prompt (correct duration + theme).
    func fetchRoute(for prompt: WalkPrompt, start: CLLocationCoordinate2D) async {
        mode = prompt.mode
        await fetchRoute(start: start, end: nil,
                         duration: prompt.duration,
                         loopTheme: prompt.loopTheme)
    }

    /// Generic fetch — used by manual search.
    func fetchRoute(start: CLLocationCoordinate2D,
                    end: CLLocationCoordinate2D?,
                    duration: Int = 30,
                    loopTheme: String? = nil) async {
        isLoading = true
        toastMessage = nil

        do {
            let route = try await API.shared.fetchRoute(
                start: start,
                end: end,
                mode: mode,
                duration: duration,
                loopTheme: loopTheme
            )
            currentRoute = route
        } catch {
            currentRoute = nil
            showToast(error.localizedDescription, isError: true)
        }

        isLoading = false
    }

    func fetchChainedRoute(start: CLLocationCoordinate2D,
                           stops: [CLLocationCoordinate2D],
                           end: CLLocationCoordinate2D?) async {
        isLoading = true
        toastMessage = nil

        do {
            let closesLoop = mode == "loop"
            let legMode = closesLoop ? "shortest" : mode

            var points = [start]
            points.append(contentsOf: stops)
            if closesLoop {
                points.append(start)
            } else if let end {
                points.append(end)
            }

            guard points.count >= 2 else {
                throw APIError.server("Add at least one stop to build this walk.")
            }

            var legs: [Route] = []
            for index in 0..<(points.count - 1) {
                let route = try await API.shared.fetchRoute(
                    start: points[index],
                    end: points[index + 1],
                    mode: legMode,
                    duration: 30,
                    loopTheme: nil
                )
                legs.append(route)
            }

            guard let combined = Route.combined(from: legs, mode: mode, closesLoop: closesLoop) else {
                throw APIError.server("Could not combine route legs.")
            }

            currentRoute = combined
        } catch {
            currentRoute = nil
            showToast(error.localizedDescription, isError: true)
        }

        isLoading = false
    }

    func clearRoute() {
        currentRoute = nil
    }

    // MARK: - Loop Assistant actions

    /// Calls POST /loop_assistant and populates loopOptions.
    func generateLoops(query: String, userLat: Double?, userLon: Double?) async {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        isLoadingLoops = true
        loopError      = nil
        loopOptions    = []
        loopOrigin     = nil
        loopSummary    = nil
        loopQuery      = query

        do {
            let response = try await API.shared.fetchLoopOptions(
                query: query,
                userLat: userLat,
                userLon: userLon
            )
            loopOptions = response.options
            loopOrigin  = response.origin
            loopSummary = response.assistantSummary
        } catch {
            loopError = error.localizedDescription
        }

        isLoadingLoops = false
    }

    /// Clears all loop assistant state (call when sheet is dismissed or a new query starts).
    func clearLoopAssistant() {
        loopQuery      = ""
        loopOptions    = []
        isLoadingLoops = false
        selectedLoop   = nil
        loopOrigin     = nil
        loopSummary    = nil
        loopError      = nil
    }

    func showToast(_ message: String, isError: Bool = true) {
        toastTask?.cancel()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            toastMessage = message
            toastIsError = isError
        }
        toastTask = Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.25)) { toastMessage = nil }
        }
    }

    // MARK: - Private

    private func downsampleDoubles(_ arr: [Double], to count: Int) -> [Double] {
        guard arr.count > count else { return arr }
        let step = Double(arr.count - 1) / Double(count - 1)
        return (0..<count).map { arr[min(Int(Double($0) * step), arr.count - 1)] }
    }
}
