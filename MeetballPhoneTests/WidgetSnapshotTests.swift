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

    func testOverlappingAndFollowing() {
        let s = WidgetSnapshot(meetings: [m("a", in: 0), m("clash", in: 15), m("then", in: 45), m("after", in: 90)], savedAt: now)
        let a = s.meetings[0]
        XCTAssertEqual(s.overlapping(a, at: now).map(\.id), ["clash"])
        XCTAssertEqual(s.overlapping(s.meetings[2], at: now), [])
        XCTAssertEqual(s.following(a)?.id, "then")
        XCTAssertNil(s.following(s.meetings[3]))
    }

    func testProgress() {
        let live = m("live", in: -10, length: 40)
        XCTAssertEqual(WidgetSnapshot.progress(of: live, at: now)!, 0.25, accuracy: 0.001)
        XCTAssertEqual(WidgetSnapshot.progress(of: m("soon", in: 15), at: now)!, 0.75, accuracy: 0.001)
        XCTAssertNil(WidgetSnapshot.progress(of: m("far", in: 90), at: now))
    }

    func testService() {
        XCTAssertEqual(WidgetService.name(URL(string: "https://meet.google.com/abc-defg-hij")), "Meet")
        XCTAssertEqual(WidgetService.name(URL(string: "https://acme.zoom.us/j/123")), "Zoom")
        XCTAssertEqual(WidgetService.name(URL(string: "https://teams.microsoft.com/l/meetup-join/x")), "Teams")
        XCTAssertNil(WidgetService.name(URL(string: "https://example.com/call")))
        XCTAssertNil(WidgetService.name(nil))
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

    // MARK: The readout and the tape

    private var utc: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        c.locale = Locale(identifier: "en_US")
        return c
    }

    func testReadoutCountsDownInsideTheHourAndShowsTheTimeBefore() {
        let s = WidgetSnapshot(meetings: [m("a", in: 42)], savedAt: now)
        let soon = WidgetReadout.make(s, at: now, calendar: utc, twentyFourHour: false)
        XCTAssertEqual(soon.phase, .soon)
        XCTAssertEqual([soon.caption, soon.digits, soon.unit, soon.message], ["STARTS IN", "42", "MIN", "a"])

        let live = WidgetReadout.make(s, at: now.addingTimeInterval(50 * 60), calendar: utc, twentyFourHour: false)
        XCTAssertEqual(live.phase, .live)
        XCTAssertEqual([live.digits, live.unit], ["22", "MIN"])

        let far = WidgetSnapshot(meetings: [m("b", in: 180)], savedAt: now)
        let later = WidgetReadout.make(far, at: now, calendar: utc, twentyFourHour: true)
        let start = WidgetClock.digits(far.meetings[0].start, calendar: utc, twentyFourHour: true)
        XCTAssertEqual(later.phase, .later)
        XCTAssertEqual(later.digits, start.digits)
        XCTAssertTrue(later.caption.hasSuffix(" AT"))
    }

    func testReadoutAlwaysHasSomethingToSay() {
        let none = WidgetReadout.make(nil, at: now, calendar: utc)
        XCTAssertEqual(none.phase, .stale)
        XCTAssertFalse(none.message.isEmpty)

        let empty = WidgetSnapshot(meetings: [], savedAt: now)
        let clear = WidgetReadout.make(empty, at: now.addingTimeInterval(3600), calendar: utc)
        XCTAssertEqual(clear.phase, .clear)
        XCTAssertEqual([clear.caption, clear.digits, clear.unit], ["ALL CLEAR", "0", "LEFT"])
        XCTAssertTrue(clear.message.hasPrefix("Nothing through "))

        let old = WidgetReadout.make(empty, at: now.addingTimeInterval(WidgetSnapshot.horizon + 60), calendar: utc)
        XCTAssertEqual(old.phase, .stale)
    }

    func testClockDigits() {
        let nine = utc.date(from: DateComponents(year: 2026, month: 11, day: 9, hour: 9, minute: 5))!
        let midnight = utc.date(from: DateComponents(year: 2026, month: 11, day: 9, hour: 0, minute: 30))!
        let evening = utc.date(from: DateComponents(year: 2026, month: 11, day: 9, hour: 20, minute: 0))!
        XCTAssertEqual(WidgetClock.digits(nine, calendar: utc, twentyFourHour: false).digits, "9:05")
        XCTAssertEqual(WidgetClock.digits(nine, calendar: utc, twentyFourHour: false).unit, "AM")
        XCTAssertEqual(WidgetClock.digits(midnight, calendar: utc, twentyFourHour: false).digits, "12:30")
        XCTAssertEqual(WidgetClock.digits(evening, calendar: utc, twentyFourHour: false).unit, "PM")
        XCTAssertEqual(WidgetClock.digits(evening, calendar: utc, twentyFourHour: true).digits, "20:00")
        XCTAssertEqual(WidgetClock.digits(evening, calendar: utc, twentyFourHour: true).unit, "")
    }

    func testTapeLightsTheHalfHoursWithMeetings() {
        // The tape starts at the half hour `now` is in; a meeting that's over lights nothing.
        let s = WidgetSnapshot(meetings: [m("gone", in: -40, length: 30), m("a", in: 45, length: 60)], savedAt: now)
        let tape = s.tape(from: now, slots: 6)
        XCTAssertEqual(tape.count, 6)
        XCTAssertLessThanOrEqual(tape[0].start, now)
        XCTAssertLessThan(now.timeIntervalSince(tape[0].start), 1800)
        XCTAssertEqual(tape[1].start.timeIntervalSince(tape[0].start), 1800)
        let lit = tape.filter { $0.colorHex != nil }.map(\.start)
        XCTAssertFalse(lit.isEmpty)
        for slot in tape {
            let end = slot.start.addingTimeInterval(1800)
            let a = s.meetings[1]
            XCTAssertEqual(slot.colorHex != nil, a.start < end && a.end > slot.start, "\(slot.start)")
        }
    }

    func testTapeLabelsEveryThirdHour() {
        let nine = utc.date(from: DateComponents(year: 2026, month: 11, day: 9, hour: 9))!
        XCTAssertEqual(WidgetTapeSlot(start: nine).label(calendar: utc, twentyFourHour: false), "9")
        XCTAssertNil(WidgetTapeSlot(start: nine.addingTimeInterval(1800)).label(calendar: utc, twentyFourHour: false))
        XCTAssertNil(WidgetTapeSlot(start: nine.addingTimeInterval(3600)).label(calendar: utc, twentyFourHour: false))
        XCTAssertEqual(WidgetTapeSlot(start: nine.addingTimeInterval(3 * 3600)).label(calendar: utc, twentyFourHour: false), "12")
        XCTAssertEqual(WidgetTapeSlot(start: nine.addingTimeInterval(6 * 3600)).label(calendar: utc, twentyFourHour: false), "3")
        XCTAssertEqual(WidgetTapeSlot(start: nine.addingTimeInterval(6 * 3600)).label(calendar: utc, twentyFourHour: true), "15")
    }

    func testTapeStartsAtTheNextMeetingsDayWhenItIsNotToday() {
        let noon = utc.date(from: DateComponents(year: 2026, month: 11, day: 9, hour: 12))!
        func at(_ id: String, _ hours: Double) -> WidgetMeeting {
            WidgetMeeting(id: id, title: id, start: noon.addingTimeInterval(hours * 3600),
                          end: noon.addingTimeInterval(hours * 3600 + 1800), colorHex: "#E8743B", joinURL: nil)
        }
        let today = WidgetSnapshot(meetings: [at("a", 3), at("b", 22)], savedAt: noon)
        XCTAssertEqual(today.tapeStart(at: noon, calendar: utc), noon)
        // At 10 PM the next one is tomorrow at 9: the tape starts at 8, an hour before tomorrow's first.
        let evening = noon.addingTimeInterval(10 * 3600)
        let tomorrow = WidgetSnapshot(meetings: [at("late", 23), at("early", 21)], savedAt: noon)
        XCTAssertEqual(tomorrow.tapeStart(at: evening, calendar: utc), noon.addingTimeInterval(20 * 3600))
        XCTAssertNotNil(tomorrow.tape(from: tomorrow.tapeStart(at: evening, calendar: utc), slots: 16).first { $0.colorHex != nil })
        // Just before midnight with one at half past: never earlier than now.
        let late = noon.addingTimeInterval(11.9 * 3600)
        XCTAssertEqual(WidgetSnapshot(meetings: [at("x", 12.5)], savedAt: noon).tapeStart(at: late, calendar: utc), late)
        XCTAssertEqual(WidgetSnapshot(meetings: [], savedAt: noon).tapeStart(at: noon, calendar: utc), noon)
    }
}
