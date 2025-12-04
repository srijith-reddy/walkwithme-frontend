import SwiftUI
import UniformTypeIdentifiers
import MapKit
import CoreLocation

struct RouteView: View {
    @StateObject private var navManager = NavigationManager()
    @StateObject private var locationManager = LocationManager.shared

    @State private var startText: String = ""
    @State private var endText: String = ""

    @State private var mapPosition: MapCameraPosition = .automatic
    @State private var showAR: Bool = false
    @State private var showMapNav: Bool = false

    // Autocomplete
    private enum ActiveField { case none, start, end }
    @State private var activeField: ActiveField = .none
    @State private var suggestions: [PlaceSuggestion] = []
    @State private var poiResults: [PlaceSearchResult] = []
    @State private var isFetchingSuggestions = false
    @State private var suggestionError: String?
    @State private var autocompleteTask: Task<Void, Never>?

    // GPX import
    @State private var showGPXPicker = false
    @State private var isImportingGPX = false
    @State private var gpxImportError: String?

    // Steps
    @ObservedObject private var steps = StepCountManager.shared

    private var hasSuggestionContent: Bool {
        !poiResults.isEmpty || !suggestions.isEmpty
    }

    // Prevent Apple Maps sheet for loop mode
    private var showMapNavBinding: Binding<Bool> {
        Binding(
            get: {
                guard let r = navManager.currentRoute else { return false }
                let mode = r.mode.lowercased()
                if mode.contains("loop") { return false }
                return showMapNav
            },
            set: { newVal in
                guard let r = navManager.currentRoute else {
                    showMapNav = false
                    return
                }
                let mode = r.mode.lowercased()
                showMapNav = mode.contains("loop") ? false : newVal
            }
        )
    }

    var body: some View {
        VStack(spacing: 0) {

            // -----------------------------------------------------
            // HEADER + INPUTS
            // -----------------------------------------------------
            VStack(spacing: 8) {

                // Steps
                HStack(spacing: 10) {
                    Image(systemName: "shoeprints.fill").foregroundColor(.purple)
                    Text("\(steps.todaySteps) today").monospacedDigit()
                    if steps.sessionSteps > 0 {
                        Divider().frame(height: 14)
                        Text("\(steps.sessionSteps) session").monospacedDigit()
                    }
                    Spacer()
                }
                .font(.footnote)
                .foregroundColor(.secondary)
                .padding(8)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 8))

                // ------------------
                // START FIELD
                // ------------------
                VStack(spacing: 4) {
                    TextField("Start (lat,lon) — blank = GPS",
                              text: $startText,
                              onEditingChanged: { editing in
                                  activeField = editing ? .start : .none
                                  if !editing { clearSuggestions() }
                              })
                        .textFieldStyle(.roundedBorder)
                        .disableAutocorrection(true)
                        .textInputAutocapitalization(.never)
                        .onChange(of: startText) { _ in
                            if activeField == .start {
                                triggerAutocomplete(with: startText)
                            }
                        }

                    if activeField == .start, isFetchingSuggestions {
                        tinyLoadingRow
                    }

                    if activeField == .start, hasSuggestionContent {
                        suggestionsList()
                            .frame(minHeight: 220, maxHeight: 420)
                            .transition(.opacity)
                            .zIndex(10)
                    }
                }

                // ------------------
                // END FIELD
                // ------------------
                VStack(spacing: 4) {
                    TextField("End (lat,lon)",
                              text: $endText,
                              onEditingChanged: { editing in
                                  activeField = editing ? .end : .none
                                  if !editing { clearSuggestions() }
                              })
                        .textFieldStyle(.roundedBorder)
                        .disableAutocorrection(true)
                        .textInputAutocapitalization(.never)
                        .onChange(of: endText) { _ in
                            if activeField == .end {
                                triggerAutocomplete(with: endText)
                            }
                        }

                    if activeField == .end, isFetchingSuggestions {
                        tinyLoadingRow
                    }

                    if activeField == .end, hasSuggestionContent {
                        suggestionsList()
                            .frame(minHeight: 220, maxHeight: 420)
                            .transition(.opacity)
                            .zIndex(10)
                    }
                }

                // ------------------
                // MODE PICKER
                // ------------------
                HStack {
                    Text("Mode").foregroundColor(.secondary)
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

                // ------------------
                // BUTTONS
                // ------------------
                HStack(spacing: 8) {

                    Button {
                        Task { await requestRoute() }
                    } label: {
                        HStack {
                            if navManager.isLoading { ProgressView() }
                            Text("Get Route")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .allowsHitTesting(activeField == .none)
                    .opacity(activeField == .none ? 1 : 0.3)

                    Button {
                        showAR = true
                    } label: {
                        Text("AR Nav")
                    }
                    .buttonStyle(.bordered)
                    .disabled(navManager.currentRoute == nil)
                    .allowsHitTesting(activeField == .none)
                    .opacity(activeField == .none ? 1 : 0.3)

                    Button {
                        showGPXPicker = true
                    } label: {
                        HStack {
                            if isImportingGPX { ProgressView().scaleEffect(0.8) }
                            Text("Import GPX")
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(isImportingGPX)
                }

                // Errors
                if let err = navManager.errorMessage {
                    Text(err).foregroundColor(.red).font(.caption)
                }
                if let err = gpxImportError {
                    Text(err).foregroundColor(.red).font(.caption)
                }

                // Route summary
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

            // -----------------------------------------------------
            // MAP VIEW
            // -----------------------------------------------------
            Map(position: $mapPosition) {

                if let route = navManager.currentRoute {
                    MapPolyline(coordinates: route.coordinatePoints)
                        .stroke(.blue, lineWidth: 5)

                    if let s = route.coordinatePoints.first {
                        Marker("Start", coordinate: s).tint(.green)
                    }
                    if let e = route.coordinatePoints.last {
                        Marker("End", coordinate: e).tint(.red)
                    }
                }

                if let user = locationManager.userLocation {
                    Annotation("You", coordinate: user) {
                        ZStack {
                            Circle().fill(Color.blue.opacity(0.3)).frame(width: 24, height: 24)
                            Circle().fill(Color.blue).frame(width: 12, height: 12)
                        }
                    }
                }
            }
            .mapStyle(.standard)
            .onAppear {
                locationManager.start()
            }
        }

        // -----------------------------------------------------
        // SHEETS
        // -----------------------------------------------------

        // AR
        .sheet(isPresented: $showAR) {
            if let r = navManager.currentRoute {
                ARScreen(route: r).ignoresSafeArea()
            }
        }

        // MAP NAV
        .sheet(isPresented: showMapNavBinding) {
            if let dest = navManager.currentRoute?.destinationItem {
                SimpleNavigationView(destination: dest).ignoresSafeArea()
            }
        }

        // GPX IMPORT
        .sheet(isPresented: $showGPXPicker) {
            DocumentPickerView(
                allowedContentTypes: ["public.xml", "com.topografix.gpx"]
            ) { url in
                guard let url else { return }
                Task { await importGPX(from: url) }
            }
        }
    }

    // -----------------------------------------------------
    // Autocomplete UI
    // -----------------------------------------------------
    private var tinyLoadingRow: some View {
        HStack(spacing: 6) {
            ProgressView().scaleEffect(0.8)
            Text("Searching…").font(.caption).foregroundColor(.secondary)
            Spacer()
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func suggestionsList() -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {

                if !poiResults.isEmpty {
                    ForEach(Array(poiResults.prefix(8))) { r in
                        Button { selectPlaceResult(r) } label: {
                            poiRow(r)
                        }
                        Divider()
                    }
                } else {
                    ForEach(Array(suggestions.prefix(8))) { s in
                        Button { selectSuggestion(s) } label: {
                            suggestionRow(s)
                        }
                        Divider()
                    }
                }
            }
            .padding(.horizontal, 10)
        }
        .scrollIndicators(.hidden)
        .frame(minHeight: 220, maxHeight: 420)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.18), radius: 12, x: 0, y: 6)
    }

    private func poiRow(_ r: PlaceSearchResult) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(r.name).foregroundColor(.primary).lineLimit(2)

                HStack(spacing: 6) {
                    if let rating = r.rating {
                        Image(systemName: "star.fill").foregroundColor(.yellow)
                        Text(String(format: "%.1f", rating))
                            .font(.caption).foregroundColor(.secondary)
                    }
                    if let reviews = r.reviews {
                        Text("(\(reviews))").font(.caption).foregroundColor(.secondary)
                    }
                    if let open = r.openNow {
                        Text(open ? "Open" : "Closed")
                            .font(.caption)
                            .foregroundColor(open ? .green : .red)
                    }
                    if let dist = r.distanceKm {
                        Text(String(format: "%.1f km", dist))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                if let addr = r.address {
                    Text(addr).font(.caption2).foregroundColor(.secondary).lineLimit(1)
                }
            }
            Spacer()
            Text(String(format: "%.5f,%.5f", r.lat, r.lon))
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 8)
    }

    private func suggestionRow(_ s: PlaceSuggestion) -> some View {
        HStack {
            Text(s.label).foregroundColor(.primary).lineLimit(2)
            Spacer()
            Text(String(format: "%.5f,%.5f", s.lat, s.lon))
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 8)
    }

    private func selectPlaceResult(_ r: PlaceSearchResult) {
        let latlon = String(format: "%.6f,%.6f", r.lat, r.lon)
        if activeField == .start { startText = latlon }
        else if activeField == .end { endText = latlon }
        clearSuggestions()
    }

    private func selectSuggestion(_ s: PlaceSuggestion) {
        let latlon = String(format: "%.6f,%.6f", s.lat, s.lon)
        if activeField == .start { startText = latlon }
        else if activeField == .end { endText = latlon }
        clearSuggestions()
    }

    private func clearSuggestions() {
        suggestions.removeAll()
        poiResults.removeAll()
        isFetchingSuggestions = false
        suggestionError = nil
        autocompleteTask?.cancel()
        autocompleteTask = nil
        activeField = .none
    }

    private func isPOIQuery(_ text: String) -> Bool {
        let q = text.lowercased()
        let poiKeywords = [
            "cafe","coffee","restaurant","food","pizza","thai","gym",
            "park","museum","mall","atm","hotel","bar","burger","boba",
            "tea","pharmacy","clinic","movie","cinema","theatre","store","shop"
        ]
        if q.contains("near me") || q.contains("nearby") { return true }
        if poiKeywords.contains(where: { q.contains($0) }) { return true }
        let hasDigit = q.contains { $0.isNumber }
        let words = q.split(separator: " ").count
        return !hasDigit && words >= 2
    }

    private func triggerAutocomplete(with text: String) {
        autocompleteTask?.cancel()

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            clearSuggestions()
            return
        }

        isFetchingSuggestions = true
        suggestionError = nil

        let userLat = locationManager.userLocation?.latitude
        let userLon = locationManager.userLocation?.longitude

        autocompleteTask = Task {
            try? await Task.sleep(nanoseconds: 250_000_000)

            do {
                if isPOIQuery(trimmed) {
                    let results = try await API.shared.fetchPlacesSearch(
                        q: trimmed, userLat: userLat, userLon: userLon
                    )
                    if Task.isCancelled { return }
                    await MainActor.run {
                        poiResults = results
                        suggestions = []
                        isFetchingSuggestions = false
                        suggestionError = results.isEmpty ? "No matches" : nil
                    }
                } else {
                    let results = try await API.shared.fetchAutocomplete(
                        q: trimmed, userLat: userLat, userLon: userLon, limit: 7
                    )
                    if Task.isCancelled { return }
                    await MainActor.run {
                        suggestions = results
                        poiResults = []
                        isFetchingSuggestions = false
                        suggestionError = results.isEmpty ? "No matches" : nil
                    }
                }
            } catch {
                if Task.isCancelled { return }
                await MainActor.run {
                    suggestions = []
                    poiResults = []
                    isFetchingSuggestions = false
                    suggestionError = error.localizedDescription
                }
            }
        }
    }

    // -----------------------------------------------------
    // ROUTING
    // -----------------------------------------------------
    private func parseCoordinate(from text: String) -> CLLocationCoordinate2D? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        let parts = trimmed.split(separator: ",")
        guard parts.count == 2,
              let lat = Double(parts[0]),
              let lon = Double(parts[1]) else { return nil }

        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    private func distanceMeters(_ a: CLLocationCoordinate2D,
                                _ b: CLLocationCoordinate2D) -> CLLocationDistance {
        CLLocation(latitude: a.latitude, longitude: a.longitude)
            .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
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
            centerMapOnRoute(r)

            let mode = r.mode.lowercased()
            if mode.contains("loop") {
                showMapNav = false
            } else if let user = locationManager.userLocation,
                      let first = r.coordinatePoints.first {
                let d = distanceMeters(user, first)
                showMapNav = (d <= 50_000) && (r.destinationItem != nil)
            } else {
                showMapNav = false
            }
        } else {
            showMapNav = false
        }
    }

    private func centerMapOnRoute(_ r: Route) {
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

    // -----------------------------------------------------
    // GPX IMPORT
    // -----------------------------------------------------
    private func importGPX(from url: URL) async {
        isImportingGPX = true
        gpxImportError = nil
        defer { isImportingGPX = false }

        let needsAccess = url.startAccessingSecurityScopedResource()
        defer { if needsAccess { url.stopAccessingSecurityScopedResource() } }

        do {
            let resp = try await API.shared.importGPX(fileURL: url)
            let route = makeRoute(from: resp)
            await MainActor.run {
                navManager.currentRoute = route
                centerMapOnRoute(route)
            }
        } catch {
            await MainActor.run {
                gpxImportError = "Import failed: \(error.localizedDescription)"
            }
        }
    }

    private func makeRoute(from gpx: API.ImportGPXResponse) -> Route {
        let coords = gpx.coordinates
        let pts = coords.compactMap { c -> CLLocationCoordinate2D? in
            guard c.count == 2 else { return nil }
            return .init(latitude: c[0], longitude: c[1])
        }

        var total: CLLocationDistance = 0
        for i in 1..<pts.count {
            total += distanceMeters(pts[i - 1], pts[i])
        }

        return Route(
            mode: "gpx",
            coordinates: coords,
            waypoints: nil,
            distanceM: total,
            durationS: nil,
            summary: nil,
            steps: nil,
            elevation: gpx.elevation,
            safetyScore: nil,
            scenicScore: nil,
            aiBestScore: nil,
            nextTurn: nil
        )
    }
}

// -----------------------------------------------------
// DOCUMENT PICKER
// -----------------------------------------------------
private struct DocumentPickerView: UIViewControllerRepresentable {
    let allowedContentTypes: [String]
    let completion: (URL?) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let types: [UTType] = allowedContentTypes.compactMap {
            UTType($0) ?? UTType(filenameExtension: $0)
        }
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types)
        picker.allowsMultipleSelection = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(
        _ uiViewController: UIDocumentPickerViewController,
        context: Context
    ) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(completion: completion)
    }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let completion: (URL?) -> Void
        init(completion: @escaping (URL?) -> Void) {
            self.completion = completion
        }
        func documentPicker(
            _ controller: UIDocumentPickerViewController,
            didPickDocumentsAt urls: [URL]
        ) {
            completion(urls.first)
        }
        func documentPickerWasCancelled(
            _ controller: UIDocumentPickerViewController
        ) {
            completion(nil)
        }
    }
}
