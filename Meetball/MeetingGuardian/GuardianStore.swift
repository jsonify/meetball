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

    init() {}

    enum CodingKeys: String, CodingKey {
        case style, leadMinutes, alsoAtFiveMinutes, playSound, breakThroughFocus, skipWhileScreenSharing, stillJoiningPrompt,
             repeatIfNotJoined, warnBeforeSleep, limitToActiveHours, activeStartHour, activeEndHour, soundName
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
