import Foundation

/// "in 5 min", "2 hr ago" style formatting.
public struct RelativeTimeFormatter {
    public static func string(for date: Date, relativeTo now: Date = Date()) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f.localizedString(for: date, relativeTo: now)
    }
}

/// Compact countdown used in the menu bar: "5m", "1h 20m", "now".
public struct TimeUntilFormatter {
    public static func string(until date: Date, now: Date = Date()) -> String {
        let secs = Int(date.timeIntervalSince(now).rounded(.up))
        if secs <= 0 { return "now" }
        let mins = (secs + 59) / 60
        if mins < 60 { return "\(mins)m" }
        let h = mins / 60, m = mins % 60
        if h >= 24 { return "\(h / 24)d" }
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }
}

public struct NewEventDateRange: Equatable {
    public var start: Date
    public var end: Date
}

/// Builds the default start/end for a new event on a chosen day: next half hour, 30 min long.
public struct NewEventDateRangeBuilder {
    public static func build(day: Date, now: Date = Date(), calendar: Calendar = .current) -> NewEventDateRange {
        var comps = calendar.dateComponents([.year, .month, .day], from: day)
        let nowComps = calendar.dateComponents([.hour, .minute], from: now)
        let isToday = calendar.isDate(day, inSameDayAs: now)
        var hour = isToday ? (nowComps.hour ?? 9) : 9
        var minute = 0
        if isToday {
            minute = (nowComps.minute ?? 0) < 30 ? 30 : 0
            if minute == 0 { hour += 1 }
        }
        if hour > 23 { hour = 23; minute = 0 }
        comps.hour = hour; comps.minute = minute
        let start = calendar.date(from: comps) ?? day
        return NewEventDateRange(start: start, end: start.addingTimeInterval(30 * 60))
    }
}
