import XCTest
@testable import MeetballPhone

/// Echo's end-of-meeting nudges and the settings that switch Echo and the pre-flight card.
final class EchoPlannerTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func ev(_ id: String, in minutes: Double, length: Double = 30, declined: Bool = false) -> CalendarEvent {
        var e = CalendarEvent(id: id, calendarID: "work", accountEmail: "Apple · iCloud", title: id,
                              start: now.addingTimeInterval(minutes * 60), end: now.addingTimeInterval((minutes + length) * 60),
                              isAllDay: false, meetURL: nil, location: nil, attendees: [], htmlLink: nil)
        e.isDeclined = declined
        return e
    }

    func testANudgeAsEachMeetingEnds() {
        let events = [ev("live", in: -10), ev("next", in: 60), ev("hold", in: 90, length: 5), ev("no", in: 120, declined: true)]
        let echoes = ReminderPlanner.echoes(events, settings: PhoneSettings(), now: now)
        XCTAssertEqual(echoes.map(\.event.id), ["live", "next"])
        XCTAssertEqual(echoes.map(\.kind), [.echo, .echo])
        XCTAssertEqual(echoes[0].fireDate, now.addingTimeInterval(20 * 60))
        XCTAssertEqual(echoes[0].title, "live just ended")
        XCTAssertTrue(echoes[0].id.hasPrefix(ReminderPlanner.idPrefix + "echo|"))
    }

    func testNoNudgesWhenEchoIsOffOrThereIsNoRoom() {
        var s = PhoneSettings()
        s.echoMode = false
        XCTAssertTrue(ReminderPlanner.echoes([ev("a", in: 60)], settings: s, now: now).isEmpty)
        XCTAssertTrue(ReminderPlanner.echoes([ev("a", in: 60)], settings: PhoneSettings(), now: now, room: 0).isEmpty)
    }

    func testOlderSettingsTurnPreFlightAndEchoOn() throws {
        let old = #"{"leadMinutes":5,"alertAtStart":true,"notifyChanges":true,"hiddenCalendars":[]}"#
        let s = try JSONDecoder().decode(PhoneSettings.self, from: Data(old.utf8))
        XCTAssertEqual(s.leadMinutes, 5)
        XCTAssertTrue(s.preFlight)
        XCTAssertTrue(s.echoMode)
        XCTAssertTrue(s.echoToReminders)
    }
}
