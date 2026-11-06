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
