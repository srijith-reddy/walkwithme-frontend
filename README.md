# WalkWithMe iOS Frontend — AR Pedestrian Navigation

WalkWithMe is an iOS frontend application that combines ARKit, RealityKit, MapKit, CoreLocation, and on-device computer vision to deliver pedestrian navigation with real-time hazard awareness.

This frontend is designed as a production-grade system, not a demo. It supports live routing, turn-by-turn guidance, AR world anchoring, vision-based hazard detection, fallback navigation strategies, and developer-friendly debugging overlays, all while remaining battery-aware and non-intrusive for continuous walking use.

---

Overview

The app allows users to:
- Search for routes using multiple routing modes
- Preview routes on a live map
- Navigate using either AR or standard map navigation
- Receive turn-by-turn instructions
- Detect and visualize nearby hazards using the device camera
- Import GPX routes
- Fall back to Apple Maps navigation when needed

SwiftUI is used for structure and layout, while all real-time logic is handled by dedicated manager objects.

---

Core Features

Routing and Navigation
- Backend-driven pedestrian routing
- Modes supported: shortest, safe, scenic, explore, elevation, AI best, loop
- Full route preview with polylines, start/end markers
- Turn instructions with distance and ETA
- GPX import for custom routes
- Automatic fallback to Apple Maps walking navigation when backend routing is unavailable

AR Navigation
- RealityKit and ARKit based AR session
- Immediate AR startup without GPS blocking loops
- Route anchors placed in real-world coordinates
- AR navigation independent of map navigation
- Designed for continuous walking scenarios

Hazard Awareness
- Live camera feed processed on-device using YOLO
- Vision detections fused with depth estimation
- Temporal smoothing and spatial filtering
- Hazards rendered as camera-relative AR overlays
- Automatic cleanup of stale hazards
- Works with LiDAR or monocular depth fallback

---

High-Level Architecture

SwiftUI Layer
- ContentView
- RouteView
- ARScreen
- TurnPanel

Managers and Controllers
- NavigationManager
- SimpleNavigator
- ARSessionManager
- ARHUDManager
- TurnHUDManager
- LocationManager
- StepCountManager

Rendering and Perception
- ARViewContainer
- YOLODebugOverlay
- FusionDebugOverlay

Networking
- API client for routing, search, autocomplete, GPX import

SwiftUI is intentionally thin. All real-time logic, navigation state, AR coordination, and perception pipelines live outside views.

---

HUD System

Compass
- Fixed top-left overlay
- Rotates smoothly with device heading
- Minimal animation to avoid motion discomfort

Live Mini-Map
- MKMapView embedded as a HUD overlay
- Two styles:
  - Bottom half-circle minimap
  - Compact floating circular minimap
- Map rotates with heading
- Fixed arrow indicating forward direction
- Live route polyline updates

Turn HUD
- Floating top-center panel
- Displays next instruction and distance
- Automatically hides when no turn is relevant
- Independent of AR hazard rendering

---

Routing Logic

Backend Routing
- Routes fetched from WalkWithMe backend
- Supports geometry, steps, elevation, safety and scenic scores
- Used for AR navigation, map preview, and GPX imports

Apple Maps Fallback
- Uses MKDirections when backend routing is unavailable
- Automatically selected without user intervention
- Uses native Apple Maps step instructions

Step Progression
- Step index advances based on distance thresholds
- Designed to remain stable even with coarse step geometry

---

Location and Motion

- CoreLocation with high-accuracy GPS
- Heading updates enabled
- Speed tracking in meters per second
- Distance filters tuned for pedestrian movement
- Motion and step counting integrated via StepCountManager

---

Debug and Developer Tooling

YOLO Debug Overlay
- Red bounding boxes
- Vision-space normalized coordinates
- SwiftUI overlay for rapid inspection

Fusion Debug Overlay
- Green bounding boxes drawn after hazard fusion
- Verifies filtering, smoothing, and classification logic

Debug Toggles
- showYOLOBoxes
- showFusionBoxes
- showARHazards

All debug layers are optional and non-blocking.

---

Networking

The frontend communicates with a deployed backend for:
- Route generation
- Autocomplete search
- POI search
- Reverse geocoding
- GPX import

Networking uses async/await, bounded timeouts, and fully typed decoding with graceful error handling.

---

Privacy and Permissions

- Camera access required for AR and hazard detection
- Location access required for navigation
- Motion and HealthKit used only for step counting
- No camera frames, videos, or sensor data are persisted
- No background tracking without user interaction

---

Build and Run

Requirements
- Xcode 15 or later
- iOS 17 or later
- Physical device for AR features

Steps
1. Clone the repository
2. Open WalkWithMe.xcodeproj
3. Select a physical device
4. Build and run

Map and routing views work on Simulator. AR requires a real device.

---

Design Principles

- Non-intrusive AR
- Graceful degradation and fallback
- Battery-aware architecture
- Debuggable by design
- Separation of UI and real-time logic

---

Status

Active development

This repository contains the iOS frontend only. Backend services, models, and training pipelines are maintained separately.
