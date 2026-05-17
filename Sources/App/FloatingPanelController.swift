import AppKit
import SwiftUI

/// Owns the detached, always-on-top window that mirrors the menu-bar
/// popover. We deliberately use an `NSPanel` we fully control rather than
/// trying to make `MenuBarExtra`'s private transient panel survive Space
/// switches — configuring `collectionBehavior` on a window you own is the
/// sanctioned AppKit path; introspecting SwiftUI's is not.
@MainActor
final class FloatingPanelController {
    static let shared = FloatingPanelController()
    private init() {}

    private var panel: NSPanel?

    var isOpen: Bool { panel?.isVisible ?? false }

    /// Show the floating window (creating it on first use), or bring it
    /// forward if it already exists. Non-activating + `orderFrontRegardless`
    /// so an accessory (LSUIElement) app can surface it without stealing
    /// focus or needing `NSApp.activate`.
    func show(state: AppState) {
        if let panel {
            panel.orderFrontRegardless()
            return
        }

        // `.fullSizeContentView` lets content draw under the (transparent)
        // title bar, but NSHostingController still reserves a safe-area inset
        // for it — that's the sloppy gap above the header. Ignore it so the
        // view fills to the very top, matching the menu-bar popover.
        // Same vibrancy as the menu-bar dropdown: the system popover is an
        // NSVisualEffectView with the `.popover` material, blending what's
        // behind the window. Put that behind the content and make the panel
        // itself transparent so the blur shows through.
        let host = NSHostingController(
            rootView: MenuView(state: state, context: .floating)
                .ignoresSafeArea()
                .background(PopoverMaterial().ignoresSafeArea()))

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 400),
            styleMask: [.titled, .closable,
                        .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered, defer: false)
        panel.contentViewController = host
        panel.isOpaque = false
        panel.backgroundColor = .clear

        // Chromeless: MenuView draws its own header (with the close button
        // that replaces the pop-out button), so hide the title bar furniture.
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true

        // The point of the feature: stay visible on every desktop, above
        // normal windows, and don't vanish when the app is inactive.
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.center()

        self.panel = panel
        panel.orderFrontRegardless()
    }

    func close() {
        panel?.close()
        panel = nil
    }
}

/// The exact material the system uses for menu-bar dropdowns / popovers,
/// blending the desktop behind the window through to it.
private struct PopoverMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .popover
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}
