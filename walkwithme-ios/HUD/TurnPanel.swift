// TurnPanel.swift
import SwiftUI

struct TurnPanel: View {
    let distance: Double
    let instruction: String

    var body: some View {
        HStack(spacing: 12) {

            Image(systemName: iconForInstruction(instruction))
                .font(.system(size: 28, weight: .semibold))
                .foregroundColor(.blue)

            VStack(alignment: .leading, spacing: 2) {
                Text(instruction)
                    .font(.headline)
                Text("\(Int(distance)) m")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(radius: 4)
    }

    private func iconForInstruction(_ text: String) -> String {
        let t = text.lowercased()
        if t.contains("left") { return "arrow.turn.up.left" }
        if t.contains("right") { return "arrow.turn.up.right" }
        if t.contains("straight") { return "arrow.up" }
        return "arrow.up"
    }
}
