import SwiftUI
import MapKit

struct SimpleNavigationView: View {
    let route: Route
    let stopCoordinates: [CLLocationCoordinate2D]

    @StateObject private var navigator = SimpleNavigator()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            TripMapRepresentable(navigator: navigator)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                topBanner
                    .padding(.horizontal, 16)
                    .padding(.top, 56)

                Spacer()

                HStack {
                    if !navigator.isFollowingUser {
                        Button {
                            navigator.recenter()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "location.north.fill")
                                    .font(.system(size: 14, weight: .bold))
                                Text("Re-center")
                                    .font(.system(size: 16, weight: .semibold))
                            }
                            .padding(.horizontal, 18)
                            .padding(.vertical, 14)
                            .background(Color.black.opacity(0.88), in: Capsule())
                            .foregroundStyle(.white)
                        }
                    }

                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)

                bottomBar
                    .padding(.horizontal, 12)
                    .padding(.bottom, 16)
            }
        }
        .statusBarHidden(false)
        .onAppear {
            navigator.start(route: route, stopCoordinates: stopCoordinates)
        }
        .onDisappear {
            navigator.stop()
        }
    }

    private var topBanner: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.12))
                        .frame(width: 54, height: 54)
                    Image(systemName: navigator.primaryTurnIcon)
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 5) {
                    if !navigator.distanceToNextTurnText.isEmpty {
                        Text(navigator.distanceToNextTurnText)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color.white.opacity(0.18), in: Capsule())
                    }
                    Text(navigator.primaryPrefixText)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.82))
                    Text(navigator.primaryTitleText)
                        .font(.system(size: 28, weight: .medium))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.72)
                }

                Spacer()

                Button {
                    navigator.recenter()
                } label: {
                    ZStack {
                        Circle()
                            .fill(.white)
                            .frame(width: 68, height: 68)
                        Image(systemName: navigator.isFollowingUser ? "location.north.circle.fill" : "location.circle.fill")
                            .font(.system(size: 30, weight: .medium))
                            .foregroundStyle(Color(red: 0.29, green: 0.56, blue: 1.0))
                    }
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)
            .padding(.bottom, 16)

            if let next = navigator.secondaryInstruction, !next.isEmpty {
                HStack(spacing: 10) {
                    Text("Then")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                    Image(systemName: navigator.secondaryTurnIcon)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.white)
                    Text(next)
                        .font(.system(size: 19, weight: .medium))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .background(Color.black.opacity(0.18))
            }
        }
        .background(Color(red: 0.04, green: 0.42, blue: 0.42), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: .black.opacity(0.22), radius: 20, y: 10)
    }

    private var bottomBar: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(navigator.tripTimeText)
                        .font(.system(size: 30, weight: .medium))
                        .foregroundStyle(.white)
                        .monospacedDigit()
                    Image(systemName: "figure.walk")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Color(red: 0.2, green: 0.57, blue: 1.0))
                }

                Text(navigator.tripMetaText)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.white.opacity(0.74))
                    .monospacedDigit()
            }

            Spacer()

            Button {
                navigator.showOverview()
            } label: {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.14))
                        .frame(width: 68, height: 68)
                    Image(systemName: "map")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            .buttonStyle(.plain)

            Button {
                navigator.stop()
                dismiss()
            } label: {
                Text("Exit")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 96, height: 68)
                    .background(Color(red: 0.9, green: 0.2, blue: 0.18), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(Color.black.opacity(0.92), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: .black.opacity(0.28), radius: 18, y: 8)
    }
}

private struct TripMapRepresentable: UIViewRepresentable {
    @ObservedObject var navigator: SimpleNavigator

    func makeUIView(context: Context) -> MKMapView {
        let mv = MKMapView()
        mv.delegate = navigator
        mv.showsUserLocation = true
        mv.showsCompass = false
        mv.showsScale = false
        mv.isPitchEnabled = true
        mv.isRotateEnabled = true
        mv.pointOfInterestFilter = .includingAll
        if #available(iOS 16.0, *) {
            let config = MKHybridMapConfiguration(elevationStyle: .realistic)
            config.showsTraffic = false
            mv.preferredConfiguration = config
        }
        navigator.mapView = mv
        return mv
    }

    func updateUIView(_ uiView: MKMapView, context: Context) {}
}
