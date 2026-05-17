import SwiftUI

@main
struct ArtichokeApp: App {
    @State private var state = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuView(state: state)
        } label: {
            // Filled bolt when actively filtering, outline when idle.
            Image(systemName: state.enabled
                  ? "bolt.horizontal.circle.fill"
                  : "bolt.horizontal.circle")
        }
        .menuBarExtraStyle(.window)
    }

    init() {
        let s = state
        Task { @MainActor in s.bootstrap() }
    }
}
