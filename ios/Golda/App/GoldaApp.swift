import SwiftUI

@main
struct GoldaApp: App {
    var body: some Scene {
        WindowGroup {
            // The shell arrives at stage 2; until then the app only proves that it builds and launches.
            Text("Golda")
                .font(.largeTitle.weight(.semibold))
        }
    }
}
