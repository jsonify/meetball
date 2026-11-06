import XCTest
@testable import MeetballPhone

final class MeetingComposerTests: XCTestCase {
    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return c
    }()

    /// Thu 5 Nov 2026 at `h`:`m` Pacific.
    private func at(_ h: Int, _ m: Int = 0, day: Int = 5) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 11, day: day, hour: h, minute: m))!
    }

    private func ev(_ title: String, _ s: Date, _ e: Date, allDay: Bool = false) -> CalendarEvent {
        CalendarEvent(id: title, calendarID: "c", accountEmail: "Apple · iCloud", title: title, start: s, end: e,
                      isAllDay: allDay, meetURL: nil, location: nil, attendees: [], htmlLink: nil)
    }

    func testConflictsIgnoreAllDayAndTouchingMeetings() {
        let events = [ev("Standup", at(9), at(9, 30)), ev("Offsite", at(0), at(23, 59), allDay: true),
                      ev("Lunch", at(12), at(13)), ev("Review", at(10), at(11))]
        let clashes = MeetingComposer.conflicts(start: at(9, 30), end: at(10, 15), in: events)
        XCTAssertEqual(clashes.map(\.title), ["Review"])
        XCTAssertEqual(MeetingComposer.conflictSummary(clashes), "Overlaps Review")
        XCTAssertNil(MeetingComposer.conflictSummary([]))
        let two = MeetingComposer.conflicts(start: at(9), end: at(12, 30), in: events)
        XCTAssertEqual(MeetingComposer.conflictSummary(two), "Overlaps Standup +2")
    }

    func testFreeSlotsTakeOnePerGapInWorkingHours() {
        let events = [ev("Standup", at(9), at(9, 30)), ev("Review", at(10), at(11)), ev("Lunch", at(12), at(13)),
                      ev("Planning", at(13), at(17, 30))]
        let slots = MeetingComposer.freeSlots(length: 30 * 60, events: events, now: at(8, 50), calendar: cal)
        // 9:30 fits before Review, 11:00 before Lunch, and 17:30 after Planning fits exactly before 18:00.
        XCTAssertEqual(slots, [at(9, 30), at(11), at(17, 30)])
        let hour = MeetingComposer.freeSlots(length: 60 * 60, events: events, now: at(8, 50), calendar: cal)
        XCTAssertEqual(hour.first, at(11))
    }

    func testFreeSlotsStartAfterNowOnAQuarterHourAndSkipTheWeekend() {
        // Fri 6 Nov 17:07: no room before 18:00 for an hour, so the next is Monday 9:00.
        let slots = MeetingComposer.freeSlots(length: 60 * 60, events: [], now: at(17, 7, day: 6), limit: 1, calendar: cal)
        XCTAssertEqual(slots, [at(9, day: 9)])
        let soon = MeetingComposer.freeSlots(length: 15 * 60, events: [], now: at(14, 7), limit: 1, calendar: cal)
        XCTAssertEqual(soon, [at(14, 15)])
    }

    func testRoundUp() {
        XCTAssertEqual(MeetingComposer.roundUp(at(14, 15)), at(14, 15))
        XCTAssertEqual(MeetingComposer.roundUp(at(14, 15).addingTimeInterval(1)), at(14, 30))
        XCTAssertEqual(MeetingComposer.roundUp(at(14, 59)), at(15))
    }

    func testGoogleCalendarLinkCarriesTimesGuestsAndAccount() throws {
        let url = try XCTUnwrap(MeetingComposer.googleCalendarURL(title: "1:1 & budget", start: at(14), end: at(14, 45),
                                                                  guests: ["sam@work.com", "ana@work.com"],
                                                                  account: "jason@work.com"))
        let c = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(c.host, "calendar.google.com")
        let q = Dictionary(uniqueKeysWithValues: (c.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(q["action"], "TEMPLATE")
        XCTAssertEqual(q["text"], "1:1 & budget")
        XCTAssertEqual(q["dates"], "20261105T220000Z/20261105T224500Z")
        XCTAssertEqual(q["add"], "sam@work.com,ana@work.com")
        XCTAssertEqual(q["authuser"], "jason@work.com")
        let bare = try XCTUnwrap(MeetingComposer.googleCalendarURL(title: "x", start: at(9), end: at(10)))
        XCTAssertFalse(bare.absoluteString.contains("authuser"))
        XCTAssertFalse(bare.absoluteString.contains("add="))
    }
}
