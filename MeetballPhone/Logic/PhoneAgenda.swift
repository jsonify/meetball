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
}
