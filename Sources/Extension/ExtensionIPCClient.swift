import Foundation
import os

/// Extension side of XPC. Per Apple's NetworkExtension model the provider is
/// the **listener**: it vends an `NSXPCListener` on the App Group Mach service
/// (authorized via the extension's `NEMachServiceName`), accepts the app's
/// client connection, and pushes discovered apps + coalesced usage deltas back
/// to the app's exported `AppXPC` object.
///
/// Usage deltas are coalesced so we send at most ~1 message/sec instead of one
/// per data callback. All mutable state is confined to `queue`, so the type is
/// safe to share. The provider-facing API (`start`, `reportDiscoveredApp`,
/// `accumulate`) is unchanged so `FilterDataProvider` call sites stay the same.
final class ExtensionIPCClient: NSObject, NSXPCListenerDelegate, ExtensionXPC,
                                @unchecked Sendable {
    static let shared = ExtensionIPCClient()

    private let log = Logger(subsystem: "dev.serdna.artichoke", category: "xpc")
    private let queue = DispatchQueue(label: "dev.serdna.artichoke.ipc")
    private var listener: NSXPCListener?
    private var connection: NSXPCConnection?
    private var pending: [String: (UInt64, UInt64)] = [:]   // id → (in,out)
    private var flushScheduled = false

    /// Start vending the listener. Called once when the provider starts.
    func start() {
        queue.async { [weak self] in
            guard let self, self.listener == nil else { return }
            let l = NSXPCListener(machServiceName: IPC.machServiceName)
            l.delegate = self
            l.resume()
            self.listener = l
            self.log.info(
                "xpc listener up on \(IPC.machServiceName, privacy: .public)")
        }
    }

    // MARK: NSXPCListenerDelegate

    func listener(_ listener: NSXPCListener,
                  shouldAcceptNewConnection conn: NSXPCConnection) -> Bool {
        conn.exportedInterface = NSXPCInterface(with: ExtensionXPC.self)
        conn.exportedObject = self
        conn.remoteObjectInterface = NSXPCInterface(with: AppXPC.self)
        conn.invalidationHandler = { [weak self] in
            self?.queue.async {
                if self?.connection === conn { self?.connection = nil }
            }
        }
        conn.interruptionHandler = { [weak self] in
            self?.queue.async {
                if self?.connection === conn { self?.connection = nil }
            }
        }
        queue.async { [weak self] in self?.connection = conn }
        conn.resume()
        return true
    }

    // MARK: ExtensionXPC (called by the app)

    func register() {
        // The app connected and announced itself; the connection captured in
        // shouldAcceptNewConnection is now live. Nothing else to do here.
        log.info("app registered as xpc client")
    }

    // MARK: Provider-facing API (call sites unchanged in FilterDataProvider)

    /// Resolve the app's back-channel proxy. Only touched on `queue`.
    private func appProxy() -> AppXPC? {
        connection?.remoteObjectProxyWithErrorHandler { _ in } as? AppXPC
    }

    func reportDiscoveredApp(id: String, name: String, path: String) {
        queue.async { [weak self] in
            self?.appProxy()?.reportDiscoveredApp(id: id, name: name, path: path)
        }
    }

    func accumulate(id: String, inBytes: UInt64, outBytes: UInt64) {
        queue.async { [weak self] in
            guard let self else { return }
            var cur = self.pending[id] ?? (0, 0)
            cur.0 &+= inBytes
            cur.1 &+= outBytes
            self.pending[id] = cur
            if !self.flushScheduled {
                self.flushScheduled = true
                self.queue.asyncAfter(deadline: .now() + 1.0) {
                    self.flush()
                }
            }
        }
    }

    private func flush() {
        flushScheduled = false
        guard !pending.isEmpty else { return }
        let snapshot = pending.mapValues { [$0.0, $0.1] }
        pending.removeAll()
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        appProxy()?.reportUsage(deltaJSON: data)
    }
}
