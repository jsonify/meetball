import Foundation

// Shared with the iPhone app (MeetballPhone), so it uses only Foundation.

/// The pure logic behind the new-meeting composer: what a proposed time clashes with, which free times fit, and the
/// Google Calendar link that carries a meeting to a calendar Meetball can't write to (a work calendar
/// seen only as a feed).
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

    /// Google Calendar's "new event" page filled in with the meeting, for a work Google calendar Meetball can only read
    /// (a feed in Apple Calendar). Opening it in the browser or the Google Calendar app saves the event straight to that
    /// calendar, invites included. `account` picks which signed-in Google account it opens as (`authuser`).
    public static func googleCalendarURL(title: String, start: Date, end: Date, guests: [String] = [],
                                         details: String? = nil, account: String? = nil) -> URL? {
        var c = URLComponents(string: "https://calendar.google.com/calendar/render")
        var items = [URLQueryItem(name: "action", value: "TEMPLATE"),
                     URLQueryItem(name: "text", value: title),
                     URLQueryItem(name: "dates", value: "\(icsDate(start))/\(icsDate(end))")]
        if !guests.isEmpty { items.append(URLQueryItem(name: "add", value: guests.joined(separator: ","))) }
        if let details, !details.isEmpty { items.append(URLQueryItem(name: "details", value: details)) }
        if let account, !account.isEmpty { items.append(URLQueryItem(name: "authuser", value: account)) }
        // Encoded by hand: queryItems leaves "&", "=" and "+" alone, which would split or change a title.
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=+?#")
        c?.percentEncodedQueryItems = items.map {
            URLQueryItem(name: $0.name, value: $0.value?.addingPercentEncoding(withAllowedCharacters: allowed))
        }
        return c?.url
    }

    /// A UTC timestamp as Google Calendar links (and iCalendar) write it: 20261106T153000Z.
    static func icsDate(_ d: Date) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return f.string(from: d)
    }
}
