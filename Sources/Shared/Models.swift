import Foundation

/// One tracked application. `id` is the code-signing identifier (bundle id when
/// available, else the executable's designated identifier) — stable across
/// launches, which is what the verdict path keys on.
struct AppEntry: Codable, Identifiable, Hashable {
    var id: String          // signing identifier
    var name: String        // display name
    var path: String        // executable / bundle path (for icon lookup)
    var allowed: Bool        // true = traffic permitted, false = dropped
}

/// Per-app byte counters. Resets are driven by the app (daily / per session).
struct UsageCounter: Codable, Hashable {
    var inBytes: UInt64 = 0
    var outBytes: UInt64 = 0
    var total: UInt64 { inBytes &+ outBytes }
}

/// The single document shared between the app and the extension via the App
/// Group container. The app owns writes for rules/state; the extension reads
/// rules on every new flow and reports usage back over XPC (not via this file,
/// to avoid write contention on the hot path).
struct FilterDocument: Codable {
    /// Master switch. When false the extension allows everything (filter is a
    /// no-op) so it is safe to leave the system extension installed.
    var enabled: Bool = false

    /// Hard cap for the current session/day, in bytes. nil = no cap.
    var capBytes: UInt64? = nil

    /// Set by the app once `usageTotal >= capBytes`. While true the extension
    /// drops *all* flows regardless of per-app rules.
    var capReached: Bool = false

    /// Default verdict for apps never seen before (TripMode-style: block by
    /// default, user opts each app in).
    var allowUnknownByDefault: Bool = false

    /// Keyed by signing identifier.
    var apps: [String: AppEntry] = [:]

    func isAllowed(_ identifier: String) -> Bool {
        guard enabled, !capReached else {
            return !enabled    // disabled ⇒ allow all; capReached ⇒ drop all
        }
        if let entry = apps[identifier] { return entry.allowed }
        return allowUnknownByDefault
    }
}
