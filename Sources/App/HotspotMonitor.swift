import Foundation
import Network

/// Watches the active path and fires when the Mac moves onto an "expensive"
/// link — i.e. an iPhone hotspot / tethered connection (`isExpensive` is set
/// for Personal Hotspot and cellular). Used for the optional auto-on feature.
/// State is only mutated from `monitor`'s serial queue.
final class HotspotMonitor: @unchecked Sendable {
    static let shared = HotspotMonitor()

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "dev.serdna.hotspotguard.path")
    private(set) var onExpensiveLink = false

    /// Called whenever expensive-link status changes (true = on hotspot).
    var onChange: ((Bool) -> Void)?

    func start() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            let expensive = path.isExpensive || path.isConstrained
            if expensive != self.onExpensiveLink {
                self.onExpensiveLink = expensive
                DispatchQueue.main.async { self.onChange?(expensive) }
            }
        }
        monitor.start(queue: queue)
    }
}
