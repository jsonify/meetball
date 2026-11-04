import XCTest
@testable import Meetball

final class LogicTests: XCTestCase {
    let cal = Calendar.current
    func ev(_ id: String, _ s: Date, _ e: Date, allDay: Bool = false) -> CalendarEvent {
        CalendarEvent(id: id, calendarID: "c", accountEmail: "a@b.c", title: id, start: s, end: e, isAllDay: allDay, meetURL: nil, location: nil, attendees: [], htmlLink: nil)
    }

    func testTimeUntil() {
        let now = Date()
        XCTAssertEqual(TimeUntilFormatter.string(until: now.addingTimeInterval(-5), now: now), "now")
        XCTAssertEqual(TimeUntilFormatter.string(until: now.addingTimeInterval(300), now: now), "5m")
        XCTAssertEqual(TimeUntilFormatter.string(until: now.addingTimeInterval(4800), now: now), "1h 20m")
    }

    func testMultiDayEventSplitsIntoSegments() {
        let d0 = cal.date(from: DateComponents(year: 2026, month: 3, day: 10, hour: 22))!
        let d1 = cal.date(from: DateComponents(year: 2026, month: 3, day: 12, hour: 2))!
        let range = CalendarVisibleRangeBuilder.build(anchor: d0)
        let out = CalendarDerivedEventsBuilder.build(events: [ev("x", d0, d1)], range: range)
        let segs = out.segmentsByDay.values.flatMap { $0 }.sorted { $0.day < $1.day }
        XCTAssertEqual(segs.count, 3)
        XCTAssertTrue(segs[0].startsOnThisDay && segs[0].continuesAfter)
        XCTAssertTrue(segs[1].continuesBefore && segs[1].continuesAfter)
        XCTAssertTrue(segs[2].continuesBefore && segs[2].endsOnThisDay)
    }

    func testOverlappingBarsGetDifferentLanes() {
        let s = cal.date(from: DateComponents(year: 2026, month: 3, day: 10))!
        let a = ev("a", s, s.addingTimeInterval(3 * 86400), allDay: true)
        let b = ev("b", s.addingTimeInterval(86400), s.addingTimeInterval(4 * 86400), allDay: true)
        let out = CalendarDerivedEventsBuilder.build(events: [a, b], range: CalendarVisibleRangeBuilder.build(anchor: s))
        let spans = out.weeks.flatMap(\.spans)
        XCTAssertEqual(Set(spans.filter { $0.event.id == "a" || $0.event.id == "b" }.map(\.lane)).count, 2)
    }

    func testNewEventRangeIsThirtyMinutes() {
        let r = NewEventDateRangeBuilder.build(day: Date().addingTimeInterval(86400 * 3))
        XCTAssertEqual(r.end.timeIntervalSince(r.start), 1800)
    }

    @MainActor func testGuardianRules() {
        let store = MeetingGuardianStore(defaults: UserDefaults(suiteName: "test.\(UUID())")!)
        store.upsert(CalendarRule(calendarKey: "a|1", style: .hard))
        store.upsert(CalendarRule(calendarKey: "a|1", style: nil))
        store.upsert(CalendarRule(calendarKey: "a|2", style: .soft))
        XCTAssertEqual(store.calendarRules.count, 2)
        XCTAssertNil(store.rule(for: "a|1")?.style)
        store.removeRulesNotIn(["a|2"])
        XCTAssertEqual(store.calendarRules.map(\.calendarKey), ["a|2"])
    }
}

final class KeychainTests: XCTestCase {
    func testRoundTrip() {
        let k = KeychainClient(service: "app.meetball.test.\(UUID())")
        k.set("tok", for: "x")
        XCTAssertEqual(k.get("x"), "tok", "Keychain write/read failed (signing/entitlements?)")
        k.remove("x"); XCTAssertNil(k.get("x"))
    }
}
