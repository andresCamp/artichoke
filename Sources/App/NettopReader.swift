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
        var bd: [String: [String: UInt64]] = [:]
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

            // Keep the real per-process name so the row can expand into a
            // line-by-line breakdown of the helpers folded into this app.
            let label = Self.procLabel(pid: r.pid, fallback: r.proc)
            bd[who.id, default: [:]][label, default: 0] &+= (din &+ dout)
        }
        if !deltas.isEmpty {
            state.applyUsageDeltas(deltas, breakdown: bd)
        }
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

    /// Resolve a pid to a stable id + display name + icon path. A process is
    /// attributed to the nearest `.app` in its own path **or its ancestry**:
    /// app helpers (Chrome/Figma renderers, XPC services) fold onto the app
    /// that bundles them, and CLI tools fold onto the app that launched them
    /// — `claude` run in a terminal is the terminal's traffic, not its own
    /// row. This is the OS-given parent chain, so it never depends on a
    /// version, path layout, or hardcoded name. Genuine system daemons (no
    /// `.app` anywhere in the chain) are named by their `comm`.
    nonisolated private static func identify(pid: Int, fallback: String)
        -> (id: String, name: String, path: String) {
        // 1. Walk self → parent → … for the first enclosing .app bundle.
        if let appURL = appBundleInChain(pid) {
            let b = Bundle(url: appURL)
            let id = canonicalID(
                b?.bundleIdentifier ?? appURL.lastPathComponent)
            let name = (b?.object(forInfoDictionaryKey:
                            "CFBundleDisplayName") as? String)
                ?? (b?.object(forInfoDictionaryKey: "CFBundleName")
                            as? String)
                ?? FileManager.default.displayName(atPath: appURL.path)
                    .replacingOccurrences(of: ".app", with: "")
            return (id, name, appURL.path)
        }
        // 2. No app anywhere in the chain → a real system daemon/CLI.
        //    Name it by `comm` (stable across versions), never the path's
        //    last component (which can be a bare version like "2.1.143").
        let n = procName(pid) ?? fallback
        return ("proc:\(n)", n, executablePath(pid) ?? "")
    }

    /// First `.app` bundle found walking the process and then its ancestors
    /// (bounded — pid 1 / cycle-safe). Returns the *outermost* `.app` at the
    /// matching level so nested helper bundles still collapse to the product.
    nonisolated private static func appBundleInChain(_ pid: Int) -> URL? {
        var cur = Int32(pid)
        for _ in 0..<24 {
            if cur <= 1 { break }
            if let exe = executablePath(Int(cur)),
               let app = enclosingAppBundle(exe) {
                return app
            }
            guard let p = parentPID(cur), p != cur else { break }
            cur = p
        }
        return nil
    }

    /// The process's `comm` (16-char kernel name, e.g. "claude"), independent
    /// of the executable's filename. nil if the pid is gone.
    nonisolated private static func procName(_ pid: Int) -> String? {
        var buf = [CChar](repeating: 0, count: 256)
        let n = proc_name(Int32(pid), &buf, UInt32(buf.count))
        guard n > 0 else { return nil }
        let s = String(cString: buf)
        return s.isEmpty ? nil : s
    }

    /// Parent pid via `sysctl(KERN_PROC_PID)`. nil if unavailable.
    nonisolated private static func parentPID(_ pid: Int32) -> Int32? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0
        else { return nil }
        let ppid = info.kp_eproc.e_ppid
        return ppid > 0 ? ppid : nil
    }

    /// Collapse a helper bundle id onto its parent app. Vendors ship the
    /// helper as a sibling bundle with its own id (`com.figma.Desktop.helper`,
    /// Chromium-style `…helper.renderer`/`.gpu`) — strip from `.helper`
    /// onward so it merges with the main app instead of forming a 2nd row.
    /// Distinct products keep their own id (`company.thebrowser.dia` ≠
    /// `company.thebrowser.browser.helper`).
    nonisolated static func canonicalID(_ id: String) -> String {
        if let r = id.range(of: ".helper",
                            options: [.caseInsensitive, .backwards]) {
            return String(id[id.startIndex..<r.lowerBound])
        }
        return id
    }

    /// The per-process label for an app's expanded breakdown — `comm`
    /// ("claude", "Ghostty Helper"), never a versioned path component.
    nonisolated private static func procLabel(pid: Int,
                                              fallback: String) -> String {
        procName(pid)
            ?? executablePath(pid).map {
                URL(fileURLWithPath: $0).lastPathComponent
            }
            ?? fallback
    }

    nonisolated private static func executablePath(_ pid: Int) -> String? {
        var buf = [CChar](repeating: 0, count: 4096)
        let n = proc_pidpath(Int32(pid), &buf, UInt32(buf.count))
        return n > 0 ? String(cString: buf) : nil
    }

    /// The *outermost* `.app` on the path. Electron/Chromium apps (Arc,
    /// Figma, Dia, …) nest helper `.app` bundles inside the main one; the
    /// top-level bundle is the real application, so all its helpers collapse
    /// to a single row instead of one per "* Helper".
    nonisolated private static func enclosingAppBundle(_ path: String)
        -> URL? {
        let comps = URL(fileURLWithPath: path).pathComponents
        guard let idx = comps.firstIndex(where: {
            $0.hasSuffix(".app")
        }) else { return nil }
        var url = URL(fileURLWithPath: "/")
        for c in comps[1...idx] { url.appendPathComponent(c) }
        return url
    }
}
