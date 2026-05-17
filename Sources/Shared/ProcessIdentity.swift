import Foundation
import Darwin

/// The single source of truth for "which app does this process belong to".
///
/// Both halves of the product MUST agree on this or filtering is incoherent:
///   • the app (`NettopReader`) keys the UI rows / allow toggles on it;
///   • the extension (`FilterDataProvider`) keys its block/allow verdict on it.
/// Previously each derived identity its own way, so a checkbox and the actual
/// verdict referred to different ids. This type is shared by both targets.
///
/// A flow is attributed to the nearest `.app` in the process's own path **or
/// its ancestry**: app helpers (Chrome/Figma renderers, XPC services) fold
/// onto the bundling app, and a CLI tool folds onto the app that launched it
/// (`claude` in a terminal is the terminal's traffic). This is the OS-given
/// parent chain — never a version, path layout, or hardcoded name. Genuine
/// system daemons (no `.app` anywhere in the chain) are named by their
/// `comm`, stable across versions.
enum ProcessIdentity {
    struct Resolved { let id: String; let name: String; let path: String }

    static func resolve(pid: Int) -> Resolved {
        if let appURL = appBundleInChain(pid) {
            return identity(forAppBundle: appURL)
        }
        let n = procName(pid) ?? "pid\(pid)"
        return Resolved(id: "proc:\(n)", name: n,
                        path: executablePath(pid) ?? "")
    }

    /// Resolve from an executable path (used when only a path is available,
    /// e.g. the extension's audit-token fallback). Same id scheme as
    /// `resolve(pid:)` so both code paths agree.
    static func resolve(execPath: String) -> Resolved {
        if let appURL = enclosingAppBundle(execPath) {
            return identity(forAppBundle: appURL)
        }
        let n = URL(fileURLWithPath: execPath).lastPathComponent
        return Resolved(id: n.isEmpty ? "proc:unknown" : "proc:\(n)",
                        name: n, path: execPath)
    }

    /// **The id is the `.app` bundle path** — a string both the unsandboxed
    /// app and the sandboxed extension observe identically. It must NOT
    /// depend on reading `Info.plist` (the extension's sandbox blocks that,
    /// which is exactly what made a verdict and a checkbox disagree). The
    /// bundle id / display name are cosmetic and best-effort only.
    private static func identity(forAppBundle url: URL) -> Resolved {
        let b = Bundle(url: url)
        let name = (b?.object(forInfoDictionaryKey:
                        "CFBundleDisplayName") as? String)
            ?? (b?.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? url.deletingPathExtension().lastPathComponent
        return Resolved(id: url.path, name: name, path: url.path)
    }

    /// Per-process label for an app's expanded breakdown — `comm`
    /// ("claude", "Ghostty Helper"), never a versioned path component.
    static func label(pid: Int, fallback: String) -> String {
        procName(pid)
            ?? executablePath(pid).map {
                URL(fileURLWithPath: $0).lastPathComponent
            }
            ?? fallback
    }

    /// Collapse a helper bundle id onto its parent app. Vendors ship the
    /// helper as a sibling bundle with its own id (`com.figma.Desktop.helper`,
    /// Chromium-style `…helper.renderer`/`.gpu`) — strip from `.helper`
    /// onward so it merges with the main app. Distinct products keep their
    /// own id (`company.thebrowser.dia` ≠ `…browser.helper`).
    static func canonicalID(_ id: String) -> String {
        if let r = id.range(of: ".helper",
                            options: [.caseInsensitive, .backwards]) {
            return String(id[id.startIndex..<r.lowerBound])
        }
        return id
    }

    // MARK: - Process introspection

    /// First `.app` bundle found walking the process then its ancestors
    /// (bounded, cycle-safe). Returns the *outermost* `.app` at the matching
    /// level so nested helper bundles still collapse to the product.
    private static func appBundleInChain(_ pid: Int) -> URL? {
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

    /// The *outermost* `.app` on a path (Electron/Chromium apps nest helper
    /// `.app` bundles inside the main one; the top-level bundle is the real
    /// application).
    private static func enclosingAppBundle(_ path: String) -> URL? {
        let comps = URL(fileURLWithPath: path).pathComponents
        guard let idx = comps.firstIndex(where: { $0.hasSuffix(".app") })
        else { return nil }
        var url = URL(fileURLWithPath: "/")
        for c in comps[1...idx] { url.appendPathComponent(c) }
        return url
    }

    private static func executablePath(_ pid: Int) -> String? {
        var buf = [CChar](repeating: 0, count: 4096)
        let n = proc_pidpath(Int32(pid), &buf, UInt32(buf.count))
        return n > 0 ? String(cString: buf) : nil
    }

    /// The process's `comm` (16-char kernel name, e.g. "claude"), independent
    /// of the executable's filename. nil if the pid is gone.
    private static func procName(_ pid: Int) -> String? {
        var buf = [CChar](repeating: 0, count: 256)
        let n = proc_name(Int32(pid), &buf, UInt32(buf.count))
        guard n > 0 else { return nil }
        let s = String(cString: buf)
        return s.isEmpty ? nil : s
    }

    /// Parent pid via `sysctl(KERN_PROC_PID)`. nil if unavailable.
    private static func parentPID(_ pid: Int32) -> Int32? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0
        else { return nil }
        let ppid = info.kp_eproc.e_ppid
        return ppid > 0 ? ppid : nil
    }
}
