import XCTest
@testable import Meetball

final class MeetingChangeCardTests: XCTestCase {
    private func ev(_ id: String, _ title: String, start: Date) -> CalendarEvent {
        CalendarEvent(id: id, calendarID: "cal", accountEmail: "Apple · iCloud", title: title, start: start,
                      end: start.addingTimeInterval(1800), isAllDay: false, meetURL: URL(string: "https://meet.google.com/abc-defg-hij"),
                      location: "Room 1", attendees: [], htmlLink: nil, colorHex: "#112233")
    }

    func testSnapshotSurvivesARestart() throws {
        let start = Date(timeIntervalSince1970: 1_900_000_000)
        let range = DateInterval(start: start.addingTimeInterval(-86400), end: start.addingTimeInterval(7 * 86400))
        var declined = ev("B@2", "Lunch", start: start.addingTimeInterval(3600)); declined.isDeclined = true
        let snap = EventSnapshot(events: [ev("A@1", "Design review", start: start), declined],
                                 calendars: ["Apple · iCloud|cal"], range: range)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("s.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        StoredEventSnapshot(snap, savedAt: start).save(to: url)
        let back = try XCTUnwrap(StoredEventSnapshot.load(from: url)?.snapshot(now: start.addingTimeInterval(600)))
        XCTAssertEqual(back.calendars, snap.calendars)
        XCTAssertEqual(back.range, range)
        XCTAssertEqual(Set(back.events.keys), Set(snap.events.keys))
        let a = try XCTUnwrap(back.events["Apple · iCloud|cal|A@1"])
        XCTAssertEqual(a.start, start); XCTAssertEqual(a.title, "Design review"); XCTAssertEqual(a.meetURL, snap.events[a.uid]?.meetURL)
        XCTAssertTrue(back.events["Apple · iCloud|cal|B@2"]?.isDeclined ?? false)

        // A move made while Meetball was closed is found against the restored snapshot.
        let moved = ev("A@3", "Design review", start: start.addingTimeInterval(7200))
        let now = start.addingTimeInterval(-3600)
        let changes = MeetingChangeDetector.diff(old: back, new: EventSnapshot(events: [moved, declined], calendars: snap.calendars, range: range), now: now)
        XCTAssertEqual(changes.map(\.kind), [.rescheduled(from: start, to: start.addingTimeInterval(7200))])
    }

    func testOldSnapshotIsIgnored() {
        let t = Date(timeIntervalSince1970: 1_900_000_000)
        let s = StoredEventSnapshot(EventSnapshot(events: [], calendars: [], range: DateInterval(start: t, duration: 86400)), savedAt: t)
        XCTAssertNotNil(s.snapshot(now: t.addingTimeInterval(3600)))
        XCTAssertNil(s.snapshot(now: t.addingTimeInterval(StoredEventSnapshot.maxAge + 1)))
    }

    @MainActor func testCardKeepsTheNewestChangePerMeeting() {
        let t = Date(timeIntervalSince1970: 1_900_000_000)
        let a1 = MeetingChange(kind: .rescheduled(from: t, to: t.addingTimeInterval(3600)), event: ev("A@1", "Design review", start: t.addingTimeInterval(3600)))
        let b = MeetingChange(kind: .linkChanged, event: ev("B", "Lunch", start: t))
        let a2 = MeetingChange(kind: .cancelled, event: ev("A@2", "Design review", start: t.addingTimeInterval(3600)))
        XCTAssertEqual(MeetingChangeCardPanel.merged([a1, b], [a2]), [a2, b])
    }

    func testCardSettingDefaultsOnForOldSettings() throws {
        let s = try JSONDecoder().decode(GuardianSettings.self, from: Data(#"{"notifyChanges": true}"#.utf8))
        XCTAssertTrue(s.changeCard)
    }
}
