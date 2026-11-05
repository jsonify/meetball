import Foundation

/// A timed event segment positioned in a day column of the time grid.
public struct TimeGridPlacement: Identifiable, Hashable {
    public let segment: CalendarEventDaySegment
    /// Sub-column within its overlap cluster, and the cluster's column count.
    public let column: Int
    public let columnCount: Int
    public var id: CalendarEventDaySegment.SegmentID { segment.id }
}

/// An all-day / multi-day bar across the displayed day columns.
public struct TimeGridAllDayBar: Identifiable, Hashable {
    public let event: CalendarEvent
    public let startIndex: Int
    public let endIndex: Int
    public let lane: Int
    public let continuesBefore: Bool
    public let continuesAfter: Bool
    public var id: String { "\(event.uid)|\(lane)" }
}

public enum TimeGridLayoutBuilder {
    /// Column-packs overlapping segments: each cluster of transitively overlapping events shares a column count,
    /// and each event takes the first free column. Very short events are treated as `minDuration` long so they stay visible.
    public static func place(_ segments: [CalendarEventDaySegment], minDuration: TimeInterval = 15 * 60) -> [TimeGridPlacement] {
        let sorted = segments.sorted {
            $0.segmentStart != $1.segmentStart ? $0.segmentStart < $1.segmentStart : $0.segmentEnd > $1.segmentEnd
        }
        var result: [TimeGridPlacement] = []
        var cluster: [(CalendarEventDaySegment, Int)] = []
        var columnEnds: [Date] = []
        var clusterEnd = Date.distantPast

        func flush() {
            let count = max(1, columnEnds.count)
            result += cluster.map { TimeGridPlacement(segment: $0.0, column: $0.1, columnCount: count) }
            cluster = []; columnEnds = []
        }

        for s in sorted {
            let end = max(s.segmentEnd, s.segmentStart.addingTimeInterval(minDuration))
            if !cluster.isEmpty && s.segmentStart >= clusterEnd { flush() }
            let col = columnEnds.firstIndex(where: { $0 <= s.segmentStart }) ?? columnEnds.count
            if col == columnEnds.count { columnEnds.append(end) } else { columnEnds[col] = end }
            cluster.append((s, col))
            clusterEnd = cluster.count == 1 ? end : max(clusterEnd, end)
        }
        flush()
        return result
    }

    /// Maps the month layout's week spans (`CalendarDerivedEventsBuilder`) onto the displayed columns.
    /// `firstDayOffset` is the displayed first day's column within that week (0 for week view, 0–6 for day view).
    public static func allDayBars(spans: [CalendarEventWeekSpan], firstDayOffset: Int, dayCount: Int) -> [TimeGridAllDayBar] {
        let lastIndex = dayCount - 1
        let visible = spans.compactMap { span -> (CalendarEventWeekSpan, Int, Int)? in
            let s = span.startColumn - firstDayOffset, e = span.endColumn - firstDayOffset
            guard e >= 0, s <= lastIndex else { return nil }
            return (span, max(0, s), min(lastIndex, e))
        }
        // Compact lanes so a day view doesn't leave gaps for bars on other days.
        let lanes = Array(Set(visible.map { $0.0.lane })).sorted()
        let laneIndex = Dictionary(uniqueKeysWithValues: lanes.enumerated().map { ($1, $0) })
        return visible.map { span, s, e in
            TimeGridAllDayBar(event: span.event, startIndex: s, endIndex: e, lane: laneIndex[span.lane] ?? 0,
                              continuesBefore: span.continuesBeforeWeek || span.startColumn - firstDayOffset < 0,
                              continuesAfter: span.continuesAfterWeek || span.endColumn - firstDayOffset > lastIndex)
        }.sorted { ($0.lane, $0.startIndex) < ($1.lane, $1.startIndex) }
    }

    /// Minutes from the start of `day` to `date`, clamped to the day.
    public static func minutes(of date: Date, in day: Date, calendar: Calendar = .current) -> Double {
        let start = calendar.startOfDay(for: day)
        return min(max(date.timeIntervalSince(start) / 60, 0), 24 * 60)
    }

    /// Time at a vertical offset in a day column, snapped down to `snapMinutes`.
    public static func date(atY y: Double, hourHeight: Double, day: Date, snapMinutes: Int = 15, calendar: Calendar = .current) -> Date {
        let raw = min(max(y / hourHeight * 60, 0), 24 * 60)
        let snapped = Int(raw / Double(snapMinutes)) * snapMinutes
        return calendar.date(byAdding: .minute, value: snapped, to: calendar.startOfDay(for: day)) ?? day
    }

    /// Start/end for a drag between two offsets; at least one snap interval long.
    public static func dragRange(fromY a: Double, toY b: Double, hourHeight: Double, day: Date, snapMinutes: Int = 15,
                                 calendar: Calendar = .current) -> NewEventDateRange {
        let t1 = date(atY: min(a, b), hourHeight: hourHeight, day: day, snapMinutes: snapMinutes, calendar: calendar)
        var t2 = date(atY: max(a, b), hourHeight: hourHeight, day: day, snapMinutes: snapMinutes, calendar: calendar)
        if let next = calendar.date(byAdding: .minute, value: snapMinutes, to: t2), max(a, b) > min(a, b) { t2 = next }
        if t2 <= t1 { t2 = t1.addingTimeInterval(Double(snapMinutes) * 60) }
        return NewEventDateRange(start: t1, end: t2)
    }
}

/// One day section of the menu bar agenda.
public struct AgendaDayGroup: Identifiable, Equatable {
    public let day: Date
    public let allDay: [CalendarEvent]
    public let timed: [CalendarEvent]
    /// Index into `timed` before which the "now" line is drawn (today only).
    public let nowLineIndex: Int?
    public var id: Date { day }
}

public enum MenuAgendaBuilder {
    /// The meeting featured at the top of the popover: in progress, else the next one starting within `horizon`.
    public static func hero(_ events: [CalendarEvent], now: Date, horizon: TimeInterval = 12 * 3600) -> CalendarEvent? {
        let timed = events.filter { !$0.isAllDay && !$0.isDeclined && $0.end > now }
        if let current = timed.filter({ $0.start <= now }).max(by: { $0.start < $1.start }) { return current }
        return timed.filter { $0.start.timeIntervalSince(now) <= horizon }.min(by: { $0.start < $1.start })
    }

    /// Groups events by day.
    /// - With `scopedDay`: every event on that day (past ones included).
    /// - Otherwise: events that haven't ended, from today through `days` days ahead, capped at `limit` timed events.
    public static func build(events: [CalendarEvent], now: Date, scopedDay: Date? = nil, days: Int = 7, limit: Int = 20,
                             excluding excluded: String? = nil, calendar: Calendar = .current) -> [AgendaDayGroup] {
        let first = calendar.startOfDay(for: scopedDay ?? now)
        let dayCount = scopedDay == nil ? days : 1
        var remaining = limit
        var groups: [AgendaDayGroup] = []
        for i in 0..<dayCount {
            guard let day = calendar.date(byAdding: .day, value: i, to: first),
                  let next = calendar.date(byAdding: .day, value: 1, to: day) else { continue }
            let onDay = events.filter { $0.start < next && $0.end > day && $0.uid != excluded }
            var allDay = onDay.filter { $0.isBarEvent(calendar: calendar) }
            var timed = onDay.filter { !$0.isBarEvent(calendar: calendar) }.sorted { $0.start < $1.start }
            if scopedDay == nil {
                timed = timed.filter { $0.end > now }
                allDay = allDay.filter { $0.end > now }
                timed = Array(timed.prefix(max(0, remaining)))
                remaining -= timed.count
            }
            guard !allDay.isEmpty || !timed.isEmpty else { continue }
            let nowIndex: Int? = calendar.isDate(day, inSameDayAs: now) ? timed.filter { $0.start <= now }.count : nil
            groups.append(AgendaDayGroup(day: day, allDay: allDay, timed: timed, nowLineIndex: nowIndex))
            if scopedDay == nil && remaining <= 0 { break }
        }
        return groups
    }

    /// Colours of up to three events per day, for the mini month's dots.
    public static func dots(events: [CalendarEvent], range: DateInterval, calendar: Calendar = .current) -> [Date: [String]] {
        let derived = CalendarDerivedEventsBuilder.build(events: events.filter { !$0.isDeclined }, range: range, calendar: calendar)
        return derived.segmentsByDay.mapValues { segs in
            var seen: [String] = []
            for s in segs where !seen.contains(s.event.colorHex) { seen.append(s.event.colorHex) }
            return Array(seen.prefix(3))
        }
    }
}

/// Hours spent in meetings on one day.
public struct DayMeetingLoad: Identifiable, Equatable {
    public let day: Date
    public let hours: Double
    public let count: Int
    public var id: Date { day }
}

public enum MeetingLoadBuilder {
    /// Time in meetings per day for `days` days from `start`: timed, non-declined events, clipped to the day,
    /// with overlapping meetings counted once.
    public static func build(events: [CalendarEvent], from start: Date, days: Int = 7, calendar: Calendar = .current) -> [DayMeetingLoad] {
        let first = calendar.startOfDay(for: start)
        return (0..<max(0, days)).compactMap { i in
            guard let day = calendar.date(byAdding: .day, value: i, to: first),
                  let next = calendar.date(byAdding: .day, value: 1, to: day) else { return nil }
            let onDay = events.filter { !$0.isDeclined && !$0.isBarEvent(calendar: calendar) && $0.start < next && $0.end > day }
            let intervals = onDay.map { (max($0.start, day), min($0.end, next)) }.sorted { $0.0 < $1.0 }
            var total: TimeInterval = 0
            var current: (Date, Date)?
            for iv in intervals {
                if let c = current, iv.0 <= c.1 { current = (c.0, max(c.1, iv.1)) }
                else { if let c = current { total += c.1.timeIntervalSince(c.0) }; current = iv }
            }
            if let c = current { total += c.1.timeIntervalSince(c.0) }
            return DayMeetingLoad(day: day, hours: total / 3600, count: onDay.count)
        }
    }
}
