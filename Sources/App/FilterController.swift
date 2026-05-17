import Foundation
import NetworkExtension
import os

/// Wraps `NEFilterManager` — the singleton that turns the installed content
/// filter on/off. Loading/saving its preferences is what actually starts or
/// stops traffic filtering system-wide.
final class FilterController: @unchecked Sendable {
    static let shared = FilterController()
    private let log = Logger(subsystem: "dev.serdna.hotspotguard",
                             category: "filter-mgr")

    func enable(_ on: Bool) async {
        let mgr = NEFilterManager.shared()
        do {
            try await mgr.loadFromPreferences()
            if mgr.providerConfiguration == nil {
                let cfg = NEFilterProviderConfiguration()
                cfg.filterPackets = false
                cfg.filterSockets = true
                mgr.providerConfiguration = cfg
                mgr.localizedDescription = "HotspotGuard"
            }
            mgr.isEnabled = on
            try await mgr.saveToPreferences()
            log.info("filter enabled=\(on)")
        } catch {
            log.error("filter toggle failed: \(error.localizedDescription)")
        }
    }

    var isEnabled: Bool { NEFilterManager.shared().isEnabled }
}
