import Foundation

// Shared with the iPhone app (MeetballPhone): no AppKit here.

/// An Echo note: what you said after a meeting, kept in Meetball (the work calendar is a read-only
/// feed, so nothing is written to the event) and, if you like, added to Reminders as a follow-up.
public struct EchoNote: Codable, Hashable, Identifiable {
    public var id = UUID()
    /// The meeting's `CalendarEvent.uid`.
    public var eventUID: String
    public var seriesID: String?
    public var meetingTitle: String
    public var meetingStart: Date
    public var meetingEnd: Date
    public var text: String
    public var createdAt: Date
    /// The Reminders item made from it (`EKReminder.calendarItemIdentifier`), when one was.
    public var reminderID: String?
}

/// Echo mode: when a meeting ends, one tap records a short voice note that becomes a follow-up reminder pinned to
/// that meeting.
public enum Echo {
    /// The longest recording: a safety stop, well past any real note (it used to be 20 seconds, which cut people off).
    public static let maxDuration: TimeInterval = 10 * 60
    /// How long after a meeting ends Meetball offers to record.
    public static let offerWindow: TimeInterval = 30 * 60
    /// Shorter meetings (a 5-minute hold) aren't worth a note.
    public static let minMeetingLength: TimeInterval = 10 * 60
    /// Notes kept; the oldest go first.
    public static let keep = 300
    /// The hour the follow-up reminder is due, the next working day.
    public static let dueHour = 9

    public static func note(for e: CalendarEvent, text: String, now: Date) -> EchoNote {
        EchoNote(eventUID: e.uid, seriesID: e.seriesID, meetingTitle: e.title, meetingStart: e.start, meetingEnd: e.end,
                 text: cleaned(text), createdAt: now)
    }

    /// Whether `note` was left for `e`: the same event, or (a meeting kept on two calendars, an id the sync changed)
    /// the same title at the same time.
    public static func matches(_ note: EchoNote, _ e: CalendarEvent) -> Bool {
        note.eventUID == e.uid
            || (note.meetingStart == e.start
                && MeetingChangeDetector.normalizedTitle(note.meetingTitle) == MeetingChangeDetector.normalizedTitle(e.title))
    }

    /// The notes left for `e`, newest first.
    public static func notes(for e: CalendarEvent, in notes: [EchoNote]) -> [EchoNote] {
        notes.filter { matches($0, e) }.sorted { $0.createdAt > $1.createdAt }
    }

    /// The meeting to offer Echo for: the one that ended most recently, within `offerWindow`, at least
    /// `minMeetingLength` long, not declined, with no note yet and not waved off.
    public static func justEnded(_ events: [CalendarEvent], notes: [EchoNote], dismissed: Set<String>, now: Date) -> CalendarEvent? {
        events.filter { e in
            !e.isAllDay && !e.isDeclined && e.end <= now && now.timeIntervalSince(e.end) < offerWindow
                && e.end.timeIntervalSince(e.start) >= minMeetingLength && !dismissed.contains(e.uid)
                && !notes.contains { matches($0, e) }
        }
        .max { $0.end < $1.end }
    }

    /// Two stretches of a note run together with a space, either of them possibly empty.
    public static func joined(_ a: String, _ b: String) -> String {
        cleaned([a, b].map(cleaned).filter { !$0.isEmpty }.joined(separator: " "))
    }

    /// Whitespace collapsed and trimmed.
    public static func cleaned(_ text: String) -> String {
        text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
    }

    /// The reminder's title: "Design review: Send Ada the deck", the note's first sentence, cut at 100 characters.
    public static func reminderTitle(_ note: EchoNote, limit: Int = 100) -> String {
        let text = cleaned(note.text)
        var first = text
        if let r = text.range(of: #"[.!?](\s|$)"#, options: .regularExpression) { first = String(text[..<r.lowerBound]) }
        let title = first.isEmpty ? "Follow up on \(note.meetingTitle)" : "\(note.meetingTitle): \(first)"
        guard title.count > limit else { return title }
        return String(title.prefix(limit - 1)).trimmingCharacters(in: .whitespaces) + "…"
    }

    /// The reminder's notes: which meeting it came from, then everything you said.
    public static func reminderNotes(_ note: EchoNote, locale: Locale = .current) -> String {
        let when = note.meetingStart.formatted(Date.FormatStyle(locale: locale).weekday(.abbreviated).month(.abbreviated).day()
            .hour().minute())
        return "From \u{201C}\(note.meetingTitle)\u{201D}, \(when). Recorded with Meetball Echo.\n\n\(note.text)"
    }

    /// When the follow-up is due: `dueHour` on the next working day (Monday to Friday) after the meeting.
    public static func dueDate(after end: Date, calendar: Calendar = .app) -> Date {
        var day = calendar.startOfDay(for: end)
        repeat {
            day = calendar.date(byAdding: .day, value: 1, to: day) ?? day.addingTimeInterval(86400)
        } while calendar.isDateInWeekend(day)
        return calendar.date(bySettingHour: dueHour, minute: 0, second: 0, of: day) ?? day
    }
}
