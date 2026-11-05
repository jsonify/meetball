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

    func testSK1CountdownDigits() {
        XCTAssertTrue(SK1CountdownDigits.compact(-30) == ("1", "MIN"))
        XCTAssertTrue(SK1CountdownDigits.compact(61) == ("2", "MIN"))
        XCTAssertTrue(SK1CountdownDigits.compact(59 * 60) == ("59", "MIN"))
        XCTAssertTrue(SK1CountdownDigits.compact(65 * 60) == ("1:05", "HR"))
        XCTAssertTrue(SK1CountdownDigits.compact(24 * 3600 - 60) == ("23:59", "HR"))
        XCTAssertTrue(SK1CountdownDigits.compact(24 * 3600) == ("1", "DAY"))
        XCTAssertTrue(SK1CountdownDigits.compact(3 * 24 * 3600 + 5) == ("3", "DAYS"))
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

final class JoinTests: XCTestCase {
    func ev(_ id: String, _ s: Date, _ e: Date, url: String? = "https://meet.google.com/abc-defg-hij", declined: Bool = false) -> CalendarEvent {
        CalendarEvent(id: id, calendarID: "c", accountEmail: "a@b.c", title: id, start: s, end: e, isAllDay: false,
                      meetURL: url.flatMap(URL.init(string:)), location: nil, attendees: [], htmlLink: nil, isDeclined: declined)
    }

    func testServiceDetection() {
        XCTAssertEqual(MeetingService.detect(URL(string: "https://meet.google.com/abc-defg-hij")!), .meet)
        XCTAssertEqual(MeetingService.detect(URL(string: "https://acme.zoom.us/j/123456789?pwd=x")!), .zoom)
        XCTAssertEqual(MeetingService.detect(URL(string: "https://teams.microsoft.com/l/meetup-join/19%3a")!), .teams)
        XCTAssertEqual(MeetingService.detect(URL(string: "https://acme.webex.com/meet/bob")!), .webex)
        XCTAssertEqual(MeetingService.detect(URL(string: "https://example.com/call")!), .other)
    }

    func testNativeURLs() {
        let zoom = MeetingService.zoom.nativeURL(for: URL(string: "https://acme.zoom.us/j/123456789?pwd=secret")!)
        let comps = URLComponents(url: zoom!, resolvingAgainstBaseURL: false)!
        XCTAssertEqual(comps.scheme, "zoommtg")
        XCTAssertEqual(comps.host, "acme.zoom.us")
        XCTAssertEqual(comps.queryItems?.first { $0.name == "confno" }?.value, "123456789")
        XCTAssertEqual(comps.queryItems?.first { $0.name == "pwd" }?.value, "secret")
        XCTAssertNil(MeetingService.zoom.nativeURL(for: URL(string: "https://zoom.us/pricing")!))
        let teams = MeetingService.teams.nativeURL(for: URL(string: "https://teams.microsoft.com/l/meetup-join/x")!)
        XCTAssertEqual(teams?.scheme, "msteams")
        XCTAssertNil(MeetingService.meet.nativeURL(for: URL(string: "https://meet.google.com/x")!))
    }

    func testOpenModeRoundTrip() {
        for m in [JoinOpenMode.defaultBrowser, .nativeApp, .browser(bundleID: "com.google.Chrome")] {
            XCTAssertEqual(JoinOpenMode(raw: m.raw), m)
        }
        let prefs = JoinPreferences(defaults: UserDefaults(suiteName: "test.\(UUID())")!)
        XCTAssertEqual(prefs.mode(for: .zoom), .nativeApp)
        XCTAssertEqual(prefs.mode(for: .meet), .defaultBrowser)
        prefs.setMode(.browser(bundleID: "org.mozilla.firefox"), for: .meet)
        XCTAssertEqual(prefs.mode(for: .meet), .browser(bundleID: "org.mozilla.firefox"))
    }

    func testNearestMeetingPrefersInProgress() {
        let now = Date()
        let current = ev("current", now.addingTimeInterval(-600), now.addingTimeInterval(1200))
        let soon = ev("soon", now.addingTimeInterval(120), now.addingTimeInterval(1800))
        XCTAssertEqual(NearestMeetingPicker.pick([soon, current], now: now)?.id, "current")
        XCTAssertEqual(NearestMeetingPicker.pick([soon], now: now)?.id, "soon")
    }

    func testNearestMeetingRespectsWindowLinksAndDeclines() {
        let now = Date()
        let later = ev("later", now.addingTimeInterval(3600), now.addingTimeInterval(5400))
        let noLink = ev("nolink", now.addingTimeInterval(-60), now.addingTimeInterval(600), url: nil)
        let declined = ev("declined", now.addingTimeInterval(-60), now.addingTimeInterval(600), declined: true)
        let ended = ev("ended", now.addingTimeInterval(-3600), now.addingTimeInterval(-60))
        XCTAssertNil(NearestMeetingPicker.pick([later, noLink, declined, ended], now: now, window: 600))
        XCTAssertEqual(NearestMeetingPicker.pick([later], now: now, window: 3600)?.id, "later")
    }

    func testHotKeyDisplay() {
        XCTAssertEqual(HotKeyCombo.defaultCombo.display, "⌃⌥⌘J")
    }
}

final class TimeGridTests: XCTestCase {
    let cal = Calendar.current
    var day: Date { cal.date(from: DateComponents(year: 2026, month: 3, day: 11))! }
    func at(_ h: Int, _ m: Int = 0) -> Date { cal.date(bySettingHour: h, minute: m, second: 0, of: day)! }
    func seg(_ id: String, _ s: Date, _ e: Date) -> CalendarEventDaySegment {
        let ev = CalendarEvent(id: id, calendarID: "c", accountEmail: "a@b.c", title: id, start: s, end: e, isAllDay: false,
                               meetURL: nil, location: nil, attendees: [], htmlLink: nil)
        return CalendarEventDaySegment(event: ev, day: day, segmentStart: s, segmentEnd: e, startsOnThisDay: true, endsOnThisDay: true)
    }

    func testOverlapPacking() {
        let a = seg("a", at(9), at(10)), b = seg("b", at(9, 30), at(10, 30)), c = seg("c", at(10), at(11))
        let d = seg("d", at(13), at(14))
        let placed = Dictionary(uniqueKeysWithValues: TimeGridLayoutBuilder.place([d, c, b, a]).map { ($0.segment.event.id, $0) })
        XCTAssertEqual(placed["a"]?.column, 0)
        XCTAssertEqual(placed["b"]?.column, 1)
        XCTAssertEqual(placed["c"]?.column, 0)   // reuses a's column once a ends
        XCTAssertEqual(placed["a"]?.columnCount, 2)
        XCTAssertEqual(placed["c"]?.columnCount, 2)
        XCTAssertEqual(placed["d"]?.column, 0)
        XCTAssertEqual(placed["d"]?.columnCount, 1)  // separate cluster
    }

    func testDragRangeSnapsToQuarterHours() {
        let h: Double = 48
        let r = TimeGridLayoutBuilder.dragRange(fromY: 9 * h + 5, toY: 10 * h + 20, hourHeight: h, day: day)
        XCTAssertEqual(r.start, at(9))
        XCTAssertEqual(r.end, at(10, 30))
        let up = TimeGridLayoutBuilder.dragRange(fromY: 10 * h + 20, toY: 9 * h + 5, hourHeight: h, day: day)
        XCTAssertEqual(up, r)
    }

    func testAllDayBarsForDayView() {
        let s = cal.date(from: DateComponents(year: 2026, month: 3, day: 10))!
        let a = CalendarEvent(id: "a", calendarID: "c", accountEmail: "a@b.c", title: "a", start: s, end: s.addingTimeInterval(86400),
                              isAllDay: true, meetURL: nil, location: nil, attendees: [], htmlLink: nil)
        let b = CalendarEvent(id: "b", calendarID: "c", accountEmail: "a@b.c", title: "b", start: s, end: s.addingTimeInterval(3 * 86400),
                              isAllDay: true, meetURL: nil, location: nil, attendees: [], htmlLink: nil)
        let week = cal.dateInterval(of: .weekOfYear, for: s)!
        let derived = CalendarDerivedEventsBuilder.build(events: [a, b], range: week)
        let spans = derived.weeks.first!.spans
        let dayAfter = cal.date(byAdding: .day, value: 1, to: s)!
        let offset = cal.dateComponents([.day], from: week.start, to: dayAfter).day!
        let bars = TimeGridLayoutBuilder.allDayBars(spans: spans, firstDayOffset: offset, dayCount: 1)
        XCTAssertEqual(bars.map(\.event.id), ["b"])   // "a" ended the day before
        XCTAssertEqual(bars.first?.lane, 0)           // lanes compacted
        XCTAssertEqual(bars.first?.continuesBefore, true)
    }
}

final class MenuAgendaTests: XCTestCase {
    let cal = Calendar.current
    func ev(_ id: String, _ s: Date, _ e: Date, allDay: Bool = false) -> CalendarEvent {
        CalendarEvent(id: id, calendarID: "c", accountEmail: "a@b.c", title: id, start: s, end: e, isAllDay: allDay,
                      meetURL: nil, location: nil, attendees: [], htmlLink: nil)
    }

    func testGroupsByDayWithNowLine() {
        let today = cal.startOfDay(for: Date())
        let now = today.addingTimeInterval(12 * 3600)
        let current = ev("current", now.addingTimeInterval(-600), now.addingTimeInterval(600))
        let next = ev("next", now.addingTimeInterval(3600), now.addingTimeInterval(5400))
        let past = ev("past", now.addingTimeInterval(-7200), now.addingTimeInterval(-3600))
        let tomorrow = ev("tomorrow", now.addingTimeInterval(86400), now.addingTimeInterval(90000))
        let groups = MenuAgendaBuilder.build(events: [past, current, next, tomorrow], now: now)
        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups[0].timed.map(\.id), ["current", "next"])
        XCTAssertEqual(groups[0].nowLineIndex, 1)
        XCTAssertEqual(groups[1].timed.map(\.id), ["tomorrow"])
        XCTAssertNil(groups[1].nowLineIndex)
        XCTAssertEqual(MenuAgendaBuilder.hero([past, current, next], now: now)?.id, "current")
    }

    func testScopedDayIncludesPastAndAllDay() {
        let today = cal.startOfDay(for: Date())
        let now = today.addingTimeInterval(12 * 3600)
        let past = ev("past", now.addingTimeInterval(-7200), now.addingTimeInterval(-3600))
        let allDay = ev("holiday", today, today.addingTimeInterval(86400), allDay: true)
        let groups = MenuAgendaBuilder.build(events: [past, allDay], now: now, scopedDay: today)
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].timed.map(\.id), ["past"])
        XCTAssertEqual(groups[0].allDay.map(\.id), ["holiday"])
        XCTAssertEqual(groups[0].nowLineIndex, 1)
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

final class MenuBarTitleTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    func ev(_ title: String, startIn: TimeInterval, minutes: Double = 30, url: String? = nil) -> CalendarEvent {
        let s = now.addingTimeInterval(startIn)
        return CalendarEvent(id: title, calendarID: "c", accountEmail: "a@b.c", title: title, start: s,
                             end: s.addingTimeInterval(minutes * 60), isAllDay: false,
                             meetURL: url.flatMap(URL.init(string:)), location: nil, attendees: [], htmlLink: nil)
    }
    func settings(_ f: MenuBarTitleFormat, max: Int = 24, hide: Int = 0) -> MenuBarTitleSettings {
        var s = MenuBarTitleSettings(); s.format = f; s.maxTitleLength = max; s.hideBeyondHours = hide; return s
    }

    func testFormats() {
        let e = ev("Design review", startIn: 12 * 60)
        XCTAssertEqual(MenuBarTitleBuilder.build(next: e, now: now, settings: settings(.countdown)).text, "12m")
        XCTAssertEqual(MenuBarTitleBuilder.build(next: e, now: now, settings: settings(.titleCountdown)).text, "Design review · in 12m")
        XCTAssertTrue(MenuBarTitleBuilder.build(next: e, now: now, settings: settings(.titleStartTime)).text.hasPrefix("Design review · "))
        XCTAssertEqual(MenuBarTitleBuilder.build(next: e, now: now, settings: settings(.iconOnly)).text, "")
    }

    func testInProgressShowsTimeLeft() {
        let e = ev("Standup", startIn: -5 * 60, minutes: 15)
        let t = MenuBarTitleBuilder.build(next: e, now: now, settings: settings(.countdown))
        XCTAssertEqual(t.text, "now · 10m left")
        XCTAssertTrue(t.inProgress)
        XCTAssertFalse(t.isSoon)
        XCTAssertEqual(MenuBarTitleBuilder.build(next: e, now: now, settings: settings(.titleCountdown)).text, "Standup · 10m left")
    }

    func testTruncation() {
        XCTAssertEqual(MenuBarTitleBuilder.truncate("Quarterly planning offsite", to: 10), "Quarterly…")
        XCTAssertEqual(MenuBarTitleBuilder.truncate("  Short  ", to: 10), "Short")
        let t = MenuBarTitleBuilder.build(next: ev(String(repeating: "x", count: 80), startIn: 600), now: now, settings: settings(.titleCountdown, max: 20))
        XCTAssertEqual(t.text, String(repeating: "x", count: 19) + "… · in 10m")
    }

    func testHideBeyondHoursAndSoon() {
        let far = ev("Later", startIn: 3 * 3600)
        XCTAssertEqual(MenuBarTitleBuilder.build(next: far, now: now, settings: settings(.countdown, hide: 2)), .idle)
        XCTAssertEqual(MenuBarTitleBuilder.build(next: far, now: now, settings: settings(.countdown, hide: 4)).text, "3h")
        XCTAssertTrue(MenuBarTitleBuilder.build(next: ev("Soon", startIn: 4 * 60), now: now, settings: settings(.countdown)).isSoon)
        XCTAssertFalse(MenuBarTitleBuilder.build(next: ev("Not yet", startIn: 6 * 60), now: now, settings: settings(.countdown)).isSoon)
    }

    func testServiceIcon() {
        let zoom = ev("Sync", startIn: 600, url: "https://acme.zoom.us/j/1")
        XCTAssertEqual(MenuBarTitleBuilder.build(next: zoom, now: now, settings: settings(.countdown)).symbol, MeetingService.zoom.symbol)
        var s = settings(.countdown); s.showServiceIcon = false
        XCTAssertEqual(MenuBarTitleBuilder.build(next: zoom, now: now, settings: s).symbol, MenuBarTitleBuilder.defaultSymbol)
        XCTAssertEqual(MenuBarTitleBuilder.build(next: ev("x", startIn: 600), now: now, settings: settings(.countdown)).symbol,
                       MenuBarTitleBuilder.defaultSymbol)
    }

    func testPicksInProgressOverNext() {
        let current = ev("Current", startIn: -600), next = ev("Next", startIn: 300)
        XCTAssertEqual(MenuBarTitleBuilder.pick([current, next], now: now)?.title, "Current")
        XCTAssertEqual(MenuBarTitleBuilder.pick([next, ev("Tomorrow", startIn: 86400)], now: now)?.title, "Next")
    }

    func testLegacyCountdownToggleMapsToIconOnly() {
        let d = UserDefaults(suiteName: "test.\(UUID())")!
        XCTAssertEqual(MenuBarTitleSettings(defaults: d).format, .countdown)
        d.set(false, forKey: "showCountdownInMenuBar")
        XCTAssertEqual(MenuBarTitleSettings(defaults: d).format, .iconOnly)
        d.set(MenuBarTitleFormat.titleCountdown.rawValue, forKey: "menuBar.format")
        XCTAssertEqual(MenuBarTitleSettings(defaults: d).format, .titleCountdown)
    }
}

final class EventDetailTests: XCTestCase {
    func testHTMLNotesBecomePlainText() {
        let html = #"<p>Agenda:</p><ul><li>Intro &amp; goals</li><li>Q&amp;A</li></ul>Docs: <a href="https://example.com/doc">the doc</a><br>Call <a href="https://meet.google.com/abc">https://meet.google.com/abc</a>"#
        XCTAssertEqual(EventNotesFormatter.plainText(html),
                       "Agenda:\n\n• Intro & goals\n• Q&A\nDocs: the doc (https://example.com/doc)\nCall https://meet.google.com/abc")
    }

    func testPlainNotesAreKeptAndTrimmed() {
        XCTAssertEqual(EventNotesFormatter.plainText("  Line 1\n\n\n\nLine 2 < 3  \n"), "Line 1\n\nLine 2 < 3")
        let long = String(repeating: "a", count: EventNotesFormatter.maxLength + 50)
        XCTAssertTrue(EventNotesFormatter.plainText(long).hasSuffix("…"))
    }

    func testLinksAreDetected() {
        let s = EventNotesFormatter.linked("See https://example.com/x for details")
        XCTAssertTrue(s.runs.contains { $0.link == URL(string: "https://example.com/x") })
    }

    func testAttendeeInitials() {
        XCTAssertEqual(EventAttendee(email: "ada@x.com", name: "Ada Lovelace").initials, "AL")
        XCTAssertEqual(EventAttendee(email: "grace.hopper@x.com").initials, "GH")
        XCTAssertEqual(EventAttendee(email: "bob@x.com").initials, "B")
        XCTAssertEqual(EventAttendee(email: "bob@x.com", name: "  ").displayName, "bob@x.com")
    }

    func testDuration() {
        let s = Date(timeIntervalSince1970: 0)
        XCTAssertEqual(DurationFormatter.string(from: s, to: s.addingTimeInterval(30 * 60)), "30 min")
        XCTAssertEqual(DurationFormatter.string(from: s, to: s.addingTimeInterval(75 * 60)), "1 hr 15 min")
        XCTAssertEqual(DurationFormatter.string(from: s, to: s.addingTimeInterval(2 * 86400)), "2 days")
    }

    @MainActor func testMuteEvent() {
        let store = MeetingGuardianStore(defaults: UserDefaults(suiteName: "test.\(UUID())")!)
        let e = CalendarEvent(id: "1", calendarID: "c", accountEmail: "a@b.c", title: "x", start: Date(), end: Date().addingTimeInterval(600),
                              isAllDay: false, meetURL: nil, location: nil, attendees: [], htmlLink: nil)
        XCTAssertFalse(store.isMuted(e))
        store.setMuted(true, for: e)
        XCTAssertTrue(store.isMuted(e))
        store.setMuted(false, for: e)
        XCTAssertFalse(store.isMuted(e))
    }
}

final class UpcomingTests: XCTestCase {
    let cal = Calendar.current
    func ev(_ id: String, _ s: Date, minutes: Double, declined: Bool = false, allDay: Bool = false) -> CalendarEvent {
        CalendarEvent(id: id, calendarID: "c", accountEmail: "a@b.c", title: id, start: s, end: s.addingTimeInterval(minutes * 60),
                      isAllDay: allDay, meetURL: nil, location: nil, attendees: [], htmlLink: nil, isDeclined: declined)
    }

    func testMeetingLoadMergesOverlapsAndSkipsDeclinedAndAllDay() {
        let day = cal.date(from: DateComponents(year: 2026, month: 3, day: 10))!
        let at = { (h: Int) in day.addingTimeInterval(Double(h) * 3600) }
        let events = [ev("a", at(9), minutes: 60), ev("b", at(9).addingTimeInterval(1800), minutes: 60), // 9:00–10:30
                      ev("c", at(14), minutes: 30), ev("d", at(16), minutes: 60, declined: true),
                      ev("e", day, minutes: 24 * 60, allDay: true)]
        let loads = MeetingLoadBuilder.build(events: events, from: day, days: 2)
        XCTAssertEqual(loads.count, 2)
        XCTAssertEqual(loads[0].hours, 2.0, accuracy: 0.001)
        XCTAssertEqual(loads[0].count, 3)
        XCTAssertEqual(loads[1].hours, 0)
    }

    func testNextTodayAndPreview() {
        let day = cal.date(from: DateComponents(year: 2026, month: 3, day: 10, hour: 15))!
        let tomorrow9 = cal.date(from: DateComponents(year: 2026, month: 3, day: 11, hour: 9))!
        let done = ev("done", day.addingTimeInterval(-7200), minutes: 30)
        let next = ev("next", tomorrow9, minutes: 30)
        XCTAssertNil(UpcomingView.nextToday([done, next], now: day))
        let preview = UpcomingView.nextDayPreview([done, next], now: day)
        XCTAssertEqual(preview?.events.map(\.id), ["next"])
        let later = ev("later", day.addingTimeInterval(3600), minutes: 30)
        XCTAssertEqual(UpcomingView.nextToday([done, later, next], now: day)?.id, "later")
    }
}

final class HotKeyComboTests: XCTestCase {
    func testLoadDefaultsClearedAndCorrupt() {
        let d = UserDefaults(suiteName: "test.\(UUID())")!
        XCTAssertEqual(HotKeyCombo.load(d), .defaultCombo, "no saved value → default")
        HotKeyCombo.save(nil, d)
        XCTAssertNil(HotKeyCombo.load(d), "cleared → no shortcut")
        d.set("not json", forKey: HotKeyCombo.defaultsKey)
        XCTAssertEqual(HotKeyCombo.load(d), .defaultCombo, "unreadable → default")
        let custom = HotKeyCombo(keyCode: 0, carbonModifiers: 256, keyLabel: "A")
        HotKeyCombo.save(custom, d)
        XCTAssertEqual(HotKeyCombo.load(d), custom)
    }
}
