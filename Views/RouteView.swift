import SwiftUI
import UniformTypeIdentifiers
import MapKit
import CoreLocation
import UIKit

// MARK: - Route Mode chips

private struct RouteMode: Identifiable {
    let id: String; let label: String; let icon: String
}

private struct RouteStopDraft: Identifiable {
    let id = UUID()
    var label: String = ""
    var coordinate: CLLocationCoordinate2D?
}

private struct RouteStopMarker: Identifiable {
    let id: UUID
    let index: Int
    let coordinate: CLLocationCoordinate2D
}

private struct ResolvedRouteLocation {
    let label: String
    let coordinate: CLLocationCoordinate2D
}

private let routeModes: [RouteMode] = [
    .init(id: "loop",      label: "Loop",    icon: "arrow.triangle.2.circlepath"),
    .init(id: "scenic",    label: "Scenic",  icon: "leaf"),
    .init(id: "explore",   label: "Explore", icon: "sparkles"),
    .init(id: "best",      label: "AI Best", icon: "wand.and.stars"),
    .init(id: "safe",      label: "Safe",    icon: "checkmark.shield"),
    .init(id: "shortest",  label: "Fastest", icon: "bolt"),
    .init(id: "elevation", label: "Hilly",   icon: "mountain.2"),
]

// MARK: - RouteView

struct RouteView: View {
    @StateObject private var vm              = RouteViewModel()
    @StateObject private var locationManager = LocationManager.shared

    // Search fields
    @State private var startText       = ""
    @State private var endText         = ""
    @State private var startCoordinate: CLLocationCoordinate2D?
    @State private var endCoordinate:   CLLocationCoordinate2D?
    @State private var stops: [RouteStopDraft] = []

    // Map
    @State private var mapPosition:    MapCameraPosition = .automatic
    @State private var useSatellite    = false
    @State private var droppedPin:     CLLocationCoordinate2D?
    @State private var droppedPinLabel = ""
    @State private var isReverseGeocoding = false

    // Polyline draw-on
    @State private var polylineProgress: Double = 0
    @State private var lastRouteID: UUID?

    // Sheets / covers
    @State private var showAR          = false
    @State private var showMapNav      = false
    @State private var showGPXPicker   = false
    @State private var showStepsSheet  = false
    @State private var showPersonaSheet = false
    @State private var showNearbySheet = false
    @State private var showThemesSheet = false
    @State private var showThemeDetailSheet = false
    @State private var showDetoursSheet = false
    @State private var showWalkCoverageSheet = false
    @State private var showExportShareSheet = false
    @State private var isImportingGPX  = false
    @State private var isLoadingPersona = false
    @State private var isLoadingNearby = false
    @State private var isLoadingThemes = false
    @State private var isLoadingThemeDetail = false
    @State private var isLoadingDetours = false
    @State private var isAnalyzingWalks = false
    @State private var isExportingGPX = false
    @State private var gpxImportError: String?
    @State private var persona: WalkPersona?
    @State private var nearbyPlaces: [NearbyPlace] = []
    @State private var nearbyCategory = "all"
    @State private var themes: [WalkTheme] = []
    @State private var selectedThemeDetail: WalkTheme?
    @State private var detoursResponse: DetoursResponse?
    @State private var walkAnalysis: WalkAnalysisResponse?
    @State private var exportedGPXURL: URL?
    @State private var fallbackComingUpPlaces: [EnrichedPlace] = []
    @State private var isLoadingComingUpPlaces = false

    // Route card dismiss gesture
    @State private var cardDragOffset: CGFloat = 0
    @State private var isRouteCardCollapsed = false

    // Loop Assistant
    @State private var showLoopAssistant = false

    // Autocomplete
    private enum ActiveField: Equatable { case none, start, stop(UUID), end }
    @State private var activeField: ActiveField = .none
    @State private var suggestions:  [PlaceSuggestion]   = []
    @State private var poiResults:   [PlaceSearchResult] = []
    @State private var isFetchingSuggestions = false
    @State private var autocompleteTask: Task<Void, Never>?

    @ObservedObject private var steps = StepCountManager.shared
    @ObservedObject private var walkHistory = WalkHistoryStore.shared

    // MARK: body

    var body: some View {
        ZStack(alignment: .top) {

            // ── 1. MAP ────────────────────────────────────────────────────
            mapLayer.ignoresSafeArea()

            // ── 2. MAP CONTROLS (satellite toggle, top-right) ─────────────
            if activeField == .none {
                VStack {
                    HStack {
                        Spacer()
                        VStack(spacing: 8) {
                            mapStyleToggle
                            stepsPill
                            utilitiesMenu
                        }
                        .padding(.top, 56)
                        .padding(.trailing, 16)
                    }
                    Spacer()
                }
                .transition(.opacity)
            }

            // ── 3. SEARCH PANEL (top) ─────────────────────────────────────
            VStack(spacing: 0) {
                searchPanel
                    .padding(.horizontal, 16)
                    .padding(.top, 56)

                if activeField != .none, isFetchingSuggestions {
                    searchLoadingPill
                        .padding(.horizontal, 16)
                        .padding(.top, 6)
                }
                if activeField != .none, hasSuggestionContent {
                    suggestionDropdown
                        .padding(.horizontal, 16)
                        .padding(.top, 4)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                        .zIndex(20)
                }

                Spacer()
            }
            .animation(.easeInOut(duration: 0.18), value: activeField == .none)
            .animation(.easeInOut(duration: 0.18), value: hasSuggestionContent)
            .animation(.easeInOut(duration: 0.22), value: vm.currentRoute == nil && !vm.isLoading)

            // ── 4. BOTTOM PANEL ───────────────────────────────────────────
            VStack {
                Spacer()
                bottomPanel
                    .padding(.horizontal, 16)
                    .padding(.bottom, 34)
                    .offset(y: cardDragOffset)
            }
            .animation(.spring(response: 0.38, dampingFraction: 0.82), value: vm.isLoading)
            .animation(.spring(response: 0.38, dampingFraction: 0.82), value: vm.currentRoute != nil)

            // ── 5. ERROR TOAST ────────────────────────────────────────────
            if let msg = vm.toastMessage {
                VStack {
                    toastView(msg, isError: vm.toastIsError)
                        .padding(.horizontal, 20)
                        .padding(.top, 120)
                    Spacer()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(50)
                .animation(.spring(response: 0.3, dampingFraction: 0.8), value: vm.toastMessage != nil)
            }
        }
        .ignoresSafeArea(edges: .bottom)
        .onChange(of: vm.currentRoute) { _, route in
            handleRouteChange(route)
        }
        // AR as fullScreenCover for the cinematic feel
        .fullScreenCover(isPresented: $showAR) {
            if let r = vm.currentRoute {
                ARScreen(route: r)
            }
        }
        .sheet(isPresented: $showStepsSheet) {
            if let route = vm.currentRoute, let steps = route.steps, !steps.isEmpty {
                StepsPreviewSheet(steps: steps)
            }
        }
        .sheet(isPresented: $showPersonaSheet) {
            PersonaSheet(persona: persona, isLoading: isLoadingPersona)
        }
        .sheet(isPresented: $showNearbySheet) {
            NearbyPlacesSheet(
                places: nearbyPlaces,
                category: nearbyCategory,
                isLoading: isLoadingNearby
            ) { category in
                Task { await loadNearby(category: category, presentSheet: false) }
            }
        }
        .sheet(isPresented: $showThemesSheet) {
            ThemesSheet(
                themes: themes,
                isLoading: isLoadingThemes
            ) { theme in
                Task { await loadThemeDetail(themeID: theme.id) }
            }
        }
        .sheet(isPresented: $showThemeDetailSheet) {
            ThemeDetailSheet(
                theme: selectedThemeDetail,
                isLoading: isLoadingThemeDetail
            ) { theme in
                applyTheme(theme)
            }
        }
        .sheet(isPresented: $showDetoursSheet) {
            DetoursSheet(
                detoursResponse: detoursResponse,
                isLoading: isLoadingDetours
            ) { detour in
                showDetoursSheet = false
                Task { await addDetourAsStop(detour) }
            }
        }
        .sheet(isPresented: $showWalkCoverageSheet) {
            WalkCoverageSheet(
                analysis: walkAnalysis,
                routeCount: walkHistory.routes.count,
                isLoading: isAnalyzingWalks
            )
        }
        .sheet(isPresented: $showLoopAssistant) {
            LoopAssistantSheet(
                vm: vm,
                userLocation: locationManager.userLocation
            ) { option, origin in
                showLoopAssistant = false
                applyLoopSelection(option: option, origin: origin)
            }
        }
        .sheet(isPresented: $showExportShareSheet, onDismiss: { exportedGPXURL = nil }) {
            if let url = exportedGPXURL {
                ActivityView(activityItems: [url])
                    .ignoresSafeArea()
            }
        }
        .fullScreenCover(isPresented: $showMapNav) {
            if let route = vm.currentRoute {
                SimpleNavigationView(route: route, stopCoordinates: stopMarkers.map(\.coordinate))
                    .ignoresSafeArea()
            }
        }
        .sheet(isPresented: $showGPXPicker) {
            DocumentPickerView(allowedContentTypes: ["public.xml", "com.topografix.gpx"]) { url in
                guard let url else { return }
                Task { await importGPX(from: url) }
            }
        }
        .onAppear {
            locationManager.start()
            Task { await refreshPersonaIfNeeded(force: false) }
        }
        .onChange(of: locationManager.userLocation.map { "\($0.latitude),\($0.longitude)" }) { _, _ in
            Task { await refreshPersonaIfNeeded(force: false) }
        }
    }

    // MARK: - Map Layer

    private var mapLayer: some View {
        MapReader { proxy in
            Map(position: $mapPosition) {
                // Route polyline (animated draw-on via sliced coordinate array)
                if let route = vm.currentRoute {
                    let allCoords = route.coordinatePoints
                    let visibleCount = max(2, Int(Double(allCoords.count) * polylineProgress))
                    let visibleCoords = Array(allCoords.prefix(visibleCount))

                    MapPolyline(coordinates: visibleCoords)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.08, green: 0.55, blue: 1.0),
                                    Color(red: 0.35, green: 0.20, blue: 0.95),
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round)
                        )

                    if let s = allCoords.first {
                        Annotation("", coordinate: s) { startPin }
                    }
                    ForEach(stopMarkers) { marker in
                        Annotation("", coordinate: marker.coordinate) {
                            stopPin(number: marker.index + 1)
                        }
                    }
                    if let e = allCoords.last {
                        if route.mode.lowercased() != "loop" {
                            Annotation("", coordinate: e) { endPin }
                        }
                    }
                }

                // Dropped pin from long-press
                if let pin = droppedPin {
                    Annotation("", coordinate: pin) { droppedPinView }
                }

                // User location
                if let user = locationManager.userLocation {
                    Annotation("", coordinate: user) { PulsingUserDot() }
                }
            }
            .mapStyle(
                useSatellite
                    ? .hybrid(elevation: .realistic)
                    : .standard(elevation: .realistic,
                                pointsOfInterest: .including([.cafe, .restaurant, .bakery, .park, .museum]))
            )
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.55)
                    .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .local))
                    .onEnded { value in
                        if case .second(true, let drag?) = value,
                           let coord = proxy.convert(drag.location, from: .local) {
                            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                            dropPin(at: coord)
                        }
                    }
            )
        }
    }

    // MARK: - Map Annotations

    private var startPin: some View {
        ZStack {
            Circle().fill(.white).frame(width: 26, height: 26)
                .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
            Circle().fill(Color(red: 0.08, green: 0.78, blue: 0.42)).frame(width: 16, height: 16)
        }
    }

    private var endPin: some View {
        ZStack {
            Circle().fill(.white).frame(width: 26, height: 26)
                .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
            Image(systemName: "flag.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color(red: 0.95, green: 0.28, blue: 0.18))
        }
    }

    private var droppedPinView: some View {
        VStack(spacing: 0) {
            ZStack {
                Circle()
                    .fill(Color(red: 0.45, green: 0.2, blue: 0.95))
                    .frame(width: 30, height: 30)
                    .shadow(color: .black.opacity(0.22), radius: 5, y: 2)
                Image(systemName: "mappin")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
            }
            Triangle()
                .fill(Color(red: 0.45, green: 0.2, blue: 0.95))
                .frame(width: 10, height: 6)
                .offset(y: -1)
        }
    }

    // MARK: - Map Controls

    private var mapStyleToggle: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { useSatellite.toggle() }
        } label: {
            Image(systemName: useSatellite ? "map.fill" : "globe.americas.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 38, height: 38)
                .background(.regularMaterial, in: Circle())
                .shadow(color: .black.opacity(0.1), radius: 6, y: 2)
        }
    }

    private var stepsPill: some View {
        HStack(spacing: 5) {
            Image(systemName: "shoeprints.fill")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.purple)
            Text("\(steps.todaySteps)")
                .font(.system(size: 12, weight: .semibold))
                .monospacedDigit()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
    }

    private var utilitiesMenu: some View {
        Menu {
            Button {
                showLoopAssistant = true
            } label: {
                Label("Loop Assistant", systemImage: "wand.and.sparkles")
            }

            Divider()

            Button {
                Task { await presentPersonaSheet() }
            } label: {
                Label("Walk Persona", systemImage: "sparkles")
            }

            Button {
                Task { await loadNearby(category: "all") }
            } label: {
                Label("Nearby Places", systemImage: "mappin.and.ellipse")
            }

            Button {
                Task { await loadNearby(category: "food") }
            } label: {
                Label("Nearby Food", systemImage: "fork.knife")
            }

            Button {
                Task { await loadNearby(category: "landmark") }
            } label: {
                Label("Nearby Landmarks", systemImage: "building.columns")
            }

            Button {
                Task { await loadNearby(category: "park") }
            } label: {
                Label("Nearby Parks", systemImage: "leaf")
            }

            Divider()

            Button {
                Task { await loadThemes() }
            } label: {
                Label("Walk Themes", systemImage: "square.grid.2x2")
            }

            Button {
                Task { await analyzeWalkCoverage() }
            } label: {
                Label("City Coverage", systemImage: "point.3.connected.trianglepath.dotted")
            }
        } label: {
            Image(systemName: "ellipsis.circle.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 38, height: 38)
                .background(.regularMaterial, in: Circle())
                .shadow(color: .black.opacity(0.1), radius: 6, y: 2)
        }
    }

    // MARK: - Search Panel

    private var searchPanel: some View {
        VStack(spacing: 0) {
            routeBuilderCard

            modeChips.padding(.top, 10)

            if let persona {
                personaStrip(persona)
                    .padding(.top, 10)
            }
        }
    }

    private var routeBuilderCard: some View {
        VStack(spacing: 0) {
            routeInputRow(
                placeholder: "From — or use your location",
                text: $startText,
                field: .start,
                icon: "circle.fill",
                iconColor: Color(red: 0.08, green: 0.78, blue: 0.42)
            )

            if !stops.isEmpty || vm.mode == "loop" {
                ForEach(Array(stops.enumerated()), id: \.element.id) { index, stop in
                    routeRowDivider
                    stopInputRow(stop, index: index)
                }
            }

            routeRowDivider
            if vm.mode == "loop" {
                loopReturnRow
            } else {
                routeInputRow(
                    placeholder: "Where to?",
                    text: $endText,
                    field: .end,
                    icon: "flag.fill",
                    iconColor: Color(red: 0.95, green: 0.28, blue: 0.18)
                )
            }

            routeRowDivider
            stopActionRow
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.11), radius: 18, y: 4)
    }

    private var routeRowDivider: some View {
        Rectangle().fill(Color.primary.opacity(0.07))
            .frame(height: 0.5)
            .padding(.horizontal, 14)
    }

    @ViewBuilder
    private func routeInputRow(
        placeholder: String,
        text: Binding<String>,
        field: ActiveField,
        icon: String,
        iconColor: Color
    ) -> some View {
        let showsCurrentLocationLabel =
            field == .start &&
            text.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            activeField != field &&
            locationManager.userLocation != nil

        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .black))
                .foregroundStyle(iconColor)
                .frame(width: 20)

            ZStack(alignment: .leading) {
                TextField(placeholder, text: text,
                          onEditingChanged: { editing in
                              withAnimation(.easeInOut(duration: 0.15)) {
                                  activeField = editing ? field : .none
                              }
                              if !editing { clearSuggestions() }
                          })
                    .font(.system(size: 16))
                    .disableAutocorrection(true)
                    .textInputAutocapitalization(.never)
                    .opacity(showsCurrentLocationLabel ? 0.02 : 1)
                    .onChange(of: text.wrappedValue) { _, v in
                        if activeField == field {
                            switch field {
                            case .start:
                                startCoordinate = nil
                            case .end:
                                endCoordinate = nil
                            case .none, .stop:
                                break
                            }
                            triggerAutocomplete(with: v)
                        }
                    }

                if showsCurrentLocationLabel {
                    Text("Current location")
                        .font(.system(size: 16))
                        .foregroundStyle(.primary)
                        .allowsHitTesting(false)
                }
            }

            if !text.wrappedValue.isEmpty {
                Button {
                    text.wrappedValue = ""
                    switch field {
                    case .start:
                        startCoordinate = nil
                    case .end:
                        endCoordinate = nil
                    case .none, .stop:
                        break
                    }
                    clearSuggestions()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16)).foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 50)
    }

    private func stopInputRow(_ stop: RouteStopDraft, index: Int) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .stroke(Color.primary.opacity(0.55), lineWidth: 2)
                    .frame(width: 18, height: 18)
                Text("\(index + 1)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.primary.opacity(0.75))
            }
            .frame(width: 20)

            TextField("Add a stop", text: stopTextBinding(for: stop.id),
                      onEditingChanged: { editing in
                          withAnimation(.easeInOut(duration: 0.15)) {
                              activeField = editing ? .stop(stop.id) : .none
                          }
                          if !editing { clearSuggestions() }
                      })
                .font(.system(size: 16))
                .disableAutocorrection(true)
                .textInputAutocapitalization(.never)

            if !(stops.first(where: { $0.id == stop.id })?.label ?? "").isEmpty {
                Button {
                    updateStop(id: stop.id, label: "", coordinate: nil)
                    clearSuggestions()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.tertiary)
                }
            }

            Button {
                removeStop(id: stop.id)
            } label: {
                Image(systemName: "minus.circle.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 50)
    }

    private var loopReturnRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.trianglehead.counterclockwise")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color(red: 0.95, green: 0.28, blue: 0.18))
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text("Returns to start")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(startText.isEmpty ? "Your walk will close back to the starting point." : startText)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 50)
    }

    private var stopActionRow: some View {
        HStack(spacing: 12) {
            Button {
                addEmptyStop()
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                    Text(stops.isEmpty ? "Add stop" : "Add another stop")
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundStyle(.blue)
            }

            Spacer()

            if vm.mode == "loop" {
                Text(stops.isEmpty ? "Pick places to visit" : "\(stops.count) stop\(stops.count == 1 ? "" : "s") in your loop")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            } else if !stops.isEmpty {
                Text("\(stops.count) stop\(stops.count == 1 ? "" : "s") on the way")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    // MARK: - Mode Chips

    private var modeChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                // GPX import
                Button { showGPXPicker = true } label: {
                    HStack(spacing: 5) {
                        if isImportingGPX {
                            ProgressView().scaleEffect(0.65)
                        } else {
                            Image(systemName: "arrow.down.doc.fill")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        Text("GPX").font(.system(size: 13, weight: .semibold))
                    }
                    .padding(.horizontal, 13).padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .foregroundStyle(.secondary)
                }
                .disabled(isImportingGPX)

                ForEach(routeModes) { m in
                    let selected = vm.mode == m.id
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        if vm.mode != m.id {
                            handleModeSwitch(to: m.id)
                        }
                        withAnimation(.spring(response: 0.22, dampingFraction: 0.72)) {
                            vm.mode = m.id
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: m.icon).font(.system(size: 11, weight: .semibold))
                            Text(m.label).font(.system(size: 13, weight: .semibold))
                        }
                        .padding(.horizontal, 13).padding(.vertical, 8)
                        .background(
                            selected ? AnyShapeStyle(Color.primary) : AnyShapeStyle(Material.ultraThinMaterial),
                            in: Capsule()
                        )
                        .foregroundStyle(selected ? Color(UIColor.systemBackground) : .primary)
                    }
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 2)
        }
        .padding(.horizontal, -16)
    }

    private func personaStrip(_ persona: WalkPersona) -> some View {
        Button {
            showPersonaSheet = true
        } label: {
            HStack(spacing: 9) {
                Text(persona.emoji)
                    .font(.system(size: 16))

                VStack(alignment: .leading, spacing: 2) {
                    Text(persona.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(persona.tagline)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                if let routingBias = persona.routingBias {
                    Text(routingBias.capitalized)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.blue)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(Color.blue.opacity(0.1), in: Capsule())
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Quick-start Prompts

    private var quickStartRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(walkPrompts) { p in
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        firePrompt(p)
                    } label: {
                        HStack(spacing: 6) {
                            Text(p.emoji).font(.system(size: 14))
                            Text(p.label).font(.system(size: 13, weight: .medium))
                        }
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        .background(.regularMaterial, in: Capsule())
                        .foregroundStyle(.primary)
                        .shadow(color: .black.opacity(0.07), radius: 5, y: 2)
                    }
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 2)
        }
        .padding(.horizontal, -16)
    }

    // MARK: - Suggestions

    private var hasSuggestionContent: Bool { !poiResults.isEmpty || !suggestions.isEmpty }

    private var searchLoadingPill: some View {
        HStack(spacing: 8) {
            ProgressView().scaleEffect(0.72)
            Text("Searching…").font(.system(size: 13)).foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var suggestionDropdown: some View {
        ScrollView {
            VStack(spacing: 0) {
                if !poiResults.isEmpty {
                    ForEach(Array(poiResults.prefix(8))) { r in
                        Button { selectPlaceResult(r) } label: { poiRow(r) }
                        if r.id != poiResults.prefix(8).last?.id {
                            Divider().padding(.leading, 56)
                        }
                    }
                } else {
                    ForEach(Array(suggestions.prefix(8))) { s in
                        Button { selectSuggestion(s) } label: { suggestionRow(s) }
                        if s.id != suggestions.prefix(8).last?.id {
                            Divider().padding(.leading, 56)
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .scrollIndicators(.hidden)
        .frame(maxHeight: 340)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.13), radius: 22, y: 6)
    }

    private func poiRow(_ r: PlaceSearchResult) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(Color.orange.opacity(0.1)).frame(width: 34, height: 34)
                Image(systemName: "mappin").font(.system(size: 13, weight: .semibold)).foregroundStyle(.orange)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(r.name).font(.system(size: 15, weight: .medium)).lineLimit(1)
                HStack(spacing: 6) {
                    if let rating = r.rating {
                        HStack(spacing: 3) {
                            Image(systemName: "star.fill").font(.system(size: 10)).foregroundStyle(.yellow)
                            Text(String(format: "%.1f", rating)).font(.system(size: 12)).foregroundStyle(.secondary)
                        }
                    }
                    if let open = r.openNow {
                        Text(open ? "Open" : "Closed")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(open ? .green : .red)
                    }
                    if let dist = r.distanceKm {
                        Text(String(format: "%.1f km", dist)).font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
        }
        .padding(.horizontal, 14).padding(.vertical, 11).contentShape(Rectangle())
    }

    private func suggestionRow(_ s: PlaceSuggestion) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(Color.blue.opacity(0.08)).frame(width: 34, height: 34)
                Image(systemName: "location").font(.system(size: 13, weight: .medium)).foregroundStyle(.blue)
            }
            Text(s.label).font(.system(size: 15)).lineLimit(2)
            Spacer()
        }
        .padding(.horizontal, 14).padding(.vertical, 11).contentShape(Rectangle())
    }

    // MARK: - Bottom Panel

    @ViewBuilder
    private var bottomPanel: some View {
        if vm.isLoading {
            routeSkeletonCard
        } else if let route = vm.currentRoute {
            Group {
                if isRouteCardCollapsed {
                    collapsedRouteCard(route)
                } else {
                    expandedRouteCard(route)
                }
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        } else {
            idleButton.transition(.opacity)
        }
    }

    private var idleButton: some View {
        VStack(spacing: 10) {
            // Loop Assistant entry point
            Button {
                showLoopAssistant = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "wand.and.sparkles")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Find a loop with AI")
                        .font(.system(size: 14, weight: .semibold))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 13)
                .background(
                    LinearGradient(
                        colors: [
                            Color(red: 0.5, green: 0.25, blue: 1.0).opacity(0.1),
                            Color(red: 0.2, green: 0.55, blue: 1.0).opacity(0.1),
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.5, green: 0.25, blue: 1.0).opacity(0.3),
                                    Color(red: 0.2, green: 0.55, blue: 1.0).opacity(0.3),
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            lineWidth: 1
                        )
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            Color(red: 0.5, green: 0.25, blue: 1.0),
                            Color(red: 0.2, green: 0.55, blue: 1.0),
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
            }
            .shadow(color: Color(red: 0.35, green: 0.2, blue: 0.9).opacity(0.18), radius: 10, y: 3)

            // Manual route build
            Button {
                Task { await requestRoute() }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "figure.walk").font(.system(size: 16, weight: .semibold))
                    Text(idleButtonTitle).font(.system(size: 17, weight: .semibold))
                }
                .frame(maxWidth: .infinity).padding(.vertical, 16)
                .background(Color.primary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .foregroundStyle(Color(UIColor.systemBackground))
            }
            .shadow(color: .black.opacity(0.16), radius: 14, y: 4)
        }
    }

    private var idleButtonTitle: String {
        if vm.mode == "loop" {
            return stops.isEmpty ? "Add stops for your loop" : "Build your loop"
        }
        if !stops.isEmpty {
            return "Build your walk"
        }
        return "Find a walk"
    }

    private func expandedRouteCard(_ route: Route) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            routeCardContent(route)
        }
        .frame(maxHeight: 430)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.13), radius: 22, y: 6)
    }

    private func collapsedRouteCard(_ route: Route) -> some View {
        Button {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) {
                isRouteCardCollapsed = false
            }
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Capsule()
                        .fill(Color.secondary.opacity(0.35))
                        .frame(width: 36, height: 5)
                    Spacer()
                    Image(systemName: "chevron.up")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                }

                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(routeTitle(for: route))
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Text(compactRouteSummary(for: route))
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    HStack(spacing: 6) {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Expand")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(.blue)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: .black.opacity(0.12), radius: 18, y: 5)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture()
                .onChanged { v in
                    if v.translation.height < 0 { cardDragOffset = v.translation.height }
                }
                .onEnded { v in
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
                        if v.translation.height < -35 {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            isRouteCardCollapsed = false
                        }
                        cardDragOffset = 0
                    }
                }
        )
    }

    private func routeCardContent(_ route: Route) -> some View {
        let displayedPlaces = displayedComingUpPlaces(for: route)
        return VStack(alignment: .leading, spacing: 12) {

            HStack {
                Capsule()
                    .fill(Color.secondary.opacity(0.35))
                    .frame(width: 36, height: 5)
                Spacer()
                Button {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) {
                        isRouteCardCollapsed = true
                    }
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 30, height: 30)
                        .background(Color.secondary.opacity(0.08), in: Circle())
                }
                .buttonStyle(.plain)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture()
                    .onChanged { v in
                        if v.translation.height > 0 { cardDragOffset = v.translation.height }
                    }
                    .onEnded { v in
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                            if v.translation.height > 170 {
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                vm.clearRoute()
                                isRouteCardCollapsed = false
                            } else if v.translation.height > 70 {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                isRouteCardCollapsed = true
                            }
                            cardDragOffset = 0
                        }
                    }
            )

            // ── Title ──────────────────────────────────────────────────────
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(routeTitle(for: route))
                        .font(.system(size: 20, weight: .semibold))
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 5) {
                    Text(modeLabel(for: route.mode))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(.secondary.opacity(0.1), in: Capsule())

                    if let steps = route.steps, !steps.isEmpty {
                        Button { showStepsSheet = true } label: {
                            HStack(spacing: 4) {
                                Text("\(steps.count) turns")
                                    .font(.system(size: 12, weight: .medium))
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 10, weight: .semibold))
                            }
                            .foregroundStyle(.blue)
                        }
                    }
                }
            }

            // ── Stats ──────────────────────────────────────────────────────
            HStack(spacing: 0) {
                statItem(icon: "figure.walk", value: vm.distanceText, label: "Distance")
                Spacer()
                if let dur = vm.durationText {
                    statItem(icon: "clock", value: dur, label: "Est. time")
                    Spacer()
                }
                if let gain = route.elevation?.elevationGainM, gain > 2 {
                    statItem(icon: "arrow.up.forward",
                             value: String(format: "+%.0f m", gain),
                             label: "Elevation")
                    Spacer()
                }
                if let s = vm.estimatedStepsText {
                    statItem(icon: "shoeprints.fill", value: s, label: "Steps")
                }
            }

            // ── Primary action buttons ─────────────────────────────────────
            HStack(spacing: 10) {
                Button {
                    showMapNav = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "location.north.line.fill")
                            .font(.system(size: 15, weight: .semibold))
                        Text("Start Trip")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(
                        Color(red: 0.17, green: 0.17, blue: 0.15),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                    )
                    .foregroundStyle(.white)
                }

                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    showAR = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "arkit").font(.system(size: 15, weight: .semibold))
                        Text("AR Navigate").font(.system(size: 16, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 15)
                    .background(.secondary.opacity(0.09), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .foregroundStyle(.primary)
                }
            }

            // ── Utility buttons ────────────────────────────────────────────
            HStack(spacing: 10) {
                if canFetchBackendDetours {
                    utilityActionButton(
                        title: isLoadingDetours ? "Loading…" : "Detours",
                        icon: "point.topleft.down.curvedto.point.bottomright.up.fill"
                    ) {
                        Task { await loadDetours() }
                    }
                }

                utilityActionButton(
                    title: isExportingGPX ? "Exporting…" : "Export GPX",
                    icon: "square.and.arrow.up"
                ) {
                    Task { await exportCurrentRoute() }
                }
            }

            // ── Enrichment (only rendered when data exists) ────────────────
            let hasEnrichment = vm.sparklineElevations != nil
                || hasScores(route)
                || route.enrichment?.neighborhoodFlavor != nil
                || route.enrichment?.highlights?.isEmpty == false
                || !displayedPlaces.isEmpty
                || isLoadingComingUpPlaces

            if hasEnrichment {
                Divider()
                    .padding(.vertical, 2)

                if let elevs = vm.sparklineElevations {
                    elevationSparkline(elevs)
                }

                if hasScores(route) {
                    HStack(spacing: 8) {
                        if let s = route.safetyScore {
                            scoreBadgeBar(icon: "checkmark.shield.fill", label: "Safety", value: s, color: .green)
                        }
                        if let s = route.scenicScore {
                            scoreBadgeBar(icon: "leaf.fill", label: "Scenic", value: s, color: .teal)
                        }
                        if let s = route.aiBestScore {
                            scoreBadgeBar(icon: "wand.and.stars", label: "AI", value: s, color: .purple)
                        }
                        Spacer()
                    }
                }

                if let flavor = route.enrichment?.neighborhoodFlavor {
                    HStack(spacing: 8) {
                        Text(flavor.displayText)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 7)
                            .background(Color.orange.opacity(0.09), in: Capsule())

                        if let description = flavor.description, !description.isEmpty {
                            Text(description)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                }

                if let highlights = route.enrichment?.highlights, !highlights.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 7) {
                            ForEach(highlights, id: \.self) { h in
                                Text(h)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(.primary)
                                    .padding(.horizontal, 11).padding(.vertical, 6)
                                    .background(Color.blue.opacity(0.08), in: Capsule())
                            }
                        }
                        .padding(.horizontal, 1)
                    }
                }

                if isLoadingComingUpPlaces {
                    HStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Finding spots along this walk…")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                } else if !displayedPlaces.isEmpty {
                    comingUpSection(displayedPlaces)
                }
            }
        }
        .padding(20)
    }

    // MARK: - Sub-components

    @ViewBuilder
    private func comingUpSection(_ places: [EnrichedPlace]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Coming up on your walk")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color.primary.opacity(0.72))
                .textCase(.uppercase)
                .tracking(0.7)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(places.prefix(6)) { place in
                        placePill(place)
                    }
                }
                .padding(.horizontal, 1)
                .padding(.vertical, 2)
            }
        }
    }

    private func stopPin(number: Int) -> some View {
        ZStack {
            Circle()
                .fill(.white)
                .frame(width: 28, height: 28)
                .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
            Circle()
                .stroke(Color.primary.opacity(0.75), lineWidth: 2)
                .frame(width: 18, height: 18)
            Text("\(number)")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.primary)
        }
    }

    private func placePill(_ place: EnrichedPlace) -> some View {
        Button {
            Task { await addSuggestedPlaceToRoute(place) }
        } label: {
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(place.accentColor.opacity(0.12))
                        .frame(width: 32, height: 32)
                    Image(systemName: place.icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(place.accentColor)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(place.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    if let note = place.note, !note.isEmpty {
                        Text(note)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    } else if let rating = place.rating {
                        HStack(spacing: 3) {
                            Image(systemName: "star.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(.yellow)
                            Text(String(format: "%.1f", rating))
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    } else if let dist = place.distanceFromStartM {
                        Text(dist < 1000
                             ? String(format: "in %.0f m", dist)
                             : String(format: "in %.1f km", dist / 1000))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Tap to add stop")
                            .font(.system(size: 11))
                            .foregroundStyle(.blue)
                    }
                }

                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.blue)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(.secondary.opacity(0.07),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func statItem(icon: String, value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                Text(value).font(.system(size: 17, weight: .semibold)).monospacedDigit()
            }
            Text(label).font(.system(size: 11)).foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private func elevationSparkline(_ normalized: [Double]) -> some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let step = normalized.count > 1 ? w / CGFloat(normalized.count - 1) : w

            // Fill
            Path { path in
                path.move(to: CGPoint(x: 0, y: h))
                for (i, v) in normalized.enumerated() {
                    path.addLine(to: CGPoint(x: CGFloat(i) * step, y: h - CGFloat(v) * h))
                }
                path.addLine(to: CGPoint(x: w, y: h))
                path.closeSubpath()
            }
            .fill(LinearGradient(colors: [Color.teal.opacity(0.25), .clear],
                                 startPoint: .top, endPoint: .bottom))

            // Stroke
            Path { path in
                for (i, v) in normalized.enumerated() {
                    let pt = CGPoint(x: CGFloat(i) * step, y: h - CGFloat(v) * h)
                    if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
                }
            }
            .stroke(Color.teal, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        }
        .frame(height: 40)
        .padding(.vertical, 2)
    }

    private func hasScores(_ r: Route) -> Bool {
        r.safetyScore != nil || r.scenicScore != nil || r.aiBestScore != nil
    }

    private func scoreBadgeBar(icon: String, label: String, value: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 10, weight: .semibold))
                Text(label).font(.system(size: 11))
                Spacer()
                Text("\(Int(value * 100))%").font(.system(size: 11, weight: .bold))
            }
            .foregroundStyle(color)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(color.opacity(0.15)).frame(height: 4)
                    Capsule().fill(color).frame(width: geo.size.width * value, height: 4)
                }
            }
            .frame(height: 4)
        }
        .padding(10)
        .frame(minWidth: 80)
        .background(color.opacity(0.07), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func utilityActionButton(title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(.secondary.opacity(0.09), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .foregroundStyle(.primary)
        }
        .disabled(isLoadingDetours || isExportingGPX)
    }

    // MARK: - Skeleton

    private var routeSkeletonCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            skeletonBar(width: 170, height: 22)
            skeletonBar(width: 110, height: 14)
            HStack(spacing: 16) {
                skeletonBar(width: 68, height: 36)
                skeletonBar(width: 68, height: 36)
                skeletonBar(width: 68, height: 36)
            }
            skeletonBar(width: .infinity, height: 40)
            skeletonBar(width: .infinity, height: 52)
        }
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.09), radius: 18, y: 4)
        .shimmering()
    }

    private func skeletonBar(width: CGFloat, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color.secondary.opacity(0.14))
            .frame(maxWidth: width, minHeight: height, maxHeight: height)
    }

    // MARK: - Error Toast

    private func toastView(_ message: String, isError: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(isError ? .red : .green)
            Text(message)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(2)
            Spacer()
            Button {
                withAnimation { vm.toastMessage = nil }
            } label: {
                Image(systemName: "xmark").font(.system(size: 12, weight: .semibold)).foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(isError ? Color.red.opacity(0.3) : Color.green.opacity(0.3), lineWidth: 1)
        )
    }

    // MARK: - Route state handler

    private func handleRouteChange(_ route: Route?) {
        if let route, route.id != lastRouteID {
            lastRouteID = route.id
            polylineProgress = 0
            fallbackComingUpPlaces = []
            isLoadingComingUpPlaces = false
            isRouteCardCollapsed = false
            cardDragOffset = 0
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            withAnimation(.easeOut(duration: 0.65)) { polylineProgress = 1.0 }
            centerMapOnRoute(route)
            if route.enrichment?.allPlaces.isEmpty != false {
                Task { await loadFallbackComingUpPlaces(for: route) }
            }
        } else if route == nil {
            polylineProgress = 0
            lastRouteID = nil
            fallbackComingUpPlaces = []
            isLoadingComingUpPlaces = false
            isRouteCardCollapsed = false
            cardDragOffset = 0
        }
    }

    // MARK: - Map / pin logic

    private func dropPin(at coord: CLLocationCoordinate2D) {
        droppedPin = coord

        // Show coordinates immediately while geocode resolves
        droppedPinLabel = String(format: "%.4f, %.4f", coord.latitude, coord.longitude)
        if vm.mode == "loop" || !stops.isEmpty {
            addStop(label: droppedPinLabel, coordinate: coord)
        } else {
            endCoordinate = coord
            endText = droppedPinLabel
        }

        // Reverse geocode to get a human name
        guard !isReverseGeocoding else { return }
        isReverseGeocoding = true
        Task {
            defer { isReverseGeocoding = false }
            if let name = try? await API.shared.reverseGeocode(coords: coord), !name.isEmpty {
                await MainActor.run {
                    droppedPinLabel = name
                    if vm.mode == "loop" || !stops.isEmpty {
                        updateLastStopIfMatchingCoordinate(coord, label: name)
                    } else {
                        endText = name
                    }
                }
            }
        }
    }

    private func centerMapOnRoute(_ r: Route) {
        let coords = r.coordinatePoints
        guard !coords.isEmpty else { return }
        guard coords.count > 1 else {
            withAnimation(.easeInOut(duration: 0.45)) {
                mapPosition = .region(MKCoordinateRegion(
                    center: coords[0],
                    span: MKCoordinateSpan(latitudeDelta: 0.04, longitudeDelta: 0.04)
                ))
            }
            return
        }
        let lats = coords.map(\.latitude),  lons = coords.map(\.longitude)
        let center = CLLocationCoordinate2D(
            latitude:  (lats.min()! + lats.max()!) / 2,
            longitude: (lons.min()! + lons.max()!) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta:  max((lats.max()! - lats.min()!) * 1.35, 0.008),
            longitudeDelta: max((lons.max()! - lons.min()!) * 1.35, 0.008)
        )
        withAnimation(.easeInOut(duration: 0.55)) {
            mapPosition = .region(MKCoordinateRegion(center: center, span: span))
        }
    }

    private var stopMarkers: [RouteStopMarker] {
        stops.enumerated().compactMap { index, stop in
            guard let coordinate = stop.coordinate ?? parseCoordinate(from: stop.label) else { return nil }
            return RouteStopMarker(id: stop.id, index: index, coordinate: coordinate)
        }
    }

    // MARK: - Route helpers

    private func routeTitle(for route: Route) -> String {
        switch route.mode.lowercased() {
        case "loop":      return "Walking Loop"
        case "scenic":    return "Scenic Route"
        case "explore":   return "Exploration Walk"
        case "best":      return "Best Route"
        case "safe":      return "Safe Route"
        case "shortest":  return "Fastest Route"
        case "elevation": return "Hilly Route"
        case "gpx":       return "GPX Route"
        default:          return "Your Route"
        }
    }

    private func compactRouteSummary(for route: Route) -> String {
        var parts: [String] = []
        if vm.distanceText != "—" {
            parts.append(vm.distanceText)
        }
        if let duration = vm.durationText {
            parts.append(duration)
        }
        if let steps = route.steps?.count, steps > 0 {
            parts.append("\(steps) turns")
        }
        return parts.isEmpty ? modeLabel(for: route.mode) : parts.joined(separator: " • ")
    }

    private func routeSubtitle(for route: Route) -> String {
        // Prefer the AI-generated one-liner from enrichment
        if let summary = route.enrichment?.summary, !summary.isEmpty {
            return summary
        }
        // Fallback to structured fields
        var parts: [String] = []
        if let flavor = route.enrichment?.neighborhoodFlavor?.displayText, !flavor.isEmpty {
            parts.append(flavor)
        } else {
            if let diff = route.elevation?.difficulty { parts.append(diff.capitalized) }
            if let s = route.steps, !s.isEmpty { parts.append("\(s.count) turns") }
        }
        return parts.isEmpty ? "Ready when you are" : parts.joined(separator: " · ")
    }

    private func displayedComingUpPlaces(for route: Route) -> [EnrichedPlace] {
        let enrichmentPlaces = route.enrichment?.allPlaces ?? []
        if !enrichmentPlaces.isEmpty { return enrichmentPlaces }
        return fallbackComingUpPlaces
    }

    private func routeDiscoveryCenter(for route: Route) -> CLLocationCoordinate2D? {
        let points = route.coordinatePoints
        guard !points.isEmpty else { return nil }
        return points[points.count / 2]
    }

    private func loadFallbackComingUpPlaces(for route: Route) async {
        guard let center = routeDiscoveryCenter(for: route) else { return }
        isLoadingComingUpPlaces = true
        defer { isLoadingComingUpPlaces = false }

        do {
            let nearby = try await API.shared.fetchNearby(
                lat: center.latitude,
                lon: center.longitude,
                radiusM: 700,
                category: "all"
            )
            let mapped = nearby.map {
                EnrichedPlace(
                    name: $0.name,
                    lat: $0.lat,
                    lon: $0.lon,
                    category: $0.category,
                    rating: nil,
                    note: $0.cuisine ?? $0.openingHours,
                    distanceFromStartM: $0.distanceFromRouteM ?? $0.distanceFromYouM
                )
            }
            fallbackComingUpPlaces = Array(mapped.prefix(8))
        } catch {
            fallbackComingUpPlaces = []
        }
    }

    private func modeLabel(for mode: String) -> String {
        routeModes.first(where: { $0.id == mode })?.label ?? mode.capitalized
    }

    private var currentResolvedStart: CLLocationCoordinate2D? {
        startCoordinate
            ?? parseCoordinate(from: startText)
            ?? locationManager.userLocation
            ?? vm.currentRoute?.coordinatePoints.first
    }

    private var currentResolvedEnd: CLLocationCoordinate2D? {
        endCoordinate
            ?? parseCoordinate(from: endText)
            ?? vm.currentRoute?.coordinatePoints.last
    }

    private var canFetchBackendDetours: Bool {
        guard let route = vm.currentRoute else { return false }
        guard vm.mode != "loop", route.mode.lowercased() != "gpx" else { return false }
        guard stops.isEmpty else { return false }
        // Need a start — end can fall back to route's last coordinate
        guard currentResolvedStart != nil else { return false }
        return currentResolvedEnd != nil || route.coordinatePoints.last != nil
    }

    private func handleModeSwitch(to newMode: String) {
        if newMode == "loop",
           stops.isEmpty,
           (!endText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || endCoordinate != nil) {
            addStop(label: endText, coordinate: endCoordinate)
            endText = ""
            endCoordinate = nil
        }
        vm.clearRoute()
        clearSuggestions()
    }

    // MARK: - Quick prompts

    private func firePrompt(_ p: WalkPrompt) {
        guard let start = locationManager.userLocation else {
            vm.showToast("GPS not available yet.", isError: true)
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            return
        }
        clearSuggestions()
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        Task { await vm.fetchRoute(for: p, start: start) }
    }

    // MARK: - Loop Assistant selection

    /// Autofills the planner from a Loop Assistant selection and fetches the route.
    /// Calls GET /route?mode=loop&duration=...&loop_theme=... via the existing fetchRoute path.
    private func applyLoopSelection(option: LoopOption, origin: LoopOrigin) {
        // Autofill planner state
        startText       = origin.label
        startCoordinate = origin.coordinate
        stops           = []
        endText         = ""
        endCoordinate   = nil

        // Ensure loop mode is active
        withAnimation(.spring(response: 0.22, dampingFraction: 0.72)) {
            vm.mode = "loop"
        }

        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        vm.showToast("Building your \(option.title)…", isError: false)

        // Fetch the full route using the existing route API
        Task {
            await vm.fetchRoute(
                start: origin.coordinate,
                end: nil,
                duration: option.durationMin,
                loopTheme: option.theme
            )
        }
    }

    private func refreshPersonaIfNeeded(force: Bool) async {
        guard let userLocation = locationManager.userLocation else { return }
        if persona != nil && !force { return }
        isLoadingPersona = true
        defer { isLoadingPersona = false }

        do {
            persona = try await API.shared.fetchPersona(lat: userLocation.latitude, lon: userLocation.longitude)
        } catch {
            if force {
                vm.showToast("Couldn’t load walk persona right now.", isError: true)
            }
        }
    }

    private func presentPersonaSheet() async {
        await refreshPersonaIfNeeded(force: true)
        showPersonaSheet = true
    }

    private func loadNearby(category: String, presentSheet: Bool = true) async {
        guard let userLocation = locationManager.userLocation else {
            vm.showToast("Need your location for nearby discovery.", isError: true)
            return
        }

        nearbyCategory = category
        isLoadingNearby = true
        if presentSheet {
            showNearbySheet = true
        }
        defer { isLoadingNearby = false }

        do {
            nearbyPlaces = try await API.shared.fetchNearby(
                lat: userLocation.latitude,
                lon: userLocation.longitude,
                radiusM: 900,
                category: category
            )
        } catch {
            nearbyPlaces = []
            vm.showToast("Couldn’t load nearby places.", isError: true)
        }
    }

    private func loadThemes() async {
        isLoadingThemes = true
        showThemesSheet = true
        defer { isLoadingThemes = false }

        do {
            themes = try await API.shared.fetchThemes()
        } catch {
            themes = []
            vm.showToast("Couldn’t load walk themes.", isError: true)
        }
    }

    private func loadThemeDetail(themeID: String) async {
        isLoadingThemeDetail = true
        showThemeDetailSheet = true
        defer { isLoadingThemeDetail = false }

        do {
            selectedThemeDetail = try await API.shared.fetchThemeDetail(themeID: themeID)
        } catch {
            selectedThemeDetail = nil
            vm.showToast("Couldn’t load that theme.", isError: true)
        }
    }

    private func applyTheme(_ theme: WalkTheme) {
        withAnimation(.spring(response: 0.22, dampingFraction: 0.72)) {
            vm.mode = "loop"
        }
        handleModeSwitch(to: "loop")
        showThemeDetailSheet = false

        if stops.isEmpty {
            addEmptyStop()
        }

        vm.showToast("Using \(theme.name). Add stops that match the theme.", isError: false)
    }

    private func addSuggestedPlaceToRoute(_ place: EnrichedPlace) async {
        guard let route = vm.currentRoute else { return }

        let coordinate = CLLocationCoordinate2D(latitude: place.lat, longitude: place.lon)
        let alreadyAddedStop = stops.contains {
            guard let stopCoordinate = $0.coordinate ?? parseCoordinate(from: $0.label) else { return false }
            return distanceMeters(stopCoordinate, coordinate) < 12
        }
        let alreadyIsDestination = currentResolvedEnd.map { distanceMeters($0, coordinate) < 12 } ?? false

        if alreadyAddedStop || alreadyIsDestination {
            vm.showToast("\(place.name) is already part of this walk.", isError: false)
            return
        }

        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        addStop(label: place.name, coordinate: coordinate)
        vm.showToast("Added \(place.name) to your walk.", isError: false)

        if route.mode.lowercased() == "gpx" {
            return
        }

        await requestRoute()
    }

    private func addDetourAsStop(_ detour: DetourPlace) async {
        guard currentResolvedStart != nil else {
            vm.showToast("Need a start location to add a detour.", isError: true)
            return
        }

        let coord = CLLocationCoordinate2D(latitude: detour.lat, longitude: detour.lon)
        addStop(label: detour.name, coordinate: coord)
        vm.showToast("Added \(detour.name) as a stop.", isError: false)
        await requestRoute()
    }

    private func loadDetours() async {
        guard let start = currentResolvedStart,
              let end = currentResolvedEnd ?? vm.currentRoute?.coordinatePoints.last else {
            vm.showToast("Need a start and end point to load detours.", isError: true)
            return
        }

        isLoadingDetours = true
        showDetoursSheet = true
        defer { isLoadingDetours = false }

        do {
            detoursResponse = try await API.shared.fetchDetours(
                start: start,
                end: end,
                mode: vm.mode,
                maxDetourM: 450,
                topN: 5
            )
        } catch {
            detoursResponse = nil
            vm.showToast("Couldn’t load detours for this route.", isError: true)
        }
    }

    private func analyzeWalkCoverage() async {
        guard !walkHistory.routes.isEmpty else {
            walkAnalysis = nil
            showWalkCoverageSheet = true
            return
        }

        isAnalyzingWalks = true
        showWalkCoverageSheet = true
        defer { isAnalyzingWalks = false }

        let center = locationManager.userLocation ?? currentResolvedStart

        do {
            walkAnalysis = try await API.shared.analyzeWalks(
                routes: walkHistory.routes,
                centerLat: center?.latitude,
                centerLon: center?.longitude,
                suggestUnexplored: true,
                radiusM: 1600
            )
        } catch {
            walkAnalysis = nil
            vm.showToast("Couldn’t analyze your walk history.", isError: true)
        }
    }

    private func exportCurrentRoute() async {
        guard let route = vm.currentRoute else { return }
        isExportingGPX = true
        defer { isExportingGPX = false }

        do {
            if let start = currentResolvedStart,
               stops.isEmpty,
               vm.mode != "loop",
               route.mode.lowercased() != "gpx" {
                exportedGPXURL = try await API.shared.exportGPX(
                    start: start,
                    end: currentResolvedEnd,
                    mode: vm.mode,
                    duration: 30,
                    loopTheme: nil,
                    name: routeTitle(for: route)
                )
            } else {
                exportedGPXURL = try exportGPXLocally(route: route, name: routeTitle(for: route))
            }
            showExportShareSheet = exportedGPXURL != nil
        } catch {
            vm.showToast("Couldn’t export this walk as GPX.", isError: true)
        }
    }

    private func exportGPXLocally(route: Route, name: String) throws -> URL {
        let formatter = ISO8601DateFormatter()
        let escapedName = name
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")

        let trackPoints = route.coordinatePoints.map { coordinate in
            "    <trkpt lat=\"\(coordinate.latitude)\" lon=\"\(coordinate.longitude)\"></trkpt>"
        }.joined(separator: "\n")

        let gpx = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="WalkWithMe" xmlns="http://www.topografix.com/GPX/1/1">
          <metadata>
            <name>\(escapedName)</name>
            <time>\(formatter.string(from: Date()))</time>
          </metadata>
          <trk>
            <name>\(escapedName)</name>
            <trkseg>
        \(trackPoints)
            </trkseg>
          </trk>
        </gpx>
        """

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("walkwithme-\(UUID().uuidString).gpx")
        guard let data = gpx.data(using: .utf8) else {
            throw APIError.server("Could not encode GPX data.")
        }
        try data.write(to: url, options: .atomic)
        return url
    }

    // MARK: - Autocomplete

    private func selectPlaceResult(_ r: PlaceSearchResult) {
        let coord = CLLocationCoordinate2D(latitude: r.lat, longitude: r.lon)
        applySelection(label: r.name, coordinate: coord)
    }

    private func selectSuggestion(_ s: PlaceSuggestion) {
        let coord = CLLocationCoordinate2D(latitude: s.lat, longitude: s.lon)
        applySelection(label: s.label, coordinate: coord)
    }

    private func clearSuggestions() {
        suggestions.removeAll(); poiResults.removeAll()
        isFetchingSuggestions = false
        autocompleteTask?.cancel(); autocompleteTask = nil
        withAnimation(.easeInOut(duration: 0.15)) { activeField = .none }
    }

    private func applySelection(label: String, coordinate: CLLocationCoordinate2D) {
        switch activeField {
        case .start:
            startText = label
            startCoordinate = coordinate
        case .end, .none:
            endText = label
            endCoordinate = coordinate
        case .stop(let id):
            updateStop(id: id, label: label, coordinate: coordinate)
        }
        clearSuggestions()
    }

    private func isPOIQuery(_ text: String) -> Bool {
        let q = text.lowercased()
        let kw = ["cafe","coffee","restaurant","food","pizza","thai","gym","park","museum",
                  "mall","atm","hotel","bar","burger","boba","tea","pharmacy","bakery",
                  "dessert","ramen","sushi","brunch","market","gallery","cinema","store","shop"]
        if q.contains("near me") || q.contains("nearby") { return true }
        if kw.contains(where: { q.contains($0) }) { return true }
        return !q.contains { $0.isNumber } && q.split(separator: " ").count >= 2
    }

    private func stopTextBinding(for id: UUID) -> Binding<String> {
        Binding(
            get: { stops.first(where: { $0.id == id })?.label ?? "" },
            set: { newValue in
                updateStop(id: id, label: newValue, coordinate: nil)
                if activeField == .stop(id) {
                    triggerAutocomplete(with: newValue)
                }
            }
        )
    }

    private func addEmptyStop() {
        stops.append(RouteStopDraft())
        if let id = stops.last?.id {
            withAnimation(.easeInOut(duration: 0.15)) {
                activeField = .stop(id)
            }
        }
    }

    private func addStop(label: String, coordinate: CLLocationCoordinate2D?) {
        stops.append(RouteStopDraft(label: label, coordinate: coordinate))
    }

    private func updateStop(id: UUID, label: String, coordinate: CLLocationCoordinate2D?) {
        guard let index = stops.firstIndex(where: { $0.id == id }) else { return }
        stops[index].label = label
        stops[index].coordinate = coordinate
    }

    private func removeStop(id: UUID) {
        stops.removeAll { $0.id == id }
        if case .stop(let activeID) = activeField, activeID == id {
            clearSuggestions()
        }
    }

    private func updateLastStopIfMatchingCoordinate(_ coordinate: CLLocationCoordinate2D, label: String) {
        guard let index = stops.lastIndex(where: {
            guard let coord = $0.coordinate else { return false }
            return distanceMeters(coord, coordinate) < 1
        }) else { return }
        stops[index].label = label
    }

    private func triggerAutocomplete(with text: String) {
        autocompleteTask?.cancel()
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { clearSuggestions(); return }

        isFetchingSuggestions = true
        let userLat = locationManager.userLocation?.latitude
        let userLon = locationManager.userLocation?.longitude

        autocompleteTask = Task {
            try? await Task.sleep(nanoseconds: 220_000_000)
            guard !Task.isCancelled else { return }
            do {
                if isPOIQuery(trimmed) {
                    let results = try await API.shared.fetchPlacesSearch(q: trimmed, userLat: userLat, userLon: userLon)
                    guard !Task.isCancelled else { return }
                    await MainActor.run { poiResults = results; suggestions = []; isFetchingSuggestions = false }
                } else {
                    let results = try await API.shared.fetchAutocomplete(q: trimmed, userLat: userLat, userLon: userLon, limit: 7)
                    guard !Task.isCancelled else { return }
                    await MainActor.run { suggestions = results; poiResults = []; isFetchingSuggestions = false }
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run { suggestions = []; poiResults = []; isFetchingSuggestions = false }
            }
        }
    }

    // MARK: - Route request

    private func parseCoordinate(from text: String) -> CLLocationCoordinate2D? {
        let t = text.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return nil }
        let parts = t.split(separator: ",")
        guard parts.count == 2, let lat = Double(parts[0]), let lon = Double(parts[1]) else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    private func distanceMeters(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> CLLocationDistance {
        CLLocation(latitude: a.latitude, longitude: a.longitude)
            .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
    }

    private func requestRoute() async {
        let resolvedStartLocation = startCoordinate != nil || parseCoordinate(from: startText) != nil
            ? nil
            : await resolveTypedLocation(startText)
        let resolvedStart =
            startCoordinate
            ?? parseCoordinate(from: startText)
            ?? resolvedStartLocation?.coordinate
            ?? locationManager.userLocation
        guard let start = resolvedStart else {
            vm.showToast("Need a start location or GPS.", isError: true)
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            return
        }

        if startCoordinate == nil,
           let resolved = resolvedStartLocation {
            startCoordinate = resolved.coordinate
            startText = resolved.label
        }

        var resolvedStops: [CLLocationCoordinate2D] = []
        for stop in stops {
            if let coordinate = stop.coordinate ?? parseCoordinate(from: stop.label) {
                resolvedStops.append(coordinate)
                continue
            }

            guard let resolved = await resolveTypedLocation(stop.label) else {
                vm.showToast("Couldn’t find one of your stops. Pick a suggestion or drop a pin.", isError: true)
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
                return
            }

            updateStop(id: stop.id, label: resolved.label, coordinate: resolved.coordinate)
            resolvedStops.append(resolved.coordinate)
        }

        if vm.mode == "loop" {
            guard !resolvedStops.isEmpty else {
                vm.showToast("Add at least one stop to build your loop.", isError: true)
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
                return
            }
            clearSuggestions()
            await vm.fetchChainedRoute(start: start, stops: resolvedStops, end: nil)
            return
        }

        let resolvedEndLocation = endCoordinate != nil || parseCoordinate(from: endText) != nil
            ? nil
            : await resolveTypedLocation(endText)
        let end = endCoordinate
            ?? parseCoordinate(from: endText)
            ?? resolvedEndLocation?.coordinate

        if endCoordinate == nil,
           let resolved = resolvedEndLocation {
            endCoordinate = resolved.coordinate
            endText = resolved.label
        }

        if !resolvedStops.isEmpty {
            guard let end else {
                vm.showToast("Choose a final destination for this route.", isError: true)
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
                return
            }
            clearSuggestions()
            await vm.fetchChainedRoute(start: start, stops: resolvedStops, end: end)
            return
        }

        clearSuggestions()
        await vm.fetchRoute(start: start, end: end)
    }

    private func resolveTypedLocation(_ text: String) async -> ResolvedRouteLocation? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let coordinate = parseCoordinate(from: trimmed) {
            return ResolvedRouteLocation(label: trimmed, coordinate: coordinate)
        }

        let userLat = locationManager.userLocation?.latitude
        let userLon = locationManager.userLocation?.longitude

        if let suggestions = try? await API.shared.fetchAutocomplete(
            q: trimmed,
            userLat: userLat,
            userLon: userLon,
            limit: 1
        ), let suggestion = suggestions.first {
            return ResolvedRouteLocation(
                label: suggestion.label,
                coordinate: CLLocationCoordinate2D(latitude: suggestion.lat, longitude: suggestion.lon)
            )
        }

        if let places = try? await API.shared.fetchPlacesSearch(
            q: trimmed,
            userLat: userLat,
            userLon: userLon
        ), let place = places.first {
            return ResolvedRouteLocation(
                label: place.name,
                coordinate: CLLocationCoordinate2D(latitude: place.lat, longitude: place.lon)
            )
        }

        return nil
    }

    // MARK: - GPX Import

    private func importGPX(from url: URL) async {
        isImportingGPX = true; gpxImportError = nil
        defer { isImportingGPX = false }
        let needsAccess = url.startAccessingSecurityScopedResource()
        defer { if needsAccess { url.stopAccessingSecurityScopedResource() } }
        do {
            let resp = try await API.shared.importGPX(fileURL: url)
            let route = makeRoute(from: resp)
            await MainActor.run { vm.currentRoute = route }
        } catch {
            vm.showToast("Import failed: \(error.localizedDescription)", isError: true)
        }
    }

    private func makeRoute(from gpx: API.ImportGPXResponse) -> Route {
        let coords = gpx.coordinates
        let pts = coords.compactMap { c -> CLLocationCoordinate2D? in
            guard c.count == 2 else { return nil }
            return .init(latitude: c[0], longitude: c[1])
        }
        var total: CLLocationDistance = 0
        for i in 1..<pts.count { total += distanceMeters(pts[i - 1], pts[i]) }
        return Route(mode: "gpx", coordinates: coords, waypoints: nil,
                     distanceM: total, durationS: nil, summary: nil,
                     steps: nil, elevation: gpx.elevation,
                     safetyScore: nil, scenicScore: nil, aiBestScore: nil,
                     nextTurn: nil, enrichment: nil)
    }
}

// MARK: - Pulsing User Dot

private struct PulsingUserDot: View {
    @State private var pulsing = false

    var body: some View {
        ZStack {
            Circle()
                .fill(Color(red: 0.1, green: 0.4, blue: 1.0).opacity(pulsing ? 0 : 0.28))
                .frame(width: pulsing ? 46 : 20, height: pulsing ? 46 : 20)
                .animation(.easeOut(duration: 1.6).repeatForever(autoreverses: false), value: pulsing)

            Circle().fill(.white).frame(width: 16, height: 16)
                .shadow(color: .black.opacity(0.18), radius: 3)
            Circle().fill(Color(red: 0.1, green: 0.4, blue: 1.0)).frame(width: 10, height: 10)
        }
        .onAppear { pulsing = true }
    }
}

// MARK: - Triangle shape (for dropped pin)

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: rect.midX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            p.closeSubpath()
        }
    }
}

// MARK: - Steps Preview Sheet

private struct StepsPreviewSheet: View {
    let steps: [Step]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(Array(steps.enumerated()), id: \.offset) { i, step in
                    HStack(spacing: 14) {
                        ZStack {
                            Circle().fill(Color.blue.opacity(0.1)).frame(width: 36, height: 36)
                            Image(systemName: iconForStep(step))
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.blue)
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            Text(step.instruction)
                                .font(.system(size: 15))
                                .foregroundStyle(.primary)
                            if let len = step.length {
                                Text(String(format: "%.0f m", len * 1000))
                                    .font(.system(size: 13))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .listStyle(.plain)
            .navigationTitle("Turn-by-turn")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func iconForStep(_ step: Step) -> String {
        let t = step.instruction.lowercased()
        if t.contains("left")  { return "arrow.turn.up.left" }
        if t.contains("right") { return "arrow.turn.up.right" }
        if t.contains("arrive") || t.contains("destination") { return "flag.checkered" }
        return "arrow.up"
    }
}

private struct PersonaSheet: View {
    let persona: WalkPersona?
    let isLoading: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading your walk persona…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let persona {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            HStack(spacing: 14) {
                                Text(persona.emoji)
                                    .font(.system(size: 42))
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(persona.name)
                                        .font(.system(size: 28, weight: .semibold))
                                    Text(persona.tagline)
                                        .font(.system(size: 15))
                                        .foregroundStyle(.secondary)
                                }
                            }

                            if let bias = persona.routingBias {
                                sheetCard(title: "Routing Bias", body: bias.capitalized)
                            }

                            if let time = persona.timeOfDay {
                                sheetCard(title: "Best Time", body: time.capitalized)
                            }

                            if let weather = persona.weather {
                                sheetCard(title: "Weather Context", body: weather.capitalized)
                            }

                            if let highlights = persona.highlightCategories, !highlights.isEmpty {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("What To Look For")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(.secondary)
                                        .textCase(.uppercase)
                                    FlexibleTagRow(tags: highlights.map(\.capitalized))
                                }
                            }
                        }
                        .padding(20)
                    }
                } else {
                    ContentUnavailableView("No Persona Yet",
                                           systemImage: "sparkles",
                                           description: Text("We need your location to figure out the right walking vibe."))
                }
            }
            .navigationTitle("Walk Persona")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.fraction(0.45), .large])
    }
}

private struct NearbyPlacesSheet: View {
    let places: [NearbyPlace]
    let category: String
    let isLoading: Bool
    let onCategoryChange: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Picker("Category", selection: Binding(
                    get: { category },
                    set: { onCategoryChange($0) }
                )) {
                    Text("All").tag("all")
                    Text("Food").tag("food")
                    Text("Landmarks").tag("landmark")
                    Text("Parks").tag("park")
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)

                if isLoading {
                    Spacer()
                    ProgressView("Finding spots near you…")
                    Spacer()
                } else if places.isEmpty {
                    Spacer()
                    ContentUnavailableView("Nothing Nearby",
                                           systemImage: "mappin.slash",
                                           description: Text("Try a different category or move the map a bit."))
                    Spacer()
                } else {
                    List(places) { place in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 8) {
                                if let emoji = place.emoji, !emoji.isEmpty {
                                    Text(emoji)
                                }
                                Text(place.name)
                                    .font(.system(size: 16, weight: .semibold))
                            }

                            HStack(spacing: 8) {
                                if let category = place.category {
                                    Text(category.capitalized)
                                }
                                if let cuisine = place.cuisine, !cuisine.isEmpty {
                                    Text(cuisine)
                                }
                                if let distance = place.distanceFromYouM {
                                    Text(distance < 1000
                                         ? String(format: "%.0f m away", distance)
                                         : String(format: "%.1f km away", distance / 1000))
                                }
                            }
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Nearby")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

private struct ThemesSheet: View {
    let themes: [WalkTheme]
    let isLoading: Bool
    let onSelectTheme: (WalkTheme) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading themes…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(spacing: 12) {
                            ForEach(themes) { theme in
                                Button {
                                    onSelectTheme(theme)
                                } label: {
                                    HStack(alignment: .top, spacing: 14) {
                                        Text(theme.emoji)
                                            .font(.system(size: 28))
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(theme.name)
                                                .font(.system(size: 17, weight: .semibold))
                                                .foregroundStyle(.primary)
                                            Text(theme.tagline)
                                                .font(.system(size: 13))
                                                .foregroundStyle(.secondary)
                                            Text("\(theme.suggestedDurationMin) min")
                                                .font(.system(size: 12, weight: .semibold))
                                                .foregroundStyle(.blue)
                                        }
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundStyle(.tertiary)
                                    }
                                    .padding(16)
                                    .background(.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(16)
                    }
                }
            }
            .navigationTitle("Walk Themes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

private struct ThemeDetailSheet: View {
    let theme: WalkTheme?
    let isLoading: Bool
    let onUseTheme: (WalkTheme) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading theme…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let theme {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            HStack(spacing: 12) {
                                Text(theme.emoji)
                                    .font(.system(size: 40))
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(theme.name)
                                        .font(.system(size: 28, weight: .semibold))
                                    Text(theme.tagline)
                                        .font(.system(size: 15))
                                        .foregroundStyle(.secondary)
                                }
                            }

                            Text(theme.description)
                                .font(.system(size: 16))
                                .foregroundStyle(.primary)

                            sheetCard(title: "Loop Style", body: theme.loopTheme.capitalized)
                            sheetCard(title: "Suggested Duration", body: "\(theme.suggestedDurationMin) min")

                            VStack(alignment: .leading, spacing: 10) {
                                Text("Tags")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                    .textCase(.uppercase)
                                FlexibleTagRow(tags: theme.tags.map(\.capitalized))
                            }

                            Button {
                                onUseTheme(theme)
                                dismiss()
                            } label: {
                                Text("Use This Theme")
                                    .font(.system(size: 16, weight: .semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 15)
                                    .background(Color.primary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                    .foregroundStyle(Color(UIColor.systemBackground))
                            }
                            .padding(.top, 4)
                        }
                        .padding(20)
                    }
                } else {
                    ContentUnavailableView("Theme Unavailable",
                                           systemImage: "square.grid.2x2",
                                           description: Text("We couldn’t load that theme right now."))
                }
            }
            .navigationTitle("Theme")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

private struct DetoursSheet: View {
    let detoursResponse: DetoursResponse?
    let isLoading: Bool
    let onAddDetour: (DetourPlace) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var addingDetour: DetourPlace.ID?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Scoring detours…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let response = detoursResponse, !response.detours.isEmpty {
                    List(response.detours) { detour in
                        HStack(spacing: 14) {
                            // Left: emoji + info
                            VStack(alignment: .leading, spacing: 5) {
                                HStack(spacing: 8) {
                                    if let emoji = detour.emoji, !emoji.isEmpty {
                                        Text(emoji).font(.system(size: 20))
                                    }
                                    Text(detour.name)
                                        .font(.system(size: 16, weight: .semibold))
                                }

                                HStack(spacing: 10) {
                                    if let extra = detour.extraMinutes {
                                        Label(String(format: "+%.0f min", extra), systemImage: "clock")
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundStyle(.secondary)
                                    }
                                    if let score = detour.worthItScore {
                                        Label(String(format: "%.0f%% worth it", score * 100), systemImage: "star.fill")
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundStyle(.orange)
                                    }
                                    if let label = detour.label, !label.isEmpty {
                                        Text(label)
                                            .font(.system(size: 12))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }

                            Spacer()

                            // Add button
                            Button {
                                addingDetour = detour.id
                                onAddDetour(detour)
                            } label: {
                                if addingDetour == detour.id {
                                    ProgressView().scaleEffect(0.8)
                                        .frame(width: 72, height: 34)
                                } else {
                                    Text("Add stop")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 7)
                                        .background(Color.blue, in: Capsule())
                                }
                            }
                            .buttonStyle(.plain)
                            .disabled(addingDetour != nil)
                        }
                        .padding(.vertical, 6)
                    }
                    .listStyle(.plain)
                } else {
                    ContentUnavailableView("Nothing Nearby",
                                           systemImage: "point.topleft.down.curvedto.point.bottomright.up",
                                           description: Text("No standout spots within detour range of this route. Try a different area or increase your walk distance."))
                }
            }
            .navigationTitle("Worthwhile Detours")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

private struct WalkCoverageSheet: View {
    let analysis: WalkAnalysisResponse?
    let routeCount: Int
    let isLoading: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Analyzing your city coverage…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let analysis {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            sheetCard(title: "Coverage", body: String(format: "%.1f%% of your local grid explored", analysis.coverage.coveragePct))
                            sheetCard(title: "Walked", body: String(format: "%.1f km total across %d walks", analysis.coverage.totalWalkedKm, analysis.coverage.routeCount))
                            sheetCard(title: "Unique", body: String(format: "%.1f km of unique ground covered", analysis.coverage.uniqueKm))

                            if !analysis.insight.isEmpty {
                                Text(analysis.insight)
                                    .font(.system(size: 15))
                                    .foregroundStyle(.secondary)
                            }

                            if !analysis.unexploredSuggestions.isEmpty {
                                Text("Try Next")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                    .textCase(.uppercase)

                                VStack(spacing: 10) {
                                    ForEach(analysis.unexploredSuggestions) { suggestion in
                                        HStack {
                                            VStack(alignment: .leading, spacing: 3) {
                                                Text(suggestion.label)
                                                    .font(.system(size: 15, weight: .semibold))
                                                Text("\(suggestion.direction) · \(Int(suggestion.distanceFromYouM)) m away")
                                                    .font(.system(size: 13))
                                                    .foregroundStyle(.secondary)
                                            }
                                            Spacer()
                                        }
                                        .padding(14)
                                        .background(.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                    }
                                }
                            }
                        }
                        .padding(20)
                    }
                } else {
                    ContentUnavailableView("No Walk History Yet",
                                           systemImage: "point.3.connected.trianglepath.dotted",
                                           description: Text(routeCount == 0
                                                             ? "Start a trip or AR walk and we’ll begin tracking your explored city."
                                                             : "We couldn’t analyze your saved walks right now."))
                }
            }
            .navigationTitle("City Coverage")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

private func sheetCard(title: String, body: String) -> some View {
    VStack(alignment: .leading, spacing: 6) {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
        Text(body)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(.primary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(14)
    .background(.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
}

private struct FlexibleTagRow: View {
    let tags: [String]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(tags, id: \.self) { tag in
                    Text(tag)
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 11)
                        .padding(.vertical, 7)
                        .background(Color.blue.opacity(0.08), in: Capsule())
                }
            }
        }
    }
}

private struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Document Picker

private struct DocumentPickerView: UIViewControllerRepresentable {
    let allowedContentTypes: [String]
    let completion: (URL?) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let types: [UTType] = allowedContentTypes.compactMap { UTType($0) ?? UTType(filenameExtension: $0) }
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types)
        picker.allowsMultipleSelection = false
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ vc: UIDocumentPickerViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(completion: completion) }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let completion: (URL?) -> Void
        init(completion: @escaping (URL?) -> Void) { self.completion = completion }
        func documentPicker(_ c: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) { completion(urls.first) }
        func documentPickerWasCancelled(_ c: UIDocumentPickerViewController) { completion(nil) }
    }
}

// MARK: - Shimmer

private struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = -1.2

    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { _ in
                    LinearGradient(
                        stops: [
                            .init(color: .clear,               location: 0.0),
                            .init(color: .white.opacity(0.30), location: 0.45),
                            .init(color: .white.opacity(0.48), location: 0.50),
                            .init(color: .white.opacity(0.30), location: 0.55),
                            .init(color: .clear,               location: 1.0),
                        ],
                        startPoint: UnitPoint(x: phase,       y: 0.5),
                        endPoint:   UnitPoint(x: phase + 1.2, y: 0.5)
                    )
                    .blendMode(.overlay)
                    .allowsHitTesting(false)
                }
            )
            .onAppear {
                withAnimation(.linear(duration: 1.3).repeatForever(autoreverses: false)) {
                    phase = 1.4
                }
            }
    }
}

private extension View {
    func shimmering() -> some View { modifier(ShimmerModifier()) }
}
