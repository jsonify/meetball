import Foundation

// Shared with the iPhone app (MeetballPhone): no AppKit here.

/// A link from a meeting's invite (a doc, a ticket, a board), for the pre-flight card.
public struct PreFlightLink: Hashable, Identifiable {
    public var url: URL
    public var label: String
    public var id: String { url.absoluteString }
}

/// What to know walking into a meeting: who's in it, when you last met (and the Echo note you left then), and the
/// links and notes from the invite.
public struct PreFlightBrief: Equatable {
    /// How the last meeting was found.
    public enum Match: String, Equatable {
        /// An earlier meeting of the same recurring series.
        case series
        /// An earlier meeting with the same title.
        case title
        /// An earlier meeting with mostly the same people.
        case people

        public var label: String {
            switch self {
            case .series: return "Last in this series"
            case .title: return "Last time, same title"
            case .people: return "Last time with these people"
            }
        }
    }

    /// Everyone invited but you, organizer first.
    public var people: [EventAttendee]
    public var lastTime: CalendarEvent?
    public var match: Match?
    public var links: [PreFlightLink]
    /// The invite's notes, without the dial-in boilerplate, cut short.
    public var notes: String?

    public var isEmpty: Bool { people.isEmpty && lastTime == nil && links.isEmpty && notes == nil }
}

/// The pre-flight card: five minutes before a meeting, the context to walk in with.
public enum PreFlight {
    /// How long before a meeting the card comes up.
    public static let lead: TimeInterval = 5 * 60
    /// How far back to look for the last meeting.
    public static let lookbackDays = 90
    public static let maxLinks = 6
    public static let notesLength = 280

    public static func brief(for event: CalendarEvent, history: [CalendarEvent]) -> PreFlightBrief {
        let last = lastMeeting(before: event, in: history)
        return PreFlightBrief(people: people(event), lastTime: last?.event, match: last?.match,
                              links: links(in: event), notes: notesExcerpt(event))
    }

    /// The range to load as `history` for `event`: whole days from `lookbackDays` back to the meeting's start, so the
    /// same meeting asks for the same range (and hits a cache) all day.
    public static func historyRange(for event: CalendarEvent, calendar: Calendar = .app) -> DateInterval {
        let today = calendar.startOfDay(for: event.start)
        let from = calendar.date(byAdding: .day, value: -lookbackDays, to: today) ?? today.addingTimeInterval(-Double(lookbackDays) * 86400)
        return DateInterval(start: from, end: max(from, event.start))
    }

    /// The meeting the card is for: the next timed, not declined meeting starting within `lead` of `now`.
    public static func due(_ upcoming: [CalendarEvent], now: Date) -> CalendarEvent? {
        upcoming.filter { isCandidate($0) && $0.start > now && $0.start.timeIntervalSince(now) <= lead }
            .min { $0.start < $1.start }
    }

    /// The next meeting the card could come up for, to wait for.
    public static func next(_ upcoming: [CalendarEvent], now: Date) -> CalendarEvent? {
        upcoming.filter { isCandidate($0) && $0.start > now }.min { $0.start < $1.start }
    }

    static func isCandidate(_ e: CalendarEvent) -> Bool { !e.isAllDay && !e.isDeclined && e.end > e.start }

    // MARK: People

    /// Everyone but you: organizer first, then by RSVP (going, maybe, no answer, declined), then by name.
    public static func people(_ e: CalendarEvent) -> [EventAttendee] {
        e.participants.filter { !$0.isSelf }.sorted {
            ($0.isOrganizer ? 0 : 1, rank($0.response), $0.displayName.lowercased())
                < ($1.isOrganizer ? 0 : 1, rank($1.response), $1.displayName.lowercased())
        }
    }

    private static func rank(_ r: AttendeeResponse) -> Int {
        switch r {
        case .accepted: return 0
        case .tentative: return 1
        case .needsAction: return 2
        case .declined: return 3
        }
    }

    /// The other people's emails, lowercased: invitees and the organizer, without you.
    static func otherEmails(_ e: CalendarEvent) -> Set<String> {
        let mine = Set(e.participants.filter(\.isSelf).compactMap { $0.email?.lowercased() }
            + (e.organizerIsSelf ? [e.organizerEmail?.lowercased()].compactMap { $0 } : []))
        let all = e.attendees + e.participants.compactMap(\.email) + [e.organizerEmail].compactMap { $0 }
        return Set(all.map { $0.lowercased().trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }).subtracting(mine)
    }

    // MARK: Last time

    /// The most recent earlier meeting that is the same meeting: the same recurring series first, then the same title,
    /// then one with mostly the same people (at least half of each meeting's other people in common).
    public static func lastMeeting(before event: CalendarEvent, in history: [CalendarEvent])
        -> (event: CalendarEvent, match: PreFlightBrief.Match)? {
        let past = history
            .filter { $0.uid != event.uid && isCandidate($0) && $0.start < event.start && $0.end <= event.start }
            .sorted { $0.start > $1.start }
        if let series = event.seriesID, let hit = past.first(where: { $0.seriesID == series }) { return (hit, .series) }
        let title = MeetingChangeDetector.normalizedTitle(event.title)
        if !genericTitles.contains(title), let hit = past.first(where: { MeetingChangeDetector.normalizedTitle($0.title) == title }) {
            return (hit, .title)
        }
        let others = otherEmails(event)
        guard !others.isEmpty else { return nil }
        let hit = past.first { e in
            let theirs = otherEmails(e)
            let shared = others.intersection(theirs).count
            return shared > 0 && shared * 2 >= others.count && shared * 2 >= theirs.count
        }
        return hit.map { ($0, .people) }
    }

    /// Titles too common to mean it's the same meeting.
    static let genericTitles: Set<String> = ["", "(no title)", "busy", "meeting", "call", "sync", "lunch", "hold", "block", "focus"]

    // MARK: Links and notes

    /// The web links in the invite's location and notes, without the join link (that's the Join key) or the dial-in
    /// boilerplate's help pages, each once.
    public static func links(in e: CalendarEvent) -> [PreFlightLink] {
        let text = [e.location, e.notes.map(EventNotesFormatter.plainText)].compactMap { $0 }.joined(separator: "\n")
        guard !text.isEmpty, let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return [] }
        let join = e.meetURL.map(key)
        var seen = Set<String>()
        var out: [PreFlightLink] = []
        for m in detector.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let url = m.url, let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { continue }
            let k = key(url)
            guard k != join, MeetingService.detect(url) == .other, !isBoilerplate(url), seen.insert(k).inserted else { continue }
            out.append(PreFlightLink(url: url, label: label(url)))
            if out.count == maxLinks { break }
        }
        return out
    }

    /// Host and path, for spotting the same link twice.
    private static func key(_ url: URL) -> String {
        let host = (url.host ?? "").lowercased()
        let path = url.path.hasSuffix("/") ? String(url.path.dropLast()) : url.path
        return host + path + (url.query.map { "?" + $0 } ?? "")
    }

    private static func isBoilerplate(_ url: URL) -> Bool {
        let host = (url.host ?? "").lowercased()
        if ["support.google.com", "accounts.google.com", "calendar.google.com", "aka.ms", "go.microsoft.com",
            "support.zoom.us", "support.zoom.com", "help.webex.com"].contains(host) { return true }
        return host.hasSuffix("google.com") && url.path.hasPrefix("/calendar")
    }

    /// A short name for a link: "Google Doc", "Figma", "GitHub · owner/repo", or else the site.
    public static func label(_ url: URL) -> String {
        var host = (url.host ?? "").lowercased()
        if host.hasPrefix("www.") { host = String(host.dropFirst(4)) }
        let path = url.path.lowercased()
        let parts = url.pathComponents.filter { $0 != "/" }
        switch host {
        case "docs.google.com":
            if path.hasPrefix("/document") { return "Google Doc" }
            if path.hasPrefix("/spreadsheets") { return "Google Sheet" }
            if path.hasPrefix("/presentation") { return "Google Slides" }
            if path.hasPrefix("/forms") { return "Google Form" }
            return "Google Docs"
        case "drive.google.com": return "Google Drive"
        case "figma.com": return "Figma"
        case "miro.com": return "Miro"
        case "linear.app": return "Linear"
        case "loom.com": return "Loom"
        case "notion.so": return "Notion"
        case "github.com":
            return parts.count >= 2 ? "GitHub · \(parts[0])/\(parts[1])" : "GitHub"
        default:
            if host.hasSuffix(".notion.site") { return "Notion" }
            if host.hasSuffix(".atlassian.net") {
                if let i = parts.firstIndex(of: "browse"), i + 1 < parts.count { return "Jira · \(parts[i + 1])" }
                return path.hasPrefix("/wiki") ? "Confluence" : "Jira"
            }
            return host.isEmpty ? url.absoluteString : host
        }
    }

    /// Lines where an invite's dial-in block starts; everything from there on is left out.
    static let boilerplateStarts = ["-::~", "join with google meet", "join by phone", "join zoom meeting",
                                    "microsoft teams meeting", "join on your computer", "join the meeting now", "______"]

    /// The invite's notes, from the top to the dial-in boilerplate, at most `notesLength` characters.
    public static func notesExcerpt(_ e: CalendarEvent) -> String? {
        guard let raw = e.notes else { return nil }
        var kept: [Substring] = []
        for line in EventNotesFormatter.plainText(raw).split(separator: "\n", omittingEmptySubsequences: false) {
            let l = line.trimmingCharacters(in: .whitespaces).lowercased()
            if boilerplateStarts.contains(where: { l.hasPrefix($0) }) { break }
            kept.append(line)
        }
        var s = kept.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        if s.count > notesLength { s = String(s.prefix(notesLength)).trimmingCharacters(in: .whitespacesAndNewlines) + "…" }
        return s
    }
}
