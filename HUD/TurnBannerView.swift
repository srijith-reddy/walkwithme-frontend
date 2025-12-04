import SwiftUI

struct TurnBannerView: View {
    let turnDirection: String?       // "left", "right", "straight"
    let distance: Double?            // meters
    let streetName: String?          // "Heath Ln"
    let isClose: Bool                // < 25m etc

    @State private var popOffset: CGFloat = 60
    @State private var chevronPulse = false

    var body: some View {
        VStack(spacing: 10) {

            // ---------------------------------------------------
            // STREET NAME PILL (like “Heath Ln”)
            // ---------------------------------------------------
            if let streetName {
                Text(streetName)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 14)
                    .background(Color.blue.opacity(0.85))
                    .cornerRadius(12)
                    .shadow(radius: 5)
            }

            // ---------------------------------------------------
            // BIG DIRECTION ARROWS <<< or >>>
            // ---------------------------------------------------
            if let dir = turnDirection {
                HStack(spacing: 12) {
                    ForEach(0..<3) { _ in
                        Image(systemName: chevronSymbol(for: dir))
                            .font(.system(size: 40, weight: .bold))
                            .foregroundColor(.white)
                            .opacity(chevronPulse ? (isClose ? 1 : 0.8) : 0.3)
                    }
                }
                .animation(
                    .easeInOut(duration: 0.6).repeatForever(autoreverses: true),
                    value: chevronPulse
                )
                .onAppear { chevronPulse = true }
            }

            // ---------------------------------------------------
            // DISTANCE BELOW ARROWS (“59m”)
            // ---------------------------------------------------
            if let distance {
                Text("\(Int(distance)) m")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.white.opacity(0.9))
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 12)
        .background(.ultraThinMaterial.opacity(0.25))
        .cornerRadius(20)
        .shadow(radius: 8)
        .offset(y: popOffset)
        .animation(.spring(response: 0.45, dampingFraction: 0.7), value: popOffset)
        .onAppear { popOffset = 0 }
    }

    // MARK: - Direction → System Image
    private func chevronSymbol(for dir: String) -> String {
        switch dir.lowercased() {
        case "left": return "arrowshape.turn.up.left.fill"
        case "right": return "arrowshape.turn.up.right.fill"
        default: return "arrow.up"
        }
    }
}
