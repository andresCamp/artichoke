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
}
