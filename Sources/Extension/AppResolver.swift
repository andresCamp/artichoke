import Foundation
import Security

/// Resolves a flow's originating app from its audit token (the only reliable
/// attribution macOS gives a content filter). Returns the code-signing
/// identifier + a human name + path for the UI.
enum AppResolver {
    struct Resolved { let id: String; let name: String; let path: String }

    // Guarded by `lock`; nonisolated(unsafe) tells Swift 6 we synchronize it.
    private nonisolated(unsafe) static var cache: [Data: Resolved] = [:]
    private static let lock = NSLock()

    static func resolve(auditToken: Data) -> Resolved {
        lock.lock(); defer { lock.unlock() }
        if let hit = cache[auditToken] { return hit }

        let resolved = uncachedResolve(auditToken: auditToken)
        cache[auditToken] = resolved
        return resolved
    }

    private static func uncachedResolve(auditToken: Data) -> Resolved {
        let attrs: NSDictionary =
            [kSecGuestAttributeAudit: auditToken]
        var codeRef: SecCode?
        var staticCode: SecStaticCode?
        var info: CFDictionary?

        guard
            SecCodeCopyGuestWithAttributes(nil, attrs, [], &codeRef) == errSecSuccess,
            let code = codeRef,
            SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess,
            let stat = staticCode,
            SecCodeCopySigningInformation(
                stat, SecCSFlags(rawValue: kSecCSSigningInformation),
                &info) == errSecSuccess,
            let dict = info as? [String: Any]
        else {
            return Resolved(id: "unknown", name: "Unknown process", path: "")
        }

        let identifier = dict[kSecCodeInfoIdentifier as String] as? String
            ?? "unknown"

        var path = ""
        if let url = (dict[kSecCodeInfoMainExecutable as String] as? URL) {
            path = url.path
        } else {
            var urlRef: CFURL?
            if SecCodeCopyPath(stat, [], &urlRef) == errSecSuccess,
               let u = urlRef as URL? { path = u.path }
        }

        let name = displayName(forBundleOrExecutableAt: path,
                               fallback: identifier)
        return Resolved(id: identifier, name: name, path: path)
    }

    private static func displayName(forBundleOrExecutableAt path: String,
                                    fallback: String) -> String {
        // Walk up to a .app bundle if the executable lives inside one.
        var url = URL(fileURLWithPath: path)
        while url.pathComponents.count > 1 {
            if url.pathExtension == "app",
               let b = Bundle(url: url),
               let n = (b.object(forInfoDictionaryKey: "CFBundleDisplayName")
                        ?? b.object(forInfoDictionaryKey: "CFBundleName"))
                       as? String {
                return n
            }
            url.deleteLastPathComponent()
        }
        if !path.isEmpty {
            return URL(fileURLWithPath: path).lastPathComponent
        }
        return fallback
    }
}

private let kSecCSSigningInformation: UInt32 = 0x2
