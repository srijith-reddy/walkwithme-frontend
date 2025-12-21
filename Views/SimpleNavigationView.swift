import SwiftUI
import MapKit

struct SimpleNavigationView: View {
    let destination: MKMapItem

    @StateObject private var navigator = SimpleNavigator()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .top) {
            MapViewRepresentable(navigator: navigator)
                .ignoresSafeArea()

            VStack(spacing: 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(navigator.instruction.isEmpty ? "Starting…" : navigator.instruction)
                            .font(.headline)
                            .lineLimit(2)
                        HStack(spacing: 12) {
                            if !navigator.distanceToNextText.isEmpty {
                                Label(navigator.distanceToNextText, systemImage: "figure.walk")
                                    .font(.subheadline)
                            }
                            if !navigator.etaText.isEmpty {
                                Label(navigator.etaText, systemImage: "clock")
                                    .font(.subheadline)
                            }
                        }
                        .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button("Close") {
                        navigator.stop()
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(12)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal)
                .padding(.top, 8)
            }
        }
        .onAppear {
            navigator.start(to: destination)
        }
        .onDisappear {
            navigator.stop()
        }
    }
}

private struct MapViewRepresentable: UIViewRepresentable {
    @ObservedObject var navigator: SimpleNavigator

    func makeUIView(context: Context) -> MKMapView {
        let mv = MKMapView()
        mv.delegate = navigator
        mv.showsUserLocation = true
        mv.userTrackingMode = .followWithHeading
        mv.isRotateEnabled = true
        mv.isPitchEnabled = true
        mv.showsCompass = false
        if #available(iOS 16.0, *) {
            mv.preferredConfiguration = MKStandardMapConfiguration(elevationStyle: .realistic)
        }
        navigator.mapView = mv
        return mv
    }

    func updateUIView(_ uiView: MKMapView, context: Context) {
        // no-op
    }
}
