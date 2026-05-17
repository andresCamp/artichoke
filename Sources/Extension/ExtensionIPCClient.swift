import Foundation

/// Extension → App side of XPC. Connects lazily to the app's listener and
/// coalesces usage deltas so we send at most ~1 message/sec instead of one
/// per data callback.
/// All mutable state is confined to `queue`, so the type is safe to share.
final class ExtensionIPCClient: @unchecked Sendable {
    static let shared = ExtensionIPCClient()

    private var connection: NSXPCConnection?
    private let queue = DispatchQueue(label: "dev.serdna.hotspotguard.ipc")
    private var pending: [String: (UInt64, UInt64)] = [:]   // id → (in,out)
    private var flushScheduled = false

    private func proxy() -> AppXPC? {
        if connection == nil {
            let c = NSXPCConnection(machServiceName: IPC.machServiceName,
                                    options: [])
            c.remoteObjectInterface = NSXPCInterface(with: AppXPC.self)
            c.invalidationHandler = { [weak self] in
                self?.queue.async { self?.connection = nil }
            }
            c.interruptionHandler = { [weak self] in
                self?.queue.async { self?.connection = nil }
            }
            c.resume()
            connection = c
        }
        return connection?.remoteObjectProxyWithErrorHandler { _ in } as? AppXPC
    }

    func reportDiscoveredApp(id: String, name: String, path: String) {
        queue.async { [weak self] in
            self?.proxy()?.reportDiscoveredApp(id: id, name: name, path: path)
        }
    }

    func accumulate(id: String, inBytes: UInt64, outBytes: UInt64) {
        queue.async { [weak self] in
            guard let self else { return }
            var cur = pending[id] ?? (0, 0)
            cur.0 &+= inBytes
            cur.1 &+= outBytes
            pending[id] = cur
            if !flushScheduled {
                flushScheduled = true
                queue.asyncAfter(deadline: .now() + 1.0) { self.flush() }
            }
        }
    }

    private func flush() {
        flushScheduled = false
        guard !pending.isEmpty else { return }
        let snapshot = pending.mapValues { [$0.0, $0.1] }
        pending.removeAll()
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        proxy()?.reportUsage(deltaJSON: data)
    }
}
