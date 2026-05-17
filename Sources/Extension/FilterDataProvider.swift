import Foundation
import NetworkExtension
import Darwin
import os

/// The content-filter system extension. Apple calls `handleNewFlow` for every
/// new connection; we attribute it to an app, consult the shared ruleset, and
/// either drop it or allow-with-accounting so the live monitor stays accurate.
/// `flowApp` is guarded by `flowLock`; the provider is otherwise stateless.
final class FilterDataProvider: NEFilterDataProvider, @unchecked Sendable {

    private let log = Logger(subsystem: "dev.serdna.artichoke",
                             category: "filter")
    private let store = SharedStore.shared
    private let ipc = ExtensionIPCClient.shared

    /// flow UUID → resolved app id, so data callbacks know who to bill.
    private var flowApp: [UUID: String] = [:]
    private let flowLock = NSLock()

    /// audit token → resolved identity. `handleNewFlow` is hot and the
    /// parent-chain walk is not free; flows from the same process repeat
    /// constantly, so memoize. Keyed on the token (pid is reused).
    private var idCache: [Data: ProcessIdentity.Resolved] = [:]
    private let idLock = NSLock()

    /// Attribute a flow to an app using the SAME resolver the UI/toggles use
    /// (`ProcessIdentity`), so a verdict and a checkbox always refer to the
    /// same id. Falls back to code-signing resolution only if the audit
    /// token yields no pid.
    private func resolveApp(token: Data)
        -> (id: String, name: String, path: String) {
        if !token.isEmpty {
            idLock.lock()
            let hit = idCache[token]
            idLock.unlock()
            if let hit { return (hit.id, hit.name, hit.path) }
        }
        if let pid = Self.pid(fromAuditToken: token) {
            let r = ProcessIdentity.resolve(pid: Int(pid))
            if !token.isEmpty {
                idLock.lock(); idCache[token] = r; idLock.unlock()
            }
            return (r.id, r.name, r.path)
        }
        let a = AppResolver.resolve(auditToken: token)
        return (a.id, a.name, a.path)
    }

    /// `audit_token_t.val[5]` is the pid (mach/audit_token.h layout).
    private static func pid(fromAuditToken data: Data) -> pid_t? {
        guard data.count == MemoryLayout<audit_token_t>.size else {
            return nil
        }
        var t = audit_token_t()
        _ = withUnsafeMutableBytes(of: &t) { raw in
            data.copyBytes(to: raw.bindMemory(to: UInt8.self))
        }
        let p = pid_t(bitPattern: t.val.5)
        return p > 0 ? p : nil
    }

    // MARK: Lifecycle

    override func startFilter(completionHandler: @escaping (Error?) -> Void) {
        // Vend the XPC listener so the app can connect as the client and
        // receive discovered apps + usage. The app cannot own the Mach
        // service, so the provider must be the listener.
        ipc.start()

        // Empty rule set + .filterData default ⇒ every flow is handed to
        // handleNewFlow, where the real per-app decision happens.
        let settings = NEFilterSettings(rules: [], defaultAction: .filterData)
        apply(settings) { error in
            if let error { self.log.error("apply settings failed: \(error.localizedDescription)") }
            completionHandler(error)
        }
    }

    override func stopFilter(with reason: NEProviderStopReason,
                             completionHandler: @escaping () -> Void) {
        completionHandler()
    }

    // MARK: Verdict

    override func handleNewFlow(_ flow: NEFilterFlow)
        -> NEFilterNewFlowVerdict {

        let token = flow.sourceAppAuditToken ?? Data()
        let app = resolveApp(token: token)

        let doc = store.loadCached()

        // Surface unseen apps to the UI so the user can choose them.
        if doc.apps[app.id] == nil && app.id != "unknown" {
            ipc.reportDiscoveredApp(id: app.id, name: app.name, path: app.path)
        }

        guard doc.isAllowed(app.id) else {
            log.debug("DROP \(app.name, privacy: .public)")
            return .drop()
        }

        // Allowed: keep the flow in-path with peeking so we can meter bytes.
        flowLock.lock()
        flowApp[flow.identifier] = app.id
        flowLock.unlock()

        return .filterDataVerdict(withFilterInbound: true,
                                  peekInboundBytes: Int.max,
                                  filterOutbound: true,
                                  peekOutboundBytes: Int.max)
    }

    // MARK: Byte accounting (live monitor + cap tracking)

    override func handleInboundData(from flow: NEFilterFlow,
                                    readBytesStartOffset offset: Int,
                                    readBytes: Data) -> NEFilterDataVerdict {
        meter(flow, inBytes: UInt64(readBytes.count), outBytes: 0)
        return continueVerdict(byteCount: readBytes.count)
    }

    override func handleOutboundData(from flow: NEFilterFlow,
                                     readBytesStartOffset offset: Int,
                                     readBytes: Data) -> NEFilterDataVerdict {
        meter(flow, inBytes: 0, outBytes: UInt64(readBytes.count))
        return continueVerdict(byteCount: readBytes.count)
    }

    override func handleInboundDataComplete(for flow: NEFilterFlow)
        -> NEFilterDataVerdict { .allow() }

    override func handleOutboundDataComplete(for flow: NEFilterFlow)
        -> NEFilterDataVerdict { .allow() }

    /// Pass everything we just saw and keep peeking the rest of the flow so
    /// metering continues. This adds per-flow overhead — acceptable for a
    /// hotspot data-saver where flows are deliberately few.
    private func continueVerdict(byteCount: Int) -> NEFilterDataVerdict {
        NEFilterDataVerdict(passBytes: byteCount, peekBytes: Int.max)
    }

    private func meter(_ flow: NEFilterFlow,
                       inBytes: UInt64, outBytes: UInt64) {
        flowLock.lock()
        let id = flowApp[flow.identifier]
        flowLock.unlock()
        guard let id else { return }
        ipc.accumulate(id: id, inBytes: inBytes, outBytes: outBytes)
    }
}
