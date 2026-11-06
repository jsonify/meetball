import XCTest
@testable import Meetball

/// The pre-flight card's brief and Echo's notes and reminders (shared with the iPhone app).
final class PreFlightTests: XCTestCase {
    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    /// Thursday 5 November 2026, `h`:`m` UTC, shifted by `days`.
    private func at(_ h: Int, _ m: Int = 0, days: Int = 0) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 11, day: 5 + days, hour: h, minute: m))!
    }

    private func ev(_ id: String, _ title: String, _ start: Date, minutes: Double = 30, series: String? = nil,
                    people: [String] = [], notes: String? = nil, location: String? = nil, url: String? = nil) -> CalendarEvent {
        var e = CalendarEvent(id: id, calendarID: "c", accountEmail: "a", title: title, start: start,
                              end: start.addingTimeInterval(minutes * 60), isAllDay: false, meetURL: url.flatMap(URL.init(string:)),
                              location: location, attendees: people, htmlLink: nil)
        e.seriesID = series
        e.notes = notes
        e.participants = people.map { EventAttendee(email: $0, name: nil, response: .accepted) }
            + [EventAttendee(email: "me@x.com", name: "Me", response: .accepted, isSelf: true)]
        return e
    }

    // MARK: Last time

    func testLastMeetingPrefersTheSameSeries() {
        let now = ev("now", "Weekly sync", at(10), series: "S")
        let sameTitle = ev("t", "Weekly sync", at(10, days: -2))
        let lastWeek = ev("s", "Weekly sync (moved)", at(10, days: -7), series: "S")
        let hit = PreFlight.lastMeeting(before: now, in: [sameTitle, lastWeek, now])
        XCTAssertEqual(hit?.event.id, "s")
        XCTAssertEqual(hit?.match, .series)
    }

    func testLastMeetingByTitleThenMostRecent() {
        let now = ev("now", "Design review", at(14))
        let older = ev("o", "design review", at(14, days: -14))
        let newer = ev("n", "Design Review ", at(9))
        let later = ev("l", "Design review", at(16))   // after this one: not "last time"
        let hit = PreFlight.lastMeeting(before: now, in: [older, later, newer])
        XCTAssertEqual(hit?.event.id, "n")
        XCTAssertEqual(hit?.match, .title)
    }

    func testGenericTitlesDontMatchButPeopleDo() {
        let now = ev("now", "Sync", at(11), people: ["ada@x.com", "bob@x.com"])
        let otherSync = ev("o", "Sync", at(11, days: -1), people: ["zed@x.com"])
        let samePeople = ev("p", "Roadmap chat", at(15, days: -3), people: ["ADA@x.com", "bob@x.com", "cy@x.com"])
        let hit = PreFlight.lastMeeting(before: now, in: [otherSync, samePeople])
        XCTAssertEqual(hit?.event.id, "p")
        XCTAssertEqual(hit?.match, .people)
    }

    func testPeopleMatchNeedsHalfOfEachSide() {
        let now = ev("now", "Kickoff", at(11), people: ["ada@x.com"])
        let crowd = ev("c", "All hands", at(11, days: -1), people: ["ada@x.com", "b@x.com", "c@x.com", "d@x.com"])
        XCTAssertNil(PreFlight.lastMeeting(before: now, in: [crowd]))
        let alone = ev("solo", "Focus", at(11))
        XCTAssertNil(PreFlight.lastMeeting(before: alone, in: [crowd]), "Just you: no people to match on")
    }

    func testDeclinedAndOverlappingMeetingsAreSkipped() {
        let now = ev("now", "Design review", at(14))
        var declined = ev("d", "Design review", at(14, days: -1))
        declined.isDeclined = true
        let stillOn = ev("s", "Design review", at(13, 45))   // runs past this one's start
        XCTAssertNil(PreFlight.lastMeeting(before: now, in: [declined, stillOn]))
    }

    // MARK: People, links, notes

    func testPeopleLeaveOutYouAndPutTheOrganizerFirst() {
        var e = ev("e", "Review", at(10))
        e.participants = [EventAttendee(email: "zoe@x.com", name: "Zoe", response: .accepted),
                          EventAttendee(email: "me@x.com", name: "Me", response: .accepted, isSelf: true),
                          EventAttendee(email: "al@x.com", name: "Al", response: .declined),
                          EventAttendee(email: "bo@x.com", name: "Bo", response: .tentative, isOrganizer: true),
                          EventAttendee(email: "cy@x.com", name: "Cy", response: .accepted)]
        XCTAssertEqual(PreFlight.people(e).map(\.displayName), ["Bo", "Cy", "Zoe", "Al"])
    }

    func testLinksSkipTheJoinLinkAndBoilerplate() {
        let notes = """
        Agenda: https://docs.google.com/document/d/abc/edit and the board https://www.figma.com/file/xyz
        Again: https://docs.google.com/document/d/abc/edit
        Ticket https://acme.atlassian.net/browse/MB-42 and https://github.com/jsonify/meetball/pull/50
        Join: https://meet.google.com/abc-defg-hij
        Help: https://support.google.com/a/users/answer/9282720
        """
        let e = ev("e", "Review", at(10), notes: notes, location: "https://zoom.us/j/123", url: "https://meet.google.com/abc-defg-hij")
        XCTAssertEqual(PreFlight.links(in: e).map(\.label), ["Google Doc", "Figma", "Jira · MB-42", "GitHub · jsonify/meetball"])
    }

    func testNotesExcerptStopsAtTheDialInBlock() {
        let notes = "Bring the Q4 numbers.\n\n-::~:~::~:~:~:~:~:~::~:~::-\nJoin with Google Meet: https://meet.google.com/x"
        XCTAssertEqual(PreFlight.notesExcerpt(ev("e", "R", at(10), notes: notes)), "Bring the Q4 numbers.")
        XCTAssertNil(PreFlight.notesExcerpt(ev("e", "R", at(10), notes: "Join Zoom Meeting\nhttps://zoom.us/j/1")))
        let long = String(repeating: "word ", count: 100)
        XCTAssertTrue(PreFlight.notesExcerpt(ev("e", "R", at(10), notes: long))!.hasSuffix("…"))
    }

    func testDueWithinFiveMinutes() {
        let soon = ev("soon", "A", at(10, 4))
        let later = ev("later", "B", at(10, 30))
        XCTAssertEqual(PreFlight.due([later, soon], now: at(10))?.id, "soon")
        XCTAssertNil(PreFlight.due([later], now: at(10)))
        XCTAssertEqual(PreFlight.next([later, soon], now: at(10, 5))?.id, "later")
    }

    func testHistoryRangeIsWholeDays() {
        let e = ev("e", "A", at(10, 17))
        let r = PreFlight.historyRange(for: e, calendar: cal)
        XCTAssertEqual(r.start, cal.date(byAdding: .day, value: -PreFlight.lookbackDays, to: at(0)))
        XCTAssertEqual(r.end, e.start)
    }

    func testBriefIsEmptyForABareEvent() {
        var e = ev("e", "Focus", at(10))
        e.participants = []
        XCTAssertTrue(PreFlight.brief(for: e, history: []).isEmpty)
    }

    // MARK: Echo

    func testJustEndedOffersTheLatestMeetingWithoutANote() {
        let a = ev("a", "Standup", at(9, 15), minutes: 30)
        let b = ev("b", "Design review", at(9, 30), minutes: 30)
        let short = ev("s", "Quick hold", at(10), minutes: 5)
        let now = at(10, 10)
        XCTAssertEqual(Echo.justEnded([a, b, short], notes: [], dismissed: [], now: now)?.id, "b")
        let note = Echo.note(for: b, text: "Send the deck", now: now)
        XCTAssertEqual(Echo.justEnded([a, b], notes: [note], dismissed: [], now: now)?.id, "a")
        XCTAssertNil(Echo.justEnded([a, b], notes: [note], dismissed: [a.uid], now: now))
        XCTAssertNil(Echo.justEnded([b], notes: [], dismissed: [], now: at(11)), "Over half an hour ago")
    }

    func testNotesMatchTheSameMeetingOnAnotherCalendar() {
        let e = ev("e", "Design review", at(9))
        let note = Echo.note(for: e, text: "  Send   the deck. ", now: at(10))
        XCTAssertEqual(note.text, "Send the deck.")
        var copy = e
        copy.calendarID = "mirror"
        XCTAssertTrue(Echo.matches(note, copy))
        XCTAssertFalse(Echo.matches(note, ev("x", "Design review", at(9, days: 7))))
    }

    func testReminderTitleUsesTheFirstSentence() {
        let e = ev("e", "Design review", at(9))
        XCTAssertEqual(Echo.reminderTitle(Echo.note(for: e, text: "Send Ada the deck. Then check budget.", now: at(10))),
                       "Design review: Send Ada the deck")
        XCTAssertEqual(Echo.reminderTitle(Echo.note(for: e, text: "", now: at(10))), "Follow up on Design review")
        let long = Echo.reminderTitle(Echo.note(for: e, text: String(repeating: "a", count: 200), now: at(10)))
        XCTAssertEqual(long.count, 100)
        XCTAssertTrue(long.hasSuffix("…"))
        XCTAssertTrue(Echo.reminderNotes(Echo.note(for: e, text: "Send it", now: at(10))).hasSuffix("\n\nSend it"))
    }

    func testDueTheNextWorkingMorning() {
        // Thursday → Friday 9:00; Friday → Monday 9:00.
        XCTAssertEqual(Echo.dueDate(after: at(16), calendar: cal), at(9, days: 1))
        XCTAssertEqual(Echo.dueDate(after: at(16, days: 1), calendar: cal), at(9, days: 4))
    }
}
