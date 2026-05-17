import Foundation
import SystemExtensions
import os

/// Installs / activates the embedded network system extension. macOS prompts
/// the user the first time ("Allow in System Settings ▸ Privacy & Security").
final class ExtensionManager: NSObject, OSSystemExtensionRequestDelegate,
                              @unchecked Sendable {
    static let shared = ExtensionManager()

    private let log = Logger(subsystem: "dev.serdna.hotspotguard",
                             category: "sysext")
    let extensionBundleID = "dev.serdna.hotspotguard.filter"
    var onStateChange: ((String) -> Void)?

    func activate() {
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
        onStateChange?("Approve in System Settings ▸ Privacy & Security")
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
        log.error("sysext failed: \(error.localizedDescription)")
        onStateChange?("Extension error: \(error.localizedDescription)")
    }
}
