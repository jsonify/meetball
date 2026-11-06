import XCTest
@testable import Meetball

final class AlertPolicyTests: XCTestCase {
    let cal = Calendar.current

    func ev(_ id: String, calendarID: String = "work", title: String? = nil, others: [String] = [],
            organizerIsSelf: Bool = false, recurrence: EventRecurrence = .none) -> CalendarEvent {
        var people = others.map { EventAttendee(email: $0, name: nil, response: .accepted) }
        people.append(EventAttendee(email: "me@acme.com", name: nil, response: .accepted, isSelf: true))
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        return CalendarEvent(id: id, calendarID: calendarID, accountEmail: "me@acme.com", title: title ?? id, start: start,
                             end: start.addingTimeInterval(1800), isAllDay: false, meetURL: nil, location: nil,
                             attendees: people.compactMap(\.email), htmlLink: nil, participants: people,
                             organizerIsSelf: organizerIsSelf, recurrence: recurrence)
    }

    func testExternalAttendees() {
        XCTAssertFalse(ev("a", others: ["ann@acme.com", "ACME@ACME.COM"]).hasExternalAttendees)
        XCTAssertFalse(ev("b", others: ["room@resource.calendar.google.com", "team@group.calendar.google.com"]).hasExternalAttendees)
        XCTAssertTrue(ev("c", others: ["ann@acme.com", "bo@client.io"]).hasExternalAttendees)
    }

    func testPolicyOrder() {
        let rules = [ImportanceRule(kind: .externalAttendees),                    // → hard
                     ImportanceRule(kind: .organizerIsMe),                        // → heads-up
                     ImportanceRule(kind: .titleContains, text: "lunch, 1:1", intensity: .off),
                     ImportanceRule(kind: .recurringDaily, enabled: false)]
        var p = AlertPolicy(defaultStyle: .soft, calendarRules: [CalendarRule(calendarKey: "me@acme.com|quiet", style: nil),
                                                                 CalendarRule(calendarKey: "me@acme.com|loud", style: .hard)],
                            importanceRules: rules, isPro: true)
        XCTAssertEqual(p.style(for: ev("plain")), .soft, "no rule → default")
        XCTAssertEqual(p.style(for: ev("ext", others: ["x@client.io"], organizerIsSelf: true)), .hard, "first match wins")
        XCTAssertEqual(p.style(for: ev("mine", organizerIsSelf: true)), .headsUp)
        XCTAssertNil(p.style(for: ev("Team Lunch")), "rule can turn alerts off")
        XCTAssertEqual(p.style(for: ev("standup", recurrence: .daily)), .soft, "disabled rules are skipped")
        XCTAssertNil(p.style(for: ev("q", calendarID: "quiet", others: ["x@client.io"])), "calendar Off beats rules")
        XCTAssertEqual(p.style(for: ev("l", calendarID: "loud")), .hard, "calendar intensity when no rule matches")
        XCTAssertEqual(p.style(for: ev("l2", calendarID: "loud", organizerIsSelf: true)), .headsUp, "rules override calendar")
        XCTAssertEqual(p.reason(for: ev("mine", organizerIsSelf: true)), "i'm the organiser")
        p.isPro = false
        XCTAssertNil(p.style(for: ev("q", calendarID: "quiet")), "free plan: calendar Off still silences")
        XCTAssertEqual(p.style(for: ev("plain")), .soft, "free plan: soft only")
        XCTAssertNil(p.reason(for: ev("mine", organizerIsSelf: true)))
    }

    func testRecurrenceClassifier() {
        let mon = cal.date(from: DateComponents(year: 2026, month: 3, day: 9, hour: 9))!
        let day = { (n: Int) in self.cal.date(byAdding: .day, value: n, to: mon)! }
        XCTAssertEqual(RecurrenceClassifier.classify([day(0), day(1), day(2), day(3), day(4), day(7)]), .daily, "weekdays")
        XCTAssertEqual(RecurrenceClassifier.classify([day(0), day(7), day(14)]), .weekly)
        XCTAssertEqual(RecurrenceClassifier.classify([day(0), day(14), day(21), day(30)]), .other)
        XCTAssertEqual(RecurrenceClassifier.classify([day(0)]), .other)

        func inst(_ id: String, _ d: Date, series: String?) -> CalendarEvent {
            var e = CalendarEvent(id: id, calendarID: "c", accountEmail: "me@acme.com", title: id, start: d, end: d.addingTimeInterval(900),
                                  isAllDay: false, meetURL: nil, location: nil, attendees: [], htmlLink: nil)
            e.seriesID = series
            return e
        }
        var apple = inst("apple", day(0), series: "s1"); apple.recurrence = .weekly
        let out = RecurrenceClassifier.annotate([inst("a", day(0), series: "s1"), inst("b", day(1), series: "s1"),
                                                 inst("one", day(0), series: nil), apple])
        XCTAssertEqual(out.map(\.recurrence), [.daily, .daily, .none, .weekly])
    }

    @MainActor func testStoreIntensityAndRulePersistence() {
        let d = UserDefaults(suiteName: "test.\(UUID())")!
        let store = MeetingGuardianStore(defaults: d)
        store.setIntensity(.off, for: "a|1")
        store.setIntensity(.hard, for: "a|2")
        XCTAssertEqual(store.intensity(for: "a|1"), .off)
        store.setIntensity(nil, for: "a|2")
        XCTAssertNil(store.intensity(for: "a|2"))
        store.importanceRules = [ImportanceRule(kind: .titleContains, text: "Board")]
        let reloaded = MeetingGuardianStore(defaults: d)
        XCTAssertEqual(reloaded.importanceRules, store.importanceRules)
        XCTAssertEqual(reloaded.intensity(for: "a|1"), .off)
    }

    func testEventTurnedOnInSilencedCalendar() {
        let rules = [ImportanceRule(kind: .organizerIsMe),                                   // → heads-up
                     ImportanceRule(kind: .titleContains, text: "nap", intensity: .off)]
        let family = ev("soccer", calendarID: "family")
        let mine = ev("party", calendarID: "family", organizerIsSelf: true)
        let nap = ev("nap", calendarID: "family")
        var p = AlertPolicy(defaultStyle: .hard, calendarRules: [CalendarRule(calendarKey: "me@acme.com|family", style: nil)],
                            importanceRules: rules, isPro: true)
        XCTAssertNil(p.style(for: family), "silenced calendar")
        p.alertOnEvents = [family.uid, mine.uid, nap.uid]
        XCTAssertEqual(p.style(for: family), .hard, "turned on → default style")
        XCTAssertEqual(p.style(for: mine), .headsUp, "a matching rule still sets the strength")
        XCTAssertEqual(p.style(for: nap), .hard, "a rule set to Off can't silence an event turned on by hand")
        XCTAssertEqual(p.reason(for: family), "turned on for this event")
        XCTAssertNil(p.style(for: ev("other", calendarID: "family")), "only that event")
        p.isPro = false
        XCTAssertEqual(p.style(for: family), .soft, "free plan: soft")
    }

    @MainActor func testStoreAlertOnAndMuteAreExclusive() {
        let d = UserDefaults(suiteName: "AlertPolicyTests.store")!
        d.removePersistentDomain(forName: "AlertPolicyTests.store")
        let store = MeetingGuardianStore(defaults: d)
        let e = ev("soccer", calendarID: "family")
        XCTAssertFalse(store.isCalendarSilenced(e))
        store.setIntensity(.off, for: e.calendarKey)
        XCTAssertTrue(store.isCalendarSilenced(e))
        store.setMuted(true, for: e)
        store.setAlertOn(true, for: e)
        XCTAssertTrue(store.isAlertOn(e)); XCTAssertFalse(store.isMuted(e))
        store.setMuted(true, for: e)
        XCTAssertFalse(store.isAlertOn(e)); XCTAssertTrue(store.isMuted(e))
        store.setMuted(false, for: e); store.setAlertOn(true, for: e)
        // Kept across launches while the event is still ahead (the test event ends in 2027).
        XCTAssertTrue(MeetingGuardianStore(defaults: d).isAlertOn(e))
    }
}
