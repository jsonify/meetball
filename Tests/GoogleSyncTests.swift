import XCTest
@testable import Meetball

final class GoogleSyncTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func at(_ hours: Double) -> Date { t0.addingTimeInterval(hours * 3600) }

    private func ev(_ id: String, _ startHour: Double, _ hours: Double = 1, series: String? = nil) -> CalendarEvent {
        var e = CalendarEvent(id: id, calendarID: "cal", accountEmail: "me@example.com", title: id, start: at(startHour),
                              end: at(startHour + hours), isAllDay: false, meetURL: nil, location: nil, attendees: [], htmlLink: nil)
        e.seriesID = series
        return e
    }

    private var window: DateInterval { DateInterval(start: at(0), end: at(48)) }

    func testFullSyncKeepsOnlyTheWindow() {
        let s = GoogleSyncState(window: window, token: "t1", events: [ev("a", 1), ev("b", 60), ev("c", -2, 3)], at: t0)
        // "c" runs into the window; "b" is past it.
        XCTAssertEqual(Set(s.events.keys), ["a", "c"])
        XCTAssertEqual(s.events(in: DateInterval(start: at(0), end: at(2))).map(\.id), ["c", "a"])
    }

    func testIncrementalChangesFoldIn() {
        let s = GoogleSyncState(window: window, token: "t1", events: [ev("a", 1), ev("b", 5)], at: t0)
        let moved = ev("a", 3)
        let next = s.applying([.upsert(moved), .remove(id: "b"), .upsert(ev("new", 10)), .upsert(ev("far", 100))], token: "t2")
        XCTAssertEqual(next.token, "t2")
        XCTAssertEqual(next.events["a"], moved)
        XCTAssertNil(next.events["b"])
        XCTAssertNotNil(next.events["new"])
        // A change outside the window isn't kept, and one moving out of it leaves.
        XCTAssertNil(next.events["far"])
        XCTAssertNil(next.applying([.upsert(ev("a", 90))], token: "t3").events["a"])
        // Removing an event Meetball never had is harmless.
        XCTAssertEqual(s.applying([.remove(id: "zzz")], token: "t2").events, s.events)
    }

    func testCoversOnlyInsideTheWindowWithATokenAndNotTooOld() {
        let s = GoogleSyncState(window: window, token: "t1", events: [], at: t0)
        let inside = DateInterval(start: at(2), end: at(30))
        XCTAssertTrue(s.covers(inside, now: at(1)))
        XCTAssertFalse(s.covers(DateInterval(start: at(-1), end: at(30)), now: at(1)))
        XCTAssertFalse(s.covers(DateInterval(start: at(2), end: at(50)), now: at(1)))
        // A full sync comes round every maxAge.
        XCTAssertFalse(s.covers(inside, now: t0.addingTimeInterval(GoogleSyncState.maxAge + 1)))
        // No token from Google: every refresh is a full one.
        XCTAssertFalse(GoogleSyncState(window: window, token: nil, events: [], at: t0).covers(inside, now: at(1)))
    }

    func testChangesToRecurringMeetingsAskForAFullSync() {
        let s = GoogleSyncState(window: window, token: "t1", events: [ev("plain", 1), ev("weekly_1", 2, series: "weekly")], at: t0)
        XCTAssertFalse(s.touchesSeries([.upsert(ev("plain", 4)), .remove(id: "plain"), .upsert(ev("other", 6))]))
        XCTAssertTrue(s.touchesSeries([.upsert(ev("weekly_2", 26, series: "weekly"))]))
        XCTAssertTrue(s.touchesSeries([.remove(id: "weekly_1")]))
        // The whole series cancelled: its id is the occurrences' series.
        XCTAssertTrue(s.touchesSeries([.remove(id: "weekly")]))
    }

    func testFullSyncWindowPadsAndJoins() {
        let range = DateInterval(start: at(0), end: at(24))
        let w = GoogleSyncState.window(for: range, previous: nil)
        XCTAssertEqual(w.start, at(-7 * 24))
        XCTAssertEqual(w.end, at(24 + 14 * 24))
        // A nearby range joins the previous window; a far one replaces it.
        let next = GoogleSyncState.window(for: DateInterval(start: at(20 * 24), end: at(21 * 24)), previous: w)
        XCTAssertEqual(next.start, w.start)
        let far = GoogleSyncState.window(for: DateInterval(start: at(400 * 24), end: at(401 * 24)), previous: w)
        XCTAssertEqual(far.start, at(393 * 24))
    }
}
