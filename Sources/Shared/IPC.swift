import Foundation

/// XPC contract. The **app** vends an `NSXPCListener` on the App Group mach
/// service name; the **extension** connects to it and pushes:
///   • newly discovered apps (so the UI can show them and the user can choose)
///   • periodic per-app byte deltas (live monitor + totals + cap tracking)
///
/// Verdicts do NOT travel over XPC — the extension reads rules straight from
/// the App Group file so blocking decisions never wait on a round trip.
@objc protocol AppXPC {
    /// Extension saw a flow from an app not yet in the ruleset.
    func reportDiscoveredApp(id: String, name: String, path: String)

    /// Byte deltas since the previous report, keyed by signing identifier.
    /// Encoded as JSON `[String: [UInt64]]` → `[id: [inDelta, outDelta]]`
    /// (NSXPC dictionaries of custom types are painful; JSON keeps it simple).
    func reportUsage(deltaJSON: Data)
}

enum IPC {
    /// Mach service name == App Group id (a permitted Mach name for both ends).
    static var machServiceName: String { AppGroup.identifier }
}
