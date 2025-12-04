import SwiftUI
import CoreLocation

struct ARScreen: View {
    let route: Route

    var body: some View {
        ARViewContainer()
            .ignoresSafeArea()
            .onAppear {
                ARSessionManager.shared.loadRoute(route)
            }
    }
}
