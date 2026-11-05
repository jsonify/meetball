import Foundation
import AppKit

/// Auto-join for one meeting, or every meeting in its recurring series (#24).
public enum AutoJoinScope: String, Hashable, CaseIterable {
    case occurrence, series
}

public enum AutoJoin {
    /// How long after the planned join time auto-join still opens a meeting (a Mac waking later leaves it alone).
    public static let grace: TimeInterval = 5 * 60
    /// A join through Meetball this long before the start counts as having joined.
    public static let earlyJoin: TimeInterval = 15 * 60
    public static let delayOptions = [0, 1, 2, 3, 5]

    /// Identifies a recurring series across its occurrences; nil for one-off events.
    public static func seriesKey(_ e: CalendarEvent) -> String? {
        guard let s = e.seriesID, !s.isEmpty else { return nil }
        return "\(e.calendarKey)|\(s)"
    }

    /// When auto-join opens `e`: `delayMinutes` after the start.
    public static func joinTime(_ e: CalendarEvent, delayMinutes: Int) -> Date {
        e.start.addingTimeInterval(Double(max(0, delayMinutes)) * 60)
    }

    /// The meeting auto-join should open now, if any: set to auto-join, has a link, not declined, past its join time
    /// by less than `grace`, not over, and not joined already (through Meetball, or by auto-join earlier).
    /// When two are due, the one that started last wins.
    public static func due(_ events: [CalendarEvent], now: Date, delayMinutes: Int, isAutoJoin: (CalendarEvent) -> Bool,
                           hasJoined: (CalendarEvent) -> Bool) -> CalendarEvent? {
        events.filter { e in
            guard !e.isAllDay, !e.isDeclined, e.meetURL != nil, e.end > now, isAutoJoin(e) else { return false }
            let at = joinTime(e, delayMinutes: delayMinutes)
            return now >= at && now < at.addingTimeInterval(grace) && !hasJoined(e)
        }
        .max { $0.start < $1.start }
    }
}

/// Opens auto-join meetings when their time comes. `tick` runs every few seconds from the app model.
@MainActor
final class AutoJoinController {
    private let store: MeetingGuardianStore
    private var opened = Set<String>()

    init(store: MeetingGuardianStore) { self.store = store }

    func tick(events: [CalendarEvent], now: Date = Date()) {
        let delay = store.settings.autoJoinDelayMinutes
        guard let e = AutoJoin.due(events, now: now, delayMinutes: delay, isAutoJoin: store.isAutoJoin,
                                   hasJoined: { [opened] e in opened.contains(Self.key(e)) || MeetingJoiner.joined(e, since: e.start.addingTimeInterval(-AutoJoin.earlyJoin)) }),
              let url = e.meetURL else { return }
        opened.insert(Self.key(e))
        MeetingJoiner.join(url)
        Toast.show("Auto-joining \(e.title)", systemImage: "bolt.circle")
    }

    /// A rescheduled meeting gets another chance.
    private static func key(_ e: CalendarEvent) -> String { "\(e.uid)|\(Int(e.start.timeIntervalSince1970))" }
}
