import Foundation
import SwiftUI
import SK1Tokens
import SK1UI

/// Meeting-first rules (Settings › Events). They decide which events the menu bar title, the popover,
/// the Upcoming dashboard, the join shortcut and Meeting Guardian alerts care about. The calendar grids draw the
/// events they'd hide at `EventFilterSettings.calendarFade` instead.
public struct EventFilterRules: Codable, Equatable {
    public var hideDeclined = true
    public var hideAllDay = false
    public var hideWithoutLink = false
    /// Tentative ("Maybe") events stay visible but are drawn faded.
    public var dimTentative = true
    /// Hide events that have no attendees besides you (focus blocks, reminders, personal holds).
    public var hideSolo = false
    /// Events whose title contains any of these (case- and accent-insensitive) are hidden.
    public var ignoredKeywords: [String] = []

    public init() {}

    enum CodingKeys: String, CodingKey { case hideDeclined, hideAllDay, hideWithoutLink, dimTentative, hideSolo, ignoredKeywords }

    /// Missing keys keep their defaults, so adding a rule never resets someone's saved choices.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        hideDeclined = try c.decodeIfPresent(Bool.self, forKey: .hideDeclined) ?? hideDeclined
        hideAllDay = try c.decodeIfPresent(Bool.self, forKey: .hideAllDay) ?? hideAllDay
        hideWithoutLink = try c.decodeIfPresent(Bool.self, forKey: .hideWithoutLink) ?? hideWithoutLink
        dimTentative = try c.decodeIfPresent(Bool.self, forKey: .dimTentative) ?? dimTentative
        hideSolo = try c.decodeIfPresent(Bool.self, forKey: .hideSolo) ?? hideSolo
        ignoredKeywords = try c.decodeIfPresent([String].self, forKey: .ignoredKeywords) ?? ignoredKeywords
    }

    /// Keywords as typed in Settings: comma separated.
    public var keywordText: String {
        get { ignoredKeywords.joined(separator: ", ") }
        set { ignoredKeywords = newValue.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }
    }
}

/// How one source (a Google account, or an Apple Calendar account) is filtered.
public enum SourceFilterMode: String, Codable, CaseIterable, Identifiable {
    case defaults, custom, showAll
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .defaults: return "Default rules"
        case .custom: return "Custom rules"
        case .showAll: return "Show everything"
        }
    }
}

public struct SourceFilterRule: Codable, Equatable {
    public var mode: SourceFilterMode = .defaults
    public var rules = EventFilterRules()
    public init(mode: SourceFilterMode = .defaults, rules: EventFilterRules = EventFilterRules()) { self.mode = mode; self.rules = rules }
}

public struct EventFilterSettings: Codable, Equatable {
    public var rules = EventFilterRules()
    /// Per-source overrides, keyed by `CalendarEvent.accountEmail` (a Google email or "Apple · <account>").
    public var sources: [String: SourceFilterRule] = [:]
    /// How strongly the Day, Week and Month views draw events the rules hide: 1 draws them like any other, 0 leaves
    /// them out.
    public var calendarFade: Double = 1

    public init() {}

    enum CodingKeys: String, CodingKey { case rules, sources, calendarFade }

    /// Missing keys keep their defaults, so adding a setting never resets someone's saved rules.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        rules = try c.decodeIfPresent(EventFilterRules.self, forKey: .rules) ?? rules
        sources = try c.decodeIfPresent([String: SourceFilterRule].self, forKey: .sources) ?? sources
        calendarFade = min(1, max(0, try c.decodeIfPresent(Double.self, forKey: .calendarFade) ?? calendarFade))
    }

    public static let defaultsKey = "eventFilters"

    /// The rules for events from `source`; nil means nothing from it is hidden or dimmed.
    public func rules(forSource source: String) -> EventFilterRules? {
        guard let o = sources[source] else { return rules }
        switch o.mode {
        case .defaults: return rules
        case .custom: return o.rules
        case .showAll: return nil
        }
    }

    public static func load(_ d: UserDefaults = .standard) -> EventFilterSettings {
        guard let data = d.data(forKey: defaultsKey), let s = try? JSONDecoder().decode(Self.self, from: data) else { return .init() }
        return s
    }

    public func save(_ d: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) { d.set(data, forKey: Self.defaultsKey) }
    }
}

/// Why an event was left out (shown in its tooltip when "show anyway" is on).
public enum EventHideReason: String {
    case declined, allDay, noLink, solo, keyword
    public var label: String {
        switch self {
        case .declined: return "Declined"
        case .allDay: return "All-day"
        case .noLink: return "No join link"
        case .solo: return "Only you"
        case .keyword: return "Ignored keyword"
        }
    }
}

public struct EventFilterResult: Equatable {
    public var shown: [CalendarEvent]
    public var hidden: [CalendarEvent]
}

public enum EventFilter {
    public static func hideReason(_ e: CalendarEvent, rules: EventFilterRules?) -> EventHideReason? {
        guard let r = rules else { return nil }
        if r.hideDeclined && e.isDeclined { return .declined }
        if r.hideAllDay && e.isBarEvent() { return .allDay }
        if r.hideWithoutLink && e.meetURL == nil { return .noLink }
        if r.hideSolo && e.isSolo { return .solo }
        if matchesKeyword(e.title, r.ignoredKeywords) { return .keyword }
        return nil
    }

    public static func hideReason(_ e: CalendarEvent, settings: EventFilterSettings) -> EventHideReason? {
        hideReason(e, rules: settings.rules(forSource: e.accountEmail))
    }

    public static func isDimmed(_ e: CalendarEvent, settings: EventFilterSettings) -> Bool {
        e.isTentative && (settings.rules(forSource: e.accountEmail)?.dimTentative ?? false)
    }

    public static func apply(_ events: [CalendarEvent], settings: EventFilterSettings) -> EventFilterResult {
        var shown: [CalendarEvent] = [], hidden: [CalendarEvent] = []
        for e in events {
            if hideReason(e, settings: settings) == nil { shown.append(e) } else { hidden.append(e) }
        }
        return EventFilterResult(shown: shown, hidden: hidden)
    }

    /// How strongly a calendar grid draws `e`: 1 when no rule hides it, otherwise the Settings fade.
    public static func calendarOpacity(_ e: CalendarEvent, settings: EventFilterSettings) -> Double {
        hideReason(e, settings: settings) == nil ? 1 : settings.calendarFade
    }

    /// The events a calendar grid lays out: all of them, less the hidden ones when the fade is all the way down (so
    /// they don't hold an empty slot).
    public static func calendarEvents(_ events: [CalendarEvent], settings: EventFilterSettings) -> [CalendarEvent] {
        settings.calendarFade > 0 ? events : events.filter { hideReason($0, settings: settings) == nil }
    }

    static func matchesKeyword(_ title: String, _ keywords: [String]) -> Bool {
        keywords.contains { k in
            let k = k.trimmingCharacters(in: .whitespaces)
            return !k.isEmpty && title.range(of: k, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }
}

extension CalendarEvent {
    /// Your own RSVP, when the source reports one.
    public var selfResponse: AttendeeResponse? { participants.first(where: \.isSelf)?.response }
    public var isTentative: Bool { selfResponse == .tentative }

    /// No attendees other than you (meeting rooms and other resources don't count).
    public var isSolo: Bool {
        !participants.contains { !$0.isSelf && !$0.isResource }
    }
}

extension EventAttendee {
    /// Google meeting rooms and other bookable resources.
    public var isResource: Bool { email?.lowercased().hasSuffix("resource.calendar.google.com") ?? false }
}

// MARK: - Environment

private struct EventFilterSettingsKey: EnvironmentKey { static let defaultValue: EventFilterSettings? = nil }

extension EnvironmentValues {
    /// Set by meeting-first views (popover, Upcoming) so rows can fade tentative events.
    var eventFilterSettings: EventFilterSettings? {
        get { self[EventFilterSettingsKey.self] }
        set { self[EventFilterSettingsKey.self] = newValue }
    }
}

private struct CalendarFilterSettingsKey: EnvironmentKey { static let defaultValue: EventFilterSettings? = nil }

extension EnvironmentValues {
    /// Set by the calendar grids (Day, Week, Month) so their events can fade the ones the rules hide.
    var calendarFilterSettings: EventFilterSettings? {
        get { self[CalendarFilterSettingsKey.self] }
        set { self[CalendarFilterSettingsKey.self] = newValue }
    }
}

/// Draws an event at `base` opacity, or fainter when the filters hide it and a calendar grid set the fade.
private struct CalendarFade: ViewModifier {
    let event: CalendarEvent
    let base: Double
    @Environment(\.calendarFilterSettings) private var settings

    func body(content: Content) -> some View {
        content.opacity(min(base, settings.map { EventFilter.calendarOpacity(event, settings: $0) } ?? 1))
    }
}

extension View {
    /// Fades `event` in a calendar grid when the filters hide it; `base` is its opacity otherwise (declined, ended).
    func calendarFade(_ event: CalendarEvent, otherwise base: Double = 1) -> some View {
        modifier(CalendarFade(event: event, base: base))
    }
}

/// The calendar-views fade as a percentage slider (Settings › Events on the Mac and the iPhone).
struct CalendarFadeSlider: View {
    @Binding var fade: Double

    var body: some View {
        HStack(spacing: 8) {
            Slider(value: $fade, in: 0...1, step: 0.05)
                .tint(Color(sk1Hex: SK1.orange))
                .accessibilityLabel("Filtered events in calendar views")
                .accessibilityValue(Self.label(fade))
            Text(Self.label(fade)).font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                .frame(width: 52, alignment: .trailing)
        }
    }

    static func label(_ fade: Double) -> String {
        fade <= 0 ? "Hidden" : fade >= 1 ? "Full" : "\(Int((fade * 100).rounded()))%"
    }
}

/// "3 hidden by filters · Show" under a filtered list.
struct HiddenEventsToggle: View {
    let count: Int
    @Binding var showing: Bool

    var body: some View {
        if count > 0 || showing {
            HStack(spacing: 4) {
                Image(systemName: "line.3.horizontal.decrease.circle")
                Text(showing ? "Showing events hidden by your filters" : "\(count) hidden by your filters")
                Button(showing ? "Hide again" : "Show anyway") { showing.toggle() }.buttonStyle(.sk1Key(size: .small))
            }
            .font(.caption).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .help("Change which events are hidden in Settings › Events")
        }
    }
}
