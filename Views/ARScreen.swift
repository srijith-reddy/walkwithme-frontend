import SwiftUI
import RealityKit
import ARKit

struct ARScreen: View {
    let route: Route

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var debug          = YOLODebugOverlay.shared
    @ObservedObject private var arSession      = ARSessionManager.shared
    @ObservedObject private var steps          = StepCountManager.shared
    @ObservedObject private var hazardOverlay  = HazardOverlayManager.shared

    @State private var appeared = false

    var body: some View {
        ZStack {
            // ── AR CAMERA ──────────────────────────────────────────────────
            ARViewContainer()
                .ignoresSafeArea()

            // ── HAZARD EDGE GLOW (2-D, no AR entities) ────────────────────
            HazardEdgeView(positions: hazardOverlay.activeHazardPositions)
                .ignoresSafeArea()

            // ── YOLO DEBUG BOXES (off by default) ──────────────────────────
            if DebugSettings.showYOLOBoxes {
                GeometryReader { geo in
                    ForEach(Array(debug.boxes.enumerated()), id: \.offset) { i, box in
                        let w = box.width  * geo.size.width
                        let h = box.height * geo.size.height
                        let x = box.midX   * geo.size.width
                        let y = (1 - box.midY) * geo.size.height
                        ZStack(alignment: .topLeading) {
                            Rectangle().stroke(Color.red, lineWidth: 2).frame(width: w, height: h)
                            if i < debug.labels.count {
                                Text(debug.labels[i])
                                    .font(.caption2).bold().padding(4)
                                    .background(Color.red.opacity(0.9))
                                    .foregroundColor(.white)
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                                    .offset(x: 2, y: 2)
                            }
                        }
                        .position(x: x, y: y)
                    }
                }
                .allowsHitTesting(false)
            }

            // ── CLOSE BUTTON (top-right) ───────────────────────────────────
            VStack {
                HStack {
                    Spacer()
                    Button {
                        arSession.stopSession()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 40, height: 40)
                            .background(.ultraThinMaterial, in: Circle())
                            .overlay(Circle().strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
                            .shadow(color: .black.opacity(0.22), radius: 8, y: 2)
                            .padding(.top, 8)
                            .padding(.trailing, 16)
                    }
                }
                Spacer()
            }

            // ── BOTTOM STATUS PILL ─────────────────────────────────────────
            VStack {
                Spacer()
                arStatusPill
                    .padding(.bottom, 44)
            }
        }
        .opacity(appeared ? 1 : 0)
        .onAppear {
            startSession()
            withAnimation(.easeIn(duration: 0.28)) { appeared = true }
        }
        .onDisappear {
            WalkHistoryStore.shared.record(route: route)
            arSession.stopSession()
        }
    }

    // MARK: - Bottom status pill

    private var arStatusPill: some View {
        HStack(spacing: 14) {
            HStack(spacing: 5) {
                Image(systemName: "figure.walk")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(distanceRemainingLabel)
                    .font(.system(size: 14, weight: .semibold))
                    .monospacedDigit()
            }

            Rectangle()
                .fill(Color.primary.opacity(0.15))
                .frame(width: 1, height: 14)

            HStack(spacing: 5) {
                Image(systemName: "shoeprints.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.purple)
                Text("\(steps.sessionSteps)")
                    .font(.system(size: 14, weight: .semibold))
                    .monospacedDigit()
                Text("steps")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.15), radius: 10, y: 3)
    }

    private var distanceRemainingLabel: String {
        let m = arSession.distanceRemainingM
        if m <= 0   { return "—" }
        if m < 1000 { return String(format: "%.0f m", m) }
        return String(format: "%.1f km", m / 1000)
    }
}

// MARK: - Session start

extension ARScreen {
    private func startSession() {
        YOLODetector.shared.forceCPUOnly = true
        YOLODetector.shared.debugOverlayEnabled = DebugSettings.showYOLOBoxes
        StepCountManager.shared.beginSession()
        ARSessionManager.shared.loadRoute(route)
    }
}

// MARK: - Hazard edge glow overlay

/// Renders subtle directional glows at the screen edges to indicate nearby hazards.
/// Left hazard → left-edge amber/red glow. Right → right. Straight → bottom.
private struct HazardEdgeView: View {
    let positions: [(label: String, normalizedX: Float)]

    @State private var pulse = false

    var body: some View {
        ZStack {
            ForEach(Array(positions.enumerated()), id: \.offset) { _, h in
                edgeGlow(for: h)
            }
        }
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }

    @ViewBuilder
    private func edgeGlow(for hazard: (label: String, normalizedX: Float)) -> some View {
        let color = tintColor(for: hazard.label)
        let x     = CGFloat(hazard.normalizedX)
        let opacity: CGFloat = pulse ? 0.42 : 0.18

        if x < 0.35 {
            // Left-side hazard
            HStack(spacing: 0) {
                LinearGradient(
                    colors: [color.opacity(opacity), .clear],
                    startPoint: .leading, endPoint: .trailing
                )
                .frame(width: 88)
                Spacer()
            }
        } else if x > 0.65 {
            // Right-side hazard
            HStack(spacing: 0) {
                Spacer()
                LinearGradient(
                    colors: [.clear, color.opacity(opacity)],
                    startPoint: .leading, endPoint: .trailing
                )
                .frame(width: 88)
            }
        } else {
            // Straight-ahead hazard — bottom warning strip
            VStack(spacing: 0) {
                Spacer()
                LinearGradient(
                    colors: [.clear, color.opacity(opacity * 0.85)],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(height: 120)
            }
        }
    }

    private func tintColor(for label: String) -> Color {
        switch label {
        case "car", "truck", "bus":         return .red
        case "bike", "bicycle", "motorcycle": return .orange
        case "person", "people", "crowd":   return .yellow
        default:                             return .orange
        }
    }
}
