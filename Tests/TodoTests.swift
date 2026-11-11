import XCTest
@testable import Meetball

/// The to-do list's order, its links back to meetings, and the action items found in meeting notes (shared with the
/// iPhone app).
final class TodoTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_762_880_400)

    private func item(_ id: String, rank: Double?, created: Double = 0, done: Bool = false, completed: Double? = nil) -> TodoItem {
        TodoItem(id: id, title: id, isDone: done, completedAt: completed.map { Date(timeIntervalSince1970: $0) },
                 createdAt: Date(timeIntervalSince1970: created), rank: rank)
    }

    private func ev(_ title: String, uid id: String = "e1") -> CalendarEvent {
        CalendarEvent(id: id, calendarID: "c", accountEmail: "a", title: title, start: start,
                      end: start.addingTimeInterval(1800), isAllDay: false, meetURL: nil, location: nil, attendees: [], htmlLink: nil)
    }

    // MARK: Link

    func testLinkRoundTripsRankAndMeeting() {
        let m = TodoMeeting(uid: "a|c|e1", title: "Design review & sync", start: start)
        let url = TodoLink.url(rank: 2.5, meeting: m)
        XCTAssertEqual(url.scheme, "meetball")
        XCTAssertEqual(url.host, "todo")
        let parsed = TodoLink.parse(url)
        XCTAssertEqual(parsed.rank, 2.5)
        XCTAssertEqual(parsed.meeting, m)
    }

    func testLinkWholeRankHasNoDecimals() {
        XCTAssertTrue(TodoLink.url(rank: 3, meeting: nil).absoluteString.contains("rank=3"))
        XCTAssertFalse(TodoLink.url(rank: 3, meeting: nil).absoluteString.contains("3.0"))
    }

    func testOtherLinksParseToNothing() {
        XCTAssertNil(TodoLink.parse(URL(string: "https://example.com/?rank=1")).rank)
        XCTAssertNil(TodoLink.parse(nil).meeting)
        XCTAssertNil(TodoLink.parse(URL(string: "meetball://join?url=x")).rank)
    }

    // MARK: Order

    func testOpenByRankThenUnrankedOldestFirstAndDoneNewestFirst() {
        let items = [item("c", rank: nil, created: 5), item("a", rank: 2), item("b", rank: 1), item("d", rank: nil, created: 1),
                     item("x", rank: 0, done: true, completed: 10), item("y", rank: 9, done: true, completed: 20)]
        let (open, done) = Todos.arrange(items)
        XCTAssertEqual(open.map(\.id), ["b", "a", "d", "c"])
        XCTAssertEqual(done.map(\.id), ["y", "x"])
    }

    func testNewItemsGoAtTheBottom() {
        XCTAssertEqual(Todos.rankForNew(after: []), 1)
        XCTAssertEqual(Todos.rankForNew(after: [item("a", rank: 4), item("b", rank: nil)]), 5)
    }

    func testMovingBetweenTwoRankedItemsTakesTheMidpoint() {
        let open = [item("a", rank: 1), item("b", rank: 2), item("c", rank: 3)]
        let order = Todos.moving(open, from: [2], to: 1)
        XCTAssertEqual(order.map(\.id), ["a", "c", "b"])
        XCTAssertEqual(Todos.ranks(for: order, moved: "c"), ["c": 1.5])
    }

    func testMovingToTheTopAndBottom() {
        let open = [item("a", rank: 1), item("b", rank: 2), item("c", rank: 3)]
        XCTAssertEqual(Todos.ranks(for: Todos.moving(open, from: [2], to: 0), moved: "c"), ["c": 0])
        XCTAssertEqual(Todos.ranks(for: Todos.moving(open, from: [0], to: 3), moved: "a"), ["a": 4])
    }

    func testMovingNextToAnUnrankedItemNumbersEverything() {
        let open = [item("a", rank: 1), item("b", rank: nil), item("c", rank: nil)]
        let order = Todos.moving(open, from: [0], to: 2)
        XCTAssertEqual(order.map(\.id), ["b", "a", "c"])
        XCTAssertEqual(Todos.ranks(for: order, moved: "a"), ["b": 1, "a": 2, "c": 3])
    }

    func testMovingIntoATinyGapNumbersEverything() {
        let open = [item("a", rank: 1), item("b", rank: 1 + 1e-9), item("c", rank: 5)]
        let order = Todos.moving(open, from: [2], to: 1)
        XCTAssertEqual(Todos.ranks(for: order, moved: "c"), ["b": 3, "c": 2])
    }

    // MARK: Meetings

    func testFollowUpsMatchTheMeetingByIdOrByTitleAndTime() {
        var a = item("a", rank: 1); a.meeting = TodoMeeting(ev("Design review"))
        var b = item("b", rank: 2); b.meeting = TodoMeeting(uid: "other", title: "design review", start: start)
        var c = item("c", rank: 3); c.meeting = TodoMeeting(uid: "other", title: "Standup", start: start)
        XCTAssertEqual(Todos.followUps(for: ev("Design review"), in: [c, b, a]).map(\.id), ["a", "b"])
    }

    func testSuggestionsFromNotes() {
        let notes = """
        Agenda
        - Budget
        TODO: send Ada the deck
        Action: book the room
        - [ ] Update the roadmap
        AI - Jason to follow up with legal
        ☐ Share notes
        todo: Send Ada the deck
        Next steps: ship it
        Random line: not an action
        """
        XCTAssertEqual(Todos.suggestions(fromNotes: notes),
                       ["send Ada the deck", "book the room", "Update the roadmap", "Jason to follow up with legal", "Share notes", "ship it"])
    }

    func testSuggestionsSkipWhatsAlreadyOnTheList() {
        var a = item("Book the room", rank: 1); a.meeting = TodoMeeting(ev("Design review"))
        XCTAssertEqual(Todos.newSuggestions(for: ev("Design review"), notes: "Action: book the room\nTODO: call Bo", items: [a]),
                       ["call Bo"])
    }

    // MARK: Echo

    func testEchoJoinsRecordings() {
        XCTAssertEqual(Echo.joined("Send the deck.", " Then call Bo "), "Send the deck. Then call Bo")
        XCTAssertEqual(Echo.joined("", "Hi"), "Hi")
        XCTAssertEqual(Echo.joined("Hi", ""), "Hi")
    }
}
