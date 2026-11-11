import Foundation

// Shared with the iPhone app (MeetballPhone): no AppKit or UIKit here, and no EventKit (TodoStore talks to Reminders).

/// The meeting a to-do came out of: enough to show its name and find it again.
public struct TodoMeeting: Hashable, Codable {
    /// The meeting's `CalendarEvent.uid`.
    public var uid: String
    public var title: String
    public var start: Date

    public init(uid: String, title: String, start: Date) {
        self.uid = uid
        self.title = title
        self.start = start
    }

    public init(_ e: CalendarEvent) {
        self.init(uid: e.uid, title: e.title, start: e.start)
    }

    /// Whether this is `e`: the same event, or (an id the sync changed) the same title at the same time.
    public func matches(_ e: CalendarEvent) -> Bool {
        uid == e.uid
            || (start == e.start && MeetingChangeDetector.normalizedTitle(title) == MeetingChangeDetector.normalizedTitle(e.title))
    }
}

/// One item on the to-do list: a reminder in the Meetball list in Reminders.
public struct TodoItem: Identifiable, Hashable {
    /// The reminder's `calendarItemIdentifier`.
    public var id: String
    public var title: String
    public var isDone: Bool = false
    public var completedAt: Date?
    public var createdAt: Date?
    public var due: Date?
    /// Where it sits in Meetball's list (Reminders doesn't share its own order with other apps). Nil for one added
    /// outside Meetball, which goes at the bottom.
    public var rank: Double?
    public var meeting: TodoMeeting?

    public init(id: String, title: String, isDone: Bool = false, completedAt: Date? = nil, createdAt: Date? = nil,
                due: Date? = nil, rank: Double? = nil, meeting: TodoMeeting? = nil) {
        self.id = id
        self.title = title
        self.isDone = isDone
        self.completedAt = completedAt
        self.createdAt = createdAt
        self.due = due
        self.rank = rank
        self.meeting = meeting
    }
}

/// The link Meetball keeps in a reminder's URL field: its place in the list and the meeting it came from.
/// `meetball://todo?rank=3&event=<uid>&title=Design%20review&start=1762880400`. Tapping it in Reminders opens Meetball.
public enum TodoLink {
    public static let host = "todo"

    public static func url(rank: Double?, meeting: TodoMeeting?) -> URL {
        var c = URLComponents()
        c.scheme = "meetball"
        c.host = host
        var items: [URLQueryItem] = []
        if let rank { items.append(URLQueryItem(name: "rank", value: format(rank))) }
        if let meeting {
            items.append(URLQueryItem(name: "event", value: meeting.uid))
            items.append(URLQueryItem(name: "title", value: meeting.title))
            items.append(URLQueryItem(name: "start", value: String(Int(meeting.start.timeIntervalSince1970))))
        }
        c.queryItems = items.isEmpty ? nil : items
        return c.url ?? URL(string: "meetball://todo")!
    }

    /// The rank and meeting in `url`; both nil for any other link (or none).
    public static func parse(_ url: URL?) -> (rank: Double?, meeting: TodoMeeting?) {
        guard let url, url.scheme == "meetball", url.host == host,
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else { return (nil, nil) }
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        let rank = value("rank").flatMap(Double.init)
        var meeting: TodoMeeting?
        if let uid = value("event"), !uid.isEmpty, let start = value("start").flatMap(Double.init) {
            meeting = TodoMeeting(uid: uid, title: value("title") ?? "", start: Date(timeIntervalSince1970: start))
        }
        return (rank, meeting)
    }

    private static func format(_ rank: Double) -> String {
        rank == rank.rounded() && abs(rank) < 1e15 ? String(Int(rank)) : String(rank)
    }
}

public enum Todos {
    /// Done items stay on the list (under Done) this long.
    public static let keepDone: TimeInterval = 7 * 86400

    /// Open items in Meetball's order (ranked first, then anything added elsewhere, oldest first), and done items,
    /// the most recently finished first.
    public static func arrange(_ items: [TodoItem]) -> (open: [TodoItem], done: [TodoItem]) {
        let open = items.filter { !$0.isDone }.sorted { a, b in
            switch (a.rank, b.rank) {
            case let (x?, y?) where x != y: return x < y
            case (.some, nil): return true
            case (nil, .some): return false
            default: return (a.createdAt ?? .distantPast, a.id) < (b.createdAt ?? .distantPast, b.id)
            }
        }
        let done = items.filter(\.isDone).sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
        return (open, done)
    }

    /// The rank for an item added at the bottom of `open`.
    public static func rankForNew(after open: [TodoItem]) -> Double {
        (open.compactMap(\.rank).max() ?? 0) + 1
    }

    /// The ranks to save once `order` is the open list with `moved` dropped in its new place: just the moved item's,
    /// between its neighbours, when there's room; otherwise every item numbered afresh (only those that change).
    public static func ranks(for order: [TodoItem], moved: String) -> [String: Double] {
        guard let i = order.firstIndex(where: { $0.id == moved }) else { return [:] }
        let prev = i > 0 ? order[i - 1].rank : nil
        let next = i + 1 < order.count ? order[i + 1].rank : nil
        let hasPrev = i > 0, hasNext = i + 1 < order.count
        var rank: Double?
        switch (hasPrev, hasNext) {
        case (false, false): rank = order[i].rank ?? 1
        case (false, true): rank = next.map { $0 - 1 }
        case (true, false): rank = prev.map { $0 + 1 }
        case (true, true):
            if let p = prev, let n = next, n - p > 1e-6 { rank = (p + n) / 2 }
        }
        if let rank { return order[i].rank == rank ? [:] : [moved: rank] }
        var changes: [String: Double] = [:]
        for (k, item) in order.enumerated() where item.rank != Double(k + 1) { changes[item.id] = Double(k + 1) }
        return changes
    }

    /// The open list after moving the items at `offsets` to `destination` (as `List.onMove` reports it).
    public static func moving(_ open: [TodoItem], from offsets: IndexSet, to destination: Int) -> [TodoItem] {
        var result = open
        let moving = offsets.sorted().map { result[$0] }
        for i in offsets.sorted(by: >) { result.remove(at: i) }
        let before = offsets.filter { $0 < destination }.count
        result.insert(contentsOf: moving, at: min(max(destination - before, 0), result.count))
        return result
    }

    /// The items that came out of `e`, open first.
    public static func followUps(for e: CalendarEvent, in items: [TodoItem]) -> [TodoItem] {
        let mine = items.filter { $0.meeting?.matches(e) == true }
        let (open, done) = arrange(mine)
        return open + done
    }

    /// The reminder's notes for an item from a meeting, so the Reminders app shows where it came from.
    public static func notes(for meeting: TodoMeeting, locale: Locale = .current) -> String {
        let when = meeting.start.formatted(Date.FormatStyle(locale: locale).weekday(.abbreviated).month(.abbreviated).day()
            .hour().minute())
        return "Follow-up from \u{201C}\(meeting.title)\u{201D}, \(when)."
    }

    /// Lines in a meeting's notes that read as things to do: "TODO: …", "Action: …", "AI: …", "Follow up: …",
    /// "Next step: …", or an empty checkbox ("- [ ] …", "☐ …"). Each once, in order, at most `limit`.
    public static func suggestions(fromNotes notes: String, limit: Int = 8) -> [String] {
        let patterns = [
            #"^\s*(?:[-*•]\s*)?(?:\[\s?\]|☐)\s*(.+)$"#,
            #"^\s*(?:[-*•]\s*)?(?:todo|to-do|to do|action items?|actions?|ai|follow[- ]?ups?|next steps?)\s*[:\-–—]\s*(.+)$"#,
        ].compactMap { try? NSRegularExpression(pattern: $0, options: [.caseInsensitive]) }
        var seen = Set<String>()
        var found: [String] = []
        for raw in notes.components(separatedBy: .newlines) {
            let line = raw as NSString
            for re in patterns {
                guard let m = re.firstMatch(in: raw, range: NSRange(location: 0, length: line.length)), m.numberOfRanges > 1 else { continue }
                var text = Echo.cleaned(line.substring(with: m.range(at: 1)))
                if text.count > 140 { text = String(text.prefix(139)).trimmingCharacters(in: .whitespaces) + "…" }
                let key = text.lowercased()
                if text.count >= 2, seen.insert(key).inserted { found.append(text) }
                break
            }
            if found.count >= limit { break }
        }
        return found
    }

    /// `suggestions` less the ones already on the list for this meeting.
    public static func newSuggestions(for e: CalendarEvent, notes: String, items: [TodoItem]) -> [String] {
        let have = Set(followUps(for: e, in: items).map { Echo.cleaned($0.title).lowercased() })
        return suggestions(fromNotes: notes).filter { !have.contains($0.lowercased()) }
    }
}
