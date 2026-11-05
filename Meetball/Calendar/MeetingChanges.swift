import Foundation

/// What happened to an upcoming meeting between two calendar syncs (#30).
public enum MeetingChangeKind: Equatable {
    /// Gone from its calendar, or retitled "Canceled: …" by the organizer's mail client.
    case cancelled
    /// Start time moved (the end usually moves with it).
    case rescheduled(from: Date, to: Date)
    /// Same time, different join link.
    case linkChanged
}

public struct MeetingChange: Equatable {
    public let kind: MeetingChangeKind
    /// The meeting as it is now, or as it was for a cancellation.
    public let event: CalendarEvent

    public var isCancellation: Bool { kind == .cancelled }
}

/// The events one sync returned, and which calendars and dates that sync covered. Only calendars covered by both
/// syncs are compared, so a failed account or a hidden calendar never reads as a wave of cancellations.
public struct EventSnapshot {
    public var events: [String: CalendarEvent]
    /// Calendar keys whose events loaded without an error.
    public var calendars: Set<String>
    public var range: DateInterval

    public init(events: [CalendarEvent], calendars: Set<String>, range: DateInterval) {
        self.events = Dictionary(events.map { ($0.uid, $0) }, uniquingKeysWith: { a, _ in a })
        self.calendars = calendars
        self.range = range
    }

    /// This sync, plus the previous sync's events for calendars that failed this time (not hidden ones), so a
    /// network blip doesn't lose track of them.
    public func carryingOver(_ previous: EventSnapshot?, hidden: Set<String>, attempted: Set<String>) -> EventSnapshot {
        guard let previous else { return self }
        var out = self
        let carried = previous.calendars.subtracting(calendars).subtracting(hidden).intersection(attempted)
        guard !carried.isEmpty else { return self }
        for (uid, e) in previous.events where carried.contains(e.calendarKey) && out.events[uid] == nil { out.events[uid] = e }
        out.calendars.formUnion(carried)
        return out
    }
}

public enum MeetingChangeDetector {
    /// Only meetings starting within this window are reported; further out, changes are routine.
    public static let lookahead: TimeInterval = 48 * 3600

    /// Changes to timed, not-declined meetings that haven't ended and start (or now start) within `lookahead`.
    /// `ignoring` holds uids the user removed in Meetball itself.
    public static func diff(old: EventSnapshot, new: EventSnapshot, now: Date, ignoring: Set<String> = [],
                            lookahead: TimeInterval = lookahead) -> [MeetingChange] {
        let shared = old.calendars.intersection(new.calendars)
        let horizon = now.addingTimeInterval(lookahead)
        let oldUIDs = Set(old.events.keys)
        var claimed = Set<String>()
        var out: [MeetingChange] = []
        for before in old.events.values.sorted(by: { $0.start < $1.start }) {
            guard shared.contains(before.calendarKey), !ignoring.contains(before.uid), !before.isAllDay, !before.isDeclined,
                  before.end > now, new.range.contains(before.start), old.range.contains(before.start) else { continue }
            guard let after = match(before, in: new, oldUIDs: oldUIDs, claimed: &claimed) else {
                if before.start <= horizon { out.append(MeetingChange(kind: .cancelled, event: before)) }
                continue
            }
            // Declining is the user's own doing, not news.
            if after.isDeclined { continue }
            if isCancelTitle(after.title) && !isCancelTitle(before.title) {
                if before.start <= horizon { out.append(MeetingChange(kind: .cancelled, event: before)) }
            } else if after.start != before.start {
                if before.start <= horizon || after.start <= horizon {
                    out.append(MeetingChange(kind: .rescheduled(from: before.start, to: after.start), event: after))
                }
            } else if before.meetURL != nil, after.meetURL != nil, before.meetURL != after.meetURL, before.start <= horizon {
                out.append(MeetingChange(kind: .linkChanged, event: after))
            }
        }
        return out
    }

    /// The same meeting in `new`: by uid, else (Apple Calendar ids carry the start time) the closest-starting event
    /// with the same underlying id that wasn't in the old sync.
    static func match(_ e: CalendarEvent, in new: EventSnapshot, oldUIDs: Set<String>, claimed: inout Set<String>) -> CalendarEvent? {
        if let same = new.events[e.uid] { return same }
        let base = baseID(e.id)
        let candidates = new.events.values.filter {
            $0.calendarKey == e.calendarKey && baseID($0.id) == base && !oldUIDs.contains($0.uid) && !claimed.contains($0.uid)
        }
        guard let best = candidates.min(by: { abs($0.start.timeIntervalSince(e.start)) < abs($1.start.timeIntervalSince(e.start)) })
        else { return nil }
        claimed.insert(best.uid)
        return best
    }

    /// "ABC@1730000000" → "ABC" (Apple Calendar occurrence ids); Google ids are returned unchanged.
    static func baseID(_ id: String) -> String {
        guard let at = id.lastIndex(of: "@"), Int(id[id.index(after: at)...]) != nil else { return id }
        return String(id[..<at])
    }

    /// Outlook and Exchange retitle a cancelled invite "Canceled: …" (or "Cancelled: …").
    public static func isCancelTitle(_ title: String) -> Bool {
        let t = title.trimmingCharacters(in: .whitespaces).lowercased()
        return t.hasPrefix("canceled:") || t.hasPrefix("cancelled:") || t.hasPrefix("canceled -") || t.hasPrefix("cancelled -")
    }
}

/// Notification wording for meeting changes.
public enum MeetingChangeText {
    public static func title(_ c: MeetingChange) -> String {
        switch c.kind {
        case .cancelled: return "\u{1F389} Canceled: \(c.event.title)"
        case .rescheduled: return "Meeting moved: \(c.event.title)"
        case .linkChanged: return "New join link: \(c.event.title)"
        }
    }

    public static func body(_ c: MeetingChange, now: Date, calendar: Calendar = .app) -> String {
        switch c.kind {
        case .cancelled:
            return "Your \(when(c.event.start, now: now, calendar: calendar)) is off the calendar. Enjoy the free time."
        case .rescheduled(let from, let to):
            return "Now \(when(to, now: now, calendar: calendar)) (was \(when(from, now: now, calendar: calendar)))."
        case .linkChanged:
            return "The meeting at \(when(c.event.start, now: now, calendar: calendar)) has a different join link."
        }
    }

    /// One summary when a sync brings several changes at once.
    public static func summary(_ changes: [MeetingChange]) -> (title: String, body: String) {
        let cancelled = changes.filter(\.isCancellation).count
        let other = changes.count - cancelled
        var parts: [String] = []
        if cancelled > 0 { parts.append("\(cancelled) canceled") }
        if other > 0 { parts.append("\(other) changed") }
        let title = cancelled > 0 ? "\u{1F389} \(changes.count) meetings updated" : "\(changes.count) meetings changed"
        return (title, parts.joined(separator: ", ") + ": " + changes.prefix(3).map(\.event.title).joined(separator: ", ")
                + (changes.count > 3 ? "\u{2026}" : ""))
    }

    /// "2:30 PM" today, "tomorrow 9:00 AM", "Tue 9:00 AM" otherwise.
    static func when(_ d: Date, now: Date, calendar: Calendar) -> String {
        if calendar.isDate(d, inSameDayAs: now) { return d.shortTime }
        if let t = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(d, inSameDayAs: t) { return "tomorrow \(d.shortTime)" }
        return "\(d.formatted(.dateTime.weekday(.abbreviated))) \(d.shortTime)"
    }
}
