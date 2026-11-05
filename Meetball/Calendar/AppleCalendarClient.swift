import EventKit
import AppKit

/// Reads calendars through EventKit, i.e. whatever accounts are already configured in macOS Calendar
/// (Exchange, iCloud, Google, ...). No OAuth, so org admins can't block it per-app. Read-only.
@MainActor
final class AppleCalendarClient {
    static let sourcePrefix = "Apple · "
    private let store = EKEventStore()

    static func isApple(_ accountEmail: String) -> Bool { accountEmail.hasPrefix(sourcePrefix) }

    var isAuthorized: Bool { EKEventStore.authorizationStatus(for: .event) == .fullAccess }
    var isDenied: Bool {
        let s = EKEventStore.authorizationStatus(for: .event)
        return s == .denied || s == .restricted
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
                                 calendarAppURL: e.eventIdentifier.flatMap(Self.calendarAppURL))
        }
    }

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
        guard let c, let n = NSColor(cgColor: c)?.usingColorSpace(.sRGB) else { return "#4285F4" }
        return String(format: "#%02X%02X%02X", Int(n.redComponent * 255), Int(n.greenComponent * 255), Int(n.blueComponent * 255))
    }
}
