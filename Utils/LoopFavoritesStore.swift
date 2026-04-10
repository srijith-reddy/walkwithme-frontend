import Foundation
import Combine

// MARK: - SavedLoop

/// Codable snapshot of a LoopOption + its origin, stored in UserDefaults.
struct SavedLoop: Codable, Identifiable {
    let id: String
    let savedAt: Date
    let title: String
    let subtitle: String
    let theme: String
    let durationMin: Int
    let distanceMiles: Double
    let whyThis: String?
    let highlights: [String]
    let suggestedStops: [String]
    let originLabel: String
    let originLat: Double
    let originLon: Double

    // Convenience reconstructors for navigation
    var asLoopOption: LoopOption {
        LoopOption(
            id: id,
            title: title,
            subtitle: subtitle,
            theme: theme,
            durationMin: durationMin,
            distanceMiles: distanceMiles,
            whyThis: whyThis,
            highlights: highlights,
            suggestedStops: suggestedStops
        )
    }

    var asLoopOrigin: LoopOrigin {
        LoopOrigin(label: originLabel, lat: originLat, lon: originLon)
    }

    var durationText: String {
        durationMin < 60
            ? "\(durationMin) min"
            : "\(durationMin / 60) hr\(durationMin % 60 > 0 ? " \(durationMin % 60) min" : "")"
    }
}

// MARK: - LoopFavoritesStore

@MainActor
final class LoopFavoritesStore: ObservableObject {
    static let shared = LoopFavoritesStore()

    @Published private(set) var savedLoops: [SavedLoop] = []

    private let defaultsKey = "loop_favorites_v1"

    private init() { load() }

    func save(_ option: LoopOption, origin: LoopOrigin) {
        guard !isSaved(id: option.id) else { return }
        let entry = SavedLoop(
            id: option.id,
            savedAt: Date(),
            title: option.title,
            subtitle: option.subtitle,
            theme: option.theme,
            durationMin: option.durationMin,
            distanceMiles: option.distanceMiles,
            whyThis: option.whyThis,
            highlights: option.highlights,
            suggestedStops: option.suggestedStops,
            originLabel: origin.label,
            originLat: origin.lat,
            originLon: origin.lon
        )
        savedLoops.insert(entry, at: 0)
        persist()
    }

    func remove(id: String) {
        savedLoops.removeAll { $0.id == id }
        persist()
    }

    func isSaved(id: String) -> Bool {
        savedLoops.contains { $0.id == id }
    }

    // MARK: - Persistence

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode([SavedLoop].self, from: data) else { return }
        savedLoops = decoded
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(savedLoops) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }
}
