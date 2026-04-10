# WalkWithMe iOS Frontend

WalkWithMe is a pedestrian-first navigation app built for city walking. It helps users discover routes, preview them on a map, launch turn-by-turn guidance, and navigate with an AR experience designed for real-world walking instead of car travel.

This repository contains the native iOS frontend. The app is built with SwiftUI and pairs with a backend that provides routing, search, place discovery, GPX support, themed walk suggestions, and walk-history analysis.

## Overview

The frontend is responsible for the user-facing experience of the product:

- route search and route preview
- AR walking guidance
- map-based fallback navigation
- hazard awareness using on-device detection
- nearby place discovery and route detours
- GPX import and export
- step tracking and walk-history analysis

The app is designed for iPhone and aims to balance a polished interface with real-time responsiveness on a physical device.

## Key Features

### Route Planning

- Search using your current location, typed places, coordinates, or dropped pins
- Generate routes for different walking goals including `loop`, `scenic`, `explore`, `best`, `safe`, `shortest`, and `elevation`
- Review route distance, duration, turns, and supporting route details before starting
- Preview step-by-step directions directly from the planning screen

### Navigation

- Launch a full-screen AR navigation experience for walking guidance
- Use a map-based navigator when AR is not needed or not available
- Show turn instructions, distance remaining, and navigation context while walking

### Loop Assistant

- Open a conversational sheet to describe any kind of walk in plain text (e.g. "food walk in East Village" or "quick 20 min loop")
- Pick from mood chips — Food, Scenic, Landmark, Quick, Chill, Surprise — to instantly trigger a curated search
- Receive up to three ranked loop suggestions, each with a title, theme badge, duration, distance, highlights, and suggested stops
- Bookmark any loop for later and re-launch saved loops directly from the Saved section without re-querying
- Loading skeleton cards keep the UI responsive while results are fetched

### Smart Exploration

- Load themed walking suggestions from the backend
- Show nearby places relevant to the current area
- Suggest route detours when they add useful or interesting stops
- Surface persona-style route suggestions for different walking moods or preferences

### Safety and Awareness

- Run on-device object detection during AR navigation
- Estimate how far detected hazards are from the user
- Highlight the most relevant hazards in the AR scene
- Blend backend hints with on-device results where applicable

### GPX and Walk History

- Import GPX files and turn them into route previews
- Export active routes as GPX files
- Track walking sessions and step counts
- Analyze saved walks to show local coverage and unexplored areas

## Tech Stack

- SwiftUI
- ARKit
- RealityKit
- MapKit
- CoreLocation
- HealthKit
- Core Motion
- Vision
- Core ML

## Architecture

The codebase is organized into focused layers so product flows remain easier to reason about and extend.

### App Entry

- `WalkWithMeApp.swift` starts the app and initializes step tracking
- `Views/ContentView.swift` serves as the top-level view

### Core Screens

- `Views/RouteView.swift` is the main planning and route-preview experience
- `Views/ARScreen.swift` presents the AR navigation flow
- `Views/SimpleNavigationView.swift` handles map-based navigation

### Networking and State

- `Utils/API.swift` contains the backend client
- `Utils/RouteViewModel.swift` manages route-loading state for the main screen
- `Utils/NavigationManager.swift` supports navigation-related route state
- `Utils/WalkHistoryStore.swift` stores completed walk data for later analysis

### AR and Hazard Awareness

- `AR/ARSessionManager.swift` coordinates the AR experience
- `AR/YOLODetector.swift` runs the bundled object-detection model
- `AR/DepthEstimator.swift` estimates distance to detected objects
- `AR/HazardFiltering.swift` reduces noise and prioritizes relevant hazards
- `AR/HazardFusion.swift` combines backend and on-device hazard context
- `AR/HazardOverlayManager.swift` manages hazard indicators in the AR experience

### Loop Assistant

- `Views/LoopAssistantSheet.swift` is the bottom-sheet UI: search bar, mood chips, results, saved loops, and loading skeletons
- `Models/LoopAssistant.swift` defines `LoopOption`, `LoopOrigin`, and `LoopAssistantResponse` decoded from `/loop_assistant`
- `Utils/LoopFavoritesStore.swift` persists bookmarked loops to UserDefaults via a shared `@MainActor` store

### UI Support

- `HUD/` contains turn banners, minimap UI, debug overlays, and AR heads-up-display components
- `Models/` contains route, step, and related response models
- `Assets.xcassets/` contains app icons and bundled visual assets

## Repository Structure

```text
.
├── AR/
├── HUD/
├── Models/
│   └── LoopAssistant.swift
├── Utils/
│   └── LoopFavoritesStore.swift
├── Views/
│   └── LoopAssistantSheet.swift
├── Assets.xcassets/
├── walkwithme.xcodeproj/
├── WalkWithMeApp.swift
├── BackendConfig.swift
├── StepCountManager.swift
├── yolo11n.mlpackage/
└── README.md
```

## Application Flow

At a high level, the user journey looks like this:

1. The user selects a start point and destination, or requests a loop route.
2. The app requests route data from the backend.
3. The route is shown in the planning interface with summary details and turn steps.
4. The user launches either AR navigation or map navigation.
5. During AR navigation, the app renders route guidance and performs hazard detection on device.
6. Completed walks can be stored for later review and analysis.

## Backend Integration

The frontend depends on a backend deployment for routing and several discovery features.

The current backend base URL is:

`https://walkwithme-app-mw2xs.ondigitalocean.app`

It is currently defined in:

- `Utils/API.swift`
- `BackendConfig.swift`

If the backend environment changes, both locations should be updated unless configuration is centralized later.

### Endpoints Used by the App

- `GET /route`
- `GET /autocomplete`
- `GET /places_search`
- `GET /reverse_geocode`
- `GET /persona`
- `GET /themes`
- `GET /themes/:id`
- `GET /nearby`
- `GET /detours`
- `GET /export_gpx`
- `POST /import_gpx`
- `POST /vision`
- `POST /walks/analyze`
- `POST /loop_assistant`

## On-Device Detection

The AR experience includes a local detection pipeline powered by the bundled Core ML model in `yolo11n.mlpackage`.

In practical terms, the app:

- reads live camera frames during AR navigation
- runs object detection on device
- estimates distance using available depth information or fallback logic
- filters noisy detections
- renders only the most relevant hazards for the user

This keeps the experience responsive and reduces dependence on round trips to the backend during navigation.

## Running the App

### Requirements

- Xcode
- an iPhone for the full AR experience
- camera, location, and motion permissions
- Health permissions if step tracking is needed
- access to the configured backend

### Setup

1. Open `walkwithme.xcodeproj` in Xcode.
2. Select the `walkwithme` scheme.
3. Choose a physical iPhone for AR testing.
4. Build and run the app.

The app launches into the main route-planning experience.

### Recommended Smoke Test

1. Search for a route from the main screen.
2. Confirm the route preview loads with summary information.
3. Open the turn list.
4. Launch map navigation.
5. Launch AR navigation on device.
6. Verify that route guidance, minimap UI, and navigation overlays appear.

## Permissions

The app relies on the following permissions:

- Camera
- Location
- Motion
- Health data access for step tracking

These are used for navigation, AR guidance, hazard awareness, and walking metrics.

## Development Notes

- This repository is the iOS app even though the repo name includes `frontend`.
- The project includes bundled model assets, so repository size and push times may be larger than a typical SwiftUI app.
- Some features depend directly on backend response structure and availability.
- The current project stores backend configuration in source rather than through environment-based config.

## Main Files to Know

- `WalkWithMeApp.swift`
- `Views/RouteView.swift`
- `Views/ARScreen.swift`
- `Views/SimpleNavigationView.swift`
- `Views/LoopAssistantSheet.swift`
- `Utils/API.swift`
- `Utils/RouteViewModel.swift`
- `Utils/LoopFavoritesStore.swift`
- `Models/LoopAssistant.swift`
- `AR/ARSessionManager.swift`
- `Utils/WalkHistoryStore.swift`

## Current State

The app already supports route planning, AR guidance, map fallback navigation, hazard awareness, GPX workflows, step tracking, route exploration features, walk analysis, and the Loop Assistant with favorites.
