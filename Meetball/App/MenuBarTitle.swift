import AppKit
import SwiftUI
import SK1Tokens
import SK1UI

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

/// How the menu bar item is drawn (#26).
public enum MenuBarStyle: String, CaseIterable, Identifiable {
    /// The system's own icon and text.
    case plain
    /// A small olive SK-1 LCD with the countdown (and the day and date) in its ink.
    case lcd
    public var id: String { rawValue }
    public var title: String { self == .plain ? "Plain" : "LCD" }
}

/// Menu bar preferences (Settings › Menu Bar). Stored in UserDefaults under `menuBar.*`.
public struct MenuBarTitleSettings: Equatable {
    public var format: MenuBarTitleFormat = .countdown
    public var maxTitleLength = 24
    public var showServiceIcon = true
    /// Only show text when the next meeting starts within this many hours; 0 = always.
    public var hideBeyondHours = 0
    public var pulseWhenSoon = true
    public var style: MenuBarStyle = .plain
    /// Show the day and date ("Thu, Nov 5") before the countdown.
    public var showDate = false

    enum Key {
        static let format = "menuBar.format"
        static let maxTitleLength = "menuBar.maxTitleLength"
        static let showServiceIcon = "menuBar.showServiceIcon"
        static let hideBeyondHours = "menuBar.hideBeyondHours"
        static let pulseWhenSoon = "menuBar.pulseWhenSoon"
        static let style = "menuBar.style"
        static let showDate = "menuBar.showDate"
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
        style = defaults.string(forKey: Key.style).flatMap(MenuBarStyle.init(rawValue:)) ?? .plain
        showDate = defaults.object(forKey: Key.showDate) as? Bool ?? false
    }
}

/// The computed menu bar label.
public struct MenuBarTitle: Equatable {
    public var text: String
    public var symbol: String
    /// The next meeting starts within `MenuBarTitleBuilder.soonWindow`.
    public var isSoon: Bool
    public var inProgress: Bool
    /// The day and date, when Settings › Menu Bar shows it.
    public var date: String? = nil

    public static let idle = MenuBarTitle(text: "", symbol: MenuBarTitleBuilder.defaultSymbol, isSoon: false, inProgress: false)

    /// Everything as one line for the plain style: "Thu, Nov 5 · 12m".
    public var plainText: String { [date, text.isEmpty ? nil : text].compactMap { $0 }.joined(separator: "  ") }
}

public enum MenuBarTitleBuilder {
    public static let defaultSymbol = "calendar"
    public static let soonWindow: TimeInterval = 5 * 60

    /// The meeting the menu bar talks about: the one in progress, else the next one (any distance ahead).
    public static func pick(_ events: [CalendarEvent], now: Date) -> CalendarEvent? {
        MenuAgendaBuilder.hero(events, now: now, horizon: .greatestFiniteMagnitude)
    }

    /// `overlapCount` is how many other meetings overlap `next`; the title shows it as "+1" so a clash isn't hidden.
    public static func build(next: CalendarEvent?, overlapCount: Int = 0, now: Date, settings: MenuBarTitleSettings,
                             calendar: Calendar = .app, locale: Locale = .current) -> MenuBarTitle {
        var title = meetingTitle(next: next, overlapCount: overlapCount, now: now, settings: settings, calendar: calendar)
        if settings.showDate { title.date = dateText(now, calendar: calendar, locale: locale) }
        return title
    }

    /// "Thu, Nov 5" in the user's locale and calendar.
    public static func dateText(_ now: Date, calendar: Calendar = .app, locale: Locale = .current) -> String {
        let f = DateFormatter()
        f.calendar = calendar; f.timeZone = calendar.timeZone; f.locale = locale
        f.setLocalizedDateFormatFromTemplate("EEEMMMd")
        return f.string(from: now)
    }

    private static func meetingTitle(next: CalendarEvent?, overlapCount: Int, now: Date, settings: MenuBarTitleSettings,
                                     calendar: Calendar) -> MenuBarTitle {
        guard let e = next, e.end > now else { return .idle }
        let inProgress = e.start <= now
        let until = e.start.timeIntervalSince(now)
        if !inProgress, settings.hideBeyondHours > 0, until > Double(settings.hideBeyondHours) * 3600 { return .idle }

        var symbol = defaultSymbol
        if settings.showServiceIcon, let url = e.meetURL {
            let service = MeetingService.detect(url)
            if service != .other { symbol = service.symbol }
        }
        let more = overlapCount > 0 ? " +\(overlapCount)" : ""
        let title = truncate(e.title, to: settings.maxTitleLength) + more
        let left = "\(TimeUntilFormatter.string(until: e.end, now: now)) left"
        let countdown = TimeUntilFormatter.string(until: e.start, now: now)
        let text: String
        switch settings.format {
        case .countdown:
            text = (inProgress ? "now · \(left)" : countdown) + more
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
        let time = d.shortTime
        if calendar.isDate(d, inSameDayAs: now) { return time }
        return "\(d.formatted(.dateTime.weekday(.abbreviated))) \(time)"
    }
}

/// The view inside `MenuBarExtra`'s label.
struct MenuBarLabelView: View {
    let title: MenuBarTitle
    /// Tinted phase of the "starting soon" pulse.
    let highlighted: Bool
    /// The LCD style's pre-rendered item (a menu bar label only draws images and text).
    var lcd: NSImage? = nil

    var body: some View {
        if let lcd {
            Image(nsImage: lcd).accessibilityLabel(Text(title.plainText.isEmpty ? "Meetball" : "Meetball, \(title.plainText)"))
        } else {
            Image(nsImage: MenuBarIcon.image(symbol: title.symbol, tint: highlighted ? .systemOrange : nil))
            if !title.plainText.isEmpty { Text(title.plainText) }
        }
    }
}

/// The LCD menu bar item (#26): olive chip glass with the icon, the day and date, and the countdown in the LCD's ink;
/// an orange lamp lights while a meeting is about to start.
struct MenuBarLCDView: View {
    let title: MenuBarTitle
    let highlighted: Bool
    static let height: CGFloat = 18

    var body: some View {
        HStack(spacing: 5) {
            if highlighted {
                SKLamp(color: .orange, lit: true, glow: 3, size: 5)
            }
            Image(systemName: title.symbol).font(.system(size: 10, weight: .semibold))
            if let date = title.date {
                Text(date.uppercased()).font(.system(size: 10.5, weight: .heavy, design: .monospaced)).tracking(0.4)
            }
            if title.date != nil && !title.text.isEmpty {
                Rectangle().fill(Color(sk1Hex: SK1.lcdInk, opacity: 0.3)).frame(width: 1, height: 10)
            }
            if !title.text.isEmpty {
                Text(title.text.uppercased()).font(.system(size: 10.5, weight: .bold, design: .monospaced)).tracking(0.3)
            }
        }
        .lineLimit(1)
        .foregroundStyle(Color(sk1Hex: SK1.lcdInk))
        .padding(.horizontal, 6)
        .frame(height: Self.height)
        .background(SKGlass(.chip, radius: 4))
        .fixedSize()
    }
}

@MainActor
enum MenuBarLCDRenderer {
    private static var cache: (key: String, image: NSImage)?

    /// Renders `MenuBarLCDView` at the screen's scale; the same title and phase reuse the last image.
    static func image(title: MenuBarTitle, highlighted: Bool, dark: Bool) -> NSImage? {
        let key = "\(title.symbol)|\(title.date ?? "")|\(title.text)|\(highlighted)|\(dark)"
        if let cache, cache.key == key { return cache.image }
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let renderer = ImageRenderer(content: MenuBarLCDView(title: title, highlighted: highlighted)
            .environment(\.colorScheme, dark ? .dark : .light))
        renderer.scale = scale
        guard let cg = renderer.cgImage else { return nil }
        let image = NSImage(cgImage: cg, size: NSSize(width: CGFloat(cg.width) / scale, height: CGFloat(cg.height) / scale))
        image.isTemplate = false
        cache = (key, image)
        return image
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
