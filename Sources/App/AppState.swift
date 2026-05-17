import Foundation
import Observation
import UserNotifications
import AppKit

/// The single observable model the menu-bar UI binds to. Owns the ruleset,
/// live + cumulative usage, the data cap, and the hotspot auto-on policy.
/// Writes the ruleset to the shared store so the extension can read it.
@MainActor
@Observable
final class AppState {
    // Ruleset / state mirrored into the shared store.
    var enabled = false { didSet { persist() } }
    var allowUnknownByDefault = false { didSet { persist() } }
    var capMB: Int = 0 { didSet { persist() } }          // 0 = no cap
    var autoOnHotspot = true

    // Usage, keyed by signing id.
    private(set) var apps: [String: AppEntry] = [:]
    private(set) var usage: [String: UsageCounter] = [:]
    private(set) var liveRate: [String: (inBps: UInt64, outBps: UInt64)] = [:]
    private(set) var capReached = false
    private(set) var onHotspot = false
    var extensionStatus = "Not installed"

    private var lastRateSample: [String: UInt64] = [:]
    private var rateTimer: Timer?
    private var dayStamp = ""

    var totalBytes: UInt64 {
        usage.values.reduce(0) { $0 &+ $1.total }
    }

    func bootstrap() {
        dayStamp = Self.today()
        let doc = SharedStore.shared.load()
        enabled = doc.enabled
        allowUnknownByDefault = doc.allowUnknownByDefault
        capMB = Int((doc.capBytes ?? 0) / 1_000_000)
        apps = doc.apps

        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound]) { _, _ in }

        AppXPCListener.shared.state = self
        AppXPCListener.shared.start()
        ExtensionManager.shared.onStateChange = { [weak self] s in
            Task { @MainActor in self?.extensionStatus = s }
        }
        ExtensionManager.shared.activate()

        HotspotMonitor.shared.onChange = { [weak self] expensive in
            Task { @MainActor in self?.hotspotChanged(expensive) }
        }
        HotspotMonitor.shared.start()

        // Sample live rate once a second.
        rateTimer = Timer.scheduledTimer(withTimeInterval: 1,
                                         repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sampleRates() }
        }
        persist()
    }

    // MARK: Toggling

    func setEnabled(_ on: Bool) {
        enabled = on
        Task { await FilterController.shared.enable(on) }
    }

    func setAllowed(_ id: String, _ allowed: Bool) {
        apps[id]?.allowed = allowed
        persist()
    }

    // MARK: Extension callbacks

    func addDiscoveredApp(id: String, name: String, path: String) {
        guard apps[id] == nil else { return }
        apps[id] = AppEntry(id: id, name: name, path: path,
                            allowed: allowUnknownByDefault)
        persist()
    }

    func applyUsageDeltas(_ deltas: [String: [UInt64]]) {
        rolloverIfNewDay()
        for (id, d) in deltas where d.count == 2 {
            var c = usage[id] ?? UsageCounter()
            c.inBytes &+= d[0]
            c.outBytes &+= d[1]
            usage[id] = c
        }
        enforceCap()
    }

    // MARK: Data cap

    private func enforceCap() {
        guard capMB > 0 else { capReached = false; return }
        let limit = UInt64(capMB) * 1_000_000
        let over = totalBytes >= limit
        if over && !capReached {
            capReached = true
            SharedStore.shared.mutate { $0.capReached = true }
            notify(title: "Data cap reached",
                   body: "All traffic is now blocked "
                       + "(\(Self.fmt(totalBytes)) used).")
        } else if !over && capReached {
            capReached = false
            SharedStore.shared.mutate { $0.capReached = false }
        }
    }

    // MARK: Hotspot auto-on

    private func hotspotChanged(_ expensive: Bool) {
        onHotspot = expensive
        guard autoOnHotspot else { return }
        if expensive && !enabled {
            setEnabled(true)
            notify(title: "Hotspot detected",
                   body: "Artichoke turned on to conserve data.")
        }
    }

    // MARK: Live rate sampling

    private func sampleRates() {
        var next: [String: (UInt64, UInt64)] = [:]
        for (id, c) in usage {
            let prev = lastRateSample[id] ?? c.total
            let delta = c.total &- min(prev, c.total)
            // Split proportionally is overkill; report combined as inBps.
            next[id] = (delta, 0)
            lastRateSample[id] = c.total
        }
        liveRate = next
    }

    // MARK: Day rollover

    private func rolloverIfNewDay() {
        let now = Self.today()
        if now != dayStamp {
            dayStamp = now
            usage.removeAll()
            lastRateSample.removeAll()
            capReached = false
            SharedStore.shared.mutate { $0.capReached = false }
        }
    }

    // MARK: Persistence

    private func persist() {
        SharedStore.shared.mutate { doc in
            doc.enabled = enabled
            doc.allowUnknownByDefault = allowUnknownByDefault
            doc.capBytes = capMB > 0 ? UInt64(capMB) * 1_000_000 : nil
            doc.apps = apps
        }
    }

    // MARK: Helpers

    private func notify(title: String, body: String) {
        let c = UNMutableNotificationContent()
        c.title = title; c.body = body; c.sound = .default
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: UUID().uuidString,
                                  content: c, trigger: nil))
    }

    static func today() -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    static func fmt(_ b: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(b),
                                  countStyle: .file)
    }
}
