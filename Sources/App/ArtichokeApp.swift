import SwiftUI

@main
struct ArtichokeApp: App {
    // Bootstrap must run from a real launch hook, not App.init(): reading
    // @State in App.init() is unsupported by SwiftUI (state graph not yet
    // connected), so the bootstrap there never ran — the system extension
    // was never requested. applicationDidFinishLaunching is the correct,
    // run-loop-ready place to call OSSystemExtensionManager.
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var state = AppState.shared

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

        Settings {
            SettingsView(state: state)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in AppState.shared.bootstrap() }
    }
}
