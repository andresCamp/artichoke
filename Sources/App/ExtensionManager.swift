import Foundation
import SystemExtensions
import os

/// Installs / activates the embedded network system extension. macOS prompts
/// the user the first time (macOS 15+: System Settings ▸ General ▸ Login
/// Items & Extensions).
final class ExtensionManager: NSObject, OSSystemExtensionRequestDelegate,
                              @unchecked Sendable {
    static let shared = ExtensionManager()

    private let log = Logger(subsystem: "dev.serdna.artichoke",
                             category: "sysext")
    let extensionBundleID = "dev.serdna.artichoke.filter"
    var onStateChange: ((String) -> Void)?

    // TEMP debug trace — file-based so it's readable without the unified log.
    private func trace(_ s: String) {
        let line = "\(Date()): \(s)\n"
        let url = URL(fileURLWithPath: "/tmp/artichoke-sysext.log")
        if let h = try? FileHandle(forWritingTo: url) {
            h.seekToEndOfFile(); h.write(line.data(using: .utf8)!); try? h.close()
        } else {
            try? line.data(using: .utf8)!.write(to: url)
        }
    }

    func activate() {
        trace("activate() called; submitting activationRequest for \(extensionBundleID)")
        let req = OSSystemExtensionRequest.activationRequest(
            forExtensionWithIdentifier: extensionBundleID,
            queue: .main)
        req.delegate = self
        OSSystemExtensionManager.shared.submitRequest(req)
        onStateChange?("Activating…")
        trace("submitRequest returned (async; awaiting delegate)")
    }

    func deactivate() {
        let req = OSSystemExtensionRequest.deactivationRequest(
            forExtensionWithIdentifier: extensionBundleID,
            queue: .main)
        req.delegate = self
        OSSystemExtensionManager.shared.submitRequest(req)
    }

    // MARK: OSSystemExtensionRequestDelegate

    func request(_ request: OSSystemExtensionRequest,
                 actionForReplacingExtension existing: OSSystemExtensionProperties,
                 withExtension ext: OSSystemExtensionProperties)
        -> OSSystemExtensionRequest.ReplacementAction { .replace }

    func requestNeedsUserApproval(_ request: OSSystemExtensionRequest) {
        trace("requestNeedsUserApproval — waiting for user in System Settings")
        log.info("awaiting user approval in System Settings")
        onStateChange?("Approve in System Settings ▸ General ▸ Login Items & Extensions")
    }

    func request(_ request: OSSystemExtensionRequest,
                 didFinishWithResult result: OSSystemExtensionRequest.Result) {
        trace("didFinishWithResult: \(result.rawValue)")
        log.info("sysext result: \(result.rawValue)")
        onStateChange?(result == .completed
                       ? "Extension active"
                       : "Reboot required to finish")
    }

    func request(_ request: OSSystemExtensionRequest,
                 didFailWithError error: Error) {
        let ns = error as NSError
        trace("didFailWithError: domain=\(ns.domain) code=\(ns.code) — \(error.localizedDescription)")
        log.error("sysext failed: \(error.localizedDescription)")
        onStateChange?("Extension error: \(error.localizedDescription)")
    }
}
