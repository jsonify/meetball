import Foundation

/// What Meetball holds for one Google calendar between refreshes, so a refresh can ask Google only for what changed
/// (a sync token) instead of every event again.
///
/// A full sync loads the events overlapping `window` and keeps the sync token Google hands back. Later refreshes send
/// that token alone (Google allows no time range with it) and get every event created, changed or deleted since,
/// wherever it falls; those are folded in and anything outside `window` is dropped. A refresh for a range the window
/// doesn't cover, a token Google has expired (410 Gone), or a response with no token falls back to a full sync.
///
/// Recurring meetings come as single occurrences, and an edit to a whole series can give its occurrences new ids
/// without cancelling the old ones, so any change that touches a series (`touchesSeries`) is answered with a full sync
/// of that calendar rather than folded in. A full sync also comes round every `maxAge` regardless, so nothing can
/// drift for long.
struct GoogleSyncState: Equatable {
    /// The span the events cover.
    var window: DateInterval
    /// Google's token for the next incremental sync; nil when none was given (every refresh is then a full one).
    var token: String?
    /// The events overlapping `window`, by id.
    var events: [String: CalendarEvent]
    /// When the last full sync was.
    var fullSyncedAt: Date

    enum Change: Equatable {
        case upsert(CalendarEvent)
        case remove(id: String)
    }

    /// The state after a full sync of `window`.
    init(window: DateInterval, token: String?, events: [CalendarEvent], at: Date = Date()) {
        self.window = window
        self.token = token
        self.fullSyncedAt = at
        self.events = [:]
        for e in events where Self.overlaps(e, window) { self.events[e.id] = e }
    }

    /// Whether an incremental sync can answer for `range` at `now`: there's a token, the window holds all of the range,
    /// and the last full sync isn't older than `maxAge`.
    func covers(_ range: DateInterval, now: Date = Date()) -> Bool {
        token != nil && window.start <= range.start && window.end >= range.end && now.timeIntervalSince(fullSyncedAt) < Self.maxAge
    }

    /// How long incremental syncs go on before a full one.
    static let maxAge: TimeInterval = 6 * 3600

    /// Whether `changes` touch a recurring series: an occurrence changed, or a series (or one of its occurrences)
    /// removed. Those are left to a full sync.
    func touchesSeries(_ changes: [Change]) -> Bool {
        changes.contains { change in
            switch change {
            case .upsert(let e):
                return e.seriesID != nil
            case .remove(let id):
                return events[id]?.seriesID != nil || events.values.contains { $0.seriesID == id }
            }
        }
    }

    /// This state with an incremental sync's changes folded in and its new token. An event that moved out of the
    /// window leaves; one that moved into it arrives.
    func applying(_ changes: [Change], token: String?) -> GoogleSyncState {
        var next = self
        next.token = token
        for change in changes {
            switch change {
            case .remove(let id):
                next.events[id] = nil
            case .upsert(let e):
                next.events[e.id] = Self.overlaps(e, window) ? e : nil
            }
        }
        return next
    }

    /// The events overlapping `range`, by start.
    func events(in range: DateInterval) -> [CalendarEvent] {
        events.values.filter { Self.overlaps($0, range) }.sorted { ($0.start, $0.id) < ($1.start, $1.id) }
    }

    /// The span a full sync loads for a refresh of `range`: a week before it and two weeks after, so day-to-day
    /// refreshes (and a few days of paging) stay inside it. A range that touches the previous window joins it, if
    /// the two together stay within `maxSpan`.
    static func window(for range: DateInterval, previous: DateInterval?) -> DateInterval {
        let padded = DateInterval(start: range.start.addingTimeInterval(-7 * 86_400), end: range.end.addingTimeInterval(14 * 86_400))
        guard let previous else { return padded }
        let joined = DateInterval(start: min(previous.start, padded.start), end: max(previous.end, padded.end))
        return joined.duration <= maxSpan ? joined : padded
    }

    /// The longest window kept: about half a year.
    static let maxSpan: TimeInterval = 183 * 86_400

    private static func overlaps(_ e: CalendarEvent, _ range: DateInterval) -> Bool {
        (e.end > range.start && e.start < range.end) || (e.start == e.end && e.start >= range.start && e.start < range.end)
    }
}

/// The sync state of every Google calendar Meetball has loaded, kept for as long as the app runs (a relaunch starts with
/// a full sync). An actor, so overlapping refreshes never interleave their updates; a refresh that fails or is
/// cancelled part way commits nothing.
actor GoogleSyncCache {
    private var states: [String: GoogleSyncState] = [:]

    func state(for key: String) -> GoogleSyncState? { states[key] }

    func store(_ state: GoogleSyncState, for key: String) { states[key] = state }

    func forget(_ key: String) { states[key] = nil }

    func forgetAll() { states = [:] }
}
