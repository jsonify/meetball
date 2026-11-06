import XCTest
@testable import MeetballPhone

final class FunTests: XCTestCase {
    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private func at(_ h: Int, _ m: Int = 0) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 11, day: 10, hour: h, minute: m))!
    }

    private func ev(_ id: String, _ h: Int, _ m: Int, minutes: Double, url: String? = nil, declined: Bool = false) -> CalendarEvent {
        var e = CalendarEvent(id: id, calendarID: "c", accountEmail: "a", title: id, start: at(h, m),
                              end: at(h, m).addingTimeInterval(minutes * 60), isAllDay: false,
                              meetURL: url.flatMap(URL.init(string:)), location: nil, attendees: [], htmlLink: nil)
        e.isDeclined = declined
        return e
    }

    func testDayStatsFindsTheFirstFreeStretch() {
        let events = [ev("a", 9, 0, minutes: 60), ev("b", 10, 0, minutes: 30), ev("c", 10, 40, minutes: 20), ev("d", 13, 0, minutes: 60),
                      ev("declined", 11, 0, minutes: 60, declined: true)]
        let s = PhoneAgenda.dayStats(events, now: at(9, 30), calendar: cal)
        XCTAssertEqual(s.left, 4)
        XCTAssertEqual(s.hours, 2 + 50.0 / 60, accuracy: 0.001)
        XCTAssertEqual(s.freeGap, DateInterval(start: at(11), end: at(13)))
        XCTAssertEqual(s.hoursDigits, "2:50")
    }

    func testDayStatsFreeNowAndNoneLeft() {
        let s = PhoneAgenda.dayStats([ev("a", 9, 0, minutes: 30)], now: at(12), calendar: cal)
        XCTAssertEqual(s.left, 0)
        XCTAssertEqual(s.freeGap, DateInterval(start: at(12), end: at(18)))
        XCTAssertEqual(s.verdict, "Meetings done. The rest is yours.")
    }

    func testDayStatsNoGapWhenBackToBackUntilTheEnd() {
        let s = PhoneAgenda.dayStats([ev("a", 16, 0, minutes: 120)], now: at(16, 5), calendar: cal)
        XCTAssertNil(s.freeGap)
    }

    func testNextJoinableSkipsLinklessAndStarted() {
        let up = [ev("live", 9, 0, minutes: 60, url: "https://meet.google.com/x"), ev("nolink", 9, 45, minutes: 30),
                  ev("next", 10, 0, minutes: 30, url: "https://zoom.us/j/1")]
        XCTAssertEqual(PhoneAgenda.nextJoinable(up, now: at(9, 30))?.id, "next")
    }

    func testJoinableWindow() {
        let base = at(9)
        func m(_ id: String, in minutes: Double, url: Bool = true) -> WidgetMeeting {
            WidgetMeeting(id: id, title: id, start: base.addingTimeInterval(minutes * 60), end: base.addingTimeInterval((minutes + 30) * 60),
                          colorHex: "#000", joinURL: url ? URL(string: "https://meet.google.com/x") : nil)
        }
        XCTAssertNil(WidgetSnapshot(meetings: [m("later", in: 20)], savedAt: base).joinable(at: base))
        XCTAssertEqual(WidgetSnapshot(meetings: [m("soon", in: 8)], savedAt: base).joinable(at: base)?.id, "soon")
        XCTAssertEqual(WidgetSnapshot(meetings: [m("soon", in: 8), m("live", in: -5)], savedAt: base).joinable(at: base)?.id, "live")
        XCTAssertNil(WidgetSnapshot(meetings: [m("nolink", in: -5, url: false)], savedAt: base).joinable(at: base))
    }

    func testSiriSentences() {
        let base = at(9)
        let soon = WidgetMeeting(id: "a", title: "Standup", start: base.addingTimeInterval(20 * 60), end: base.addingTimeInterval(35 * 60),
                                 colorHex: "#000", joinURL: nil)
        let s = WidgetSnapshot(meetings: [soon], savedAt: base)
        XCTAssertTrue(NextMeetingIntent.sentence(s, now: base).hasPrefix("Standup starts in 20 minutes"))
        XCTAssertTrue(NextMeetingIntent.sentence(s, now: base, joinable: false).hasPrefix("Nothing to join yet. Standup"))
        XCTAssertTrue(NextMeetingIntent.sentence(s, now: base.addingTimeInterval(25 * 60)).hasPrefix("You're in Standup until"))
        XCTAssertEqual(NextMeetingIntent.sentence(nil, now: base), "Open Meetball once so it can read your calendar.")
        XCTAssertEqual(NextMeetingIntent.sentence(WidgetSnapshot(meetings: [], savedAt: base), now: base),
                       "No meetings in the next two days. Enjoy it.")
    }

    func testOldSettingsGetTheCountdownMoment() throws {
        let s = try JSONDecoder().decode(PhoneSettings.self, from: Data(#"{"leadMinutes":15}"#.utf8))
        XCTAssertEqual(s.leadMinutes, 15)
        XCTAssertTrue(s.countdownMoment)
    }
}
