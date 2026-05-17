import Foundation
import NetworkExtension
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
        let app = AppResolver.resolve(auditToken: token)

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
