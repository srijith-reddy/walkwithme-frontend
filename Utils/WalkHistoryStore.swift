import Foundation
import Combine

@MainActor
final class WalkHistoryStore: ObservableObject {
    static let shared = WalkHistoryStore()

    @Published private(set) var routes: [[[Double]]] = []

    private let defaultsKey = "walk_history_routes_v1"
    private let maxStoredRoutes = 40

    private init() {
        load()
    }

    func record(route: Route) {
        let coordinates = route.coordinates
        guard coordinates.count >= 2 else { return }

        if let last = routes.last, Self.matches(lhs: last, rhs: coordinates) {
            return
        }

        routes.append(coordinates)
        if routes.count > maxStoredRoutes {
            routes.removeFirst(routes.count - maxStoredRoutes)
        }
        save()
    }

    func clear() {
        routes.removeAll()
        save()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode([[[Double]]].self, from: data) else { return }
        routes = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(routes) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }

    private static func matches(lhs: [[Double]], rhs: [[Double]]) -> Bool {
        guard lhs.count == rhs.count else { return false }
        guard let a = lhs.first, let b = rhs.first, let c = lhs.last, let d = rhs.last else { return false }
        return close(a, b) && close(c, d)
    }

    private static func close(_ lhs: [Double], _ rhs: [Double]) -> Bool {
        guard lhs.count == 2, rhs.count == 2 else { return false }
        return abs(lhs[0] - rhs[0]) < 0.00001 && abs(lhs[1] - rhs[1]) < 0.00001
    }
}
