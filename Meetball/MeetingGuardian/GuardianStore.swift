import Foundation
import SwiftUI

public enum AlertStyle: String, Codable, CaseIterable, Identifiable {
    case soft, headsUp, hard
    public var id: String { rawValue }
    var title: String {
        switch self {
        case .soft: "Soft reminder (system notification)"
        case .headsUp: "Heads-up overlay"
        case .hard: "Hard alert (full screen)"
        }
    }
    /// Short name for compact UI ("Heads-up").
    var shortTitle: String {
        switch self {
        case .soft: "Soft"
        case .headsUp: "Heads-up"
        case .hard: "Hard"
        }
    }
    var symbol: String {
        switch self {
        case .soft: "bell"
        case .headsUp: "rectangle.inset.topright.filled"
        case .hard: "rectangle.inset.filled"
        }
    }
    var detail: String {
        switch self {
        case .soft: "Standard macOS notification in the corner of your screen. Easy to dismiss, good for low-stress reminders."
        case .headsUp: "A card slides in at the top right with a live countdown, Join, Snooze and Dismiss. It never takes focus from what you're doing."
        case .hard: "Covers every display with a large countdown, the meeting's details and a big Join button. Ideal if you absolutely cannot afford to miss meetings."
        }
    }
    var isPro: Bool { self != .soft }
}

public struct TimingOption: Identifiable, Hashable {
    public let minutes: Int
    public var id: Int { minutes }
    public var isPro: Bool { minutes != 1 && minutes != 5 }
    public var title: String { minutes == 0 ? "At start time" : "\(minutes) minute\(minutes == 1 ? "" : "s") before" }
    public static let all = [0, 1, 2, 5, 10, 15].map(TimingOption.init)
}

public struct CalendarRule: Codable, Hashable {
    public var calendarKey: String
    public var style: AlertStyle?      // nil = no Meeting Guardian actions for this calendar
}

public struct GuardianSettings: Codable, Equatable {
    var style: AlertStyle = .soft
    var leadMinutes: Int = 1
    var alsoAtFiveMinutes = false
    var playSound = true
    var breakThroughFocus = false
    var skipWhileScreenSharing = true
    var stillJoiningPrompt = true          // "Are you still joining?" 2 min after start
    var repeatIfNotJoined = false
    var warnBeforeSleep = true
    var limitToActiveHours = false
    var activeStartHour = 8
    var activeEndHour = 19
    /// System sound played with hard alerts (a name from /System/Library/Sounds).
    var soundName = AlertSound.defaultName
    /// Notify when an upcoming meeting is moved, gets a new link, or is cancelled (#30).
    var notifyChanges = true
    /// Confetti when a meeting is cancelled.
    var celebrateCancellations = true
    /// Also show an on-screen card for meeting changes that stays until it's dismissed.
    var changeCard = true
    /// Minutes after the start that auto-join opens a meeting nobody joined yet (#24); 0 = at the start.
    var autoJoinDelayMinutes = 1
    /// Recurring meetings auto-join unless their series is turned off (#53).
    var autoJoinRecurring = false

    init() {}

    enum CodingKeys: String, CodingKey {
        case style, leadMinutes, alsoAtFiveMinutes, playSound, breakThroughFocus, skipWhileScreenSharing, stillJoiningPrompt,
             repeatIfNotJoined, warnBeforeSleep, limitToActiveHours, activeStartHour, activeEndHour, soundName,
             notifyChanges, celebrateCancellations, changeCard, autoJoinDelayMinutes, autoJoinRecurring
    }

    /// Missing keys keep their defaults, so adding a setting never resets the saved ones.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func v<T: Decodable>(_ k: CodingKeys, _ d: T) throws -> T { try c.decodeIfPresent(T.self, forKey: k) ?? d }
        style = try v(.style, style)
        leadMinutes = try v(.leadMinutes, leadMinutes)
        alsoAtFiveMinutes = try v(.alsoAtFiveMinutes, alsoAtFiveMinutes)
        playSound = try v(.playSound, playSound)
        breakThroughFocus = try v(.breakThroughFocus, breakThroughFocus)
        skipWhileScreenSharing = try v(.skipWhileScreenSharing, skipWhileScreenSharing)
        stillJoiningPrompt = try v(.stillJoiningPrompt, stillJoiningPrompt)
        repeatIfNotJoined = try v(.repeatIfNotJoined, repeatIfNotJoined)
        warnBeforeSleep = try v(.warnBeforeSleep, warnBeforeSleep)
        limitToActiveHours = try v(.limitToActiveHours, limitToActiveHours)
        activeStartHour = try v(.activeStartHour, activeStartHour)
        activeEndHour = try v(.activeEndHour, activeEndHour)
        soundName = try v(.soundName, soundName)
        notifyChanges = try v(.notifyChanges, notifyChanges)
        celebrateCancellations = try v(.celebrateCancellations, celebrateCancellations)
        changeCard = try v(.changeCard, changeCard)
        autoJoinDelayMinutes = try v(.autoJoinDelayMinutes, autoJoinDelayMinutes)
        autoJoinRecurring = try v(.autoJoinRecurring, autoJoinRecurring)
    }
}

/// System alert sounds offered for hard alerts.
public enum AlertSound {
    public static let defaultName = "Sosumi"

    /// Names of the sounds in /System/Library/Sounds, sorted.
    public static var available: [String] {
        let dir = URL(fileURLWithPath: "/System/Library/Sounds")
        let names = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil))?
            .filter { ["aiff", "aif", "caf", "wav"].contains($0.pathExtension.lowercased()) }
            .map { $0.deletingPathExtension().lastPathComponent } ?? []
        return names.isEmpty ? [defaultName] : names.sorted()
    }
}

/// Persistence for settings and per-calendar rules.
@MainActor
public final class MeetingGuardianStore: ObservableObject {
    @Published var settings = GuardianSettings() { didSet { save() } }
    @Published public var calendarRules: [CalendarRule] = [] { didSet { save() } }
    /// Checked top to bottom; the first enabled match sets the alert intensity.
    @Published public var importanceRules: [ImportanceRule] = [] { didSet { save() } }
    /// Events whose alerts the user muted, keyed by event uid, valued by the event's end (pruned once it has passed).
    @Published public private(set) var mutedEvents: [String: Date] = [:] { didSet { save() } }
    /// Events on a calendar set to Off that the user wants alerts for anyway, keyed by event uid, valued by the event's
    /// end (pruned once it has passed).
    @Published public private(set) var alertOnEvents: [String: Date] = [:] { didSet { save() } }
    /// Single meetings set to auto-join, keyed by event uid, valued by the event's end (pruned once it has passed).
    @Published public private(set) var autoJoinEvents: [String: Date] = [:] { didSet { save() } }
    /// Recurring series set to auto-join, keyed by `AutoJoin.seriesKey`.
    @Published public private(set) var autoJoinSeries: Set<String> = [] { didSet { save() } }
    /// Recurring series turned off while "Auto-join recurring meetings" is on (#53), keyed by `AutoJoin.seriesKey`.
    @Published public private(set) var autoJoinSeriesOff: Set<String> = [] { didSet { save() } }
    private let defaults: UserDefaults
    private var loading = false

    public init(defaults: UserDefaults = .standard) { self.defaults = defaults; load() }

    func load() {
        loading = true; defer { loading = false }
        if let d = defaults.data(forKey: "guardian.settings"), let s = try? JSONDecoder().decode(GuardianSettings.self, from: d) { settings = s }
        if let d = defaults.data(forKey: "guardian.rules"), let r = try? JSONDecoder().decode([CalendarRule].self, from: d) { calendarRules = r }
        if let d = defaults.data(forKey: "guardian.importance"), let r = try? JSONDecoder().decode([ImportanceRule].self, from: d) { importanceRules = r }
        if let d = defaults.data(forKey: "guardian.muted"), let m = try? JSONDecoder().decode([String: Date].self, from: d) {
            let now = Date()
            mutedEvents = m.filter { $0.value > now }
        }
        if let d = defaults.data(forKey: "guardian.alertOn"), let m = try? JSONDecoder().decode([String: Date].self, from: d) {
            let now = Date()
            alertOnEvents = m.filter { $0.value > now }
        }
        if let d = defaults.data(forKey: "guardian.autoJoin"), let m = try? JSONDecoder().decode([String: Date].self, from: d) {
            let now = Date()
            autoJoinEvents = m.filter { $0.value > now }
        }
        if let d = defaults.data(forKey: "guardian.autoJoinSeries"), let s = try? JSONDecoder().decode(Set<String>.self, from: d) {
            autoJoinSeries = s
        }
        if let d = defaults.data(forKey: "guardian.autoJoinSeriesOff"), let s = try? JSONDecoder().decode(Set<String>.self, from: d) {
            autoJoinSeriesOff = s
        }
    }
    func save() {
        guard !loading else { return }
        if let d = try? JSONEncoder().encode(settings) { defaults.set(d, forKey: "guardian.settings") }
        if let d = try? JSONEncoder().encode(calendarRules) { defaults.set(d, forKey: "guardian.rules") }
        if let d = try? JSONEncoder().encode(importanceRules) { defaults.set(d, forKey: "guardian.importance") }
        if let d = try? JSONEncoder().encode(mutedEvents) { defaults.set(d, forKey: "guardian.muted") }
        if let d = try? JSONEncoder().encode(alertOnEvents) { defaults.set(d, forKey: "guardian.alertOn") }
        if let d = try? JSONEncoder().encode(autoJoinEvents) { defaults.set(d, forKey: "guardian.autoJoin") }
        if let d = try? JSONEncoder().encode(autoJoinSeries) { defaults.set(d, forKey: "guardian.autoJoinSeries") }
        if let d = try? JSONEncoder().encode(autoJoinSeriesOff) { defaults.set(d, forKey: "guardian.autoJoinSeriesOff") }
    }

    /// Whether auto-join is on for `e`, and for just this meeting or its whole series. With "Auto-join recurring
    /// meetings" on (#53), every recurring meeting counts as on for its series unless that series was turned off.
    public func autoJoinScope(for e: CalendarEvent) -> AutoJoinScope? {
        if autoJoinEvents[e.uid] != nil { return .occurrence }
        guard let key = AutoJoin.seriesKey(e) else { return nil }
        if autoJoinSeries.contains(key) { return .series }
        return settings.autoJoinRecurring && !autoJoinSeriesOff.contains(key) ? .series : nil
    }
    public func isAutoJoin(_ e: CalendarEvent) -> Bool { autoJoinScope(for: e) != nil }
    /// True when `e` auto-joins only because recurring meetings auto-join by default.
    public func isAutoJoinByDefault(_ e: CalendarEvent) -> Bool {
        guard autoJoinScope(for: e) == .series, let key = AutoJoin.seriesKey(e) else { return false }
        return !autoJoinSeries.contains(key)
    }
    /// nil turns auto-join off for this meeting and (if set) its series. Choosing just this one turns the rest of
    /// its series off too, even when recurring meetings auto-join by default.
    public func setAutoJoin(_ scope: AutoJoinScope?, for e: CalendarEvent) {
        let series = AutoJoin.seriesKey(e)
        switch scope {
        case .occurrence?:
            if let series { autoJoinSeries.remove(series); autoJoinSeriesOff.insert(series) }
            autoJoinEvents[e.uid] = e.end
        case .series?:
            guard let series else { autoJoinEvents[e.uid] = e.end; return }
            autoJoinEvents[e.uid] = nil
            autoJoinSeriesOff.remove(series)
            autoJoinSeries.insert(series)
        case nil:
            if let series { autoJoinSeries.remove(series); autoJoinSeriesOff.insert(series) }
            autoJoinEvents[e.uid] = nil
        }
    }
    public func isMuted(_ e: CalendarEvent) -> Bool { mutedEvents[e.uid] != nil }
    public func setMuted(_ muted: Bool, for e: CalendarEvent) {
        if muted { mutedEvents[e.uid] = e.end; alertOnEvents[e.uid] = nil } else { mutedEvents[e.uid] = nil }
    }
    /// True when the user asked for alerts on this event although its calendar is set to Off.
    public func isAlertOn(_ e: CalendarEvent) -> Bool { alertOnEvents[e.uid] != nil }
    public func setAlertOn(_ on: Bool, for e: CalendarEvent) {
        if on { alertOnEvents[e.uid] = e.end; mutedEvents[e.uid] = nil } else { alertOnEvents[e.uid] = nil }
    }
    /// True when `e`'s calendar is set to Off.
    public func isCalendarSilenced(_ e: CalendarEvent) -> Bool { rule(for: e.calendarKey).map { $0.style == nil } ?? false }
    public func rule(for key: String) -> CalendarRule? { calendarRules.first { $0.calendarKey == key } }
    public func upsert(_ rule: CalendarRule) {
        if let i = calendarRules.firstIndex(where: { $0.calendarKey == rule.calendarKey }) { calendarRules[i] = rule } else { calendarRules.append(rule) }
    }
    /// Sets a calendar's intensity; nil returns it to the default style.
    public func setIntensity(_ intensity: AlertIntensity?, for calendarKey: String) {
        if let intensity { upsert(CalendarRule(calendarKey: calendarKey, style: intensity.style)) }
        else { calendarRules.removeAll { $0.calendarKey == calendarKey } }
    }
    public func intensity(for calendarKey: String) -> AlertIntensity? { rule(for: calendarKey).map { AlertIntensity($0.style) } }
    public func removeRulesNotIn(_ keys: Set<String>) { calendarRules.removeAll { !keys.contains($0.calendarKey) } }
}
