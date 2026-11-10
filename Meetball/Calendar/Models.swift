import Foundation
import SwiftUI

public struct GCalendar: Identifiable, Codable, Hashable {
    public var id: String
    public var accountEmail: String
    public var summary: String
    public var colorHex: String
    public var accessRole: String
    public var isPrimary: Bool
    public var allowsMeet: Bool
    public var canWrite: Bool { accessRole == "owner" || accessRole == "writer" }
    public var key: String { "\(accountEmail)|\(id)" }
}

public struct CalendarEvent: Identifiable, Hashable {
    public var id: String
    public var calendarID: String
    public var accountEmail: String
    public var title: String
    public var start: Date
    public var end: Date
    public var isAllDay: Bool
    public var meetURL: URL?
    public var location: String?
    public var attendees: [String]
    public var htmlLink: URL?
    public var colorHex: String = "#4285F4"
    /// The signed-in user declined this event.
    public var isDeclined: Bool = false
    /// Description / notes as provided by the source (Google descriptions may contain HTML).
    public var notes: String? = nil
    /// Organizer's display name or email.
    public var organizer: String? = nil
    /// Attendees with their RSVP state (richer than `attendees`, which only holds emails).
    public var participants: [EventAttendee] = []
    /// Deep link that opens the event in Calendar.app (Apple Calendar events only).
    public var calendarAppURL: URL? = nil
    /// You organise this event (or it's your own event with no one invited).
    public var organizerIsSelf = false
    /// Shared by every instance of a recurring event (Google `recurringEventId`, EventKit item id).
    public var seriesID: String? = nil
    public var recurrence: EventRecurrence = .none
    /// The time zone the event was set in (Google `start.timeZone`, EventKit `timeZone`); nil for floating events.
    public var timeZoneID: String? = nil
    /// The source's own id for the event: the iCalendar UID (EventKit `calendarItemExternalIdentifier`). Google's feeds
    /// write `<eventId>@google.com`, which is how a read-only work feed's events find their Google edit page.
    public var externalID: String? = nil
    /// The organizer's email, when the source gives one.
    public var organizerEmail: String? = nil
    /// A recurring occurrence's original start (EventKit `occurrenceDate`), which still names the instance after it moved.
    public var occurrenceDate: Date? = nil
    /// The place's coordinates when the source has them (an EventKit structured location, as Calendar saves for a place
    /// picked from its map), so drive times needn't look the address up.
    public var locationLatitude: Double? = nil
    public var locationLongitude: Double? = nil
    public var uid: String { "\(accountEmail)|\(calendarID)|\(id)" }
    public var calendarKey: String { "\(accountEmail)|\(calendarID)" }

    /// The event's own time zone when it isn't `local` and the event has a clock time.
    public func foreignTimeZone(local: TimeZone = .current, at date: Date? = nil) -> TimeZone? {
        guard !isAllDay, let id = timeZoneID, let tz = TimeZone(identifier: id) else { return nil }
        let when = date ?? start
        return tz.secondsFromGMT(for: when) == local.secondsFromGMT(for: when) ? nil : tz
    }

    /// All-day events and those a day long or more render as bars (month grid, all-day row) rather than timed blocks.
    /// A shorter timed event that runs past midnight (11:43 PM – 12:13 AM) stays a timed block, split across the two
    /// days' columns, so it shows at its time instead of hiding in the all-day strip.
    public func isBarEvent(calendar: Calendar = .app) -> Bool {
        isAllDay || end.timeIntervalSince(start) >= 86400
    }

    /// You're on the guest list (not the organizer), so you can say whether you're going.
    public var canRespond: Bool { !organizerIsSelf && participants.contains { $0.isSelf && !$0.isOrganizer } }

    /// This event as it reads once you've answered `response`: your guest entry and the declined flag change.
    public func responding(_ response: AttendeeResponse) -> CalendarEvent {
        var e = self
        e.participants = participants.map { p in
            guard p.isSelf else { return p }
            var p = p; p.response = response; return p
        }
        e.isDeclined = response == .declined
        return e
    }
}

public enum EventRecurrence: String, Hashable, Codable {
    case none, daily, weekly, other
    public var isRecurring: Bool { self != .none }
}

public enum AttendeeResponse: String, Hashable {
    case accepted, declined, tentative, needsAction

    var symbol: String {
        switch self {
        case .accepted: return "checkmark.circle.fill"
        case .declined: return "xmark.circle.fill"
        case .tentative: return "questionmark.circle.fill"
        case .needsAction: return "circle.dashed"
        }
    }

    var label: String {
        switch self {
        case .accepted: return "Accepted"
        case .declined: return "Declined"
        case .tentative: return "Maybe"
        case .needsAction: return "Awaiting response"
        }
    }

    /// Confirms a reply you just sent.
    var replyToast: String {
        switch self {
        case .accepted: return "You\u{2019}re going"
        case .declined: return "You\u{2019}re not going"
        case .tentative: return "Replied maybe"
        case .needsAction: return "Reply cleared"
        }
    }
}

public struct EventAttendee: Hashable {
    public var email: String?
    public var name: String?
    public var response: AttendeeResponse = .needsAction
    public var isOrganizer = false
    public var isSelf = false

    public var displayName: String {
        if let n = name?.trimmingCharacters(in: .whitespaces), !n.isEmpty { return n }
        return email ?? "Unknown"
    }

    /// One or two letters for an avatar: "Ada Lovelace" → "AL", "ada.lovelace@x.com" → "AL", "bob@x.com" → "B".
    public var initials: String {
        var base = displayName
        if name?.isEmpty ?? true, let at = base.firstIndex(of: "@") { base = String(base[..<at]) }
        let words = base.split(whereSeparator: { " ._-".contains($0) }).filter { $0.first?.isLetter ?? false }
        let letters = words.prefix(2).compactMap(\.first).map { String($0).uppercased() }
        return letters.isEmpty ? String(base.prefix(1)).uppercased() : letters.joined()
    }
}

public struct NewEventDraft {
    public var title = ""
    public var start: Date
    public var end: Date
    public var calendar: GCalendar?
    public var addMeet = false
    public var attendees: [String] = []
    public var isFocusBlock = false
}

extension Color {
    init(hex: String) {
        var s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        var v: UInt64 = 0; Scanner(string: s).scanHexInt64(&v)
        self.init(red: Double((v >> 16) & 255) / 255, green: Double((v >> 8) & 255) / 255, blue: Double(v & 255) / 255)
    }
}

enum EmailValidator {
    static func isValid(_ s: String) -> Bool {
        s.range(of: #"^[^\s@]+@[^\s@]+\.[^\s@]+$"#, options: .regularExpression) != nil
    }
}
