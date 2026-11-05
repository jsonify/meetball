import Foundation

/// Stretches of time worth calling out across the menu calendar (#28): being away, or on call.
public enum EventCallout: String, Hashable, CaseIterable {
    case away, onCall

    public var symbol: String { self == .away ? "airplane" : "phone.badge.waveform" }
    public var label: String { self == .away ? "Away" : "On call" }

    static let awayWords = ["vacation", "holiday", "pto", "ooo", "out of office", "out-of-office", "leave", "time off", "day off",
                            "annual leave", "sabbatical", "away", "off sick", "sick day"]
    static let onCallWords = ["on-call", "on call", "oncall", "pager", "pagerduty", "standby", "support rotation"]

    /// From the title, matching whole words: "Vacation — Hawaii", "OOO", "On-call (primary)".
    public static func detect(_ title: String) -> EventCallout? {
        let t = " " + title.lowercased().map { $0.isLetter || $0.isNumber || $0 == "-" ? $0 : " " } + " "
        func has(_ words: [String]) -> Bool {
            words.contains { w in t.contains(" " + w.map { $0.isLetter || $0.isNumber || $0 == "-" ? $0 : " " } + " ") }
        }
        if has(onCallWords) { return .onCall }
        if has(awayWords) { return .away }
        return nil
    }
}

/// One stretch of a multi-day event across a week row of the mini month.
public struct MiniMonthRibbon: Identifiable, Hashable {
    public let event: CalendarEvent
    public let weekStart: Date
    public let startColumn: Int
    public let endColumn: Int
    public let lane: Int
    public let continuesBefore: Bool
    public let continuesAfter: Bool
    public let callout: EventCallout?
    public var id: String { "\(event.uid)|\(weekStart.timeIntervalSince1970)" }
}

public enum MiniMonthRibbonBuilder {
    /// Ribbon lanes shown per week; more overlapping stretches fall back to the day's dots.
    public static let maxLanes = 2

    /// Days `e` covers (an all-day event ending at midnight doesn't cover the next day).
    static func dayCount(_ e: CalendarEvent, calendar: Calendar) -> Int {
        let last = e.end > e.start ? e.end.addingTimeInterval(-1) : e.start
        return (calendar.dateComponents([.day], from: calendar.startOfDay(for: e.start), to: calendar.startOfDay(for: last)).day ?? 0) + 1
    }

    /// Spans two or more days (all day, or a day or longer), or is a one-day all-day away/on-call event.
    /// A late meeting that runs past midnight stays a dot.
    public static func isRibbon(_ e: CalendarEvent, calendar: Calendar = .app) -> Bool {
        guard !e.isDeclined else { return false }
        let days = dayCount(e, calendar: calendar)
        if days >= 2 && (e.isAllDay || e.end.timeIntervalSince(e.start) >= 86400 - 1) { return true }
        return e.isAllDay && EventCallout.detect(e.title) != nil
    }

    /// Ribbons by week start for the weeks in `range`. Away and on-call stretches take the top lanes.
    public static func build(events: [CalendarEvent], range: DateInterval, calendar: Calendar = .app) -> [Date: [MiniMonthRibbon]] {
        let ribbons = events.filter { isRibbon($0, calendar: calendar) }
            .sorted { a, b in
                let ca = EventCallout.detect(a.title) != nil, cb = EventCallout.detect(b.title) != nil
                if ca != cb { return ca }
                if a.start != b.start { return a.start < b.start }
                return a.end > b.end
            }
        var out: [Date: [MiniMonthRibbon]] = [:]
        var weekStart = range.start
        while weekStart < range.end {
            guard let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart) else { break }
            var lanes: [[ClosedRange<Int>]] = []
            var row: [MiniMonthRibbon] = []
            for e in ribbons where e.start < weekEnd && e.end > weekStart {
                let last = e.end > e.start ? e.end.addingTimeInterval(-1) : e.start
                let s = max(0, column(e.start, weekStart, calendar)), en = min(6, column(last, weekStart, calendar))
                guard s <= en else { continue }
                let span = s...en
                guard let lane = lanes.firstIndex(where: { !$0.contains { $0.overlaps(span) } }) ?? (lanes.count < maxLanes ? lanes.count : nil)
                else { continue }
                if lane == lanes.count { lanes.append([]) }
                lanes[lane].append(span)
                row.append(MiniMonthRibbon(event: e, weekStart: weekStart, startColumn: s, endColumn: en, lane: lane,
                                           continuesBefore: e.start < weekStart, continuesAfter: last >= weekEnd,
                                           callout: EventCallout.detect(e.title)))
            }
            if !row.isEmpty { out[weekStart] = row }
            weekStart = weekEnd
        }
        return out
    }

    /// Uids of the events drawn as ribbons in `ribbons`, so their days don't also get dots.
    public static func uids(_ ribbons: [Date: [MiniMonthRibbon]]) -> Set<String> {
        Set(ribbons.values.flatMap { $0.map(\.event.uid) })
    }

    private static func column(_ d: Date, _ weekStart: Date, _ cal: Calendar) -> Int {
        cal.dateComponents([.day], from: weekStart, to: cal.startOfDay(for: d)).day ?? 0
    }
}
