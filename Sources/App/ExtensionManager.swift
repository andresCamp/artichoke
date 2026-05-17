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

    func activate() {
        log.info("submitting activation request for \(self.extensionBundleID, privacy: .public)")
        let req = OSSystemExtensionRequest.activationRequest(
            forExtensionWithIdentifier: extensionBundleID,
            queue: .main)
        req.delegate = self
        OSSystemExtensionManager.shared.submitRequest(req)
        onStateChange?("Activating…")
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
        log.info("awaiting user approval in System Settings")
        onStateChange?("Approve in System Settings ▸ General ▸ Login Items & Extensions")
    }

    func request(_ request: OSSystemExtensionRequest,
                 didFinishWithResult result: OSSystemExtensionRequest.Result) {
        log.info("sysext result: \(result.rawValue)")
        onStateChange?(result == .completed
                       ? "Extension active"
                       : "Reboot required to finish")
    }

    func request(_ request: OSSystemExtensionRequest,
                 didFailWithError error: Error) {
        let ns = error as NSError
        log.error("sysext failed: domain=\(ns.domain, privacy: .public) code=\(ns.code) — \(error.localizedDescription, privacy: .public)")
        onStateChange?("Extension error: \(error.localizedDescription)")
    }
}
