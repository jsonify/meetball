import XCTest
@testable import MeetballPhone

private let now = Date(timeIntervalSince1970: 1_800_000_000)

private func ev(_ id: String, _ title: String = "Standup", in minutes: Double, length: Double = 30, calendar: String = "work",
                allDay: Bool = false, declined: Bool = false, url: String? = "https://meet.google.com/abc-defg-hij") -> CalendarEvent {
    var e = CalendarEvent(id: id, calendarID: calendar, accountEmail: "Apple · iCloud", title: title,
                          start: now.addingTimeInterval(minutes * 60), end: now.addingTimeInterval((minutes + length) * 60),
                          isAllDay: allDay, meetURL: url.flatMap(URL.init(string:)), location: nil, attendees: [], htmlLink: nil)
    e.isDeclined = declined
    return e
}

final class ReminderPlannerTests: XCTestCase {
    func testLeadReminderFiresBeforeStart() {
        let plan = ReminderPlanner.plan([ev("a", in: 60)], settings: PhoneSettings(), now: now)
        XCTAssertEqual(plan.count, 1)
        XCTAssertEqual(plan[0].kind, .lead)
        XCTAssertEqual(plan[0].fireDate, now.addingTimeInterval(50 * 60))
        XCTAssertEqual(plan[0].title, "Standup")
        XCTAssertTrue(plan[0].body.hasPrefix("Starts in 10 min · "), plan[0].body)
    }

    func testLeadAlreadyPassedIsSkippedButStartAlertKept() {
        var s = PhoneSettings()
        s.alertAtStart = true
        let plan = ReminderPlanner.plan([ev("a", in: 5)], settings: s, now: now)
        XCTAssertEqual(plan.map(\.kind), [.start])
        XCTAssertTrue(plan[0].body.hasPrefix("Starting now"))
    }

    func testSkipsAllDayDeclinedHiddenStartedAndFarOff() {
        var s = PhoneSettings()
        s.hiddenCalendars = ["Apple · iCloud|hidden"]
        let events = [
            ev("allday", in: 120, allDay: true),
            ev("declined", in: 120, declined: true),
            ev("hidden", in: 120, calendar: "hidden"),
            ev("started", in: -5),
            ev("far", in: 49 * 60),
            ev("ok", "Planning", in: 120),
        ]
        XCTAssertEqual(ReminderPlanner.plan(events, settings: s, now: now).map(\.event.id), ["ok"])
    }

    func testInProgressMeetingIsUpcomingButGetsNoReminder() {
        let events = [ev("live", in: -5), ev("next", in: 30)]
        XCTAssertEqual(ReminderPlanner.meetings(events, settings: PhoneSettings(), now: now).map(\.id), ["live", "next"])
        XCTAssertEqual(ReminderPlanner.plan(events, settings: PhoneSettings(), now: now).map(\.event.id), ["next"])
    }

    func testSameMeetingOnTwoCalendarsAlertsOnce() {
        let events = [ev("a", "Artifactory Standup", in: 60, calendar: "google"), ev("b", "artifactory standup ", in: 60, calendar: "icloud")]
        XCTAssertEqual(ReminderPlanner.plan(events, settings: PhoneSettings(), now: now).count, 1)
    }

    func testMovedMeetingSaysSoFirst() {
        let e = ev("a", "Artifactory Standup", in: 60)
        let plan = ReminderPlanner.plan([e], settings: PhoneSettings(), moved: [e.uid], now: now)
        XCTAssertTrue(plan[0].body.hasPrefix("Moved to \(e.start.shortTime) · Starts in 10 min"), plan[0].body)
    }

    func testCapsPendingReminders() {
        var s = PhoneSettings()
        s.alertAtStart = true
        let events = (0..<40).map { ev("e\($0)", "M\($0)", in: Double(20 + $0 * 60)) }
        let plan = ReminderPlanner.plan(events, settings: s, now: now)
        XCTAssertEqual(plan.count, ReminderPlanner.maxPending)
        XCTAssertEqual(plan, plan.sorted { $0.fireDate < $1.fireDate })
        XCTAssertEqual(Set(plan.map(\.id)).count, plan.count)
    }

    func testChangeAlertDropsEmojiForSiri() {
        let cancelled = MeetingChange(kind: .cancelled, event: ev("a", "1:1", in: 60))
        let alert = ReminderPlanner.changeAlert([cancelled], now: now)
        XCTAssertEqual(alert?.title, "Canceled: 1:1")
        XCTAssertNil(ReminderPlanner.changeAlert([], now: now))
        let moved = MeetingChange(kind: .rescheduled(from: now.addingTimeInterval(3600), to: now.addingTimeInterval(7200)),
                                  event: ev("b", in: 120))
        XCTAssertEqual(ReminderPlanner.changeAlert([cancelled, moved], now: now)?.title, "2 meetings updated")
    }

    func testMovedUIDsTrackReschedulesAndExpire() {
        let e = ev("a", in: 120)
        let moved = MeetingChange(kind: .rescheduled(from: now.addingTimeInterval(3600), to: e.start), event: e)
        let out = ReminderPlanner.movedUIDs(["old": now.addingTimeInterval(-60), "keep": now.addingTimeInterval(60)],
                                            changes: [moved], now: now)
        XCTAssertEqual(Set(out.keys), [e.uid, "keep"])
    }

    func testSettingsRoundTrip() {
        let d = UserDefaults(suiteName: "ReminderPlannerTests")!
        d.removePersistentDomain(forName: "ReminderPlannerTests")
        XCTAssertEqual(PhoneSettings.load(d), PhoneSettings())
        var s = PhoneSettings()
        s.leadMinutes = 5; s.alertAtStart = true; s.hiddenCalendars = ["x"]; s.silencedCalendars = ["y"]
        s.alertOnEvents = ["future": now.addingTimeInterval(3600)]
        s.mutedEvents = ["past": now.addingTimeInterval(-60)]
        s.save(d)
        var loaded = PhoneSettings.load(d, now: now)
        XCTAssertEqual(loaded.mutedEvents, [:], "ended meetings are pruned")
        loaded.mutedEvents = s.mutedEvents
        XCTAssertEqual(loaded, s)
    }

    func testSilencedCalendarSkipsAlertsUnlessTurnedOn() {
        var s = PhoneSettings()
        s.alertAtStart = true
        let family = "Apple · iCloud|family"
        s.silencedCalendars = [family]
        let soccer = ev("soccer", "Soccer", in: 60, calendar: "family")
        let recital = ev("recital", "Recital", in: 90, calendar: "family")
        let standup = ev("standup", in: 120)
        let events = [soccer, recital, standup]
        XCTAssertEqual(Set(ReminderPlanner.plan(events, settings: s, now: now).map(\.event.uid)), [standup.uid])
        XCTAssertEqual(ReminderPlanner.meetings(events, settings: s, now: now).count, 3, "still shown")
        XCTAssertFalse(ReminderPlanner.echoes(events, settings: s, now: now).contains { $0.event.uid == soccer.uid })

        s.setAlerts(true, for: recital)
        XCTAssertEqual(Set(ReminderPlanner.plan(events, settings: s, now: now).map(\.event.uid)), [recital.uid, standup.uid])

        s.setAlerts(false, for: standup)
        XCTAssertFalse(s.alerts(for: standup), "a meeting on a loud calendar can be muted on its own")
        XCTAssertEqual(Set(ReminderPlanner.plan(events, settings: s, now: now).map(\.event.uid)), [recital.uid])

        s.setAlerts(false, for: recital)
        XCTAssertTrue(s.alertOnEvents.isEmpty && s.mutedEvents.keys.sorted() == [standup.uid])
    }

    func testEventFiltersDecideWhatAlerts() {
        var s = PhoneSettings()
        let standup = ev("standup", in: 60)
        let lunch = ev("lunch", "Team Lunch", in: 90)
        let focus = ev("focus", "Focus time", in: 120, url: nil)
        let events = [standup, lunch, focus]
        XCTAssertEqual(ReminderPlanner.meetings(events, settings: s, now: now).count, 3, "default rules hide nothing here")

        s.filters.rules.ignoredKeywords = ["lunch"]
        s.filters.rules.hideWithoutLink = true
        XCTAssertEqual(ReminderPlanner.meetings(events, settings: s, now: now).map(\.uid), [standup.uid])
        XCTAssertEqual(Set(ReminderPlanner.plan(events, settings: s, now: now).map(\.event.uid)), [standup.uid])

        // A source set to show everything ignores the rules.
        s.filters.sources["Apple · iCloud"] = SourceFilterRule(mode: .showAll)
        XCTAssertEqual(ReminderPlanner.meetings(events, settings: s, now: now).count, 3)
    }

    func testSettingsWithoutFiltersKeepDefaultRules() throws {
        let s = try JSONDecoder().decode(PhoneSettings.self, from: Data(#"{"leadMinutes": 5}"#.utf8))
        XCTAssertEqual(s.leadMinutes, 5)
        XCTAssertEqual(s.filters, EventFilterSettings())
        var round = PhoneSettings()
        round.filters.rules.hideSolo = true
        round.filters.sources["Apple · Work"] = SourceFilterRule(mode: .custom)
        XCTAssertEqual(try JSONDecoder().decode(PhoneSettings.self, from: JSONEncoder().encode(round)), round)
    }
}
