import Foundation

/// XPC contract between the container app and the content-filter **system
/// extension**.
///
/// Per Apple's NetworkExtension model the *provider* (system extension) vends
/// the listener and the *app* connects as the client — a plain app cannot own
/// a Mach service. The Mach service name is the App Group id, declared as the
/// extension's `NEMachServiceName` so the provider is permitted to register it.
///
/// Direction of calls:
///   • App → Extension (`ExtensionXPC`): the app calls `register()` once after
///     connecting so the provider captures the connection and gains a
///     back-channel to the app.
///   • Extension → App (`AppXPC`): the provider pushes newly discovered apps
///     and coalesced per-app byte deltas.
///
/// Verdicts never travel over XPC — the extension reads rules straight from
/// the App Group file so blocking decisions never wait on a round trip.
@objc protocol ExtensionXPC {
    /// Called by the app after connecting so the provider stores the
    /// connection and can call back on the app's exported `AppXPC` object.
    func register()
}

@objc protocol AppXPC {
    /// Extension saw a flow from an app not yet in the ruleset.
    func reportDiscoveredApp(id: String, name: String, path: String)

    /// Byte deltas since the previous report, keyed by signing identifier.
    /// Encoded as JSON `[String: [UInt64]]` → `[id: [inDelta, outDelta]]`.
    func reportUsage(deltaJSON: Data)
}

enum IPC {
    /// Mach service name == App Group id. Declared as the extension's
    /// `NEMachServiceName`, a permitted Mach name for the NE provider to vend.
    static var machServiceName: String { AppGroup.identifier }
}
