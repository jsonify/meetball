import AppKit
import SwiftUI

/// What the menu bar item shows next to its icon.
public enum MenuBarTitleFormat: String, CaseIterable, Identifiable {
    case countdown, titleCountdown, titleStartTime, iconOnly
    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .countdown: return "Countdown"
        case .titleCountdown: return "Title · Countdown"
        case .titleStartTime: return "Title · Start time"
        case .iconOnly: return "Icon only"
        }
    }

    public var example: String {
        switch self {
        case .countdown: return "12m"
        case .titleCountdown: return "Design review · in 12m"
        case .titleStartTime: return "Design review · 2:30 PM"
        case .iconOnly: return ""
        }
    }
}

/// Menu bar preferences (Settings › Menu Bar). Stored in UserDefaults under `menuBar.*`.
public struct MenuBarTitleSettings: Equatable {
    public var format: MenuBarTitleFormat = .countdown
    public var maxTitleLength = 24
    public var showServiceIcon = true
    /// Only show text when the next meeting starts within this many hours; 0 = always.
    public var hideBeyondHours = 0
    public var pulseWhenSoon = true

    enum Key {
        static let format = "menuBar.format"
        static let maxTitleLength = "menuBar.maxTitleLength"
        static let showServiceIcon = "menuBar.showServiceIcon"
        static let hideBeyondHours = "menuBar.hideBeyondHours"
        static let pulseWhenSoon = "menuBar.pulseWhenSoon"
        /// Pre-format toggle; `false` maps to `.iconOnly` until a format is chosen.
        static let legacyShowCountdown = "showCountdownInMenuBar"
    }

    public static let titleLengthRange = 8...60

    public init() {}

    public init(defaults: UserDefaults) {
        if let raw = defaults.string(forKey: Key.format), let f = MenuBarTitleFormat(rawValue: raw) {
            format = f
        } else if defaults.object(forKey: Key.legacyShowCountdown) as? Bool == false {
            format = .iconOnly
        }
        if let n = defaults.object(forKey: Key.maxTitleLength) as? Int {
            maxTitleLength = min(max(n, Self.titleLengthRange.lowerBound), Self.titleLengthRange.upperBound)
        }
        showServiceIcon = defaults.object(forKey: Key.showServiceIcon) as? Bool ?? true
        hideBeyondHours = max(0, defaults.object(forKey: Key.hideBeyondHours) as? Int ?? 0)
        pulseWhenSoon = defaults.object(forKey: Key.pulseWhenSoon) as? Bool ?? true
    }
}

/// The computed menu bar label.
public struct MenuBarTitle: Equatable {
    public var text: String
    public var symbol: String
    /// The next meeting starts within `MenuBarTitleBuilder.soonWindow`.
    public var isSoon: Bool
    public var inProgress: Bool

    public static let idle = MenuBarTitle(text: "", symbol: MenuBarTitleBuilder.defaultSymbol, isSoon: false, inProgress: false)
}

public enum MenuBarTitleBuilder {
    public static let defaultSymbol = "calendar"
    public static let soonWindow: TimeInterval = 5 * 60

    /// The meeting the menu bar talks about: the one in progress, else the next one (any distance ahead).
    public static func pick(_ events: [CalendarEvent], now: Date) -> CalendarEvent? {
        MenuAgendaBuilder.hero(events, now: now, horizon: .greatestFiniteMagnitude)
    }

    public static func build(next: CalendarEvent?, now: Date, settings: MenuBarTitleSettings,
                             calendar: Calendar = .current) -> MenuBarTitle {
        guard let e = next, e.end > now else { return .idle }
        let inProgress = e.start <= now
        let until = e.start.timeIntervalSince(now)
        if !inProgress, settings.hideBeyondHours > 0, until > Double(settings.hideBeyondHours) * 3600 { return .idle }

        var symbol = defaultSymbol
        if settings.showServiceIcon, let url = e.meetURL {
            let service = MeetingService.detect(url)
            if service != .other { symbol = service.symbol }
        }
        let title = truncate(e.title, to: settings.maxTitleLength)
        let left = "\(TimeUntilFormatter.string(until: e.end, now: now)) left"
        let countdown = TimeUntilFormatter.string(until: e.start, now: now)
        let text: String
        switch settings.format {
        case .countdown:
            text = inProgress ? "now · \(left)" : countdown
        case .titleCountdown:
            text = inProgress ? "\(title) · \(left)" : "\(title) · in \(countdown)"
        case .titleStartTime:
            text = inProgress ? "\(title) · now" : "\(title) · \(startText(e.start, now: now, calendar: calendar))"
        case .iconOnly:
            text = ""
        }
        return MenuBarTitle(text: text, symbol: symbol, isSoon: !inProgress && until <= soonWindow, inProgress: inProgress)
    }

    /// Trims whitespace and cuts to `max` characters (including the trailing "…").
    public static func truncate(_ s: String, to max: Int) -> String {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard max > 1, t.count > max else { return t }
        return String(t.prefix(max - 1)).trimmingCharacters(in: .whitespaces) + "…"
    }

    /// "2:30 PM" today, "Tue 9:00 AM" on another day.
    static func startText(_ d: Date, now: Date, calendar: Calendar) -> String {
        let time = d.formatted(date: .omitted, time: .shortened)
        if calendar.isDate(d, inSameDayAs: now) { return time }
        return "\(d.formatted(.dateTime.weekday(.abbreviated))) \(time)"
    }
}

/// The view inside `MenuBarExtra`'s label.
struct MenuBarLabelView: View {
    let title: MenuBarTitle
    /// Tinted phase of the "starting soon" pulse.
    let highlighted: Bool

    var body: some View {
        Image(nsImage: MenuBarIcon.image(symbol: title.symbol, tint: highlighted ? .systemOrange : nil))
        if !title.text.isEmpty { Text(title.text) }
    }
}

enum MenuBarIcon {
    /// A template image normally; a palette-coloured, non-template one when tinted (the menu bar keeps its colour).
    static func image(symbol: String, tint: NSColor?) -> NSImage {
        let base = NSImage(systemSymbolName: symbol, accessibilityDescription: "Meetball")
            ?? NSImage(systemSymbolName: MenuBarTitleBuilder.defaultSymbol, accessibilityDescription: "Meetball")
            ?? NSImage()
        guard let tint else { base.isTemplate = true; return base }
        let tinted = base.withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors: [tint])) ?? base
        tinted.isTemplate = false
        return tinted
    }
}
