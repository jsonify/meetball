import Foundation

/// A slice of an event on a single day (multi-day events produce several).
public struct CalendarEventDaySegment: Identifiable, Hashable {
    public struct SegmentID: Hashable { public let eventID: String; public let day: Date }
    public let event: CalendarEvent
    public let day: Date
    public let segmentStart: Date
    public let segmentEnd: Date
    public let startsOnThisDay: Bool
    public let endsOnThisDay: Bool
    public var continuesBefore: Bool { !startsOnThisDay }
    public var continuesAfter: Bool { !endsOnThisDay }
    public var id: SegmentID { SegmentID(eventID: event.uid, day: day) }
    public var bucketHour: Int { Calendar.app.component(.hour, from: segmentStart) }

    public func timeRangeText() -> String {
        if event.isAllDay { return "All day" }
        if continuesBefore && continuesAfter { return "All day" }
        if continuesBefore { return "until \(segmentEnd.shortTime)" }
        if continuesAfter { return "from \(segmentStart.shortTime)" }
        return "\(segmentStart.shortTime) – \(segmentEnd.shortTime)"
    }
}

/// An event bar spanning columns of one calendar week row.
public struct CalendarEventWeekSpan: Identifiable, Hashable {
    public struct SpanID: Hashable { public let eventID: String; public let weekStartDay: Date; public let lane: Int }
    public let event: CalendarEvent
    public let weekStartDay: Date
    public let startColumn: Int
    public let endColumn: Int
    public let lane: Int
    public let continuesBeforeWeek: Bool
    public let continuesAfterWeek: Bool
    public var id: SpanID { SpanID(eventID: event.uid, weekStartDay: weekStartDay, lane: lane) }
}

public struct CalendarVisibleRangeBuilder {
    /// Full weeks covering the month containing `anchor`.
    public static func build(anchor: Date, calendar: Calendar = .app) -> DateInterval {
        let monthStart = calendar.dateInterval(of: .month, for: anchor)!.start
        let monthEnd = calendar.dateInterval(of: .month, for: anchor)!.end
        let first = calendar.dateInterval(of: .weekOfYear, for: monthStart)!.start
        let lastDay = calendar.date(byAdding: .day, value: -1, to: monthEnd)!
        let last = calendar.dateInterval(of: .weekOfYear, for: lastDay)!.end
        return DateInterval(start: first, end: last)
    }
}

public struct CalendarDerivedEvents {
    public var segmentsByDay: [Date: [CalendarEventDaySegment]] = [:]
    public var weeks: [(weekStart: Date, spans: [CalendarEventWeekSpan], laneCount: Int)] = []
}

public struct CalendarDerivedEventsBuilder {
    public static func build(events: [CalendarEvent], range: DateInterval, calendar: Calendar = .app) -> CalendarDerivedEvents {
        var out = CalendarDerivedEvents()
        // Day segments
        for e in events {
            var endForDays = e.end
            if e.isAllDay || e.end > e.start { endForDays = e.end.addingTimeInterval(-1) }
            if endForDays < e.start { endForDays = e.start }
            var day = calendar.startOfDay(for: e.start)
            let lastDay = calendar.startOfDay(for: endForDays)
            while day <= lastDay {
                let next = calendar.date(byAdding: .day, value: 1, to: day)!
                let segStart = max(e.start, day), segEnd = min(e.end, next)
                if day >= range.start && day < range.end {
                    out.segmentsByDay[day, default: []].append(CalendarEventDaySegment(
                        event: e, day: day, segmentStart: segStart, segmentEnd: segEnd,
                        startsOnThisDay: calendar.isDate(e.start, inSameDayAs: day),
                        endsOnThisDay: endForDays < next))
                }
                day = next
            }
        }
        for k in out.segmentsByDay.keys {
            out.segmentsByDay[k]!.sort { ($0.event.isAllDay ? 0 : 1, $0.segmentStart) < ($1.event.isAllDay ? 0 : 1, $1.segmentStart) }
        }
        // Week spans with greedy lane packing (only multi-day / all-day events become bars)
        var weekStart = range.start
        while weekStart < range.end {
            let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart)!
            let bars = events.filter { $0.isBarEvent(calendar: calendar) && $0.start < weekEnd && $0.end > weekStart }
                .sorted { $0.start == $1.start ? $0.end > $1.end : $0.start < $1.start }
            var laneEnds: [Int] = []
            var spans: [CalendarEventWeekSpan] = []
            for e in bars {
                let s = max(0, dayIndex(e.start, weekStart, calendar))
                let lastInstant = e.end > e.start ? e.end.addingTimeInterval(-1) : e.end
                let en = min(6, dayIndex(lastInstant, weekStart, calendar))
                var lane = laneEnds.firstIndex(where: { $0 < s }) ?? laneEnds.count
                if lane == laneEnds.count { laneEnds.append(en) } else { laneEnds[lane] = en }
                lane = min(lane, laneEnds.count - 1)
                spans.append(CalendarEventWeekSpan(event: e, weekStartDay: weekStart, startColumn: s, endColumn: max(s, en), lane: lane,
                                                   continuesBeforeWeek: e.start < weekStart, continuesAfterWeek: e.end > weekEnd))
            }
            out.weeks.append((weekStart, spans, laneEnds.count))
            weekStart = weekEnd
        }
        return out
    }

    private static func dayIndex(_ d: Date, _ weekStart: Date, _ cal: Calendar) -> Int {
        cal.dateComponents([.day], from: weekStart, to: cal.startOfDay(for: d)).day ?? 0
    }
}
