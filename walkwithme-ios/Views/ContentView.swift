import SwiftUI

struct ContentView: View {
    var body: some View {
        NavigationStack {
            RouteView()
                .navigationTitle("Walk With Me")
                .navigationBarTitleDisplayMode(.inline)
        }
    }
}

#Preview {
    ContentView()
}
