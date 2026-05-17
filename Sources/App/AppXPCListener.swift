import Foundation
import os

/// App side of XPC: vends a listener on the App Group mach service and
/// forwards extension reports to `AppState` on the main actor.
final class AppXPCListener: NSObject, NSXPCListenerDelegate, AppXPC,
                            @unchecked Sendable {
    static let shared = AppXPCListener()
    private let log = Logger(subsystem: "dev.serdna.hotspotguard",
                             category: "xpc")
    private var listener: NSXPCListener?

    weak var state: AppState?

    func start() {
        let l = NSXPCListener(machServiceName: IPC.machServiceName)
        l.delegate = self
        l.resume()
        listener = l
        log.info("xpc listener up on \(IPC.machServiceName, privacy: .public)")
    }

    func listener(_ listener: NSXPCListener,
                  shouldAcceptNewConnection conn: NSXPCConnection) -> Bool {
        conn.exportedInterface = NSXPCInterface(with: AppXPC.self)
        conn.exportedObject = self
        conn.resume()
        return true
    }

    // MARK: AppXPC (called by the extension)

    func reportDiscoveredApp(id: String, name: String, path: String) {
        Task { @MainActor in
            self.state?.addDiscoveredApp(id: id, name: name, path: path)
        }
    }

    func reportUsage(deltaJSON: Data) {
        guard let deltas = try? JSONDecoder()
            .decode([String: [UInt64]].self, from: deltaJSON) else { return }
        Task { @MainActor in
            self.state?.applyUsageDeltas(deltas)
        }
    }
}
