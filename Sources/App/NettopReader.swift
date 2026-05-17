import Foundation
import AppKit
import Darwin   // proc_pidpath

/// Per-process network accounting via Apple's `nettop` CLI — the same data
/// source Activity Monitor uses (NetworkStatistics.framework). It needs no
/// entitlement, system extension, or user approval, so the UI shows real
/// traffic the moment the app launches, independent of the content filter
/// (which is only required to *block*). Requires the app to stay unsandboxed
/// so it can spawn `/usr/bin/nettop` (it already is).
@MainActor
final class NettopReader {
    static let shared = NettopReader()

    weak var state: AppState?

    /// pid → cumulative (in, out) bytes from the previous snapshot, used to
    /// derive per-interval deltas the way Stats / Activity Monitor do.
    private var prev: [Int: (UInt64, UInt64)] = [:]
    private var timer: Timer?
    private let interval: TimeInterval = 2

    func start() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: interval,
                                     repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { await self.tick() }
        }
        Task { await tick() }
    }

    func stop() { timer?.invalidate(); timer = nil }

    private func tick() async {
        // Run the (blocking, ~0.5–1s) snapshot off the main actor.
        let rows = await Task.detached(priority: .utility) {
            Self.parse(Self.runNettop() ?? "")
        }.value
        apply(rows)
    }

    private func apply(_ rows: [(pid: Int, proc: String,
                                 cin: UInt64, cout: UInt64)]) {
        guard let state else { return }
        var deltas: [String: [UInt64]] = [:]
        for r in rows {
            let (pin, pout) = prev[r.pid] ?? (r.cin, r.cout)
            // Counters can reset (pid reuse / connection churn) — clamp.
            let din  = r.cin  >= pin  ? r.cin  - pin  : r.cin
            let dout = r.cout >= pout ? r.cout - pout : r.cout
            prev[r.pid] = (r.cin, r.cout)
            guard din != 0 || dout != 0 else { continue }

            let who = Self.identify(pid: r.pid, fallback: r.proc)
            state.ensureApp(id: who.id, name: who.name, path: who.path)
            var e = deltas[who.id] ?? [0, 0]
            e[0] &+= din; e[1] &+= dout
            deltas[who.id] = e
        }
        if !deltas.isEmpty { state.applyUsageDeltas(deltas) }
    }

    // MARK: nettop

    /// One CSV snapshot. `-k` *removes* the listed columns, leaving
    /// `procname.pid, bytes_in, bytes_out` — the column set Stats relies on.
    nonisolated private static func runNettop() -> String? {
        let t = Process()
        t.launchPath = "/usr/bin/nettop"
        t.arguments = ["-P", "-L", "1", "-n", "-k",
            "time,interface,state,rx_dupe,rx_ooo,re-tx,rtt_avg,rcvsize," +
            "tx_win,tc_class,tc_mgt,cc_algo,P,C,R,W,arch"]
        t.environment = ["NSUnbufferedIO": "YES", "LC_ALL": "en_US.UTF-8"]
        let out = Pipe()
        t.standardOutput = out
        t.standardError = Pipe()
        do { try t.run() } catch { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        t.waitUntilExit()
        return String(data: data, encoding: .utf8)
    }

    nonisolated private static func parse(_ s: String)
        -> [(pid: Int, proc: String, cin: UInt64, cout: UInt64)] {
        var res: [(Int, String, UInt64, UInt64)] = []
        var skippedHeader = false
        s.enumerateLines { line, _ in
            if !skippedHeader { skippedHeader = true; return }
            let f = line.split(separator: ",")
            guard f.count >= 3 else { return }
            let np = f[0].split(separator: ".")
            guard let pidStr = np.last, let pid = Int(pidStr) else { return }
            let name = np.dropLast().joined(separator: ".")
            res.append((pid,
                        name.isEmpty ? "\(pid)" : name,
                        UInt64(f[1]) ?? 0,
                        UInt64(f[2]) ?? 0))
        }
        return res
    }

    /// Resolve a pid to a stable id + display name + icon path. Helper
    /// processes (Chrome/Figma/Electron renderers, XPC services) are rolled
    /// up into the `.app` that contains them so the list shows one row per
    /// real app instead of a dozen "* Helper" fragments. Daemons fall back
    /// to a clean executable name, never `nettop`'s mangled string.
    nonisolated private static func identify(pid: Int, fallback: String)
        -> (id: String, name: String, path: String) {
        // 1. Foreground GUI app — cleanest identity directly.
        if let app = NSRunningApplication(processIdentifier: pid_t(pid)),
           let bid = app.bundleIdentifier {
            return (bid, app.localizedName ?? bid,
                    app.bundleURL?.path ?? "")
        }
        // 2. Resolve the real executable and group it under its .app bundle.
        if let exe = executablePath(pid) {
            if let appURL = enclosingAppBundle(exe) {
                let b = Bundle(url: appURL)
                let id = b?.bundleIdentifier ?? appURL.lastPathComponent
                let name = (b?.object(forInfoDictionaryKey: "CFBundleName")
                                as? String)
                    ?? FileManager.default.displayName(atPath: appURL.path)
                    .replacingOccurrences(of: ".app", with: "")
                return (id, name, appURL.path)
            }
            // 3. Plain daemon/CLI: clean binary name from its path.
            let n = URL(fileURLWithPath: exe).lastPathComponent
            return ("proc:\(n)", n, exe)
        }
        // 4. Last resort: nettop's process token.
        return ("proc:\(fallback)", fallback, "")
    }

    nonisolated private static func executablePath(_ pid: Int) -> String? {
        var buf = [CChar](repeating: 0, count: 4096)
        let n = proc_pidpath(Int32(pid), &buf, UInt32(buf.count))
        return n > 0 ? String(cString: buf) : nil
    }

    nonisolated private static func enclosingAppBundle(_ path: String)
        -> URL? {
        var url = URL(fileURLWithPath: path)
        while url.pathComponents.count > 1 {
            if url.pathExtension == "app" { return url }
            url.deleteLastPathComponent()
        }
        return nil
    }
}
