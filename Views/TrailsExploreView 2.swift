// TrailsExploreView.swift
import SwiftUI
import CoreLocation
import MapKit

struct TrailsExploreView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var loc = LocationManager.shared

    let onPickedRoute: (Route) -> Void

    @State private var trails: [Trail] = []
    @State private var isLoading = false
    @State private var error: String?

    @State private var fetchTask: Task<Void, Never>?

    var body: some View {
        NavigationView {
            Group {
                if isLoading {
                    ProgressView("Finding nearby trails…")
                        .padding()
                } else if let error {
                    VStack(spacing: 12) {
                        Text(error).multilineTextAlignment(.center)
                        Button("Retry") { loadTrails() }
                    }
                    .padding()
                } else if trails.isEmpty {
                    VStack(spacing: 12) {
                        Text("No trails found nearby.")
                        Button("Reload") { loadTrails() }
                    }
                    .padding()
                } else {
                    List(trails) { trail in
                        TrailCard(trail: trail) {
                            startTrail(trail)
                        }
                        .listRowSeparator(.hidden)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Nearby Trails")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .onAppear {
            loc.start()
            loadTrails()
        }
        .onDisappear {
            fetchTask?.cancel()
            fetchTask = nil
        }
    }

    private func loadTrails() {
        fetchTask?.cancel()
        isLoading = true
        error = nil

        guard let user = loc.userLocation else {
            isLoading = false
            error = "Waiting for your location…"
            return
        }

        fetchTask = Task {
            do {
                // Radius increased from 3000 (3 km) to 12000 (12 km)
                let ts = try await API.shared.fetchTrails(start: user, radius: 12000, limit: 10)
                if Task.isCancelled { return }
                await MainActor.run {
                    self.trails = ts
                    self.isLoading = false
                }
            } catch {
                if Task.isCancelled { return }
                await MainActor.run {
                    self.error = error.localizedDescription
                    self.isLoading = false
                }
            }
        }
    }

    private func startTrail(_ trail: Trail) {
        guard let user = loc.userLocation else {
            self.error = "Need your location to start."
            return
        }

        Task {
            do {
                let route = try await API.shared.fetchTrailRoute(start: user, end: trail.centerCoordinate)
                await MainActor.run {
                    onPickedRoute(route)
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                }
            }
        }
    }
}

private struct TrailCard: View {
    let trail: Trail
    let onStart: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Mini map preview using the trail's preview polyline
            if !trail.previewPoints.isEmpty {
                MiniMapView(routeCoords: trail.previewPoints)
                    .frame(height: 160)
            }

            Text(trail.name)
                .font(.headline)

            HStack(spacing: 8) {
                if let m = metersString(trail.lengthM) {
                    Label(m, systemImage: "ruler")
                }
                if let mins = trail.estTimeMin {
                    Label("\(mins) min", systemImage: "clock")
                }
                Label(trail.difficultyLevel, systemImage: "figure.walk")
                if let dist = trail.distanceFromUserM {
                    Label(distanceString(dist), systemImage: "location")
                }
            }
            .font(.caption)
            .foregroundColor(.secondary)

            HStack {
                if let surf = trail.surface, !surf.isEmpty {
                    Chip(text: surf.capitalized)
                }
                if let use = trail.use, !use.isEmpty {
                    Chip(text: use.capitalized)
                }
            }

            Button(action: onStart) {
                HStack {
                    Image(systemName: "map")
                    Text("Start")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.vertical, 8)
    }

    private func metersString(_ meters: Double) -> String? {
        if meters <= 0 { return nil }
        if meters < 1000 { return String(format: "%.0f m", meters) }
        return String(format: "%.1f km", meters / 1000.0)
    }

    private func distanceString(_ meters: Double) -> String {
        if meters < 1000 { return String(format: "%.0f m away", meters) }
        return String(format: "%.1f km away", meters / 1000.0)
    }
}

private struct Chip: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.caption2)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.secondary.opacity(0.15))
            .clipShape(Capsule())
    }
}
