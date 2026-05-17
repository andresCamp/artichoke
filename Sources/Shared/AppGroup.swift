import Foundation
import Security

/// Resolves the App Group identifier from the *current process's* entitlements
/// at runtime. Both the app and the system extension carry the same
/// `com.apple.security.application-groups` entitlement (expanded from
/// `$(TeamIdentifierPrefix)`), so this returns the identical container id in
/// both processes without anyone hardcoding a Team ID. It also doubles as the
/// XPC mach service name (an app-group id is a permitted Mach service name).
enum AppGroup {
    static let identifier: String = {
        guard
            let task = SecTaskCreateFromSelf(nil),
            let value = SecTaskCopyValueForEntitlement(
                task, "com.apple.security.application-groups" as CFString, nil),
            let groups = value as? [String],
            let first = groups.first
        else {
            // Last-resort fallback for unsigned/dev runs; real builds always
            // resolve the entitlement above.
            return "group.dev.serdna.hotspotguard"
        }
        return first
    }()

    /// Shared on-disk container used for the ruleset + usage snapshot.
    static var containerURL: URL? {
        FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: identifier)
    }
}
