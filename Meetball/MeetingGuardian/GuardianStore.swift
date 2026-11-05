import Foundation
import SwiftUI

public enum AlertStyle: String, Codable, CaseIterable, Identifiable {
    case soft, headsUp, hard
    public var id: String { rawValue }
    var title: String {
        switch self {
        case .soft: "Soft reminder (system notification)"
        case .headsUp: "Heads-up overlay"
        case .hard: "Hard alert (fullscreen-ish)"
        }
    }
    var detail: String {
        switch self {
        case .soft: "Standard macOS notification in the corner of your screen. Easy to dismiss, good for low-stress reminders."
        case .headsUp: "A small overlay in the center of your screen with a clear Join button. It slightly dims the background but doesn't take over your entire display."
        case .hard: "A large, focused overlay that appears on top of everything with a big Join button. Ideal if you absolutely cannot afford to miss meetings."
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
}

/// Persistence for settings and per-calendar rules.
@MainActor
public final class MeetingGuardianStore: ObservableObject {
    @Published var settings = GuardianSettings() { didSet { save() } }
    @Published public var calendarRules: [CalendarRule] = [] { didSet { save() } }
    /// Events whose alerts the user muted, keyed by event uid, valued by the event's end (pruned once it has passed).
    @Published public private(set) var mutedEvents: [String: Date] = [:] { didSet { save() } }
    private let defaults: UserDefaults
    private var loading = false

    public init(defaults: UserDefaults = .standard) { self.defaults = defaults; load() }

    func load() {
        loading = true; defer { loading = false }
        if let d = defaults.data(forKey: "guardian.settings"), let s = try? JSONDecoder().decode(GuardianSettings.self, from: d) { settings = s }
        if let d = defaults.data(forKey: "guardian.rules"), let r = try? JSONDecoder().decode([CalendarRule].self, from: d) { calendarRules = r }
        if let d = defaults.data(forKey: "guardian.muted"), let m = try? JSONDecoder().decode([String: Date].self, from: d) {
            let now = Date()
            mutedEvents = m.filter { $0.value > now }
        }
    }
    func save() {
        guard !loading else { return }
        if let d = try? JSONEncoder().encode(settings) { defaults.set(d, forKey: "guardian.settings") }
        if let d = try? JSONEncoder().encode(calendarRules) { defaults.set(d, forKey: "guardian.rules") }
        if let d = try? JSONEncoder().encode(mutedEvents) { defaults.set(d, forKey: "guardian.muted") }
    }
    public func isMuted(_ e: CalendarEvent) -> Bool { mutedEvents[e.uid] != nil }
    public func setMuted(_ muted: Bool, for e: CalendarEvent) {
        if muted { mutedEvents[e.uid] = e.end } else { mutedEvents[e.uid] = nil }
    }
    public func rule(for key: String) -> CalendarRule? { calendarRules.first { $0.calendarKey == key } }
    public func upsert(_ rule: CalendarRule) {
        if let i = calendarRules.firstIndex(where: { $0.calendarKey == rule.calendarKey }) { calendarRules[i] = rule } else { calendarRules.append(rule) }
    }
    public func removeRulesNotIn(_ keys: Set<String>) { calendarRules.removeAll { !keys.contains($0.calendarKey) } }
}
