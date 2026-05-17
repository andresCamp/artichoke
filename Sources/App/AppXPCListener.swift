import Foundation
import os

/// App side of XPC. Per Apple's NetworkExtension model the app is the
/// **client**: it connects to the provider's listener on the App Group Mach
/// service, exports an `AppXPC` object so the provider can push discovered
/// apps + usage, and calls `register()` to establish the link. It reconnects
/// with capped exponential backoff while the extension is not yet up/approved.
///
/// The type name and `state` hook are unchanged so `AppState` call sites stay
/// the same.
final class AppXPCListener: NSObject, AppXPC, @unchecked Sendable {
    static let shared = AppXPCListener()

    private let log = Logger(subsystem: "dev.serdna.artichoke",
                             category: "xpc")
    private let queue = DispatchQueue(label: "dev.serdna.artichoke.xpc.client")
    private var connection: NSXPCConnection?
    private var retryDelay: TimeInterval = 1
    private var reconnectScheduled = false

    weak var state: AppState?

    func start() { queue.async { [weak self] in self?.connect() } }

    private func connect() {
        let c = NSXPCConnection(machServiceName: IPC.machServiceName,
                                options: [])
        c.remoteObjectInterface = NSXPCInterface(with: ExtensionXPC.self)
        c.exportedInterface = NSXPCInterface(with: AppXPC.self)
        c.exportedObject = self
        c.invalidationHandler = { [weak self] in self?.scheduleReconnect() }
        c.interruptionHandler = { [weak self] in self?.scheduleReconnect() }
        c.resume()
        connection = c

        // Calling a remote method forces the connection to establish and lets
        // the provider capture our connection for its back-channel. If the
        // extension isn't up/approved yet this errors → backoff + retry.
        let proxy = c.remoteObjectProxyWithErrorHandler { [weak self] err in
            self?.log.error(
                "xpc not reachable: \(err.localizedDescription, privacy: .public)")
            self?.scheduleReconnect()
        } as? ExtensionXPC
        proxy?.register()
        log.info(
            "xpc client connecting to \(IPC.machServiceName, privacy: .public)")
    }

    private func scheduleReconnect() {
        queue.async { [weak self] in
            guard let self, !self.reconnectScheduled else { return }
            self.reconnectScheduled = true
            self.connection?.invalidate()
            self.connection = nil
            let delay = self.retryDelay
            self.retryDelay = min(delay * 2, 30)
            self.queue.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self else { return }
                self.reconnectScheduled = false
                self.connect()
            }
        }
    }

    // MARK: AppXPC (called by the extension)

    func reportDiscoveredApp(id: String, name: String, path: String) {
        // First successful inbound call means the link is healthy.
        queue.async { [weak self] in self?.retryDelay = 1 }
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
