# WalkWithMe iOS Frontend — AR Pedestrian Navigation, Hazard Awareness, and Backend-Driven City Walking

This repository contains the iOS frontend for WalkWithMe, a pedestrian-first navigation and city exploration app designed to support route discovery, AR walking guidance, live hazard awareness, map-based fallback navigation, GPX import, and step-aware walking experiences.

The app is built with SwiftUI, ARKit, RealityKit, MapKit, CoreLocation, HealthKit, Core Motion, Vision, and a bundled YOLO Core ML model. It is designed to pair with the WalkWithMe backend for routing, place search, reverse geocoding, GPX parsing, and lightweight hazard interpretation, while keeping real-time camera perception and AR rendering on device.

The system is designed for walking-first experiences rather than car navigation, and it prioritizes mobile-native interaction, graceful degradation, and real-time responsiveness on a physical iPhone.

---

System Responsibilities

The frontend is responsible for:

- Presenting route search and route mode selection
- Rendering backend-provided walking geometry on a live map
- Launching AR navigation from computed routes
- Displaying turn-by-turn instructions and distance cues
- Running on-device hazard detection from the camera feed
- Estimating hazard distance using LiDAR, monocular depth, or visual fallback heuristics
- Fusing backend hazard hints with on-device detections for AR presentation
- Rendering AR route anchors, chevrons, markers, and hazard overlays
- Providing a live AR HUD with compass, minimap, and turn banners
- Supporting map-based fallback navigation with Apple Maps directions
- Importing GPX files and visualizing imported paths
- Tracking today and session step counts during walking sessions
- Handling location, heading, camera, motion, and health permissions
- Providing a mobile-first UI for route preview, walking stats, and navigation launch

---

High-Level Architecture

The frontend is structured as a layered native iOS application:

App Layer
- `WalkWithMeApp.swift` initializes the app and starts step-count services
- `Views/ContentView.swift` boots directly into the route experience
- `Views/RouteView.swift` is the primary search, route preview, and launch surface

Networking Layer
- `Utils/API.swift` handles backend requests for route generation, autocomplete, POI search, reverse geocoding, and GPX import
- `BackendConfig.swift` stores the backend base URL used by the vision uploader
- Async/await networking with typed decoding and bounded timeouts

Routing and Navigation Layer
- `Utils/RouteViewModel.swift` owns route fetch state for the main route screen
- `Utils/NavigationManager.swift` manages backend route state for map navigation flows
- `Views/SimpleNavigator.swift` provides Apple Maps first, backend fallback, turn-aware map navigation

AR and Perception Layer
- `AR/ARSessionManager.swift` coordinates AR world setup, route anchoring, HUD updates, and hazard upload
- `AR/YOLODetector.swift` runs the bundled Core ML object detector on-device
- `AR/DepthEstimator.swift` estimates distance to hazards using scene depth, Vision depth, or size heuristics
- `AR/HazardFiltering.swift` suppresses noise and ranks only the highest-value hazards
- `AR/HazardFusion.swift` merges backend hazard hints with on-device detections

HUD and Presentation Layer
- `HUD/ARHUDManager.swift` manages the AR compass and live minimap
- `HUD/TurnHUDManager.swift` manages turn instruction overlays in AR
- `HUD/YOLODebugOverlay.swift` and `HUD/FusionDebugOverlay.swift` support debugging and tuning

System Services
- `Utils/LocationManager.swift` handles user location, heading, and speed
- `StepCountManager.swift` integrates HealthKit and Core Motion for day/session steps

Bundled Assets and Models
- `yolo11n.mlpackage/` contains the on-device Core ML detection model
- `Assets.xcassets/` contains app icons and UI assets

---

Application Flow

Typical runtime flow:

1. The user enters a start and destination or uses current location
2. The route screen calls the backend for route generation
3. The returned route geometry, steps, and scores are rendered in the route preview UI
4. The user launches either AR navigation or map navigation
5. AR mode anchors route geometry into the world and starts the HUD update loop
6. Camera frames are analyzed on device by YOLO
7. Hazard detections are distance-estimated, filtered, optionally enriched with backend hints, and rendered into AR
8. Turn instructions, minimap, compass, and walking stats update continuously while the user walks

---

Core User Experiences

Route Search and Preview
- Search by typed address, POI query, or raw coordinates
- Supports walking modes: `loop`, `scenic`, `explore`, `best`, `safe`, `shortest`, `elevation`
- Displays route distance, duration, steps estimate, elevation gain, and backend scores when available
- Supports step preview sheets for turn-by-turn browsing

AR Navigation
- Full-screen AR session with RealityKit route markers and chevrons
- Route anchored relative to the user’s current position
- Live distance remaining pill
- AR-specific turn HUD and compass/minimap overlay
- Designed to function without blocking on perfect GPS lock before UI appears

Map Navigation Fallback
- Standard map navigation view using `MKMapView`
- Prefers Apple walking directions when available
- Falls back to backend-provided route geometry and steps when Apple routing fails
- Displays instructions, distance to next turn, and ETA

Hazard Awareness
- On-device object detection for people, vehicles, bikes, dogs, and select traffic objects
- Distance estimation from LiDAR when available
- Monocular Vision depth fallback on supported devices
- Bounding-box-based heuristic fallback when depth is unavailable
- Conservative filtering to reduce alarm fatigue
- Top hazard selection with severity scoring and AR placement

GPX Import
- Uploads a GPX file to the backend
- Decodes returned coordinates and elevation analysis
- Converts imported data into the app’s route model for preview and navigation

Walking Metrics
- Day-total steps via HealthKit
- Session steps via Core Motion pedometer
- Step tracking starts automatically at app launch and resets per navigation session

---

High-Level UI Architecture

Primary views:

- `Views/RouteView.swift`
  The main search, route mode, preview, and launch interface.

- `Views/ARScreen.swift`
  Full-screen AR navigation with route overlays and hazard rendering.

- `Views/SimpleNavigationView.swift`
  Map-based turn display backed by Apple Maps or backend routing fallback.

Supporting presentation components:

- `HUD/TurnPanel.swift`
- `HUD/TurnBannerView.swift`
- `HUD/MiniMapView.swift`
- `Views/Route+MapKit.swift`
- `AR/MapKit.swift`

SwiftUI remains intentionally thin. Most stateful navigation, AR, detection, and integration logic lives in dedicated manager objects rather than the view layer.

---

Perception and Hazard Pipeline

Hazard detection is primarily an on-device pipeline with optional backend reinforcement.

Pipeline flow:

1. ARKit provides camera frames and scene depth where supported
2. `YOLODetector` runs the bundled `yolo11n` Core ML model
3. Only hazard-relevant classes are retained
4. Non-max suppression and per-class confidence thresholds reduce noise
5. `DepthEstimator` computes distance using:
   - AR scene depth
   - Vision monocular depth
   - bounding-box heuristic fallback
6. `HazardFiltering` applies:
   - minimum box size filtering
   - near-person suppression when stationary
   - crowd clustering
   - forward-cone filtering
   - severity ranking
7. `VisionUploader` optionally sends detection metadata to the backend `/vision` endpoint
8. `HazardFusion` boosts or confirms selected hazards using backend labels when present
9. `HazardOverlayManager` renders the final top hazards in AR

Hazard classes currently emphasized:
- `person`
- `car`, `truck`, `bus`
- `bike`, `bicycle`, `motorcycle`
- `dog`
- `stop_sign`, `traffic_light`

---

AR Navigation Architecture

`ARSessionManager` is the core runtime coordinator for AR mode.

Responsibilities:

- Configuring the AR session
- Managing world anchors
- Placing start and end markers
- Sampling route geometry into world-space chevrons
- Updating compass, minimap, and turn HUD on a timer
- Tracking distance remaining
- Running the camera perception loop
- Uploading hazard metadata to the backend
- Cleaning up AR resources on dismiss

AR route rendering includes:
- Start marker
- End marker
- Repeated route chevrons sampled approximately every 20 meters
- Hazard entities placed relative to camera and path context

HUD components in AR:
- Compass
- Live rotating minimap
- Turn panel
- Optional YOLO and fusion debug overlays

---

Backend Integration

The frontend is backend-driven, but it does not currently use every backend endpoint described in the backend system design.

Endpoints currently integrated in this repo:

- `GET /route`
- `GET /autocomplete`
- `GET /places_search`
- `GET /reverse_geocode`
- `POST /import_gpx`
- `POST /vision`

Frontend expectations for route responses:
- route `mode`
- decoded `coordinates`
- optional `waypoints`
- optional `distance_m` and `duration_s`
- optional `summary`
- optional `steps`
- optional `elevation`
- optional `safety_score`, `scenic_score`, `ai_best_score`
- optional `next_turn`
- optional `places`

Important integration note:

The app currently hardcodes the backend URL in two places:
- `Utils/API.swift`
- `BackendConfig.swift`

If you change environments, update both unless you centralize the configuration first.

---

Route and Search Integration

The frontend supports:

- Route fetches by coordinate pair
- Loop mode requests without an end coordinate
- Address-style autocomplete
- POI-style free-text search
- Reverse geocoding for dropped pins
- GPX import via multipart upload

Current route mode surface in the UI:
- Loop
- Scenic
- Explore
- AI Best
- Safe
- Fastest
- Hilly

Current client limitations relative to the backend:
- The frontend does not yet request `enrich=true`
- The frontend does not yet request `elevation=true` on normal route fetches
- The frontend does not yet send `loop_theme`
- The frontend does not yet consume the richer backend enrichment block described for landmarks, food, parks, highlights, and neighborhood flavor
- The frontend does not currently expose endpoints like `/detours`, `/persona`, `/themes`, `/nearby`, `/export_gpx`, or `/walks/analyze`

---

Location, Heading, and Motion

The app uses:

- `CoreLocation` for user position and heading
- `MapKit` for map rendering and Apple route fallback
- `HealthKit` for daily step counts
- `Core Motion` pedometer updates for active walking sessions

Location behavior:
- High-accuracy GPS
- Heading updates enabled
- Speed estimation from `CLLocation`
- Short distance and heading filters tuned for walking

Step behavior:
- App launch initializes step services
- Session step count begins when navigation starts
- Session count ends when navigation ends

---

Repository Structure

Top-level layout:

```text
.
├── AR/
│   ├── AR session, routing anchors, hazard rendering, depth, YOLO, fusion
├── HUD/
│   ├── AR HUD, turn panels, debug overlays, minimap
├── Models/
│   ├── Route, step, and place response models
├── Utils/
│   ├── API client, view models, navigation manager, location utilities
├── Views/
│   ├── Route UI, AR screen, map navigation, SwiftUI presentation
├── Assets.xcassets/
│   ├── App icons and asset catalog
├── yolo11n.mlpackage/
│   ├── Bundled Core ML detection model
├── WalkWithMeApp.swift
├── BackendConfig.swift
└── StepCountManager.swift
```

Notable files:

- `Views/RouteView.swift`
  Main entry screen and user-facing route workflow.

- `Utils/API.swift`
  Typed backend client for core app networking.

- `AR/ARSessionManager.swift`
  Central AR runtime coordinator.

- `AR/YOLODetector.swift`
  On-device object detection pipeline.

- `AR/DepthEstimator.swift`
  Hazard distance estimation pipeline.

- `AR/HazardFiltering.swift`
  Noise reduction and ranking logic for hazards.

- `Views/SimpleNavigator.swift`
  Apple Maps first, backend fallback map navigation.

- `StepCountManager.swift`
  HealthKit and pedometer integration.

---

Build Requirements

Requirements:

- Xcode with iOS SDK support for ARKit, RealityKit, Vision, and Core ML
- A physical iPhone for AR functionality
- Camera, location, motion, and Health permissions
- A reachable WalkWithMe backend deployment

Simulator support:
- Route UI and some map flows can be exercised in Simulator
- AR navigation, real camera perception, and depth-dependent features require a real device

Bundled model requirement:
- `yolo11n.mlpackage` must remain included in the target for on-device hazard detection to work

---

Configuration

This frontend does not currently use a `.env`-style configuration system. Backend configuration is compiled into source.

Current backend configuration locations:

- `Utils/API.swift`
  Base URL used for route, search, reverse geocode, and GPX import

- `BackendConfig.swift`
  Base URL used for `/vision`

Before running against a different backend environment, update both values.

Additional operational requirements:

- The backend must expose the expected WalkWithMe API contract
- The `/vision` endpoint should be available if backend hazard confirmation is desired
- Google Places-backed POI search depends on backend support, not frontend configuration

---

Permissions

The app currently declares usage for:

- Camera
- Location when in use
- Motion
- Health data read access for step count

These permissions support:

- AR navigation and hazard detection
- Live user location and heading
- Step counting during walking sessions

---

Local Development

Open and run:

```bash
open walkwithme.xcodeproj
```

Suggested local workflow:

1. Open the project in Xcode
2. Select a physical iPhone for AR testing
3. Confirm the backend base URL in `Utils/API.swift`
4. Confirm the backend base URL in `BackendConfig.swift`
5. Build and run
6. Grant camera, location, motion, and Health permissions when prompted

Recommended smoke test:

1. Search for a route in `RouteView`
2. Preview the route card and turn list
3. Launch AR navigation
4. Confirm compass, minimap, and route chevrons appear
5. Confirm hazard overlays appear when relevant detections are in frame
6. Confirm map fallback navigation opens for non-loop routes

---

Design Principles

- Pedestrian-first, not car-centric
- AR as an enhancement, not a gimmick
- Real-time perception should stay on device when possible
- Backend integration should remain thin and typed
- SwiftUI for presentation, managers for stateful runtime systems
- Graceful fallback when a subsystem is unavailable
- Debuggable perception and navigation tooling for iteration
- Walking UX should stay lightweight, glanceable, and non-intrusive

---

Current Status

Active development

This repository contains the iOS frontend only. It is intended to pair with the WalkWithMe backend and currently provides route preview, AR navigation, hazard awareness, GPX import, Apple Maps fallback navigation, and walking metrics on iPhone.
