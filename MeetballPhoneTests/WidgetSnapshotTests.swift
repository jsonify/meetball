import XCTest
@testable import MeetballPhone

private let now = Date(timeIntervalSinceReferenceDate: 799_999_200) // on a quarter hour

private func m(_ id: String, in minutes: Double, length: Double = 30) -> WidgetMeeting {
    WidgetMeeting(id: id, title: id, start: now.addingTimeInterval(minutes * 60),
                  end: now.addingTimeInterval((minutes + length) * 60), colorHex: "#E8743B", joinURL: nil)
}

final class WidgetSnapshotTests: XCTestCase {
    func testCurrentPrefersTheMeetingOnNow() {
        let s = WidgetSnapshot(meetings: [m("next", in: 20), m("live", in: -10)], savedAt: now)
        XCTAssertEqual(s.current(at: now)?.id, "live")
        XCTAssertEqual(s.current(at: now.addingTimeInterval(25 * 60))?.id, "next")
        XCTAssertNil(s.current(at: now.addingTimeInterval(3 * 3600)))
    }

    func testLaterSkipsTheCurrentMeeting() {
        let s = WidgetSnapshot(meetings: [m("a", in: 10), m("b", in: 60), m("c", in: 120), m("d", in: 180)], savedAt: now)
        XCTAssertEqual(s.later(than: s.current(at: now), now: now, limit: 2).map(\.id), ["b", "c"])
    }

    func testTimelineIsPerMinuteNearAMeetingAndSparseOtherwise() {
        let s = WidgetSnapshot(meetings: [m("a", in: 3 * 60)], savedAt: now)
        let dates = s.timelineDates(from: now, span: 5 * 3600)
        XCTAssertEqual(dates.first, now)
        let gaps = zip(dates, dates.dropFirst()).map { $1.timeIntervalSince($0) }
        XCTAssertTrue(gaps.allSatisfy { $0 > 0 && $0 <= 15 * 60 })
        // Sparse until the hour before, every minute from then until it ends.
        let hourBefore = now.addingTimeInterval(2 * 3600)
        XCTAssertTrue(dates.contains(hourBefore))
        XCTAssertTrue(dates.contains(now.addingTimeInterval(3 * 3600)))
        XCTAssertTrue(dates.contains(now.addingTimeInterval(3 * 3600 + 60)))
        XCTAssertFalse(dates.contains(now.addingTimeInterval(60)))
        XCTAssertLessThanOrEqual(dates.count, 240)
    }

    func testSaveReportsChanges() {
        let d = UserDefaults(suiteName: "WidgetSnapshotTests")!
        d.removePersistentDomain(forName: "WidgetSnapshotTests")
        let s = WidgetSnapshot(meetings: [m("a", in: 10)], savedAt: now)
        XCTAssertTrue(s.save(to: d))
        XCTAssertFalse(WidgetSnapshot(meetings: s.meetings, savedAt: now.addingTimeInterval(60)).save(to: d))
        XCTAssertEqual(WidgetSnapshot.load(from: d)?.meetings, s.meetings)
    }

    func testCountdownDigits() {
        XCTAssertEqual(WidgetCountdown.digits(42 * 60).digits, "42")
        XCTAssertEqual(WidgetCountdown.digits(65 * 60).digits, "1:05")
        XCTAssertEqual(WidgetCountdown.digits(3 * 86400).unit, "DAYS")
    }

    func testLinksRoundTripAndOnlyJoinWebLinks() {
        let meet = URL(string: "https://meet.google.com/abc-defg-hij?authuser=0")!
        XCTAssertEqual(MeetballLink.parse(MeetballLink.join(meet)), .join(meet))
        XCTAssertEqual(MeetballLink.parse(MeetballLink.today), .today)
        XCTAssertEqual(MeetballLink.parse(URL(string: "meetball://join?url=tel:123")!), .today)
        XCTAssertNil(MeetballLink.parse(URL(string: "https://example.com")!))
    }

    func testLiveActivityOnlyInTheLastHour() {
        func ev(_ minutes: Double) -> CalendarEvent {
            CalendarEvent(id: "\(minutes)", calendarID: "c", accountEmail: "a", title: "T", start: now.addingTimeInterval(minutes * 60),
                          end: now.addingTimeInterval((minutes + 30) * 60), isAllDay: false, meetURL: nil, location: nil,
                          attendees: [], htmlLink: nil)
        }
        XCTAssertNil(LiveActivityController.meeting(from: [ev(90)], now: now))
        XCTAssertEqual(LiveActivityController.meeting(from: [ev(90), ev(45)], now: now)?.id, "45.0")
        XCTAssertEqual(LiveActivityController.meeting(from: [ev(-10)], now: now)?.id, "-10.0")
    }
}
