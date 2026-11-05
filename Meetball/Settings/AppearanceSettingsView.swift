import SwiftUI
import SK1Tokens
import SK1UI

/// Settings › Appearance: light or dark, the week, the clock and how tightly the calendar views pack.
struct AppearanceSettings: View {
    @EnvironmentObject var calendar: CalendarStore
    @AppStorage(AppPreferences.Key.firstWeekday) private var firstWeekday = 0
    @AppStorage(AppPreferences.Key.weekNumbers) private var showWeekNumbers = false
    @AppStorage(AppPreferences.Key.highlightWeekends) private var highlightWeekends = true
    @AppStorage(AppPreferences.Key.clockStyle) private var clockRaw = ClockStyle.system.rawValue
    @AppStorage(AppPreferences.Key.showEventTimeZone) private var showEventTimeZone = true
    @AppStorage(AppPreferences.Key.density) private var densityRaw = LayoutDensity.comfortable.rawValue
    @AppStorage(AppPreferences.Key.theme) private var themeRaw = AppTheme.system.rawValue

    var body: some View {
        SK1SettingsPane {
            SKGroup(caption: "Appearance") {
                SKRow(title: "Theme", subtitle: "Light is the cream SK-1 look, Dark the charcoal one. System follows macOS.") {
                    SKSegmented(selection: $themeRaw, options: AppTheme.allCases.map { SKSegmented<String>.Option($0.rawValue, $0.title) })
                        .frame(width: 210)
                        .onChange(of: themeRaw) { _, raw in ThemeController.apply(AppTheme(rawValue: raw) ?? .system) }
                }
            }
            SKGroup(caption: "Week") {
                SKRow(title: "First day of the week", subtitle: "For the month grid, the week view and the mini calendar.") {
                    SKPicker(selection: $firstWeekday, options: Self.weekdayOptions, stepper: false)
                        .onChange(of: firstWeekday) { _, _ in calendar.refresh() }
                }
                SKRow(title: "Show week numbers", subtitle: "In the month grid and the menu bar's mini calendar.") {
                    Toggle("Show week numbers", isOn: $showWeekNumbers).toggleStyle(.sk1Switch)
                }
                SKRow(title: "Shade weekends", subtitle: "Weekend days are tinted in the month grid and the mini calendar.") {
                    Toggle("Shade weekends", isOn: $highlightWeekends).toggleStyle(.sk1Switch)
                }
            }
            SKGroup(caption: "Time") {
                SKRow(title: "Clock", subtitle: "For example \u{201C}\(example)\u{201D}.") {
                    SKSegmented(selection: $clockRaw, options: ClockStyle.allCases.map { SKSegmented<String>.Option($0.rawValue, $0.title) })
                        .frame(width: 250)
                }
                SKRow(title: "Show an event's own time zone",
                      subtitle: "When a meeting was set in another time zone, its details also show the time there.") {
                    Toggle("Show an event's own time zone", isOn: $showEventTimeZone).toggleStyle(.sk1Switch)
                }
            }
            SKGroup(caption: "Layout", note: "Compact fits more of the day on screen in the Day and Week views.") {
                SKRow(title: "Density") {
                    SKSegmented(selection: $densityRaw, options: LayoutDensity.allCases.map { SKSegmented<String>.Option($0.rawValue, $0.title) })
                        .frame(width: 220)
                }
            }
        }
    }

    private var example: String {
        let d = Calendar.current.date(bySettingHour: 14, minute: 30, second: 0, of: Date()) ?? Date()
        return d.shortTime(locale: AppPreferences.locale(clock: ClockStyle(rawValue: clockRaw) ?? .system))
    }

    /// "System (Sunday)", then every weekday by name.
    static var weekdayOptions: [SKPicker<Int>.Option] {
        let names = Calendar.current.weekdaySymbols
        let system = names[Calendar.current.firstWeekday - 1]
        return [SKPicker<Int>.Option(0, "System (\(system))")] + names.enumerated().map { SKPicker<Int>.Option($0.offset + 1, $0.element) }
    }
}

// MARK: - Settings search

/// One searchable setting: where it lives and words people might type for it.
struct SettingsSearchEntry: Identifiable, Hashable {
    let title: String
    let tab: SettingsTab
    let group: String
    let keywords: [String]
    var id: String { "\(tab.rawValue)|\(title)" }
}

enum SettingsSearch {
    static let entries: [SettingsSearchEntry] = [
        .init(title: "Launch at login", tab: .general, group: "App", keywords: ["startup", "login", "open automatically"]),
        .init(title: "Menu bar only", tab: .general, group: "App", keywords: ["dock", "dock icon", "hide", "accessory"]),
        .init(title: "Setup assistant", tab: .general, group: "App", keywords: ["onboarding", "welcome", "setup", "start over"]),
        .init(title: "Join nearest meeting shortcut", tab: .general, group: "Shortcuts", keywords: ["hotkey", "keyboard", "join"]),
        .init(title: "Open the menu bar popover shortcut", tab: .general, group: "Shortcuts", keywords: ["hotkey", "keyboard", "popover", "menu bar"]),
        .init(title: "Quick add shortcut", tab: .general, group: "Shortcuts", keywords: ["hotkey", "keyboard", "new event", "create"]),
        .init(title: "Refresh calendars", tab: .general, group: "Sync", keywords: ["sync", "interval", "refresh", "update", "google", "apple"]),
        .init(title: "Version", tab: .about, group: "Meetball", keywords: ["version", "build", "about", "commit"]),
        .init(title: "Theme", tab: .appearance, group: "Appearance", keywords: ["dark mode", "light mode", "dark", "light", "system", "theme", "charcoal", "cream"]),
        .init(title: "First day of the week", tab: .appearance, group: "Week", keywords: ["monday", "sunday", "week start", "weekday"]),
        .init(title: "Show week numbers", tab: .appearance, group: "Week", keywords: ["week number", "iso", "calendar week"]),
        .init(title: "Shade weekends", tab: .appearance, group: "Week", keywords: ["weekend", "highlight", "saturday", "sunday"]),
        .init(title: "Clock", tab: .appearance, group: "Time", keywords: ["12-hour", "24-hour", "am pm", "time format", "military"]),
        .init(title: "Show an event's own time zone", tab: .appearance, group: "Time", keywords: ["time zone", "timezone", "travel"]),
        .init(title: "Density", tab: .appearance, group: "Layout", keywords: ["compact", "comfortable", "spacing", "size"]),
        .init(title: "Menu bar title", tab: .menuBar, group: "Title", keywords: ["countdown", "format", "title", "text"]),
        .init(title: "Longest title", tab: .menuBar, group: "Title", keywords: ["length", "truncate", "characters"]),
        .init(title: "Use the meeting's service icon", tab: .menuBar, group: "Icon", keywords: ["zoom", "meet", "teams", "icon"]),
        .init(title: "Pulse when a meeting is near", tab: .menuBar, group: "Icon", keywords: ["blink", "flash", "pulse"]),
        .init(title: "World clocks", tab: .menuBar, group: "World clocks", keywords: ["time zone", "timezone", "city", "clock"]),
        .init(title: "Hide or fade events", tab: .events, group: "Hide or fade", keywords: ["filter", "declined", "all-day", "focus", "ignore"]),
        .init(title: "Rules per source", tab: .events, group: "Per source", keywords: ["filter", "account", "source"]),
        .init(title: "Google accounts", tab: .accounts, group: "Google accounts", keywords: ["sign in", "google", "account", "accent", "colour", "color"]),
        .init(title: "Use Apple Calendar", tab: .accounts, group: "Apple Calendar", keywords: ["icloud", "exchange", "apple", "calendar access"]),
        .init(title: "Alert style", tab: .alerts, group: "Alert style", keywords: ["guardian", "notification", "heads-up", "hard alert", "full screen"]),
        .init(title: "Sound", tab: .alerts, group: "Alert style", keywords: ["sound", "audio", "chime"]),
        .init(title: "Remind me", tab: .alerts, group: "Timing", keywords: ["minutes before", "lead time", "reminder"]),
        .init(title: "Break through Focus", tab: .alerts, group: "When alerts show", keywords: ["focus", "do not disturb", "dnd"]),
        .init(title: "Quiet while screen-sharing", tab: .alerts, group: "When alerts show", keywords: ["presenting", "screen share"]),
        .init(title: "Active hours", tab: .alerts, group: "When alerts show", keywords: ["working hours", "schedule"]),
        .init(title: "Alerts per calendar", tab: .alerts, group: "Per calendar", keywords: ["calendar", "strength", "importance", "rules"]),
        .init(title: "Look ahead", tab: .joining, group: "Join nearest meeting", keywords: ["window", "minutes", "join"]),
        .init(title: "Open meeting links in", tab: .joining, group: "Open meeting links in", keywords: ["browser", "zoom app", "teams app", "chrome", "safari"]),
        .init(title: "Meetball Pro", tab: .pro, group: "Pro", keywords: ["subscription", "upgrade", "purchase", "restore"]),
    ]

    /// Settings whose title, group or keywords contain every word typed (case- and accent-insensitive).
    static func matches(_ query: String, in entries: [SettingsSearchEntry] = entries) -> [SettingsSearchEntry] {
        let words = query.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return [] }
        return entries.filter { e in
            let haystack = ([e.title, e.group, e.tab.title] + e.keywords).joined(separator: " ")
                .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            return words.allSatisfy { haystack.contains($0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)) }
        }
    }
}

// MARK: - World clocks

/// Settings › Menu Bar › World clocks: the cities shown under the popover's status strip.
struct WorldClockSettingsGroup: View {
    @AppStorage(AppPreferences.Key.worldClocks) private var raw = ""
    @State private var query = ""

    private var clocks: [WorldClock] { WorldClock.decode(raw) }

    var body: some View {
        SKGroup(caption: "World clocks", note: "Shown in the menu bar popover, under the status strip. Up to \(WorldClock.limit).") {
            ForEach(clocks) { clock in
                SKRow(title: clock.displayLabel, subtitle: "\(clock.timeZoneID) · \(clock.offsetText(from: .current))") {
                    HStack(spacing: 6) {
                        SKTextField("Label for \(clock.displayLabel)", text: labelBinding(clock), prompt: WorldClock.cityName(clock.timeZoneID), height: 26)
                            .frame(width: 140)
                        Button { update { $0.removeAll { $0.id == clock.id } } } label: { Image(systemName: "minus") }
                            .buttonStyle(.sk1Key(.round, size: .small))
                            .help("Remove \(clock.displayLabel)").accessibilityLabel("Remove \(clock.displayLabel)")
                    }
                }
            }
            if clocks.count < WorldClock.limit {
                SKRow(title: "Add a city", subtitle: clocks.isEmpty ? "Search by city or region, like \u{201C}London\u{201D} or \u{201C}Tokyo\u{201D}." : nil) {
                    SKTextField("Search cities", text: $query, prompt: "City", height: 26).frame(width: 200)
                }
                ForEach(WorldClock.search(query).filter { id in !clocks.contains { $0.timeZoneID == id } }, id: \.self) { id in
                    SKRow(title: WorldClock.cityName(id), subtitle: id) {
                        Button("Add") {
                            update { $0.append(WorldClock(timeZoneID: id, label: WorldClock.cityName(id))) }
                            query = ""
                        }
                        .buttonStyle(.sk1Key(size: .small))
                    }
                }
            }
        }
    }

    private func update(_ change: (inout [WorldClock]) -> Void) {
        var c = clocks; change(&c); raw = WorldClock.encode(c)
    }

    private func labelBinding(_ clock: WorldClock) -> Binding<String> {
        Binding(get: { clock.label },
                set: { new in update { list in if let i = list.firstIndex(where: { $0.id == clock.id }) { list[i].label = new } } })
    }
}
