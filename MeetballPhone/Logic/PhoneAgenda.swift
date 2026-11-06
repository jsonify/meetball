import Foundation

/// A meeting that moved, got a new link or was cancelled, shown as a card on Today until it's dismissed (the iPhone
/// version of the Mac's change card), so a change can't slip by between glances at the phone.
struct ChangeCard: Codable, Equatable, Identifiable {
    enum Kind: String, Codable { case cancelled, moved, link }

    var id = UUID()
    var kind: Kind
    var eventTitle: String
    var detail: String
    /// When the meeting starts (or started, for a cancellation); cards drop off a day after.
    var start: Date
    var at: Date

    init(kind: Kind, eventTitle: String, detail: String, start: Date, at: Date) {
        self.kind = kind
        self.eventTitle = eventTitle
        self.detail = detail
        self.start = start
        self.at = at
    }

    init(_ change: MeetingChange, now: Date) {
        let kind: Kind
        switch change.kind {
        case .cancelled: kind = .cancelled
        case .rescheduled: kind = .moved
        case .linkChanged: kind = .link
        }
        self.init(kind: kind, eventTitle: change.event.title, detail: MeetingChangeText.body(change, now: now),
                  start: change.event.start, at: now)
    }

    var caption: String {
        switch kind {
        case .cancelled: return "Canceled"
        case .moved: return "Moved"
        case .link: return "New link"
        }
    }

    /// Newest first, one card per meeting (a meeting that changes again replaces its card), at most `limit`, and none
    /// for meetings more than a day past.
    static func merged(_ old: [ChangeCard], _ new: [ChangeCard], now: Date, limit: Int = 8) -> [ChangeCard] {
        let titles = Set(new.map { MeetingChangeDetector.normalizedTitle($0.eventTitle) })
        let kept = old.filter { !titles.contains(MeetingChangeDetector.normalizedTitle($0.eventTitle)) }
        return Array((new + kept).filter { $0.start.addingTimeInterval(86400) > now }.prefix(limit))
    }
}

/// Confetti for a cancelled meeting, waiting to be shown when Meetball is next on screen.
struct Celebration: Codable, Equatable, Identifiable {
    var id = UUID()
    var title: String
    /// Other meetings cancelled in the same sync.
    var extra: Int

    init(title: String, extra: Int) {
        self.title = title
        self.extra = extra
    }

    /// For the first cancellation in `changes`, if any.
    init?(_ changes: [MeetingChange]) {
        let cancelled = changes.filter(\.isCancellation)
        guard let first = cancelled.first else { return nil }
        self.init(title: first.event.title, extra: cancelled.count - 1)
    }
}

/// What the Today, Week and Month screens show, worked out from the loaded events.
enum PhoneAgenda {
    /// A meeting on two calendars (a work calendar mirrored into iCloud, say) is kept once.
    static func dedupe(_ events: [CalendarEvent]) -> [CalendarEvent] {
        var seen = Set<String>()
        return events
            .sorted { ($0.start, $0.end, $0.calendarKey) < ($1.start, $1.end, $1.calendarKey) }
            .filter { e in
                let key = "\(Int(e.start.timeIntervalSince1970))|\(Int(e.end.timeIntervalSince1970))|\(e.isAllDay)|"
                    + MeetingChangeDetector.normalizedTitle(e.title)
                return seen.insert(key).inserted
            }
    }

    /// The days of the month containing `anchor`, in rows of seven (whole weeks, so it starts and ends with days of the
    /// neighbouring months).
    static func monthWeeks(anchor: Date, calendar: Calendar = .app) -> [[Date]] {
        let range = CalendarVisibleRangeBuilder.build(anchor: anchor, calendar: calendar)
        var days: [Date] = []
        var d = range.start
        while d < range.end {
            days.append(d)
            guard let next = calendar.date(byAdding: .day, value: 1, to: d) else { break }
            d = next
        }
        return stride(from: 0, to: days.count, by: 7).map { Array(days[$0..<min($0 + 7, days.count)]) }
    }

    /// Short weekday names starting from the calendar's first weekday ("M T W T F S S").
    static func weekdaySymbols(calendar: Calendar = .app) -> [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return (0..<7).map { symbols[(first + $0) % 7] }
    }

    /// "Today", "Tomorrow", or "Wednesday, Nov 12".
    static func dayTitle(_ day: Date, now: Date = Date(), calendar: Calendar = .app) -> String {
        if calendar.isDate(day, inSameDayAs: now) { return "Today" }
        if let t = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(day, inSameDayAs: t) { return "Tomorrow" }
        return day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }

    /// The meeting-load meter's fill for `hours` of meetings: 0 to `segments` lit segments, full at `fullDay` hours.
    static func loadSegments(_ hours: Double, segments: Int = 8, fullDay: Double = 8) -> Int {
        guard hours > 0 else { return 0 }
        return min(segments, max(1, Int((hours / fullDay * Double(segments)).rounded())))
    }

    /// The shake readout's numbers for the rest of today.
    struct DayStats: Equatable {
        /// Timed meetings today that haven't ended.
        var left: Int
        /// Hours in meetings today (overlaps counted once).
        var hours: Double
        /// The first stretch of at least `minGap` with no meeting, from now until `dayEndHour` (nil when there is none).
        var freeGap: DateInterval?

        /// "2:30" for 2.5 hours, for the seven-segment LCD.
        var hoursDigits: String {
            let mins = Int((hours * 60).rounded())
            return String(format: "%d:%02d", mins / 60, mins % 60)
        }

        /// A line about the day, from how booked it is.
        var verdict: String {
            if left == 0 { return hours == 0 ? "Not a single meeting. Legendary." : "Meetings done. The rest is yours." }
            if hours >= 6 { return "Stacked. Drink water between calls." }
            if hours >= 3.5 { return "Busy, but there's room to breathe." }
            return "Light day. Go make something."
        }
    }

    static func dayStats(_ events: [CalendarEvent], now: Date, dayEndHour: Int = 18, minGap: TimeInterval = 15 * 60,
                         calendar: Calendar = .app) -> DayStats {
        let start = calendar.startOfDay(for: now)
        let next = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86400)
        let timed = events.filter { !$0.isDeclined && !$0.isBarEvent(calendar: calendar) && $0.start < next && $0.end > start }
        let left = timed.filter { $0.end > now }.count
        let hours = MeetingLoadBuilder.build(events: timed, from: now, days: 1, calendar: calendar).first?.hours ?? 0

        var dayEnd = calendar.date(bySettingHour: dayEndHour, minute: 0, second: 0, of: now) ?? next
        if dayEnd <= now { dayEnd = next }
        var cursor = now
        var gap: DateInterval?
        for e in timed.filter({ $0.end > now }).sorted(by: { $0.start < $1.start }) {
            if e.start.timeIntervalSince(cursor) >= minGap {
                gap = DateInterval(start: cursor, end: min(e.start, dayEnd))
                break
            }
            cursor = max(cursor, e.end)
            if cursor >= dayEnd { break }
        }
        if gap == nil, cursor < dayEnd, dayEnd.timeIntervalSince(cursor) >= minGap {
            gap = DateInterval(start: cursor, end: dayEnd)
        }
        if let g = gap, g.duration < minGap { gap = nil }
        return DayStats(left: left, hours: hours, freeGap: gap)
    }

    /// The meeting the countdown moment is for: the next one with a join link that hasn't started.
    static func nextJoinable(_ upcoming: [CalendarEvent], now: Date) -> CalendarEvent? {
        upcoming.filter { $0.meetURL != nil && $0.start > now }.min { $0.start < $1.start }
    }
}
