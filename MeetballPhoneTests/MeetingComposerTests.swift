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

    func testGoogleEditLinkNamesTheEventOnYourCalendar() throws {
        var e = ev("Budget review", at(14), at(15))
        e.externalID = "7kq2abc0def@google.com"
        e.organizerEmail = "boss@work.com"
        let url = try XCTUnwrap(GoogleEventLink.editURL(for: e, account: " Jason@Work.com "))
        let c = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(c.host, "calendar.google.com")
        XCTAssertTrue(c.path.hasPrefix("/calendar/r/eventedit/"))
        let eid = String(c.path.dropFirst("/calendar/r/eventedit/".count))
        XCTAssertFalse(eid.contains("="))
        let padded = eid.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
            + String(repeating: "=", count: (4 - eid.count % 4) % 4)
        let decoded = try XCTUnwrap(Data(base64Encoded: padded).flatMap { String(data: $0, encoding: .utf8) })
        XCTAssertEqual(decoded, "7kq2abc0def jason@work.com")
        XCTAssertEqual(c.queryItems?.first { $0.name == "authuser" }?.value, "jason@work.com")
    }

    func testGoogleEditLinkFallsBackToOrganizerAndNamesTheOccurrence() throws {
        var e = ev("Standup", at(9), at(9, 15))
        e.externalID = "abc123@google.com"
        e.organizerEmail = "jason@work.com"
        e.occurrenceDate = at(9)
        let url = try XCTUnwrap(GoogleEventLink.editURL(for: e, account: "", calendar: cal))
        let eid = String(url.path.dropFirst("/calendar/r/eventedit/".count))
        let padded = eid.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
            + String(repeating: "=", count: (4 - eid.count % 4) % 4)
        let decoded = try XCTUnwrap(Data(base64Encoded: padded).flatMap { String(data: $0, encoding: .utf8) })
        XCTAssertEqual(decoded, "abc123_20261105T170000Z jason@work.com")

        XCTAssertEqual(GoogleEventLink.instanceID("abc123", occurrence: at(0), allDay: true, calendar: cal), "abc123_20261105")
    }

    func testGoogleEditLinkOnlyForGoogleEvents() {
        var e = ev("Dentist", at(9), at(10))
        e.externalID = "5F1C-22@icloud.com"
        e.organizerEmail = "jason@work.com"
        XCTAssertFalse(GoogleEventLink.isFromGoogle(e))
        XCTAssertNil(GoogleEventLink.editURL(for: e, account: "jason@work.com"))
        e.externalID = "abc@google.com"
        e.organizerEmail = nil
        XCTAssertTrue(GoogleEventLink.isFromGoogle(e))
        XCTAssertNil(GoogleEventLink.editURL(for: e, account: nil))
        XCTAssertNotNil(GoogleEventLink.searchURL(for: e, account: nil))
    }
}
