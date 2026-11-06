import Foundation

// Shared with the iPhone app (MeetballPhone), so it uses only Foundation.

/// The pure logic behind the new-meeting composer: what a proposed time clashes with, which free times fit, and the
/// .ics invite that carries a meeting to a calendar Meetball can't write to (a work calendar seen only as a feed).
public enum MeetingComposer {
    /// The length keys on the composer, in minutes.
    public static let lengthChoices = [15, 30, 45, 60]
    /// Free times start on a quarter hour.
    public static let slotStep: TimeInterval = 15 * 60

    /// Timed meetings you haven't declined that overlap `start..<end`, earliest first.
    public static func conflicts(start: Date, end: Date, in events: [CalendarEvent]) -> [CalendarEvent] {
        events.filter { !$0.isAllDay && !$0.isDeclined && $0.start < end && $0.end > start }
            .sorted { ($0.start, $0.title) < ($1.start, $1.title) }
    }

    /// A short readout of what a proposed time clashes with: "Overlaps Standup", "Overlaps Standup +2", or nil.
    public static func conflictSummary(_ clashes: [CalendarEvent]) -> String? {
        guard let first = clashes.first else { return nil }
        return clashes.count == 1 ? "Overlaps \(first.title)" : "Overlaps \(first.title) +\(clashes.count - 1)"
    }

    /// Up to `limit` start times, from `now` on, where a meeting of `length` fits between `events` inside working
    /// hours (`dayStart`..<`dayEnd`, hours of the day) on weekdays, looking `days` days ahead. One per free gap, at the
    /// gap's first quarter hour, so the suggestions spread across the day rather than being 9:00, 9:15 and 9:30.
    public static func freeSlots(length: TimeInterval, events: [CalendarEvent], now: Date, limit: Int = 3,
                                 days: Int = 5, dayStart: Int = 9, dayEnd: Int = 18,
                                 calendar: Calendar = .current) -> [Date] {
        guard length > 0, limit > 0 else { return [] }
        let busy = events.filter { !$0.isAllDay && !$0.isDeclined }.sorted { $0.start < $1.start }
        var found: [Date] = []
        let today = calendar.startOfDay(for: now)
        for offset in 0..<max(days, 1) {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                  !calendar.isDateInWeekend(day),
                  let open = calendar.date(bySettingHour: dayStart, minute: 0, second: 0, of: day),
                  let close = calendar.date(bySettingHour: dayEnd, minute: 0, second: 0, of: day) else { continue }
            var cursor = roundUp(max(open, now))
            for b in busy where b.end > cursor && b.start < close {
                if b.start.timeIntervalSince(cursor) >= length {
                    found.append(cursor)
                    if found.count == limit { return found }
                }
                cursor = roundUp(max(cursor, b.end))
            }
            if close.timeIntervalSince(cursor) >= length {
                found.append(cursor)
                if found.count == limit { return found }
            }
        }
        return found
    }

    /// `date` moved up to the next quarter hour (unchanged when it's already on one). Every time zone's offset is a
    /// whole number of quarter hours, so this is a local quarter hour too.
    public static func roundUp(_ date: Date) -> Date {
        let t = date.timeIntervalSinceReferenceDate
        return Date(timeIntervalSinceReferenceDate: (t / slotStep).rounded(.up) * slotStep)
    }

    /// A slot's label for a key: "Today 3:30 PM", "Tomorrow 10:00 AM", "Mon 9:00 AM".
    public static func slotLabel(_ start: Date, now: Date, calendar: Calendar = .current, locale: Locale = .current) -> String {
        let time = start.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: locale, timeZone: calendar.timeZone))
        if calendar.isDate(start, inSameDayAs: now) { return "Today \(time)" }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(start, inSameDayAs: tomorrow) {
            return "Tomorrow \(time)"
        }
        var style = Date.FormatStyle(locale: locale, timeZone: calendar.timeZone).weekday(.abbreviated)
        style.calendar = calendar
        return "\(start.formatted(style)) \(time)"
    }

    /// The meeting as an iCalendar file to email to an address whose calendar Meetball can't write to. It's published
    /// (`METHOD:PUBLISH`) rather than sent as a request, so opening it in Outlook offers to add it to that calendar
    /// without anyone else being invited or any reply going back.
    public static func icsInvite(title: String, start: Date, end: Date, uid: String = UUID().uuidString,
                                 notes: String? = nil, now: Date = Date()) -> String {
        var lines = [
            "BEGIN:VCALENDAR",
            "VERSION:2.0",
            "PRODID:-//Meetball//Meetball for iPhone//EN",
            "CALSCALE:GREGORIAN",
            "METHOD:PUBLISH",
            "BEGIN:VEVENT",
            "UID:\(uid)@meetball.app",
            "DTSTAMP:\(icsDate(now))",
            "DTSTART:\(icsDate(start))",
            "DTEND:\(icsDate(end))",
            "SUMMARY:\(icsEscape(title))",
            "STATUS:CONFIRMED",
            "TRANSP:OPAQUE",
        ]
        if let notes, !notes.isEmpty { lines.append("DESCRIPTION:\(icsEscape(notes))") }
        lines += ["END:VEVENT", "END:VCALENDAR"]
        return lines.flatMap(fold).joined(separator: "\r\n") + "\r\n"
    }

    /// A UTC timestamp as iCalendar writes it: 20261106T153000Z.
    static func icsDate(_ d: Date) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return f.string(from: d)
    }

    /// Backslash, semicolon, comma and newline escaped for an iCalendar text value.
    static func icsEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: ";", with: "\\;")
            .replacingOccurrences(of: ",", with: "\\,")
            .replacingOccurrences(of: "\r\n", with: "\\n")
            .replacingOccurrences(of: "\n", with: "\\n")
    }

    /// A content line folded to 75 octets, continuation lines starting with a space (RFC 5545 3.1).
    static func fold(_ line: String) -> [String] {
        var out: [String] = []
        var current = ""
        var bytes = 0
        for ch in line {
            let n = String(ch).utf8.count
            let limit = out.isEmpty ? 75 : 74
            if bytes + n > limit {
                out.append(out.isEmpty ? current : " " + current)
                current = ""
                bytes = 0
            }
            current.append(ch)
            bytes += n
        }
        out.append(out.isEmpty ? current : " " + current)
        return out
    }
}
