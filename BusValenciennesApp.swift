import SwiftUI

@main
struct BusValenciennesApp: App {
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .ignoresSafeArea()
        }
        .onChange(of: phase) { _ in
            if phase == .active { LiveActivityManager.shared.endExpired() }
        }
    }
}
