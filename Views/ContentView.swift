import SwiftUI
import CoreLocation
import Combine

struct ContentView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    private var showOnboarding: Binding<Bool> {
        Binding(
            get: { !hasCompletedOnboarding },
            set: { _ in }   // dismissal controlled via hasCompletedOnboarding = true
        )
    }

    var body: some View {
        RouteView()
            .fullScreenCover(isPresented: showOnboarding) {
                OnboardingView {
                    hasCompletedOnboarding = true
                }
            }
    }
}

// MARK: - Onboarding

private struct OnboardingView: View {
    let onComplete: () -> Void
    @State private var page = 0

    var body: some View {
        TabView(selection: $page) {
            WelcomePage { withAnimation(.easeInOut(duration: 0.38)) { page = 1 } }
                .tag(0)
            LocationPage(onComplete: onComplete)
                .tag(1)
        }
        .tabViewStyle(.page(indexDisplayMode: .always))
        .ignoresSafeArea()
    }
}

// MARK: - Welcome Page

private struct WelcomePage: View {
    let onNext: () -> Void
    @State private var appeared = false

    private let features: [(icon: String, color: Color, title: String, subtitle: String)] = [
        ("wand.and.stars",   .purple, "AI-Curated Routes",      "Pick a vibe — scenic, hilly, safe, or let the AI decide"),
        ("arkit",            .blue,   "AR Navigation",           "Walk in AR with live hazard detection and turn prompts"),
        ("map.circle.fill",  .teal,   "Explore Your City",       "Build loops, discover landmarks, track every street you've walked"),
    ]

    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [
                    Color(red: 0.04, green: 0.06, blue: 0.14),
                    Color(red: 0.08, green: 0.10, blue: 0.22),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            // Subtle grid pattern
            GeometryReader { geo in
                Canvas { ctx, size in
                    ctx.opacity = 0.04
                    let step: CGFloat = 38
                    var x: CGFloat = 0
                    while x < size.width {
                        ctx.stroke(Path { p in p.move(to: .init(x: x, y: 0)); p.addLine(to: .init(x: x, y: size.height)) },
                                   with: .color(.white), lineWidth: 0.5)
                        x += step
                    }
                    var y: CGFloat = 0
                    while y < size.height {
                        ctx.stroke(Path { p in p.move(to: .init(x: 0, y: y)); p.addLine(to: .init(x: size.width, y: y)) },
                                   with: .color(.white), lineWidth: 0.5)
                        y += step
                    }
                }
            }
            .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // Logo + title
                VStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(LinearGradient(
                                colors: [Color(red: 0.08, green: 0.55, blue: 1.0),
                                         Color(red: 0.35, green: 0.20, blue: 0.95)],
                                startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 88, height: 88)
                            .shadow(color: Color(red: 0.08, green: 0.55, blue: 1.0).opacity(0.45), radius: 24, y: 8)

                        Image(systemName: "figure.walk")
                            .font(.system(size: 38, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    .scaleEffect(appeared ? 1.0 : 0.6)
                    .opacity(appeared ? 1.0 : 0)

                    VStack(spacing: 8) {
                        Text("WalkWithMe")
                            .font(.system(size: 36, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)

                        Text("City walking with purpose")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    .opacity(appeared ? 1.0 : 0)
                    .offset(y: appeared ? 0 : 12)
                }

                Spacer().frame(height: 52)

                // Feature list
                VStack(spacing: 16) {
                    ForEach(Array(features.enumerated()), id: \.offset) { index, f in
                        FeatureRow(icon: f.icon, color: f.color, title: f.title, subtitle: f.subtitle)
                            .opacity(appeared ? 1.0 : 0)
                            .offset(y: appeared ? 0 : 20)
                            .animation(.easeOut(duration: 0.45).delay(0.18 + Double(index) * 0.08), value: appeared)
                    }
                }
                .padding(.horizontal, 28)

                Spacer()

                // CTA button
                Button(action: onNext) {
                    HStack(spacing: 10) {
                        Text("Get Started")
                            .font(.system(size: 18, weight: .semibold))
                        Image(systemName: "arrow.right")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(
                        LinearGradient(
                            colors: [Color(red: 0.08, green: 0.55, blue: 1.0),
                                     Color(red: 0.35, green: 0.20, blue: 0.95)],
                            startPoint: .leading, endPoint: .trailing),
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                    )
                    .foregroundStyle(.white)
                    .shadow(color: Color(red: 0.08, green: 0.55, blue: 1.0).opacity(0.4), radius: 16, y: 6)
                }
                .padding(.horizontal, 28)
                .opacity(appeared ? 1.0 : 0)
                .offset(y: appeared ? 0 : 16)
                .animation(.easeOut(duration: 0.45).delay(0.42), value: appeared)

                Spacer().frame(height: 60)
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.55).delay(0.12)) { appeared = true }
        }
    }
}

private struct FeatureRow: View {
    let icon: String
    let color: Color
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(color.opacity(0.18))
                    .frame(width: 52, height: 52)
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(color)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.56))
                    .lineLimit(2)
            }

            Spacer()
        }
    }
}

// MARK: - Location Permission Page

private final class OnboardingLocationDelegate: NSObject, CLLocationManagerDelegate, ObservableObject {
    @Published var status: CLAuthorizationStatus = .notDetermined
    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        status = manager.authorizationStatus
    }

    func request() {
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        status = manager.authorizationStatus
    }
}

private struct LocationPage: View {
    let onComplete: () -> Void
    @State private var appeared = false
    @StateObject private var locationDelegate = OnboardingLocationDelegate()
    @State private var didRequest = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.04, green: 0.06, blue: 0.14),
                    Color(red: 0.08, green: 0.10, blue: 0.22),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // Icon
                ZStack {
                    Circle()
                        .fill(Color.teal.opacity(0.18))
                        .frame(width: 110, height: 110)
                    Circle()
                        .fill(Color.teal.opacity(0.10))
                        .frame(width: 150, height: 150)
                    Image(systemName: "location.fill")
                        .font(.system(size: 46, weight: .semibold))
                        .foregroundStyle(Color.teal)
                }
                .scaleEffect(appeared ? 1.0 : 0.7)
                .opacity(appeared ? 1.0 : 0)

                Spacer().frame(height: 36)

                VStack(spacing: 12) {
                    Text("Let's find you")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    Text("WalkWithMe uses your location to build routes from where you are, guide you turn-by-turn, and personalise your walk experience.")
                        .font(.system(size: 16))
                        .foregroundStyle(.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                .opacity(appeared ? 1.0 : 0)
                .offset(y: appeared ? 0 : 14)

                Spacer().frame(height: 20)

                // Permission bullets
                VStack(spacing: 12) {
                    permissionBullet(icon: "map.fill",           text: "Build personalised routes from your position")
                    permissionBullet(icon: "location.north.fill", text: "Turn-by-turn guidance as you walk")
                    permissionBullet(icon: "shoeprints.fill",     text: "Track steps and walk history")
                }
                .padding(.horizontal, 32)
                .opacity(appeared ? 1.0 : 0)
                .offset(y: appeared ? 0 : 14)
                .animation(.easeOut(duration: 0.45).delay(0.18), value: appeared)

                Spacer()

                VStack(spacing: 14) {
                    Button {
                        requestLocation()
                    } label: {
                        Text("Allow Location Access")
                            .font(.system(size: 18, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                            .background(Color.teal, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .foregroundStyle(.white)
                            .shadow(color: Color.teal.opacity(0.35), radius: 14, y: 5)
                    }
                    .opacity(appeared ? 1.0 : 0)
                    .animation(.easeOut(duration: 0.45).delay(0.28), value: appeared)

                    Button {
                        onComplete()
                    } label: {
                        Text("Skip for now")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.white.opacity(0.45))
                    }
                    .opacity(appeared ? 1.0 : 0)
                    .animation(.easeOut(duration: 0.45).delay(0.34), value: appeared)
                }
                .padding(.horizontal, 28)

                Spacer().frame(height: 60)
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.5).delay(0.1)) { appeared = true }
        }
        .onChange(of: locationDelegate.status) { _, status in
            if status != .notDetermined, didRequest {
                onComplete()
            }
        }
    }

    private func requestLocation() {
        didRequest = true
        if locationDelegate.status == .notDetermined {
            locationDelegate.request()
        } else {
            onComplete()
        }
    }

    private func permissionBullet(icon: String, text: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.teal)
                .frame(width: 24)
            Text(text)
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.65))
            Spacer()
        }
    }
}

#Preview {
    ContentView()
}
