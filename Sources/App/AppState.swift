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
    /// Single shared instance — the menu-bar Scene and the app delegate's
    /// launch hook must operate on the same model.
    static let shared = AppState()

    // Ruleset / state mirrored into the shared store.
    var enabled = false { didSet { persist() } }
    var allowUnknownByDefault = false { didSet { persist() } }
    var capMB: Int = 0 { didSet { persist() } }          // 0 = no cap
    var autoOnHotspot = true

    // Usage, keyed by signing id.
    private(set) var apps: [String: AppEntry] = [:]
    private(set) var usage: [String: UsageCounter] = [:]
    /// app id → (process label → bytes). The list shows one row per app;
    /// expanding it reveals this per-process line-by-line breakdown.
    private(set) var breakdown: [String: [String: UInt64]] = [:]
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
        // Fold ghosts left by resolver/path changes into one canonical
        // entry: helper-id strip, APFS-firmlink-normalised path, drop
        // pre-path-scheme bundle ids that can't be remapped, and OR the
        // allowed flag so a previously-checked variant isn't lost.
        var migrated: [String: AppEntry] = [:]
        for (_, e) in doc.apps {
            var cid = ProcessIdentity.canonicalID(e.id)
            if cid.hasPrefix("/") { cid = ProcessIdentity.canonicalPath(cid) }
            guard cid.hasPrefix("/") || cid.hasPrefix("proc:") else {
                continue   // legacy bundle-id ghost — no pid to remap it
            }
            let path = ProcessIdentity.canonicalPath(e.path)
            if var existing = migrated[cid] {
                existing.allowed = existing.allowed || e.allowed
                if existing.name.isEmpty { existing.name = e.name }
                if existing.path.isEmpty { existing.path = path }
                migrated[cid] = existing
            } else {
                migrated[cid] = AppEntry(id: cid, name: e.name,
                                         path: path, allowed: e.allowed)
            }
        }
        apps = migrated

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

        // Per-app traffic via `nettop` — works immediately, no approval, and
        // independent of the content filter. The filter is consulted only to
        // block/cap; this is what populates the list.
        NettopReader.shared.state = self
        NettopReader.shared.start()

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

    /// Live monitor discovery. In-memory only — `nettop` sees hundreds of
    /// transient processes; persisting them would bloat the extension's
    /// ruleset doc and leave ghost rows when the resolver changes. Only an
    /// explicit user allow/deny (`setAllowed`) is written to disk.
    func ensureApp(id: String, name: String, path: String) {
        if var e = apps[id] {
            if e.path.isEmpty, !path.isEmpty { e.path = path }
            if (e.name.isEmpty || e.name == e.id), name != id, !name.isEmpty {
                e.name = name
            }
            apps[id] = e
        } else {
            apps[id] = AppEntry(id: id, name: name, path: path,
                                allowed: allowUnknownByDefault)
        }
    }

    func applyUsageDeltas(_ deltas: [String: [UInt64]],
                          breakdown bd: [String: [String: UInt64]] = [:]) {
        rolloverIfNewDay()
        for (id, d) in deltas where d.count == 2 {
            var c = usage[id] ?? UsageCounter()
            c.inBytes &+= d[0]
            c.outBytes &+= d[1]
            usage[id] = c
        }
        for (id, procs) in bd {
            for (p, b) in procs {
                breakdown[id, default: [:]][p, default: 0] &+= b
            }
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
            breakdown.removeAll()
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
            // Only persist apps the user explicitly moved off the default
            // verdict. Apps at the default behave identically whether listed
            // or absent (the extension applies allowUnknownByDefault to
            // anything not listed), so this keeps the rules doc tiny and
            // immune to the nettop monitor's churn.
            doc.apps = apps.filter { $0.value.allowed != allowUnknownByDefault }
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
