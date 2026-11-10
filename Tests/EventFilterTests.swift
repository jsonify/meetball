import XCTest
@testable import Meetball

final class EventFilterTests: XCTestCase {
    let start = Date(timeIntervalSince1970: 1_800_000_000)

    func ev(_ id: String, account: String = "me@acme.com", title: String? = nil, link: Bool = true, allDay: Bool = false,
            declined: Bool = false, me: AttendeeResponse? = nil, others: [String] = ["ann@acme.com"]) -> CalendarEvent {
        var people = others.map { EventAttendee(email: $0, name: nil, response: .accepted) }
        if let me { people.append(EventAttendee(email: account, name: nil, response: me, isSelf: true)) }
        return CalendarEvent(id: id, calendarID: "c", accountEmail: account, title: title ?? id, start: start,
                             end: start.addingTimeInterval(allDay ? 86400 : 1800), isAllDay: allDay,
                             meetURL: link ? URL(string: "https://meet.google.com/abc-defg-hij") : nil, location: nil,
                             attendees: people.compactMap(\.email), htmlLink: nil, isDeclined: declined, participants: people)
    }

    func testDefaultsHideOnlyDeclined() {
        let r = EventFilter.apply([ev("a"), ev("b", declined: true), ev("c", link: false, allDay: true, others: [])],
                                  settings: EventFilterSettings())
        XCTAssertEqual(r.shown.map(\.id), ["a", "c"])
        XCTAssertEqual(r.hidden.map(\.id), ["b"])
    }

    func testEachRule() {
        var rules = EventFilterRules()
        rules.hideAllDay = true; rules.hideWithoutLink = true; rules.hideSolo = true
        rules.keywordText = " lunch ,, Focus "
        XCTAssertEqual(rules.ignoredKeywords, ["lunch", "Focus"])
        XCTAssertEqual(EventFilter.hideReason(ev("a", allDay: true), rules: rules), .allDay)
        XCTAssertEqual(EventFilter.hideReason(ev("b", link: false), rules: rules), .noLink)
        XCTAssertEqual(EventFilter.hideReason(ev("c", me: .accepted, others: []), rules: rules), .solo)
        XCTAssertEqual(EventFilter.hideReason(ev("d", others: ["room@resource.calendar.google.com"]), rules: rules), .solo,
                       "rooms aren't people")
        XCTAssertEqual(EventFilter.hideReason(ev("e", title: "Team LUNCH"), rules: rules), .keyword)
        XCTAssertEqual(EventFilter.hideReason(ev("f", title: "Focüs time"), rules: rules), .keyword, "accent-insensitive")
        XCTAssertNil(EventFilter.hideReason(ev("g", title: "Design review"), rules: rules))
        XCTAssertNil(EventFilter.hideReason(ev("h", declined: true), rules: nil), "nil rules hide nothing")
    }

    func testTentativeIsDimmedNotHidden() {
        let maybe = ev("m", me: .tentative)
        var s = EventFilterSettings()
        XCTAssertTrue(EventFilter.isDimmed(maybe, settings: s))
        XCTAssertNil(EventFilter.hideReason(maybe, settings: s))
        XCTAssertFalse(EventFilter.isDimmed(ev("y", me: .accepted), settings: s))
        s.rules.dimTentative = false
        XCTAssertFalse(EventFilter.isDimmed(maybe, settings: s))
    }

    func testPerSourceOverrides() {
        var s = EventFilterSettings()
        s.rules.hideWithoutLink = true
        var custom = EventFilterRules(); custom.hideDeclined = false
        s.sources["work@acme.com"] = SourceFilterRule(mode: .custom, rules: custom)
        s.sources["Apple · iCloud"] = SourceFilterRule(mode: .showAll)
        let events = [ev("home", link: false), ev("work", account: "work@acme.com", link: false, declined: true),
                      ev("apple", account: "Apple · iCloud", link: false, declined: true)]
        XCTAssertEqual(EventFilter.apply(events, settings: s).shown.map(\.id), ["work", "apple"])
    }

    func testSettingsRoundTripAndTolerateMissingKeys() throws {
        let d = UserDefaults(suiteName: "test.\(UUID())")!
        XCTAssertEqual(EventFilterSettings.load(d), EventFilterSettings())
        var s = EventFilterSettings()
        s.rules.hideSolo = true
        s.sources["a@b.c"] = SourceFilterRule(mode: .showAll)
        s.save(d)
        XCTAssertEqual(EventFilterSettings.load(d), s)
        let partial = try JSONDecoder().decode(EventFilterRules.self, from: Data(#"{"hideAllDay":true}"#.utf8))
        XCTAssertTrue(partial.hideAllDay)
        XCTAssertTrue(partial.hideDeclined, "missing keys keep defaults")
    }

    func testHiddenUpcomingCount() {
        let now = start.addingTimeInterval(-600)
        let hidden = [ev("solo", others: []), ev("declined", declined: true), ev("allday", allDay: true)]
        XCTAssertEqual(UpcomingView.hiddenUpcoming(hidden, now: now), 1)
    }

    func testRespondingChangesOnlyYourReply() {
        let e = ev("a", me: .accepted)
        XCTAssertTrue(e.canRespond)
        let no = e.responding(.declined)
        XCTAssertEqual(no.selfResponse, .declined)
        XCTAssertTrue(no.isDeclined)
        XCTAssertEqual(no.participants.filter { !$0.isSelf }.map(\.response), [.accepted], "other guests keep their replies")
        let maybe = no.responding(.tentative)
        XCTAssertEqual(maybe.selfResponse, .tentative)
        XCTAssertFalse(maybe.isDeclined)
        XCTAssertEqual(EventFilter.hideReason(no, settings: EventFilterSettings()), .declined, "declining hides it from Up Next")
    }

    func testOnlyGuestsCanRespond() {
        XCTAssertFalse(ev("a").canRespond, "not on the guest list")
        var mine = ev("b", me: .accepted)
        mine.organizerIsSelf = true
        XCTAssertFalse(mine.canRespond, "the organizer doesn't RSVP")
    }

    func testCalendarFade() {
        var s = EventFilterSettings()
        s.rules.ignoredKeywords = ["lunch"]
        let shown = ev("a"), hidden = ev("b", title: "Lunch")
        XCTAssertEqual(EventFilter.calendarOpacity(shown, settings: s), 1)
        XCTAssertEqual(EventFilter.calendarOpacity(hidden, settings: s), 1, "full by default, as before")
        s.calendarFade = 0.3
        XCTAssertEqual(EventFilter.calendarOpacity(hidden, settings: s), 0.3)
        XCTAssertEqual(EventFilter.calendarOpacity(shown, settings: s), 1, "only filtered events fade")
        XCTAssertEqual(EventFilter.calendarEvents([shown, hidden], settings: s).map(\.id), ["a", "b"], "faded, still laid out")
        s.calendarFade = 0
        XCTAssertEqual(EventFilter.calendarEvents([shown, hidden], settings: s).map(\.id), ["a"], "0 leaves them out")
        s.sources["me@acme.com"] = SourceFilterRule(mode: .showAll)
        XCTAssertEqual(EventFilter.calendarOpacity(hidden, settings: s), 1, "a show-everything source never fades")
    }

    func testFilterSettingsDecodeWithoutFade() throws {
        var old = EventFilterSettings()
        old.rules.hideAllDay = true
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(old)) as! [String: Any]
        json.removeValue(forKey: "calendarFade")
        let decoded = try JSONDecoder().decode(EventFilterSettings.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertTrue(decoded.rules.hideAllDay, "saved rules survive the new setting")
        XCTAssertEqual(decoded.calendarFade, 1)
    }
}

/// Work calendars and "Work only" (#52).
final class CalendarVisibilityTests: XCTestCase {
    func testWorkOnly() {
        let hidden: Set = ["me|old"], work: Set = ["me|work"]
        func shown(_ k: String, workOnly: Bool, work: Set<String> = work) -> Bool {
            CalendarVisibility.isShown(k, hidden: hidden, work: work, workOnly: workOnly)
        }
        XCTAssertTrue(shown("me|home", workOnly: false))
        XCTAssertFalse(shown("me|home", workOnly: true))
        XCTAssertTrue(shown("me|work", workOnly: true))
        XCTAssertFalse(shown("me|old", workOnly: false), "hidden stays hidden")
        XCTAssertFalse(shown("me|old", workOnly: true, work: ["me|old"]), "hidden wins over work")
        XCTAssertTrue(shown("me|home", workOnly: true, work: []), "no work calendars marked: show everything")
    }
}
