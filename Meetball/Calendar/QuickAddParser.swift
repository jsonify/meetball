import Foundation

/// What a quick-add line like "Lunch with Anna tomorrow 12:30-1:30 +meet anna@example.com" describes.
public struct QuickAddResult: Equatable {
    public var title: String
    public var start: Date
    public var end: Date
    public var attendees: [String]
    public var addMeet: Bool
    /// The line named a day ("tomorrow", "fri", "dec 3").
    public var hasDate: Bool
    /// The line named a time ("3pm", "12:30-1:30", "noon").
    public var hasTime: Bool
}

/// Parses one line of natural language into an event. It understands, anywhere in the line:
/// - days: today, tonight, tomorrow, a weekday ("fri", "next monday"), "in 3 days", "in 2 weeks", "dec 3", "3 december",
///   "12/3" (month and day in the order the locale writes them)
/// - times: "3pm", "3:30 pm", "15:00", "noon", "midnight", "at 9"; a bare hour from 1 to 7 is taken as the afternoon
/// - ranges: "12:30-1:30", "3-4pm", "from 3 to 4:30pm", "9am–10am"
/// - durations: "for 45 min", "for 1.5 hours", "for 2h"
/// - attendees: any email address; "+meet" adds a Google Meet link
/// What's left, minus joining words at either end, is the title. With no time it starts at the next half hour (or
/// 9:00 on a later day), 30 minutes long, like the New Event form.
public enum QuickAddParser {
    public static let defaultDuration: TimeInterval = 30 * 60

    public static func parse(_ text: String, now: Date = Date(), calendar: Calendar = .app, locale: Locale = .current) -> QuickAddResult {
        var s = " " + text + " "
        var attendees: [String] = []
        var addMeet = false

        // +meet
        if take(#"(?i)\s\+(?:g?meet|video)\b"#, from: &s) != nil { addMeet = true }

        // Emails
        while let m = take(#"(?i)(?:\swith)?\s([A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,})(?=[\s,;]|$)"#, from: &s) {
            let e = m[1]
            if !attendees.contains(e) { attendees.append(e) }
        }

        // Day
        var day: Date?
        let today = calendar.startOfDay(for: now)
        var evening = false
        if take(#"(?i)\s(?:on\s)?(?:today|tod)\b"#, from: &s) != nil { day = today }
        else if take(#"(?i)\s(?:on\s)?(?:tonight)\b"#, from: &s) != nil { day = today; evening = true }
        else if take(#"(?i)\s(?:on\s)?(?:tomorrow|tmrw|tmr)\b"#, from: &s) != nil { day = calendar.date(byAdding: .day, value: 1, to: today) }
        else if let m = take(#"(?i)\sin\s(\d{1,3})\s(day|days|week|weeks)\b"#, from: &s), let n = Int(m[1]) {
            day = calendar.date(byAdding: m[2].lowercased().hasPrefix("week") ? .weekOfYear : .day, value: n, to: today)
        } else if let m = take(#"(?i)\s(?:on\s)?(next\s)?("# + weekdayPattern + #")\b\.?"#, from: &s),
                  let wd = weekday(m[2]) {
            day = nextWeekday(wd, after: today, includeToday: m[1].isEmpty, calendar: calendar)
        } else if let m = take(#"(?i)\s(?:on\s)?("# + monthPattern + #")\.?\s(\d{1,2})(?:st|nd|rd|th)?\b"#, from: &s),
                  let mo = month(m[1]), let d = Int(m[2]) {
            day = upcoming(month: mo, day: d, from: today, calendar: calendar)
        } else if let m = take(#"(?i)\s(?:on\s)?(?:the\s)?(\d{1,2})(?:st|nd|rd|th)?\s(?:of\s)?("# + monthPattern + #")\b\.?"#, from: &s),
                  let d = Int(m[1]), let mo = month(m[2]) {
            day = upcoming(month: mo, day: d, from: today, calendar: calendar)
        } else if let m = take(#"\s(?:on\s)?(\d{1,2})/(\d{1,2})(?=\s)"#, from: &s), let a = Int(m[1]), let b = Int(m[2]) {
            let (mo, d) = monthFirst(locale) ? (a, b) : (b, a)
            day = upcoming(month: mo, day: d, from: today, calendar: calendar)
        }

        // Time range, then a single time, then a duration.
        var startTime: (h: Int, m: Int)?
        var endTime: (h: Int, m: Int)?
        let t = #"(\d{1,2})(?::(\d{2}))?\s?(am|pm)?"#
        if let m = take(#"(?i)\s(?:from\s|at\s)?"# + t + #"\s?(?:-|–|—|to|until|till)\s?"# + t + #"(?=[\s,.;]|$)"#, from: &s) {
            let endMer = m[6].isEmpty ? nil : m[6]
            let startMer = m[3].isEmpty ? nil : m[3]
            if let e = clock(m[4], m[5], endMer, bareIsAfternoon: true) {
                endTime = e
                // "3-4pm": the start shares the end's half of the day when that keeps it before the end.
                let inherit = startMer ?? endMer
                var st = clock(m[1], m[2], inherit, bareIsAfternoon: true)
                if startMer == nil, let s0 = st, minutes(s0) >= minutes(e), let alt = clock(m[1], m[2], nil, bareIsAfternoon: false),
                   minutes(alt) < minutes(e) { st = alt }
                startTime = st
            }
        } else if take(#"(?i)\s(?:at\s)?noon\b"#, from: &s) != nil { startTime = (12, 0) }
        else if take(#"(?i)\s(?:at\s)?midnight\b"#, from: &s) != nil { startTime = (0, 0) }
        else if let m = take(#"(?i)\s(?:at\s|@\s?)?(\d{1,2}):(\d{2})\s?(am|pm)?(?=[\s,.;]|$)"#, from: &s) {
            startTime = clock(m[1], m[2], m[3].isEmpty ? nil : m[3], bareIsAfternoon: true)
        } else if let m = take(#"(?i)\s(?:at\s|@\s?)?(\d{1,2})\s?(am|pm)(?=[\s,.;]|$)"#, from: &s) {
            startTime = clock(m[1], "", m[2], bareIsAfternoon: true)
        } else if let m = take(#"(?i)\s(?:at|@)\s?(\d{1,2})(?=[\s,.;]|$)"#, from: &s) {
            startTime = clock(m[1], "", nil, bareIsAfternoon: true)
        }
        var duration: TimeInterval?
        if let m = take(#"(?i)\s(?:for\s)?(\d+(?:\.\d+)?)\s?(minutes|minute|mins|min|m|hours|hour|hrs|hr|h)\b"#, from: &s),
           let n = Double(m[1]) {
            duration = n * (m[2].lowercased().hasPrefix("m") ? 60 : 3600)
        }

        if evening && startTime == nil { startTime = (19, 0) }
        let hasDate = day != nil
        let hasTime = startTime != nil
        let baseDay = day ?? today
        var start: Date
        if let st = startTime {
            start = calendar.date(bySettingHour: st.h, minute: st.m, second: 0, of: baseDay) ?? baseDay
            // A time already past today, with no day named, means tomorrow.
            if !hasDate && start <= now { start = calendar.date(byAdding: .day, value: 1, to: start) ?? start }
        } else {
            start = NewEventDateRangeBuilder.build(day: baseDay, now: now, calendar: calendar).start
        }
        var end = start.addingTimeInterval(duration ?? defaultDuration)
        if let et = endTime, let e = calendar.date(bySettingHour: et.h, minute: et.m, second: 0, of: start) {
            end = e > start ? e : (calendar.date(byAdding: .day, value: 1, to: e) ?? e)
        }

        return QuickAddResult(title: cleanTitle(s), start: start, end: end, attendees: attendees, addMeet: addMeet,
                              hasDate: hasDate, hasTime: hasTime)
    }

    // MARK: Pieces

    static let weekdayPattern = "sunday|sun|monday|mon|tuesday|tues|tue|wednesday|wed|thursday|thurs|thur|thu|friday|fri|saturday|sat"
    static let monthPattern = "january|jan|february|feb|march|mar|april|apr|may|june|jun|july|jul|august|aug|september|sept|sep|october|oct|november|nov|december|dec"

    /// 1 = Sunday … 7 = Saturday.
    static func weekday(_ s: String) -> Int? {
        let order = ["sun", "mon", "tue", "wed", "thu", "fri", "sat"]
        return order.firstIndex(of: String(s.lowercased().prefix(3))).map { $0 + 1 }
    }

    static func month(_ s: String) -> Int? {
        let order = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]
        return order.firstIndex(of: String(s.lowercased().prefix(3))).map { $0 + 1 }
    }

    static func nextWeekday(_ wd: Int, after today: Date, includeToday: Bool, calendar: Calendar) -> Date? {
        let current = calendar.component(.weekday, from: today)
        var delta = (wd - current + 7) % 7
        if delta == 0 && !includeToday { delta = 7 }
        return calendar.date(byAdding: .day, value: delta, to: today)
    }

    /// This year's date, or next year's once it has passed.
    static func upcoming(month: Int, day: Int, from today: Date, calendar: Calendar) -> Date? {
        guard (1...12).contains(month), (1...31).contains(day) else { return nil }
        let year = calendar.component(.year, from: today)
        guard let d = calendar.date(from: DateComponents(year: year, month: month, day: day)),
              calendar.component(.day, from: d) == day else { return nil }
        return d < today ? calendar.date(byAdding: .year, value: 1, to: d) : d
    }

    static func monthFirst(_ locale: Locale) -> Bool {
        let f = DateFormatter.dateFormat(fromTemplate: "Md", options: 0, locale: locale) ?? "M/d"
        guard let m = f.firstIndex(of: "M"), let d = f.firstIndex(of: "d") else { return true }
        return m < d
    }

    /// Hours and minutes from "3", "30", "pm". With no am/pm, 1–7 is the afternoon when `bareIsAfternoon`.
    static func clock(_ hour: String, _ minute: String, _ meridiem: String?, bareIsAfternoon: Bool) -> (h: Int, m: Int)? {
        guard var h = Int(hour) else { return nil }
        let m = Int(minute) ?? 0
        guard (0...59).contains(m) else { return nil }
        if let mer = meridiem?.lowercased() {
            guard (1...12).contains(h) else { return nil }
            let pm = mer.hasPrefix("p")
            if h == 12 { h = pm ? 12 : 0 } else if pm { h += 12 }
        } else {
            guard (0...23).contains(h) else { return nil }
            if bareIsAfternoon && (1...7).contains(h) { h += 12 }
        }
        return (h, m)
    }

    static func minutes(_ t: (h: Int, m: Int)) -> Int { t.h * 60 + t.m }

    /// Removes the first match of `pattern` from `s` (leaving a space) and returns its capture groups (0 = whole match;
    /// a group that didn't take part is "").
    static func take(_ pattern: String, from s: inout String) -> [String]? {
        guard let re = try? NSRegularExpression(pattern: pattern),
              let match = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
              let whole = Range(match.range, in: s) else { return nil }
        let groups = (0..<match.numberOfRanges).map { i -> String in
            Range(match.range(at: i), in: s).map { String(s[$0]) } ?? ""
        }
        s.replaceSubrange(whole, with: " ")
        return groups
    }

    /// Collapses spaces and drops joining words and punctuation left at either end ("Lunch with" → "Lunch").
    static func cleanTitle(_ s: String) -> String {
        var words = s.split(whereSeparator: \.isWhitespace).map(String.init)
        let joiners: Set<String> = ["with", "at", "on", "from", "for", "-", "–", ",", "@", "+"]
        func bare(_ w: String) -> String { w.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ",;:")) }
        while let last = words.last, joiners.contains(bare(last)) || bare(last).isEmpty { words.removeLast() }
        while let first = words.first, joiners.contains(bare(first)) || bare(first).isEmpty { words.removeFirst() }
        var title = words.joined(separator: " ")
        while let c = title.last, ",;:".contains(c) { title.removeLast() }
        return title
    }
}
