import XCTest
@testable import Meetball

final class GuardianAlertTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testCountdownClock() {
        XCTAssertEqual(AlertCountdown.clock(until: now.addingTimeInterval(299.2), now: now), "5:00")
        XCTAssertEqual(AlertCountdown.clock(until: now.addingTimeInterval(59), now: now), "0:59")
        XCTAssertEqual(AlertCountdown.clock(until: now.addingTimeInterval(3723), now: now), "1:02:03")
        XCTAssertEqual(AlertCountdown.clock(until: now, now: now), "Now")
        XCTAssertEqual(AlertCountdown.clock(until: now.addingTimeInterval(-30), now: now), "Now")
        XCTAssertEqual(AlertCountdown.clock(until: now.addingTimeInterval(-185), now: now), "3 min ago")
        XCTAssertEqual(AlertCountdown.caption(until: now.addingTimeInterval(10), now: now), "Starts in")
        XCTAssertEqual(AlertCountdown.caption(until: now.addingTimeInterval(-10), now: now), "Starting")
        XCTAssertEqual(AlertCountdown.caption(until: now.addingTimeInterval(-120), now: now), "Started")
    }

    func testOldSavedSettingsStillLoad() throws {
        // Saved before soundName existed: must keep the user's choices, not reset to defaults.
        let old = #"{"style":"hard","leadMinutes":10,"alsoAtFiveMinutes":true,"playSound":false,"breakThroughFocus":false,"skipWhileScreenSharing":true,"stillJoiningPrompt":true,"repeatIfNotJoined":false,"warnBeforeSleep":true,"limitToActiveHours":false,"activeStartHour":8,"activeEndHour":19}"#
        let s = try JSONDecoder().decode(GuardianSettings.self, from: Data(old.utf8))
        XCTAssertEqual(s.style, .hard)
        XCTAssertEqual(s.leadMinutes, 10)
        XCTAssertFalse(s.playSound)
        XCTAssertEqual(s.soundName, AlertSound.defaultName)
        var changed = s; changed.soundName = "Glass"
        let round = try JSONDecoder().decode(GuardianSettings.self, from: JSONEncoder().encode(changed))
        XCTAssertEqual(round, changed)
    }

    func testSoundListHasDefault() {
        XCTAssertTrue(AlertSound.available.contains(AlertSound.defaultName))
    }
}
