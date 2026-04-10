import SwiftUI
import CoreLocation

// MARK: - Mood Chip Model

private struct Mood: Identifiable {
    let id = UUID()
    let label: String
    let icon: String
    let query: String
}

private let moods: [Mood] = [
    .init(label: "Food",     icon: "fork.knife",         query: "food loop"),
    .init(label: "Scenic",   icon: "leaf",               query: "scenic loop"),
    .init(label: "Landmark", icon: "building.columns",   query: "landmark loop"),
    .init(label: "Quick",    icon: "bolt",               query: "quick 20 min loop"),
    .init(label: "Chill",    icon: "moon.stars",         query: "chill loop"),
    .init(label: "Surprise", icon: "sparkles",           query: "surprise me"),
]

// MARK: - LoopAssistantSheet

struct LoopAssistantSheet: View {

    @ObservedObject var vm: RouteViewModel
    @StateObject private var favorites = LoopFavoritesStore.shared
    var userLocation: CLLocationCoordinate2D?
    var onSelect: (LoopOption, LoopOrigin) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draftQuery   = ""
    @State private var selectedMood: UUID?
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            assistantHeader
            Divider().opacity(0.5)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {

                    // Saved loops — only shown when there are any
                    if !favorites.savedLoops.isEmpty {
                        savedLoopsSection
                            .padding(.top, 20)
                    }

                    moodChipsRow
                        .padding(.top, favorites.savedLoops.isEmpty ? 20 : 0)

                    contentArea
                        .padding(.bottom, 40)
                }
                .padding(.horizontal, 20)
            }
        }
        .background(Color(UIColor.systemGroupedBackground).ignoresSafeArea())
        .onDisappear { vm.clearLoopAssistant() }
    }

    // MARK: - Header

    private var assistantHeader: some View {
        VStack(spacing: 12) {
            Capsule()
                .fill(Color.secondary.opacity(0.3))
                .frame(width: 36, height: 5)
                .padding(.top, 10)

            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color(red: 0.5, green: 0.25, blue: 1.0),
                                     Color(red: 0.2, green: 0.55, blue: 1.0)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 18)

                TextField("Find a great walk…", text: $draftQuery)
                    .font(.system(size: 16))
                    .focused($inputFocused)
                    .disableAutocorrection(true)
                    .textInputAutocapitalization(.never)
                    .submitLabel(.search)
                    .onSubmit { submitQuery() }

                if !draftQuery.isEmpty {
                    Button {
                        draftQuery = ""
                        selectedMood = nil
                        vm.clearLoopAssistant()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                            .font(.system(size: 16))
                    }
                }

                if !draftQuery.isEmpty || vm.isLoadingLoops {
                    Button { submitQuery() } label: {
                        if vm.isLoadingLoops {
                            ProgressView().scaleEffect(0.75).frame(width: 28, height: 28)
                        } else {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 26))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [Color(red: 0.5, green: 0.25, blue: 1.0),
                                                 Color(red: 0.2, green: 0.55, blue: 1.0)],
                                        startPoint: .topLeading, endPoint: .bottomTrailing
                                    )
                                )
                        }
                    }
                    .disabled(vm.isLoadingLoops || draftQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: .black.opacity(0.06), radius: 10, y: 3)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
        .background(Color(UIColor.systemGroupedBackground))
    }

    // MARK: - Saved Loops Section

    private var savedLoopsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Saved")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.8)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(favorites.savedLoops) { saved in
                        SavedLoopPill(saved: saved) {
                            // Tap → launch
                            onSelect(saved.asLoopOption, saved.asLoopOrigin)
                        } onRemove: {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                                favorites.remove(id: saved.id)
                            }
                        }
                    }
                }
                .padding(.horizontal, 1)
                .padding(.vertical, 2)
            }
            .padding(.horizontal, -2)
        }
    }

    // MARK: - Mood Chips

    private var moodChipsRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("What kind of walk?")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.8)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(moods) { mood in
                        moodChip(mood)
                    }
                }
                .padding(.horizontal, 1)
                .padding(.vertical, 2)
            }
            .padding(.horizontal, -2)
        }
    }

    private func moodChip(_ mood: Mood) -> some View {
        let isSelected = selectedMood == mood.id
        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            selectedMood = mood.id
            draftQuery = mood.query
            submitQuery()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: mood.icon).font(.system(size: 12, weight: .semibold))
                Text(mood.label).font(.system(size: 13, weight: .semibold))
            }
            .padding(.horizontal, 14).padding(.vertical, 9)
            .background(
                isSelected
                    ? AnyShapeStyle(LinearGradient(
                        colors: [Color(red: 0.5, green: 0.25, blue: 1.0),
                                 Color(red: 0.2, green: 0.55, blue: 1.0)],
                        startPoint: .topLeading, endPoint: .bottomTrailing))
                    : AnyShapeStyle(Material.regularMaterial),
                in: Capsule()
            )
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .shadow(color: .black.opacity(isSelected ? 0.14 : 0.07), radius: 6, y: 2)
            .animation(.spring(response: 0.22, dampingFraction: 0.72), value: isSelected)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Content Area

    @ViewBuilder
    private var contentArea: some View {
        if vm.isLoadingLoops {
            loadingSkeletonStack
        } else if !vm.loopOptions.isEmpty, let origin = vm.loopOrigin {
            resultsStack(origin: origin)
        } else if let error = vm.loopError {
            errorState(message: error)
        } else if !vm.loopQuery.isEmpty && vm.loopOptions.isEmpty && !vm.isLoadingLoops {
            emptyState
        } else {
            hintState
        }
    }

    // MARK: - Results

    private func resultsStack(origin: LoopOrigin) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            if let summary = vm.loopSummary {
                Text(summary)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            ForEach(Array(vm.loopOptions.enumerated()), id: \.element.id) { _, option in
                LoopOptionCard(
                    option: option,
                    origin: origin,
                    isSaved: favorites.isSaved(id: option.id)
                ) {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    onSelect(option, origin)
                } onBookmark: {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                        if favorites.isSaved(id: option.id) {
                            favorites.remove(id: option.id)
                        } else {
                            favorites.save(option, origin: origin)
                        }
                    }
                }
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .move(edge: .bottom)),
                    removal: .opacity
                ))
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.8), value: vm.loopOptions.count)
    }

    // MARK: - Loading Skeletons

    private var loadingSkeletonStack: some View {
        VStack(spacing: 16) {
            ForEach(0..<3, id: \.self) { i in
                LoopSkeletonCard().opacity(1.0 - Double(i) * 0.2)
            }
        }
        .transition(.opacity)
    }

    // MARK: - Empty / Error / Hint States

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "map.circle")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.secondary)
            VStack(spacing: 6) {
                Text("No loops found")
                    .font(.system(size: 16, weight: .semibold))
                Text("Try Food, Scenic, or Surprise for better results.")
                    .font(.system(size: 14)).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity).padding(.vertical, 48).transition(.opacity)
    }

    private func errorState(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 36, weight: .light)).foregroundStyle(.orange)
            VStack(spacing: 6) {
                Text("Couldn't build loops")
                    .font(.system(size: 16, weight: .semibold))
                Text(message).font(.system(size: 13)).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).lineLimit(3)
            }
            Button { submitQuery() } label: {
                Text("Try again").font(.system(size: 14, weight: .semibold))
                    .padding(.horizontal, 20).padding(.vertical, 10)
                    .background(Color.primary.opacity(0.08), in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 48)
    }

    private var hintState: some View {
        VStack(spacing: 8) {
            Text("Just tell us what you're looking for.")
                .font(.system(size: 15, weight: .medium)).multilineTextAlignment(.center)
            Text("\"loop from 23rd St\" · \"food walk in East Village\" · \"surprise me\"")
                .font(.system(size: 13)).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).lineLimit(3)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 48)
    }

    // MARK: - Actions

    private func submitQuery() {
        let trimmed = draftQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        inputFocused = false
        Task { await vm.generateLoops(query: trimmed, userLat: userLocation?.latitude, userLon: userLocation?.longitude) }
    }
}

// MARK: - SavedLoopPill

private struct SavedLoopPill: View {
    let saved: SavedLoop
    let onTap: () -> Void
    let onRemove: () -> Void

    var body: some View {
        Button { onTap() } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(saved.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Text(saved.durationText)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Text(saved.theme.capitalized)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(themeColor)
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(themeColor.opacity(0.1), in: Capsule())
                    }
                }

                Button {
                    onRemove()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 20, height: 20)
                        .background(Color.secondary.opacity(0.1), in: Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14).padding(.vertical, 11)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.primary.opacity(0.07), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.07), radius: 8, y: 2)
        }
        .buttonStyle(.plain)
    }

    private var themeColor: Color { LoopOptionCard.color(for: saved.theme) }
}

// MARK: - LoopOptionCard

struct LoopOptionCard: View {
    let option: LoopOption
    let origin: LoopOrigin
    var isSaved: Bool = false
    let onTap: () -> Void
    var onBookmark: (() -> Void)? = nil

    var body: some View {
        Button { onTap() } label: { cardContent }
            .buttonStyle(CardPressStyle())
    }

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Theme accent stripe
            LinearGradient(colors: [themeColor, themeColor.opacity(0.6)],
                           startPoint: .leading, endPoint: .trailing)
                .frame(height: 4)
                .clipShape(RoundedCornerTop(radius: 20))

            VStack(alignment: .leading, spacing: 14) {

                // Header row
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(option.title)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.primary).lineLimit(2)
                        Text(option.subtitle)
                            .font(.system(size: 13)).foregroundStyle(.secondary).lineLimit(2)
                    }
                    Spacer(minLength: 8)

                    // Bookmark button
                    if let onBookmark {
                        Button { onBookmark() } label: {
                            Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(isSaved ? themeColor : Color.secondary)
                                .frame(width: 32, height: 32)
                                .background(
                                    isSaved ? themeColor.opacity(0.1) : Color.secondary.opacity(0.07),
                                    in: Circle()
                                )
                                .animation(.spring(response: 0.22, dampingFraction: 0.7), value: isSaved)
                        }
                        .buttonStyle(.plain)
                    }

                    // Theme badge
                    Text(option.theme.capitalized)
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(themeColor.opacity(0.12), in: Capsule())
                        .foregroundStyle(themeColor)
                }

                // Stats
                HStack(spacing: 16) {
                    statPill(icon: "clock", text: option.durationText)
                    if !option.distanceText.isEmpty {
                        statPill(icon: "arrow.left.and.right", text: option.distanceText)
                    }
                    Spacer()
                }

                // Why this
                if let why = option.whyThis, !why.isEmpty {
                    Text(why).font(.system(size: 13))
                        .foregroundStyle(Color.primary.opacity(0.65))
                        .fixedSize(horizontal: false, vertical: true).lineLimit(3)
                }

                // Highlights
                if !option.highlights.isEmpty {
                    HighlightChipsView(highlights: option.highlights)
                }

                // Suggested stops
                if !option.suggestedStops.isEmpty {
                    StopPillsView(stops: option.suggestedStops)
                }

                // Origin footer + CTA
                HStack {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                        Text(option.originLabel(from: origin))
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    HStack(spacing: 5) {
                        Text("Start").font(.system(size: 13, weight: .semibold))
                        Image(systemName: "arrow.right").font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(themeColor)
                }
            }
            .padding(18)
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
            .stroke(Color.primary.opacity(0.06), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.09), radius: 16, y: 4)
    }

    private var themeColor: Color { Self.color(for: option.theme) }

    /// Shared so SavedLoopPill can reuse it without importing the whole card.
    static func color(for theme: String) -> Color {
        switch theme.lowercased() {
        case "food", "coffee", "brunch": return Color(red: 0.95, green: 0.45, blue: 0.1)
        case "scenic", "nature", "park": return Color(red: 0.1,  green: 0.72, blue: 0.38)
        case "landmark", "history":      return Color(red: 0.15, green: 0.45, blue: 0.95)
        case "quick", "fast":            return Color(red: 0.9,  green: 0.18, blue: 0.18)
        case "chill", "relax":           return Color(red: 0.4,  green: 0.35, blue: 0.9)
        default:                         return Color(red: 0.45, green: 0.25, blue: 0.95)
        }
    }

    private func statPill(icon: String, text: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
            Text(text).font(.system(size: 13, weight: .medium)).monospacedDigit()
        }
    }
}

// MARK: - Highlight Chips

struct HighlightChipsView: View {
    let highlights: [String]
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(highlights.prefix(5), id: \.self) { h in
                    Text(h).font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Color.primary.opacity(0.06), in: Capsule())
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 1)
        }
    }
}

// MARK: - Stop Pills

struct StopPillsView: View {
    let stops: [String]
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Stops along the way")
                .font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                .textCase(.uppercase).tracking(0.7)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(stops.prefix(4), id: \.self) { stop in
                        HStack(spacing: 5) {
                            Circle().fill(Color.secondary.opacity(0.3)).frame(width: 5, height: 5)
                            Text(stop).font(.system(size: 12)).lineLimit(1)
                        }
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Color.secondary.opacity(0.07),
                                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }
                .padding(.horizontal, 1)
            }
        }
    }
}

// MARK: - Skeleton Loading Card

struct LoopSkeletonCard: View {
    @State private var shimmer = false
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            skeletonBar(width: 180, height: 16)
            skeletonBar(width: 240, height: 13)
            HStack(spacing: 12) {
                skeletonBar(width: 60, height: 12)
                skeletonBar(width: 50, height: 12)
            }
            skeletonBar(width: nil, height: 12)
            skeletonBar(width: nil, height: 12)
            skeletonBar(width: 120, height: 12)
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
            .stroke(Color.primary.opacity(0.05), lineWidth: 0.5))
        .onAppear {
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { shimmer = true }
        }
    }
    private func skeletonBar(width: CGFloat?, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: height / 2)
            .fill(Color.primary.opacity(shimmer ? 0.07 : 0.12))
            .frame(maxWidth: width == nil ? .infinity : nil)
            .frame(width: width, height: height)
            .animation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true), value: shimmer)
    }
}

// MARK: - Card Press Button Style

private struct CardPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.974 : 1.0)
            .opacity(configuration.isPressed ? 0.92 : 1.0)
            .animation(.spring(response: 0.22, dampingFraction: 0.82), value: configuration.isPressed)
    }
}

// MARK: - Rounded Corner Top Shape

private struct RoundedCornerTop: Shape {
    var radius: CGFloat
    func path(in rect: CGRect) -> Path {
        let r = min(radius, min(rect.width, rect.height) / 2)
        return Path { p in
            p.move(to: CGPoint(x: rect.minX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
            p.addArc(center: CGPoint(x: rect.minX + r, y: rect.minY + r),
                     radius: r, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
            p.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
            p.addArc(center: CGPoint(x: rect.maxX - r, y: rect.minY + r),
                     radius: r, startAngle: .degrees(270), endAngle: .degrees(0), clockwise: false)
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            p.closeSubpath()
        }
    }
}
