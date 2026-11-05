import Foundation
import SwiftUI

/// 12- or 24-hour clock, or whatever the system uses (Settings › Appearance).
public enum ClockStyle: String, CaseIterable, Identifiable, Sendable {
    case system, twelveHour, twentyFourHour
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .system: return "System"
        case .twelveHour: return "12-hour"
        case .twentyFourHour: return "24-hour"
        }
    }
}

/// How tightly the calendar views pack their rows (Settings › Appearance).
public enum LayoutDensity: String, CaseIterable, Identifiable, Sendable {
    case comfortable, compact
    public var id: String { rawValue }
    public var title: String { self == .comfortable ? "Comfortable" : "Compact" }
    /// Height of one hour in the day and week grids.
    public var hourHeight: CGFloat { self == .comfortable ? 48 : 34 }
    /// Height of one event lane in the month grid.
    public var monthLaneHeight: CGFloat { self == .comfortable ? 18 : 15 }
    /// Vertical padding around an agenda row.
    public var rowPadding: CGFloat { self == .comfortable ? 2 : 0 }
}

/// App-wide display preferences. Views read them through `@AppStorage` with these keys; code that isn't a view reads
/// them here.
public enum AppPreferences {
    public enum Key {
        /// 0 follows the system; 1 = Sunday … 7 = Saturday.
        public static let firstWeekday = "appearance.firstWeekday"
        public static let clockStyle = "appearance.clockStyle"
        public static let density = "appearance.density"
        public static let highlightWeekends = "appearance.highlightWeekends"
        public static let hideDockIcon = "app.hideDockIcon"
        public static let worldClocks = "menuBar.worldClocks"
        public static let showEventTimeZone = "appearance.showEventTimeZone"
        /// Week numbers in the mini calendar and the month grid (the key predates the Appearance tab).
        public static let weekNumbers = "menuBar.showWeekNumbers"
    }

    public static var defaults: UserDefaults { .standard }

    public static func firstWeekday(_ d: UserDefaults = defaults) -> Int { d.integer(forKey: Key.firstWeekday) }
    public static func clockStyle(_ d: UserDefaults = defaults) -> ClockStyle {
        ClockStyle(rawValue: d.string(forKey: Key.clockStyle) ?? "") ?? .system
    }
    public static func density(_ d: UserDefaults = defaults) -> LayoutDensity {
        LayoutDensity(rawValue: d.string(forKey: Key.density) ?? "") ?? .comfortable
    }

    /// The user's calendar with the first weekday from Settings, when one is chosen.
    public static func calendar(firstWeekday: Int, base: Calendar = .current) -> Calendar {
        var c = base
        if (1...7).contains(firstWeekday) { c.firstWeekday = firstWeekday }
        return c
    }

    /// The user's locale with the hour cycle from Settings, when one is chosen.
    public static func locale(clock: ClockStyle, base: Locale = .current) -> Locale {
        guard clock != .system else { return base }
        var parts = Locale.Components(locale: base)
        parts.hourCycle = clock == .twelveHour ? .oneToTwelve : .zeroToTwentyThree
        return Locale(components: parts)
    }

    public static var locale: Locale { locale(clock: clockStyle()) }
}

extension Calendar {
    /// The calendar every view and builder uses: the system's, with the first weekday from Settings › Appearance.
    public static var app: Calendar { AppPreferences.calendar(firstWeekday: AppPreferences.firstWeekday()) }
}

extension Date {
    /// "9:30 AM" or "09:30", following Settings › Appearance › Clock.
    public var shortTime: String { shortTime(locale: AppPreferences.locale) }

    public func shortTime(locale: Locale, timeZone: TimeZone = .current) -> String {
        formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: locale, timeZone: timeZone))
    }

    /// "9 AM" or "09", for the hour gutter.
    public var hourText: String { formatted(Date.FormatStyle.dateTime.hour().locale(AppPreferences.locale)) }
}
