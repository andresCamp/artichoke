import SwiftUI

@main
struct ArtichokeApp: App {
    @State private var state = AppState()

    var body: some Scene {
        // Documented initializer (Apple): pass an asset-catalog image name so
        // the system sizes/positions the status item. Both SVGs share an
        // identical 18×18 square viewBox (art centered) so the status item
        // width is constant — no layout shift on toggle. ON = sealed
        // artichoke, OFF = crossed-out artichoke. Template-rendered.
        MenuBarExtra("Artichoke",
                     image: state.enabled ? "MenuBarOn" : "MenuBarOff") {
            MenuView(state: state)
        }
        .menuBarExtraStyle(.window)
    }

    init() {
        let s = state
        Task { @MainActor in s.bootstrap() }
    }
}
