import XCTest
@testable import MeetballPhone

private let now = Date(timeIntervalSince1970: 1_800_000_000)

private func ev(_ id: String, _ title: String = "Standup", in minutes: Double, length: Double = 30,
                calendar: String = "work") -> CalendarEvent {
    CalendarEvent(id: id, calendarID: calendar, accountEmail: "Apple · iCloud", title: title,
                  start: now.addingTimeInterval(minutes * 60), end: now.addingTimeInterval((minutes + length) * 60),
                  isAllDay: false, meetURL: nil, location: nil, attendees: [], htmlLink: nil)
}

final class PhoneAgendaTests: XCTestCase {
    func testDedupeKeepsAMirroredMeetingOnce() {
        let out = PhoneAgenda.dedupe([ev("a", in: 60, calendar: "work"), ev("b", "standup ", in: 60, calendar: "icloud"),
                                      ev("c", in: 120)])
        XCTAssertEqual(out.count, 2)
        XCTAssertEqual(out.map(\.start), [now.addingTimeInterval(3600), now.addingTimeInterval(7200)])
    }

    func testDedupeKeepsDifferentLengths() {
        XCTAssertEqual(PhoneAgenda.dedupe([ev("a", in: 60), ev("b", in: 60, length: 60)]).count, 2)
    }

    func testChangeCardFromChanges() {
        let moved = MeetingChange(kind: .rescheduled(from: now.addingTimeInterval(3600), to: now.addingTimeInterval(7200)),
                                  event: ev("a", "Design review", in: 120))
        let card = ChangeCard(moved, now: now)
        XCTAssertEqual(card.kind, .moved)
        XCTAssertEqual(card.eventTitle, "Design review")
        XCTAssertEqual(card.caption, "Moved")
        XCTAssertEqual(ChangeCard(MeetingChange(kind: .cancelled, event: ev("b", in: 30)), now: now).kind, .cancelled)
        XCTAssertEqual(ChangeCard(MeetingChange(kind: .linkChanged, event: ev("c", in: 30)), now: now).kind, .link)
    }

    func testMergedReplacesTheSameMeetingAndDropsOldOnes() {
        let old = ChangeCard(kind: .moved, eventTitle: "Design review", detail: "old", start: now.addingTimeInterval(3600), at: now)
        let stale = ChangeCard(kind: .moved, eventTitle: "Last week", detail: "", start: now.addingTimeInterval(-3 * 86400), at: now)
        let other = ChangeCard(kind: .link, eventTitle: "1:1", detail: "", start: now.addingTimeInterval(3600), at: now)
        let new = ChangeCard(kind: .cancelled, eventTitle: "Design Review", detail: "new", start: now.addingTimeInterval(3600), at: now)
        let out = ChangeCard.merged([old, stale, other], [new], now: now)
        XCTAssertEqual(out.map(\.detail), ["new", ""])
        XCTAssertEqual(out.map(\.eventTitle), ["Design Review", "1:1"])
    }

    func testMergedCapsTheList() {
        let cards = (0..<12).map { ChangeCard(kind: .moved, eventTitle: "M\($0)", detail: "", start: now, at: now) }
        XCTAssertEqual(ChangeCard.merged([], cards, now: now, limit: 8).count, 8)
    }

    func testCelebrationOnlyForCancellations() {
        XCTAssertNil(Celebration([MeetingChange(kind: .linkChanged, event: ev("a", in: 30))]))
        let party = Celebration([MeetingChange(kind: .linkChanged, event: ev("a", in: 30)),
                                 MeetingChange(kind: .cancelled, event: ev("b", "Budget sync", in: 60)),
                                 MeetingChange(kind: .cancelled, event: ev("c", in: 90))])
        XCTAssertEqual(party?.title, "Budget sync")
        XCTAssertEqual(party?.extra, 1)
    }

    func testLoadSegments() {
        XCTAssertEqual(PhoneAgenda.loadSegments(0), 0)
        XCTAssertEqual(PhoneAgenda.loadSegments(0.1), 1)
        XCTAssertEqual(PhoneAgenda.loadSegments(4), 4)
        XCTAssertEqual(PhoneAgenda.loadSegments(20), 8)
    }

    func testMonthWeeksAreWholeWeeks() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        cal.firstWeekday = 2
        let anchor = cal.date(from: DateComponents(year: 2026, month: 11, day: 15))!
        let weeks = PhoneAgenda.monthWeeks(anchor: anchor, calendar: cal)
        XCTAssertTrue(weeks.allSatisfy { $0.count == 7 })
        XCTAssertEqual(cal.component(.weekday, from: weeks[0][0]), 2)
        XCTAssertTrue(weeks.flatMap { $0 }.contains { cal.isDate($0, inSameDayAs: cal.date(from: DateComponents(year: 2026, month: 11, day: 30))!) })
        XCTAssertEqual(PhoneAgenda.weekdaySymbols(calendar: cal).count, 7)
    }

    func testOldSettingsKeepTheirValuesAndGetNewDefaults() throws {
        let json = #"{"leadMinutes":5,"alertAtStart":true,"notifyChanges":false,"hiddenCalendars":["a|b"]}"#
        let s = try JSONDecoder().decode(PhoneSettings.self, from: Data(json.utf8))
        XCTAssertEqual(s.leadMinutes, 5)
        XCTAssertTrue(s.alertAtStart)
        XCTAssertFalse(s.notifyChanges)
        XCTAssertEqual(s.hiddenCalendars, ["a|b"])
        XCTAssertTrue(s.celebrateCancellations)
        var round = s
        round.celebrateCancellations = false
        XCTAssertEqual(try JSONDecoder().decode(PhoneSettings.self, from: JSONEncoder().encode(round)), round)
    }
}
