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
    public var uid: String { "\(accountEmail)|\(calendarID)|\(id)" }
    public var calendarKey: String { "\(accountEmail)|\(calendarID)" }

    /// All-day or multi-day events render as bars (month grid, all-day row) rather than timed blocks.
    public func isBarEvent(calendar: Calendar = .current) -> Bool {
        isAllDay || end.timeIntervalSince(start) >= 86400 || !calendar.isDate(start, inSameDayAs: end.addingTimeInterval(-1))
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
