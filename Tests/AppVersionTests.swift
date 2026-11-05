import XCTest
@testable import Meetball

final class AppVersionTests: XCTestCase {
    func testStampedBuild() {
        let v = AppVersion(info: ["CFBundleShortVersionString": "0.1.0", "CFBundleVersion": "142",
                                  "MeetballCommit": "a1b2c3d", "MeetballBuildDate": "2026-11-05T20:00:00Z"])
        XCTAssertEqual(v.short, "0.1.0 (142)")
        XCTAssertEqual(v.full, "Meetball 0.1.0 (142) a1b2c3d")
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        let d = v.detailText(calendar: cal, locale: Locale(identifier: "en_US"))
        XCTAssertTrue(d.hasPrefix("Commit a1b2c3d · built Nov 5, 2026"), d)
    }

    func testUnstampedBuildIgnoresEmptyAndUnexpandedValues() {
        let v = AppVersion(info: ["CFBundleShortVersionString": "0.1.0", "CFBundleVersion": "1",
                                  "MeetballCommit": "", "MeetballBuildDate": "$(MEETBALL_BUILD_DATE)"])
        XCTAssertNil(v.commit)
        XCTAssertNil(v.builtAt)
        XCTAssertEqual(v.full, "Meetball 0.1.0 (1)")
        XCTAssertEqual(v.detailText(), "Development build (not built with make).")
    }
}
