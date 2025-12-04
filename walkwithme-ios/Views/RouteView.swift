import SwiftUI
import MapKit
import CoreLocation

struct RouteView: View {
    @StateObject private var navManager = NavigationManager()
    @StateObject private var locationManager = LocationManager.shared

    @State private var startText: String = ""
    @State private var endText: String = ""

    @State private var mapPosition: MapCameraPosition = .automatic
    @State private var showAR: Bool = false

    var body: some View {
        VStack(spacing: 0) {

            // -----------------------------
            // TOP CONTROLS
            // -----------------------------
            VStack(spacing: 8) {

                HStack {
                    Text("Walk With Me")
                        .font(.title2.bold())

                    Spacer()

                    Picker("", selection: $navManager.mode) {
                        Text("Shortest").tag("shortest")
                        Text("Safe").tag("safe")
                        Text("Scenic").tag("scenic")
                        Text("Explore").tag("explore")
                        Text("Elevation").tag("elevation")
                        Text("AI Best").tag("best")
                        Text("Loop").tag("loop")
                    }
                    .pickerStyle(MenuPickerStyle())
                }

                HStack {
                    TextField("Start (lat,lon) — leave blank for GPS",
                              text: $startText)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                        .textFieldStyle(.roundedBorder)
                }

                HStack {
                    TextField("End (lat,lon)",
                              text: $endText)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                        .textFieldStyle(.roundedBorder)
                }

                HStack {

                    Button {
                        Task { await requestRoute() }
                    } label: {
                        HStack {
                            if navManager.isLoading {
                                ProgressView()
                            }
                            Text("Get Route")
                        }
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        showAR = true
                    } label: {
                        Text("AR Nav")
                    }
                    .buttonStyle(.bordered)
                    .disabled(navManager.currentRoute == nil)
                }

                if let error = navManager.errorMessage {
                    Text(error)
                        .foregroundColor(.red)
                        .font(.caption)
                }

                if let route = navManager.currentRoute {
                    HStack {
                        Text(navManager.distanceText)
                        Spacer()
                        Text(route.mode.capitalized)
                        Spacer()
                        if let diff = route.elevation?.difficulty {
                            Text(diff)
                        }
                    }
                    .font(.footnote)
                    .foregroundColor(.secondary)
                }
            }
            .padding()
            .background(.thinMaterial)

            // -----------------------------
            // MAP
            // -----------------------------
            Map(position: $mapPosition) {

                if let route = navManager.currentRoute {

                    MapPolyline(coordinates: route.coordinatePoints)
                        .stroke(.blue, lineWidth: 5)

                    if let first = route.coordinatePoints.first {
                        MapMarker(first, tint: .green)
                    }

                    if let last = route.coordinatePoints.last {
                        MapMarker(last, tint: .red)
                    }
                }

                if let user = locationManager.userLocation {
                    UserAnnotation()
                        .mapOverlay(position: .init(user))
                }
            }
            .mapStyle(.standard)
            .onAppear {
                locationManager.requestPermission()
            }
        }

        // -----------------------------
        // AR SHEET
        // -----------------------------
        .sheet(isPresented: $showAR) {
            if let r = navManager.currentRoute {
                ARScreen(route: r)
                    .ignoresSafeArea()
            }
        }
    }

    // --------------------------------------------------------
    // MARK: - Helpers
    // --------------------------------------------------------
    private func parseCoordinate(from text: String) -> CLLocationCoordinate2D? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let parts = trimmed.split(separator: ",")
        guard parts.count == 2,
              let lat = Double(parts[0]),
              let lon = Double(parts[1]) else { return nil }

        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    private func requestRoute() async {
        guard let startCoord =
                parseCoordinate(from: startText)
                ?? locationManager.userLocation
        else {
            navManager.errorMessage = "Need a valid start location or GPS."
            return
        }

        let endCoord = parseCoordinate(from: endText)

        await navManager.fetchRoute(start: startCoord, end: endCoord)

        if let r = navManager.currentRoute {
            if let first = r.coordinatePoints.first {
                mapPosition = .region(
                    MKCoordinateRegion(
                        center: first,
                        span: MKCoordinateSpan(latitudeDelta: 0.05,
                                               longitudeDelta: 0.05)
                    )
                )
            }
        }
    }
}
