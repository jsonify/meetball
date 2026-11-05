import Foundation

/// How strongly Meeting Guardian interrupts for a calendar or a rule.
public enum AlertIntensity: String, Codable, CaseIterable, Identifiable {
    case off, soft, headsUp, hard
    public var id: String { rawValue }
    public var style: AlertStyle? {
        switch self {
        case .off: return nil
        case .soft: return .soft
        case .headsUp: return .headsUp
        case .hard: return .hard
        }
    }
    public init(_ style: AlertStyle?) {
        switch style {
        case nil: self = .off
        case .soft: self = .soft
        case .headsUp: self = .headsUp
        case .hard: self = .hard
        }
    }
    public var title: String { style?.shortTitle ?? "Off" }
}

/// What makes a meeting important.
public enum ImportanceKind: String, Codable, CaseIterable, Identifiable {
    case externalAttendees, organizerIsMe, titleContains, recurringDaily
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .externalAttendees: return "Has external attendees"
        case .organizerIsMe: return "I'm the organiser"
        case .titleContains: return "Title contains"
        case .recurringDaily: return "Repeats daily"
        }
    }
    /// Intensity a new rule of this kind starts with.
    public var suggested: AlertIntensity {
        switch self {
        case .externalAttendees: return .hard
        case .organizerIsMe: return .headsUp
        case .titleContains: return .hard
        case .recurringDaily: return .soft
        }
    }
}

public struct ImportanceRule: Codable, Hashable, Identifiable {
    public var id = UUID()
    public var kind: ImportanceKind
    /// Comma-separated words for `.titleContains`.
    public var text = ""
    public var intensity: AlertIntensity
    public var enabled = true

    public init(kind: ImportanceKind, text: String = "", intensity: AlertIntensity? = nil, enabled: Bool = true) {
        self.kind = kind; self.text = text; self.intensity = intensity ?? kind.suggested; self.enabled = enabled
    }

    public func matches(_ e: CalendarEvent) -> Bool {
        switch kind {
        case .externalAttendees: return e.hasExternalAttendees
        case .organizerIsMe: return e.organizerIsSelf
        case .titleContains: return EventFilter.matchesKeyword(e.title, text.split(separator: ",").map(String.init))
        case .recurringDaily: return e.recurrence == .daily
        }
    }

    /// "Has external attendees → Hard"
    public var summary: String {
        let cond = kind == .titleContains ? "Title contains \u{201C}\(text)\u{201D}" : kind.title
        return "\(cond) → \(intensity.title)"
    }
}

extension CalendarEvent {
    /// Someone invited whose email domain differs from yours (rooms and resources don't count).
    public var hasExternalAttendees: Bool {
        let selfEmail = participants.first(where: \.isSelf)?.email ?? (accountEmail.contains("@") ? accountEmail : nil)
        guard let mine = selfEmail.flatMap(Self.domain) else { return false }
        return participants.contains { p in
            guard !p.isSelf, !p.isResource, let d = p.email.flatMap(Self.domain) else { return false }
            return d != mine && !d.hasSuffix("calendar.google.com")
        }
    }

    static func domain(_ email: String) -> String? {
        guard let at = email.lastIndex(of: "@") else { return nil }
        let d = email[email.index(after: at)...].lowercased()
        return d.isEmpty ? nil : d
    }
}

/// Decides the alert style for an event. Order:
/// 1. Free plan: soft reminders only.
/// 2. A calendar set to Off never alerts.
/// 3. The first enabled importance rule that matches.
/// 4. The calendar's intensity, else the default style.
public struct AlertPolicy {
    public var defaultStyle: AlertStyle
    public var calendarRules: [CalendarRule]
    public var importanceRules: [ImportanceRule]
    public var isPro: Bool

    public func matchingRule(for e: CalendarEvent) -> ImportanceRule? {
        importanceRules.first { $0.enabled && $0.matches(e) }
    }

    /// nil means no alert.
    public func style(for e: CalendarEvent) -> AlertStyle? {
        guard isPro else { return .soft }
        let cal = calendarRules.first { $0.calendarKey == e.calendarKey }
        if let cal, cal.style == nil { return nil }
        if let rule = matchingRule(for: e) { return rule.intensity.style }
        return cal?.style ?? defaultStyle
    }

    /// Why `style(for:)` chose what it did, for the live summary.
    public func reason(for e: CalendarEvent) -> String? {
        guard isPro else { return nil }
        if let rule = matchingRule(for: e) { return rule.kind == .titleContains ? "title rule" : rule.kind.title.lowercased() }
        if calendarRules.contains(where: { $0.calendarKey == e.calendarKey }) { return "calendar setting" }
        return nil
    }
}
