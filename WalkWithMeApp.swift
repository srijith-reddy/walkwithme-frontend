import SwiftUI

@main
struct WalkWithMeApp: App {

    init() {
        // Register HealthKit observer and start motion access early.
        StepCountManager.shared.start()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
