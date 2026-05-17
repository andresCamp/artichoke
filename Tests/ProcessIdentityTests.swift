import XCTest

/// These cover the pure path/string logic that every choking bug so far has
/// come from: the unsandboxed app and the sandboxed extension MUST derive an
/// identical id for the same process or a checkbox and a verdict disagree.
final class ProcessIdentityTests: XCTestCase {

    // MARK: canonicalPath — the APFS firmlink divergence

    func testCanonicalPathStripsDataFirmlink() {
        XCTAssertEqual(
            ProcessIdentity.canonicalPath(
                "/System/Volumes/Data/Applications/Dia.app"),
            "/Applications/Dia.app")
    }

    func testCanonicalPathLeavesPlainPathUntouched() {
        XCTAssertEqual(
            ProcessIdentity.canonicalPath("/Applications/Dia.app"),
            "/Applications/Dia.app")
    }

    func testCanonicalPathDoesNotStripLookalikePrefix() {
        // Must be the firmlink root + "/", not a substring match.
        XCTAssertEqual(
            ProcessIdentity.canonicalPath("/System/Volumes/DataX/foo"),
            "/System/Volumes/DataX/foo")
    }

    /// The actual bug: the two forms one bundle can present across the
    /// sandbox boundary must collapse to ONE id.
    func testBothFirmlinkFormsConvergeToSameID() {
        let app = ProcessIdentity.resolve(
            execPath: "/Applications/Dia.app/Contents/MacOS/Dia")
        let ext = ProcessIdentity.resolve(
            execPath:
              "/System/Volumes/Data/Applications/Dia.app/Contents/MacOS/Dia")
        XCTAssertEqual(app.id, ext.id)
        XCTAssertEqual(app.id, "/Applications/Dia.app")
    }

    // MARK: canonicalID — helper-bundle collapse

    func testCanonicalIDStripsHelperSuffix() {
        XCTAssertEqual(
            ProcessIdentity.canonicalID("com.figma.Desktop.helper"),
            "com.figma.Desktop")
    }

    func testCanonicalIDStripsChromiumHelperVariant() {
        XCTAssertEqual(
            ProcessIdentity.canonicalID(
                "com.google.Chrome.helper.renderer"),
            "com.google.Chrome")
    }

    func testCanonicalIDKeepsDistinctProduct() {
        // A sibling product is NOT a helper of another.
        XCTAssertEqual(
            ProcessIdentity.canonicalID("company.thebrowser.dia"),
            "company.thebrowser.dia")
    }

    // MARK: resolve(execPath:) — enclosing .app + nesting

    func testResolveCollapsesNestedHelperToOutermostApp() {
        let r = ProcessIdentity.resolve(execPath:
            "/Applications/Ghostty.app/Contents/Frameworks/"
            + "Ghostty Helper.app/Contents/MacOS/Ghostty Helper")
        XCTAssertEqual(r.id, "/Applications/Ghostty.app")
        XCTAssertEqual(r.path, "/Applications/Ghostty.app")
    }

    func testResolveNonAppBecomesProcByBasename() {
        let r = ProcessIdentity.resolve(execPath: "/usr/sbin/mDNSResponder")
        XCTAssertEqual(r.id, "proc:mDNSResponder")
        XCTAssertEqual(r.name, "mDNSResponder")
    }

    func testResolveDataVolumeCLIStillProc() {
        // A daemon on the data volume is still a daemon, just named by binary.
        let r = ProcessIdentity.resolve(
            execPath: "/System/Volumes/Data/usr/local/bin/node")
        XCTAssertEqual(r.id, "proc:node")
    }

    func testResolveEmptyPathIsUnknownProc() {
        let r = ProcessIdentity.resolve(execPath: "")
        XCTAssertEqual(r.id, "proc:unknown")
    }

    // MARK: The allow bug, end to end

    /// This is the regression for "Dia is checked but won't load": the app
    /// writes the rule under the id it resolves; the extension may observe
    /// the firmlink form. The verdict must still be ALLOW. Before
    /// canonicalPath the two ids differed → isAllowed false → the bug.
    func testAllowDecisionSurvivesFirmlinkDivergence() {
        var doc = FilterDocument()
        doc.enabled = true

        // App side (unsandboxed) writes the rule.
        let appID = ProcessIdentity.resolve(
            execPath: "/Applications/Dia.app/Contents/MacOS/Dia").id
        doc.apps[appID] = AppEntry(id: appID, name: "Dia",
                                   path: appID, allowed: true)

        // Extension side (sandboxed) may see the data-volume path.
        let extID = ProcessIdentity.resolve(
            execPath:
              "/System/Volumes/Data/Applications/Dia.app/Contents/MacOS/Dia")
            .id

        XCTAssertEqual(extID, appID, "ids must converge across the sandbox")
        XCTAssertTrue(doc.isAllowed(extID),
            "a checked app must stay allowed even when the extension "
            + "observes the firmlink path")
    }

    func testUncheckedAppIsBlockedWhenChoking() {
        var doc = FilterDocument()
        doc.enabled = true
        doc.allowUnknownByDefault = false
        XCTAssertFalse(doc.isAllowed("/Applications/Unchecked.app"))
    }

    func testEverythingAllowedWhenNotChoking() {
        var doc = FilterDocument()
        doc.enabled = false
        XCTAssertTrue(doc.isAllowed("/Applications/Anything.app"),
            "switch off must never block")
    }
}
