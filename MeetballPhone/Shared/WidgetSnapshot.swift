import Foundation

// Compiled into both the app and the widget extension (MeetballWidgets), so it uses only Foundation.

/// One meeting as the widgets and the Live Activity see it.
struct WidgetMeeting: Codable, Equatable, Hashable {
    var id: String
    var title: String
    var start: Date
    var end: Date
    var colorHex: String
    var joinURL: URL?
}

/// The next two days of meetings, written by the app to the shared App Group after each refresh and read by the widgets,
/// which can't read the calendar themselves without asking for access again.
struct WidgetSnapshot: Codable, Equatable {
    var meetings: [WidgetMeeting]
    var savedAt: Date

    static let appGroup = "group.app.meetball.MeetballPhone"
    static let key = "widget.snapshot"
    static var shared: UserDefaults? { UserDefaults(suiteName: appGroup) }

    static func load(from defaults: UserDefaults? = shared) -> WidgetSnapshot? {
        guard let data = defaults?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    /// Saves it; returns whether the meetings differ from what was saved (so widgets only reload when they need to).
    @discardableResult
    func save(to defaults: UserDefaults? = shared) -> Bool {
        let changed = Self.load(from: defaults)?.meetings != meetings
        if let data = try? JSONEncoder().encode(self) { defaults?.set(data, forKey: Self.key) }
        return changed
    }

    /// The meeting on now (the latest-started one), else the next one.
    func current(at now: Date) -> WidgetMeeting? {
        let live = meetings.filter { $0.start <= now && $0.end > now }.max { $0.start < $1.start }
        return live ?? meetings.filter { $0.start > now }.min { $0.start < $1.start }
    }

    /// The meeting a Join button should open: the latest-started one on now with a link, else the next with a link
    /// starting within `window` (the Mac's join shortcut rule).
    func joinable(at now: Date, window: TimeInterval = 10 * 60) -> WidgetMeeting? {
        let linked = meetings.filter { $0.joinURL != nil && $0.end > now }
        if let live = linked.filter({ $0.start <= now }).max(by: { $0.start < $1.start }) { return live }
        return linked.filter { $0.start > now && $0.start.timeIntervalSince(now) <= window }.min { $0.start < $1.start }
    }

    /// Meetings after `meeting` (or after `now` when nil) that haven't ended.
    func later(than meeting: WidgetMeeting?, now: Date, limit: Int) -> [WidgetMeeting] {
        Array(meetings.filter { $0.end > now && $0.id != meeting?.id && $0.start >= (meeting?.start ?? now) }
            .sorted { $0.start < $1.start }.prefix(limit))
    }

    /// Meetings that overlap `meeting` and haven't ended (a double-booking), soonest first.
    func overlapping(_ meeting: WidgetMeeting, at now: Date) -> [WidgetMeeting] {
        meetings.filter { $0.id != meeting.id && $0.end > now && $0.start < meeting.end && $0.end > meeting.start }
            .sorted { $0.start < $1.start }
    }

    /// The first meeting starting once `meeting` is over, on the same day: what comes after it.
    func following(_ meeting: WidgetMeeting, calendar: Calendar = .current) -> WidgetMeeting? {
        meetings.filter { $0.id != meeting.id && $0.start >= meeting.end && calendar.isDate($0.start, inSameDayAs: meeting.start) }
            .min { $0.start < $1.start }
    }

    /// How far along: the share of a meeting on now that has gone by, or of the last hour before one starts (empty an
    /// hour out, full at the start). Nil when it's more than an hour away.
    static func progress(of m: WidgetMeeting, at now: Date) -> Double? {
        if m.start <= now {
            let length = m.end.timeIntervalSince(m.start)
            return length > 0 ? min(1, max(0, now.timeIntervalSince(m.start) / length)) : 1
        }
        let until = m.start.timeIntervalSince(now)
        return until <= 3600 ? 1 - until / 3600 : nil
    }

    /// Meetings today that haven't ended.
    func remainingToday(at now: Date, calendar: Calendar = .current) -> Int {
        meetings.filter { $0.end > now && calendar.isDate($0.start, inSameDayAs: now) }.count
    }

    /// When the widgets should redraw: every minute from an hour before a meeting until it ends (the LCD counts in
    /// minutes), every 15 minutes otherwise, at most `limit` dates within `span`.
    func timelineDates(from now: Date, span: TimeInterval = 6 * 3600, limit: Int = 240) -> [Date] {
        var dates: [Date] = []
        var t = now
        let end = now.addingTimeInterval(span)
        while t < end && dates.count < limit {
            dates.append(t)
            let busy = meetings.contains { t >= $0.start.addingTimeInterval(-3600) && t < $0.end }
            let step: TimeInterval = busy ? 60 : 15 * 60
            var next = Date(timeIntervalSinceReferenceDate: (t.timeIntervalSinceReferenceDate / step).rounded(.down) * step + step)
            // Don't step over a meeting's start or end, or the hour-before mark.
            for m in meetings {
                for mark in [m.start.addingTimeInterval(-3600), m.start, m.end] where mark > t && mark < next { next = mark }
            }
            t = next
        }
        return dates
    }
}

/// What the MB-1 display reads on a widget, whatever is or isn't coming: a caption, seven-segment digits with their
/// unit, and a line of text. There is always something to show, so a widget is never blank.
struct WidgetReadout: Equatable {
    enum Phase: Equatable {
        /// A meeting is on: the minutes until it ends.
        case live
        /// One starts within the hour: the minutes until it does.
        case soon
        /// The next one is further off: the time it starts.
        case later
        /// Nothing in the days the app saved.
        case clear
        /// The saved days have run out, or nothing was ever saved: Meetball has to be opened.
        case stale
    }

    var phase: Phase
    var caption: String
    var digits: String
    var unit: String
    /// The meeting's title, or what to make of there being none.
    var message: String
    var meeting: WidgetMeeting?

    /// A countdown takes over from the start time this long before a meeting.
    static let soon: TimeInterval = 3600

    static func make(_ snapshot: WidgetSnapshot?, at now: Date, calendar: Calendar = .current,
                     twentyFourHour: Bool = WidgetClock.twentyFourHour) -> WidgetReadout {
        guard let snapshot else {
            return WidgetReadout(phase: .stale, caption: "MB-1", digits: "--", unit: "", message: "Open Meetball to set up")
        }
        guard let m = snapshot.current(at: now) else {
            if now >= snapshot.coversUntil {
                return WidgetReadout(phase: .stale, caption: "OUT OF DATE", digits: "--", unit: "", message: "Open Meetball to catch up")
            }
            let through = calendar.shortWeekdaySymbols[calendar.component(.weekday, from: snapshot.coversUntil) - 1]
            return WidgetReadout(phase: .clear, caption: "ALL CLEAR", digits: "0", unit: "LEFT", message: "Nothing through \(through)")
        }
        if m.start <= now {
            let c = WidgetCountdown.digits(m.end.timeIntervalSince(now))
            return WidgetReadout(phase: .live, caption: "ON NOW · ENDS IN", digits: c.digits, unit: c.unit, message: m.title, meeting: m)
        }
        if m.start.timeIntervalSince(now) <= soon {
            let c = WidgetCountdown.digits(m.start.timeIntervalSince(now))
            return WidgetReadout(phase: .soon, caption: "STARTS IN", digits: c.digits, unit: c.unit, message: m.title, meeting: m)
        }
        let c = WidgetClock.digits(m.start, calendar: calendar, twentyFourHour: twentyFourHour)
        let day: String
        if calendar.isDate(m.start, inSameDayAs: now) {
            day = "NEXT"
        } else if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(m.start, inSameDayAs: tomorrow) {
            day = "TOMORROW"
        } else {
            day = calendar.shortWeekdaySymbols[calendar.component(.weekday, from: m.start) - 1].uppercased()
        }
        return WidgetReadout(phase: .later, caption: "\(day) AT", digits: c.digits, unit: c.unit, message: m.title, meeting: m)
    }
}

/// A time of day for the seven-segment LCD: "8:00" AM, or "20:00" on a 24-hour clock.
enum WidgetClock {
    static var twentyFourHour: Bool {
        !(DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: .current) ?? "").contains("a")
    }

    static func digits(_ date: Date, calendar: Calendar = .current, twentyFourHour: Bool = WidgetClock.twentyFourHour) -> (digits: String, unit: String) {
        let hour = calendar.component(.hour, from: date), minute = calendar.component(.minute, from: date)
        if twentyFourHour { return (String(format: "%d:%02d", hour, minute), "") }
        return (String(format: "%d:%02d", hour % 12 == 0 ? 12 : hour % 12, minute), hour < 12 ? "AM" : "PM")
    }
}

/// One half hour on the tape: the strip of the hours ahead, lit where there's a meeting.
struct WidgetTapeSlot: Equatable {
    var start: Date
    /// The colour of the meeting in it (the earliest, when they overlap); nil when it's free.
    var colorHex: String?

    /// The hour to print under the slot: every third hour, on the hour ("9", "12", "3"; "15" on a 24-hour clock).
    func label(calendar: Calendar = .current, twentyFourHour: Bool = WidgetClock.twentyFourHour) -> String? {
        let hour = calendar.component(.hour, from: start)
        guard calendar.component(.minute, from: start) == 0, hour % 3 == 0 else { return nil }
        return twentyFourHour ? "\(hour)" : "\(hour % 12 == 0 ? 12 : hour % 12)"
    }
}

extension WidgetSnapshot {
    /// How far ahead the app saves meetings.
    static let horizon: TimeInterval = 2 * 24 * 3600

    /// Until when this snapshot knows the calendar.
    var coversUntil: Date { savedAt.addingTimeInterval(Self.horizon) }

    /// Where the tape should start so it has something to show: now while the next meeting is today, else an hour
    /// before the first meeting of the day it's on (so the evening shows tomorrow's shape, not an empty night).
    func tapeStart(at now: Date, calendar: Calendar = .current) -> Date {
        guard let m = current(at: now), !calendar.isDate(m.start, inSameDayAs: now) else { return now }
        let first = meetings.filter { $0.end > now && calendar.isDate($0.start, inSameDayAs: m.start) }.map(\.start).min() ?? m.start
        return max(now, first.addingTimeInterval(-3600))
    }

    /// The hours ahead in `slots` steps of `length`, from the step `now` is in: which are taken, and by what.
    func tape(from now: Date, slots: Int, length: TimeInterval = 1800) -> [WidgetTapeSlot] {
        let first = (now.timeIntervalSinceReferenceDate / length).rounded(.down) * length
        return (0..<slots).map { i in
            let start = Date(timeIntervalSinceReferenceDate: first + Double(i) * length)
            let end = start.addingTimeInterval(length)
            let taken = meetings.filter { $0.end > max(start, now) && $0.start < end }.min { $0.start < $1.start }
            return WidgetTapeSlot(start: start, colorHex: taken?.colorHex)
        }
    }
}

/// Countdown digits for the seven-segment LCD: "42" MIN under an hour, "1:05" HR under a day, then "3" DAYS
/// (the Mac's `SK1CountdownDigits`, here so the widgets needn't compile the Mac's formatters).
enum WidgetCountdown {
    static func digits(_ interval: TimeInterval) -> (digits: String, unit: String) {
        let mins = max(1, Int((interval / 60).rounded(.up)))
        if mins < 60 { return ("\(mins)", "MIN") }
        if mins < 24 * 60 { return (String(format: "%d:%02d", mins / 60, mins % 60), "HR") }
        let days = mins / (24 * 60)
        return ("\(days)", days == 1 ? "DAY" : "DAYS")
    }
}

/// The video service behind a join link, for the widget's label ("Meet", "Zoom", …); nil when it isn't one of these.
enum WidgetService {
    static func name(_ url: URL?) -> String? {
        guard let host = url?.host?.lowercased() else { return nil }
        if host.hasSuffix("meet.google.com") { return "Meet" }
        if host.hasSuffix("zoom.us") || host.hasSuffix("zoomgov.com") { return "Zoom" }
        if host.contains("teams.microsoft") || host.contains("teams.live") { return "Teams" }
        if host.hasSuffix("webex.com") { return "Webex" }
        return nil
    }
}

/// `meetball://` links from the widgets and the Live Activity into the app.
enum MeetballLink {
    static let scheme = "meetball"

    enum Action: Equatable {
        case today
        case join(URL)
    }

    static var today: URL { URL(string: "\(scheme)://today")! }

    static func join(_ meeting: URL) -> URL {
        var c = URLComponents()
        c.scheme = scheme
        c.host = "join"
        c.queryItems = [URLQueryItem(name: "url", value: meeting.absoluteString)]
        return c.url ?? today
    }

    static func parse(_ url: URL) -> Action? {
        guard url.scheme == scheme else { return nil }
        switch url.host {
        case "join":
            let link = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "url" }?.value
            guard let link, let target = URL(string: link), ["https", "http"].contains(target.scheme?.lowercased() ?? "") else {
                return .today
            }
            return .join(target)
        default:
            return .today
        }
    }
}
