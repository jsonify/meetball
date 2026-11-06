import EventKit
import CoreGraphics

/// Reads calendars through EventKit, i.e. whatever accounts are already configured in macOS Calendar
/// (Exchange, iCloud, Google, ...). No OAuth, so org admins can't block it per-app. Read-only.
/// Shared with the iPhone notifier (MeetballPhone), so it uses no AppKit.
@MainActor
final class AppleCalendarClient {
    static let sourcePrefix = "Apple · "
    private var store = EKEventStore()

    static func isApple(_ accountEmail: String) -> Bool { accountEmail.hasPrefix(sourcePrefix) }

    var isAuthorized: Bool { EKEventStore.authorizationStatus(for: .event) == .fullAccess }
    var isDenied: Bool {
        let s = EKEventStore.authorizationStatus(for: .event)
        return s == .denied || s == .restricted
    }

    /// Asks the servers behind Calendar.app's accounts (iCloud, Exchange, CalDAV) to sync. EventKit posts
    /// `EKEventStoreChanged` when new data arrives, which reloads Meetball again.
    ///
    /// `fresh` (a Refresh the user asked for) also swaps in a new event store. A store that has been open for hours can
    /// keep serving its cached view of the calendar database, so the menu bar's Refresh showed the old meeting time.
    func sync(fresh: Bool) {
        guard isAuthorized else { return }
        if fresh { store = EKEventStore() }
        store.refreshSourcesIfNecessary()
    }

    /// Prompts the first time; returns whether full access is granted.
    func requestAccess() async -> Bool {
        if isAuthorized { return true }
        return (try? await store.requestFullAccessToEvents()) ?? false
    }

    func calendars() -> [GCalendar] {
        guard isAuthorized else { return [] }
        return store.calendars(for: .event).map {
            GCalendar(id: $0.calendarIdentifier, accountEmail: Self.sourcePrefix + $0.source.title, summary: $0.title,
                      colorHex: Self.hex($0.cgColor), accessRole: "reader",
                      isPrimary: false, allowsMeet: false)
        }
    }

    func events(for cal: GCalendar, range: DateInterval) -> [CalendarEvent] {
        guard isAuthorized, let ek = store.calendar(withIdentifier: cal.id) else { return [] }
        let pred = store.predicateForEvents(withStart: range.start, end: range.end, calendars: [ek])
        return store.events(matching: pred).compactMap { e in
            guard e.status != .canceled, let s = e.startDate, let en = e.endDate else { return nil }
            let base = e.eventIdentifier ?? UUID().uuidString
            let people = (e.attendees ?? []).map(Self.attendee)
            return CalendarEvent(id: "\(base)@\(Int(s.timeIntervalSince1970))", calendarID: cal.id, accountEmail: cal.accountEmail,
                                 title: e.title ?? "(No title)", start: s, end: en, isAllDay: e.isAllDay,
                                 meetURL: Self.joinURL(in: [e.url?.absoluteString, e.location, e.notes]),
                                 location: e.location,
                                 attendees: people.compactMap(\.email),
                                 htmlLink: nil, colorHex: cal.colorHex,
                                 isDeclined: people.contains { $0.isSelf && $0.response == .declined },
                                 notes: e.notes,
                                 organizer: e.organizer.map { Self.attendee($0).displayName },
                                 participants: people,
                                 calendarAppURL: e.eventIdentifier.flatMap(Self.calendarAppURL),
                                 organizerIsSelf: e.organizer?.isCurrentUser ?? people.isEmpty,
                                 seriesID: e.hasRecurrenceRules ? e.calendarItemIdentifier : nil,
                                 recurrence: Self.recurrence(e),
                                 timeZoneID: e.timeZone?.identifier,
                                 externalID: e.calendarItemExternalIdentifier,
                                 organizerEmail: e.organizer.flatMap { Self.attendee($0).email },
                                 occurrenceDate: e.hasRecurrenceRules ? e.occurrenceDate : nil)
        }
    }

    /// The stored EventKit event behind `event`, when its calendar can be changed (for Apple's event editor). Nil for
    /// read-only calendars such as a subscribed work feed.
    func editableEvent(for event: CalendarEvent) -> EKEvent? {
        guard isAuthorized, let ek = store.calendar(withIdentifier: event.calendarID), ek.allowsContentModifications,
              let at = event.id.lastIndex(of: "@") else { return nil }
        let base = String(event.id[..<at])
        let stamp = Int(event.id[event.id.index(after: at)...])
        let pred = store.predicateForEvents(withStart: event.start.addingTimeInterval(-60),
                                            end: event.end.addingTimeInterval(60), calendars: [ek])
        return store.events(matching: pred).first {
            $0.eventIdentifier == base && (stamp == nil || $0.startDate.map { Int($0.timeIntervalSince1970) } == stamp)
        }
    }

    /// Identifiers of the calendars new events can be added to (the iPhone app's quick add).
    func writableCalendarIDs() -> Set<String> {
        guard isAuthorized else { return [] }
        return Set(store.calendars(for: .event).filter(\.allowsContentModifications).map(\.calendarIdentifier))
    }

    /// The calendar the Calendar app puts new events on.
    var defaultCalendarID: String? { isAuthorized ? store.defaultCalendarForNewEvents?.calendarIdentifier : nil }

    /// Adds an event with no invitees (the iPhone app's quick add). Throws when the calendar is gone or read-only.
    func addEvent(title: String, start: Date, end: Date, calendarID: String) throws {
        guard isAuthorized, let ek = store.calendar(withIdentifier: calendarID), ek.allowsContentModifications else {
            throw CocoaError(.featureUnsupported)
        }
        let e = EKEvent(eventStore: store)
        e.calendar = ek
        e.title = title
        e.startDate = start
        e.endDate = end
        try store.save(e, span: .thisEvent, commit: true)
    }

    /// An unsaved event filled in with what the composer has, for Apple's own event editor (the only way to invite
    /// people: EventKit can't add attendees itself). The editor saves it, or not, in `eventStore`.
    func draftEvent(title: String, start: Date, end: Date, calendarID: String?) -> EKEvent? {
        guard isAuthorized else { return nil }
        let e = EKEvent(eventStore: store)
        e.title = title
        e.startDate = start
        e.endDate = end
        if let calendarID, let ek = store.calendar(withIdentifier: calendarID), ek.allowsContentModifications {
            e.calendar = ek
        } else {
            e.calendar = store.defaultCalendarForNewEvents
        }
        return e
    }

    /// The store `draftEvent` events belong to.
    var eventStore: EKEventStore { store }

    private static func attendee(_ p: EKParticipant) -> EventAttendee {
        let raw = p.url.absoluteString
        let email = raw.lowercased().hasPrefix("mailto:") ? String(raw.dropFirst(7)) : nil
        let response: AttendeeResponse
        switch p.participantStatus {
        case .accepted: response = .accepted
        case .declined: response = .declined
        case .tentative: response = .tentative
        default: response = .needsAction
        }
        return EventAttendee(email: email, name: p.name, response: response,
                             isOrganizer: p.participantRole == .chair, isSelf: p.isCurrentUser)
    }

    private static func recurrence(_ e: EKEvent) -> EventRecurrence {
        guard e.hasRecurrenceRules, let rule = e.recurrenceRules?.first else { return .none }
        switch rule.frequency {
        case .daily: return rule.interval == 1 ? .daily : .other
        case .weekly:
            // "Every weekday" is stored as weekly on Mon–Fri.
            if rule.interval == 1, (rule.daysOfTheWeek?.count ?? 0) >= 5 { return .daily }
            return .weekly
        default: return .other
        }
    }

    /// Calendar.app's URL scheme for showing a specific event.
    static func calendarAppURL(_ eventIdentifier: String) -> URL? {
        guard let id = eventIdentifier.addingPercentEncoding(withAllowedCharacters: .alphanumerics) else { return nil }
        return URL(string: "ical://ekevent/\(id)?method=show&options=more")
    }

    private static let joinPattern = try! NSRegularExpression(
        pattern: #"https://(?:meet\.google\.com/[a-z\-]+|[\w.\-]*zoom\.(?:us|com)/[^\s<>"]+|teams\.microsoft\.com/l/meetup-join/[^\s<>"]+|teams\.live\.com/meet/[^\s<>"]+|[\w.\-]*webex\.com/[^\s<>"]+)"#,
        options: [.caseInsensitive])

    static func joinURL(in fields: [String?]) -> URL? {
        for f in fields.compactMap({ $0 }) {
            let r = NSRange(f.startIndex..., in: f)
            if let m = joinPattern.firstMatch(in: f, range: r), let rr = Range(m.range, in: f) {
                return URL(string: String(f[rr]))
            }
        }
        return nil
    }

    private static func hex(_ c: CGColor?) -> String {
        guard let c, let srgb = CGColorSpace(name: CGColorSpace.sRGB),
              let n = c.converted(to: srgb, intent: .defaultIntent, options: nil), let comps = n.components, comps.count >= 3
        else { return "#4285F4" }
        let v = comps.prefix(3).map { Int((min(max($0, 0), 1) * 255).rounded(.down)) }
        return String(format: "#%02X%02X%02X", v[0], v[1], v[2])
    }
}
