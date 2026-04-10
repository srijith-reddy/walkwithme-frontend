import SwiftUI

struct TurnPanel: View {
    let distance: Double
    let instruction: String

    var body: some View {
        HStack(spacing: 0) {

            // ── Accent icon column ─────────────────────────────────────────
            ZStack {
                accentColor
                Image(systemName: iconForInstruction(instruction))
                    .font(.system(size: 28, weight: .black))
                    .foregroundStyle(.white)
            }
            .frame(width: 70)
            .clipShape(
                UnevenRoundedRectangle(
                    topLeadingRadius: 18, bottomLeadingRadius: 18,
                    bottomTrailingRadius: 0, topTrailingRadius: 0,
                    style: .continuous
                )
            )

            // ── Instruction text ───────────────────────────────────────────
            VStack(alignment: .leading, spacing: 3) {
                if distance > 8 {
                    Text(distanceLabel)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(accentColor)
                        .tracking(0.6)
                }
                Text(instruction)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minHeight: 72)
        .background(Color.black.opacity(0.82))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(accentColor.opacity(0.28), lineWidth: 1)
        )
        .shadow(color: accentColor.opacity(0.38), radius: 22, y: 6)
    }

    // MARK: - Helpers

    private var accentColor: Color {
        let t = instruction.lowercased()
        if t.contains("arrive") || t.contains("destination") { return .green }
        if t.contains("u-turn") || t.contains("uturn")       { return .orange }
        return Color(red: 0.14, green: 0.56, blue: 1.0)
    }

    private var distanceLabel: String {
        if distance < 1000 { return "IN \(Int(distance)) M" }
        return String(format: "IN %.1f KM", distance / 1000)
    }

    private func iconForInstruction(_ text: String) -> String {
        let t = text.lowercased()
        if t.contains("left")                                { return "arrow.turn.up.left" }
        if t.contains("right")                               { return "arrow.turn.up.right" }
        if t.contains("u-turn") || t.contains("uturn")      { return "arrow.uturn.left" }
        if t.contains("arrive") || t.contains("destination") { return "flag.checkered" }
        if t.contains("roundabout") || t.contains("circle")  { return "arrow.clockwise" }
        return "arrow.up"
    }
}
