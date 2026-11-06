import XCTest
@testable import Meetball

private func cal() -> Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "America/Los_Angeles")!
    c.firstWeekday = 1
    return c
}

private func at(_ y: Int, _ mo: Int, _ d: Int, _ h: Int = 0, _ mi: Int = 0) -> Date {
    cal().date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi))!
}

private func ev(_ id: String, _ title: String = "Sync", start: Date, minutes: Double = 30, allDay: Bool = false, end: Date? = nil,
                url: String? = "https://meet.google.com/abc-defg-hij", declined: Bool = false, series: String? = nil,
                calendar: String = "cal") -> CalendarEvent {
    var e = CalendarEvent(id: id, calendarID: calendar, accountEmail: "me@example.com", title: title, start: start,
                          end: end ?? start.addingTimeInterval(minutes * 60), isAllDay: allDay, meetURL: url.flatMap(URL.init(string:)),
                          location: nil, attendees: [], htmlLink: nil)
    e.isDeclined = declined
    e.seriesID = series
    return e
}

/// Meeting change and cancellation detection (#30).
final class MeetingChangeTests: XCTestCase {
    let now = at(2030, 11, 6, 9)
    let range = DateInterval(start: at(2030, 11, 1), end: at(2030, 12, 1))

    func snap(_ events: [CalendarEvent], calendars: Set<String> = ["me@example.com|cal"]) -> EventSnapshot {
        EventSnapshot(events: events, calendars: calendars, range: range)
    }

    func testCancelledWhenMeetingDisappears() {
        let a = ev("a", start: at(2030, 11, 6, 14))
        let changes = MeetingChangeDetector.diff(old: snap([a]), new: snap([]), now: now)
        XCTAssertEqual(changes, [MeetingChange(kind: .cancelled, event: a)])
    }

    func testCancelledTitlePrefix() {
        let a = ev("a", "Design review", start: at(2030, 11, 6, 14))
        var b = a; b.title = "Canceled: Design review"
        XCTAssertEqual(MeetingChangeDetector.diff(old: snap([a]), new: snap([b]), now: now).map(\.kind), [.cancelled])
        XCTAssertTrue(MeetingChangeDetector.isCancelTitle("Cancelled: x"))
        XCTAssertFalse(MeetingChangeDetector.isCancelTitle("Why we canceled the launch"))
    }

    func testRescheduled() {
        let a = ev("a", start: at(2030, 11, 6, 14))
        let b = ev("a", start: at(2030, 11, 6, 15))
        XCTAssertEqual(MeetingChangeDetector.diff(old: snap([a]), new: snap([b]), now: now).map(\.kind),
                       [.rescheduled(from: at(2030, 11, 6, 14), to: at(2030, 11, 6, 15))])
    }

    func testAppleOccurrenceIDFollowsTheMove() {
        // Apple Calendar ids carry the start time, so a moved event comes back with a new id.
        let a = ev("ABC@\(Int(at(2030, 11, 6, 14).timeIntervalSince1970))", start: at(2030, 11, 6, 14))
        let b = ev("ABC@\(Int(at(2030, 11, 7, 10).timeIntervalSince1970))", start: at(2030, 11, 7, 10))
        let changes = MeetingChangeDetector.diff(old: snap([a]), new: snap([b]), now: now)
        XCTAssertEqual(changes.map(\.kind), [.rescheduled(from: at(2030, 11, 6, 14), to: at(2030, 11, 7, 10))])
    }

    func testMoveIsFollowedWhenCalendarAppGivesTheEventANewIdentifier() {
        // Exchange/CalDAV: editing in Calendar.app can change eventIdentifier, so neither uid nor base id matches.
        let a = ev("OLD@\(Int(at(2030, 11, 6, 14).timeIntervalSince1970))", "Design review", start: at(2030, 11, 6, 14))
        let b = ev("NEW@\(Int(at(2030, 11, 6, 16).timeIntervalSince1970))", "Design review", start: at(2030, 11, 6, 16))
        let other = ev("X@\(Int(at(2030, 11, 6, 15).timeIntervalSince1970))", "Lunch", start: at(2030, 11, 6, 15))
        XCTAssertEqual(MeetingChangeDetector.diff(old: snap([a]), new: snap([other, b]), now: now).map(\.kind),
                       [.rescheduled(from: at(2030, 11, 6, 14), to: at(2030, 11, 6, 16))])
    }

    func testNewIdentifierWithADifferentTitleIsStillACancellation() {
        let a = ev("OLD@1", "Design review", start: at(2030, 11, 6, 14))
        let b = ev("NEW@2", "Lunch", start: at(2030, 11, 6, 14))
        XCTAssertEqual(MeetingChangeDetector.diff(old: snap([a]), new: snap([b]), now: now).map(\.kind), [.cancelled])
    }

    func testTitleFallbackIgnoresEventsThatWereAlreadyThere() {
        // Two same-titled meetings; one disappears. The one that stayed is not a "move" target.
        let a = ev("A", "Standup", start: at(2030, 11, 6, 10))
        let b = ev("B", "Standup", start: at(2030, 11, 6, 14))
        XCTAssertEqual(MeetingChangeDetector.diff(old: snap([a, b]), new: snap([b]), now: now),
                       [MeetingChange(kind: .cancelled, event: a)])
    }

    func testCancelTitleWithNewIdentifierIsACancellation() {
        let a = ev("OLD", "Design review", start: at(2030, 11, 6, 14))
        let b = ev("NEW", "Canceled: Design review", start: at(2030, 11, 6, 14))
        XCTAssertEqual(MeetingChangeDetector.diff(old: snap([a]), new: snap([b]), now: now).map(\.kind), [.cancelled])
    }

    func testLinkChanged() {
        let a = ev("a", start: at(2030, 11, 6, 14))
        let b = ev("a", start: at(2030, 11, 6, 14), url: "https://zoom.us/j/123")
        XCTAssertEqual(MeetingChangeDetector.diff(old: snap([a]), new: snap([b]), now: now).map(\.kind), [.linkChanged])
    }

    func testQuietCases() {
        let soon = ev("a", start: at(2030, 11, 6, 14))
        // Calendar didn't load this time (failed account or hidden): no news.
        XCTAssertTrue(MeetingChangeDetector.diff(old: snap([soon]), new: snap([], calendars: []), now: now).isEmpty)
        // Deleted in Meetball.
        XCTAssertTrue(MeetingChangeDetector.diff(old: snap([soon]), new: snap([]), now: now, ignoring: [soon.uid]).isEmpty)
        // Already over, all day, declined, or too far ahead.
        let over = ev("b", start: at(2030, 11, 6, 7))
        let allDay = ev("c", start: at(2030, 11, 6), minutes: 1440, allDay: true)
        let declined = ev("d", start: at(2030, 11, 6, 15), declined: true)
        let far = ev("e", start: at(2030, 11, 20, 10))
        XCTAssertTrue(MeetingChangeDetector.diff(old: snap([over, allDay, declined, far]), new: snap([]), now: now).isEmpty)
        // You declining it isn't a change.
        let youDeclined = ev("a", start: at(2030, 11, 6, 15), declined: true)
        XCTAssertTrue(MeetingChangeDetector.diff(old: snap([soon]), new: snap([youDeclined]), now: now).isEmpty)
        // Nothing changed.
        XCTAssertTrue(MeetingChangeDetector.diff(old: snap([soon]), new: snap([soon]), now: now).isEmpty)
    }

    func testFarMeetingMovedIntoTheWindowIsReported() {
        let a = ev("a", start: at(2030, 11, 20, 10))
        let b = ev("a", start: at(2030, 11, 6, 16))
        XCTAssertEqual(MeetingChangeDetector.diff(old: snap([a]), new: snap([b]), now: now).count, 1)
    }

    func testCarryOverKeepsFailedCalendarsButNotHiddenOnes() {
        let a = ev("a", start: at(2030, 11, 6, 14), calendar: "work")
        let b = ev("b", start: at(2030, 11, 6, 15), calendar: "home")
        let previous = snap([a, b], calendars: ["me@example.com|work", "me@example.com|home"])
        let current = snap([], calendars: [])
        let carried = current.carryingOver(previous, hidden: ["me@example.com|home"],
                                           attempted: ["me@example.com|work", "me@example.com|home"])
        XCTAssertEqual(Set(carried.events.keys), [a.uid])
        XCTAssertEqual(carried.calendars, ["me@example.com|work"])
    }

    func testSummaryText() {
        let a = ev("a", "Standup", start: at(2030, 11, 6, 14)), b = ev("b", "1:1", start: at(2030, 11, 6, 15))
        let s = MeetingChangeText.summary([MeetingChange(kind: .cancelled, event: a),
                                           MeetingChange(kind: .rescheduled(from: b.start, to: b.start), event: b)])
        XCTAssertTrue(s.title.contains("2 meetings"))
        XCTAssertTrue(s.body.hasPrefix("1 canceled, 1 changed: Standup, 1:1"))
        XCTAssertTrue(MeetingChangeText.title(MeetingChange(kind: .cancelled, event: a)).contains("Canceled: Standup"))
    }
}

/// Ribbons for multi-day events in the menu calendar (#28).
final class MiniMonthRibbonTests: XCTestCase {
    let c = cal()
    /// November 2030's grid: Sun 27 Oct … Sat 7 Dec.
    var range: DateInterval { CalendarVisibleRangeBuilder.build(anchor: at(2030, 11, 15), calendar: c) }

    func testCalloutDetection() {
        XCTAssertEqual(EventCallout.detect("Vacation — Hawaii"), .away)
        XCTAssertEqual(EventCallout.detect("OOO"), .away)
        XCTAssertEqual(EventCallout.detect("PTO (Jason)"), .away)
        XCTAssertEqual(EventCallout.detect("On-call (primary)"), .onCall)
        XCTAssertEqual(EventCallout.detect("Primary on call"), .onCall)
        XCTAssertNil(EventCallout.detect("Pottery class"))
        XCTAssertNil(EventCallout.detect("Spoon review"))
    }

    func testWhichEventsBecomeRibbons() {
        let trip = ev("t", "Vacation", start: at(2030, 11, 11), allDay: true, end: at(2030, 11, 16), url: nil)
        let conf = ev("c", "Conference", start: at(2030, 11, 12), allDay: true, end: at(2030, 11, 14), url: nil)
        let oneDayOOO = ev("o", "OOO", start: at(2030, 11, 20), allDay: true, end: at(2030, 11, 21), url: nil)
        let birthday = ev("b", "Birthday", start: at(2030, 11, 20), allDay: true, end: at(2030, 11, 21), url: nil)
        let lateNight = ev("l", "Deploy", start: at(2030, 11, 20, 23), minutes: 120)
        let rotation = ev("r", "On-call", start: at(2030, 11, 18, 9), end: at(2030, 11, 25, 9))
        XCTAssertTrue(MiniMonthRibbonBuilder.isRibbon(trip, calendar: c))
        XCTAssertTrue(MiniMonthRibbonBuilder.isRibbon(conf, calendar: c))
        XCTAssertTrue(MiniMonthRibbonBuilder.isRibbon(oneDayOOO, calendar: c))
        XCTAssertFalse(MiniMonthRibbonBuilder.isRibbon(birthday, calendar: c))
        XCTAssertFalse(MiniMonthRibbonBuilder.isRibbon(lateNight, calendar: c))
        XCTAssertTrue(MiniMonthRibbonBuilder.isRibbon(rotation, calendar: c))
    }

    func testSpansAcrossWeeksWithCalloutsOnTop() {
        let conf = ev("c", "Conference", start: at(2030, 11, 8), allDay: true, end: at(2030, 11, 13), url: nil)
        let trip = ev("t", "Vacation", start: at(2030, 11, 9), allDay: true, end: at(2030, 11, 12), url: nil)
        let byWeek = MiniMonthRibbonBuilder.build(events: [conf, trip], range: range, calendar: c)
        // Week of Sun 3 Nov: the conference runs Fri 8–Sat 9 and carries on.
        let w1 = byWeek[at(2030, 11, 3)]!
        let tripW1 = w1.first { $0.event.id == "t" }!, confW1 = w1.first { $0.event.id == "c" }!
        XCTAssertEqual(tripW1.lane, 0, "away stretches take the top lane")
        XCTAssertEqual(tripW1.callout, .away)
        XCTAssertEqual(confW1.lane, 1)
        XCTAssertEqual(confW1.startColumn, 5); XCTAssertEqual(confW1.endColumn, 6)
        XCTAssertFalse(confW1.continuesBefore); XCTAssertTrue(confW1.continuesAfter)
        // Week of Sun 10 Nov: conference Sun–Tue, ending there.
        let confW2 = byWeek[at(2030, 11, 10)]!.first { $0.event.id == "c" }!
        XCTAssertEqual(confW2.startColumn, 0); XCTAssertEqual(confW2.endColumn, 2)
        XCTAssertTrue(confW2.continuesBefore); XCTAssertFalse(confW2.continuesAfter)
        XCTAssertEqual(MiniMonthRibbonBuilder.uids(byWeek), [conf.uid, trip.uid])
    }

    func testLanesAreCapped() {
        let evs = (0..<4).map { ev("x\($0)", "Trip \($0)", start: at(2030, 11, 11), allDay: true, end: at(2030, 11, 14), url: nil) }
        let row = MiniMonthRibbonBuilder.build(events: evs, range: range, calendar: c)[at(2030, 11, 10)]!
        XCTAssertEqual(row.count, MiniMonthRibbonBuilder.maxLanes)
    }
}

/// Auto-join timing (#24).
final class AutoJoinTests: XCTestCase {
    let start = at(2030, 11, 6, 10)

    func testDueAfterTheDelayWithinGrace() {
        let e = ev("a", start: start, minutes: 30)
        func due(_ now: Date, joined: Bool = false, on: Bool = true) -> CalendarEvent? {
            AutoJoin.due([e], now: now, delayMinutes: 1, isAutoJoin: { _ in on }, hasJoined: { _ in joined })
        }
        XCTAssertNil(due(start.addingTimeInterval(30)), "before the delay")
        XCTAssertEqual(due(start.addingTimeInterval(61))?.id, "a")
        XCTAssertNil(due(start.addingTimeInterval(61), joined: true), "already joined")
        XCTAssertNil(due(start.addingTimeInterval(61), on: false), "auto-join off")
        XCTAssertNil(due(start.addingTimeInterval(60 + AutoJoin.grace + 1)), "too late, e.g. after waking up")
    }

    func testNeedsALinkAndNotDeclined() {
        let noLink = ev("a", start: start, url: nil)
        let declined = ev("b", start: start, declined: true)
        XCTAssertNil(AutoJoin.due([noLink, declined], now: start.addingTimeInterval(10), delayMinutes: 0,
                                  isAutoJoin: { _ in true }, hasJoined: { _ in false }))
    }

    func testLatestStartWins() {
        let early = ev("a", start: start, minutes: 60), late = ev("b", start: start.addingTimeInterval(120), minutes: 30)
        XCTAssertEqual(AutoJoin.due([early, late], now: start.addingTimeInterval(150), delayMinutes: 0,
                                    isAutoJoin: { _ in true }, hasJoined: { _ in false })?.id, "b")
    }

    @MainActor func testScopesPersist() {
        let defaults = UserDefaults(suiteName: "AutoJoinTests-\(UUID().uuidString)")!
        let store = MeetingGuardianStore(defaults: defaults)
        let one = ev("a", start: start)
        let weekly = ev("w1", start: start, series: "S1")
        let nextWeek = ev("w2", start: start.addingTimeInterval(7 * 86400), series: "S1")
        store.setAutoJoin(.occurrence, for: one)
        store.setAutoJoin(.series, for: weekly)
        XCTAssertEqual(store.autoJoinScope(for: one), .occurrence)
        XCTAssertEqual(store.autoJoinScope(for: nextWeek), .series)
        let reloaded = MeetingGuardianStore(defaults: defaults)
        XCTAssertTrue(reloaded.isAutoJoin(nextWeek))
        reloaded.setAutoJoin(nil, for: nextWeek)
        XCTAssertFalse(reloaded.isAutoJoin(weekly))
        // A one-off asked to auto-join "every one" falls back to just itself.
        reloaded.setAutoJoin(.series, for: one)
        XCTAssertEqual(reloaded.autoJoinScope(for: one), .occurrence)
    }

    @MainActor func testRecurringMeetingsAutoJoinByDefault() {
        let store = MeetingGuardianStore(defaults: UserDefaults(suiteName: "AutoJoinTests-\(UUID().uuidString)")!)
        let one = ev("a", start: start)
        let weekly = ev("w1", start: start, series: "S1")
        let nextWeek = ev("w2", start: start.addingTimeInterval(7 * 86400), series: "S1")
        let daily = ev("d1", start: start, series: "S2")
        XCTAssertFalse(store.isAutoJoin(weekly), "off until the setting is on")
        store.settings.autoJoinRecurring = true
        XCTAssertEqual(store.autoJoinScope(for: weekly), .series)
        XCTAssertTrue(store.isAutoJoinByDefault(weekly))
        XCTAssertFalse(store.isAutoJoin(one), "one-off meetings stay opt-in")
        // Turning a series off sticks, for every occurrence.
        store.setAutoJoin(nil, for: weekly)
        XCTAssertFalse(store.isAutoJoin(nextWeek))
        XCTAssertTrue(store.isAutoJoin(daily))
        // "This one" leaves the rest of the series off.
        store.setAutoJoin(.occurrence, for: daily)
        XCTAssertEqual(store.autoJoinScope(for: daily), .occurrence)
        XCTAssertFalse(store.isAutoJoin(ev("d2", start: start.addingTimeInterval(86400), series: "S2")))
        // "Every one" turns it back on, explicitly, so it survives the setting going off.
        store.setAutoJoin(.series, for: nextWeek)
        XCTAssertFalse(store.isAutoJoinByDefault(weekly))
        store.settings.autoJoinRecurring = false
        XCTAssertTrue(store.isAutoJoin(weekly))
        XCTAssertFalse(store.isAutoJoin(ev("x1", start: start, series: "S3")))
    }

    func testOldSettingsDecodeWithAutoJoinDefaults() throws {
        let s = try JSONDecoder().decode(GuardianSettings.self, from: Data(#"{"style":"soft"}"#.utf8))
        XCTAssertEqual(s.autoJoinDelayMinutes, 1)
        XCTAssertFalse(s.autoJoinRecurring)
        XCTAssertTrue(s.notifyChanges)
        XCTAssertTrue(s.celebrateCancellations)
    }
}

/// Day and date in the menu bar (#26).
final class MenuBarDateTests: XCTestCase {
    func testDateText() {
        XCTAssertEqual(MenuBarTitleBuilder.dateText(at(2030, 11, 6, 9), calendar: cal(), locale: Locale(identifier: "en_US")),
                       "Wed, Nov 6")
    }

    func testDateShownWithAndWithoutAMeeting() {
        let now = at(2030, 11, 6, 9)
        var s = MenuBarTitleSettings()
        s.showDate = true
        let idle = MenuBarTitleBuilder.build(next: nil, now: now, settings: s, calendar: cal(), locale: Locale(identifier: "en_US"))
        XCTAssertEqual(idle.plainText, "Wed, Nov 6")
        let soon = ev("a", start: now.addingTimeInterval(12 * 60))
        let t = MenuBarTitleBuilder.build(next: soon, now: now, settings: s, calendar: cal(), locale: Locale(identifier: "en_US"))
        XCTAssertEqual(t.date, "Wed, Nov 6")
        XCTAssertEqual(t.plainText, "Wed, Nov 6  \(t.text)")
        s.showDate = false
        XCTAssertNil(MenuBarTitleBuilder.build(next: soon, now: now, settings: s, calendar: cal()).date)
    }

    func testStyleSetting() {
        let d = UserDefaults(suiteName: "MenuBarDateTests-\(UUID().uuidString)")!
        XCTAssertEqual(MenuBarTitleSettings(defaults: d).style, .plain)
        d.set("lcd", forKey: MenuBarTitleSettings.Key.style)
        d.set(true, forKey: MenuBarTitleSettings.Key.showDate)
        let s = MenuBarTitleSettings(defaults: d)
        XCTAssertEqual(s.style, .lcd)
        XCTAssertTrue(s.showDate)
    }
}
