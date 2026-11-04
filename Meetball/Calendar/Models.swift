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
    public var uid: String { "\(accountEmail)|\(calendarID)|\(id)" }
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
