import SwiftUI
import ServiceManagement
import SK1UI

/// The Settings window's sections, in the sidebar's order (About is pinned under the rest). Settings search jumps
/// between them.
enum SettingsTab: String, CaseIterable, Identifiable {
    case general, appearance, menuBar, events, accounts, alerts, joining, pro, about
    var id: String { rawValue }
    var title: String {
        switch self {
        case .general: return "General"
        case .appearance: return "Appearance"
        case .menuBar: return "Menu Bar"
        case .events: return "Events"
        case .accounts: return "Accounts"
        case .alerts: return "Alerts"
        case .joining: return "Joining"
        case .pro: return "Pro"
        case .about: return "About"
        }
    }
    var symbol: String {
        switch self {
        case .general: return "gearshape.fill"
        case .appearance: return "paintpalette.fill"
        case .menuBar: return "menubar.rectangle"
        case .events: return "line.3.horizontal.decrease.circle.fill"
        case .accounts: return "person.crop.circle.fill"
        case .alerts: return "bell.badge.fill"
        case .joining: return "video.fill"
        case .pro: return "star.fill"
        case .about: return "info"
        }
    }
    /// The sections in the sidebar's main tray; About sits in its own at the bottom.
    static var navigation: [SettingsTab] { allCases.filter { $0 != .about } }
}

/// The Settings window, laid out as Skreener's: a sidebar (an LCD naming the section, a tray of keys for the
/// sections, About pinned at the bottom), a groove, and the section's pane.
struct SettingsView: View {
    @State private var tab: SettingsTab = .general

    var body: some View {
        HStack(spacing: 0) {
            SettingsSidebar(selection: $tab)
            SKGroove(.vertical)
            pane
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .id(tab)
        }
        // Skreener's Settings: 810 pt wide under a title strip with the caption and a 6 × 2 grille, and a groove.
        .sk1WindowChrome(grille: (6, 2), groove: true) { SKCaption("Meetball Settings", tone: .soft) }
        .frame(width: 810, height: 660)
        .sk1Chassis()
        .navigationTitle("Meetball Settings")
    }

    @ViewBuilder private var pane: some View {
        switch tab {
        case .general: GeneralSettings(tab: $tab)
        case .appearance: AppearanceSettings()
        case .menuBar: MenuBarSettingsView()
        case .events: EventFilterSettingsView()
        case .accounts: AccountsSettings()
        case .alerts: MeetingGuardianSettingsView()
        case .joining: JoinSettingsView()
        case .pro: SubscriptionSettings()
        case .about: AboutSettings()
        }
    }
}

struct GeneralSettings: View {
    @Binding var tab: SettingsTab
    @EnvironmentObject var join: JoinController
    @EnvironmentObject var shortcuts: AppShortcuts
    @Environment(\.openWindow) private var openWindow
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var query = ""
    @AppStorage("refreshIntervalSeconds") private var refresh: Double = 120
    @AppStorage(AppPreferences.Key.hideDockIcon) private var hideDockIcon = false
    @AppStorage(OnboardingState.Key.completed) private var onboardingCompleted = false

    var body: some View {
        SK1SettingsPane {
            SKGroup(caption: "Find a setting") {
                SKRow(title: "Search") {
                    SKTextField("Search settings", text: $query, prompt: "Week numbers, shortcut, sound…", height: 30)
                        .frame(width: 260)
                }
                ForEach(SettingsSearch.matches(query)) { hit in
                    SKRow(title: hit.title, subtitle: "\(hit.tab.title) › \(hit.group)") {
                        Button("Show") { tab = hit.tab; query = "" }.buttonStyle(.sk1Key(size: .small))
                    }
                }
                if !query.trimmingCharacters(in: .whitespaces).isEmpty && SettingsSearch.matches(query).isEmpty {
                    SKRow(title: "No matching settings", subtitle: "Try a shorter word, like \u{201C}week\u{201D} or \u{201C}alert\u{201D}.") {
                        SKLamp(color: .warning, lit: true, label: "No matches")
                    }
                }
            }
            SKGroup(caption: "App") {
                SKRow(title: "Launch at login", subtitle: "Open Meetball automatically when you sign in to your Mac.") {
                    Toggle("Launch at login", isOn: $launchAtLogin).toggleStyle(.sk1Switch)
                        .onChange(of: launchAtLogin) { _, on in
                            do { if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } } catch { launchAtLogin.toggle() }
                        }
                }
                SKRow(title: "Menu bar only", subtitle: "Hide Meetball's Dock icon. The calendar window still opens from the menu bar.") {
                    Toggle("Menu bar only", isOn: $hideDockIcon).toggleStyle(.sk1Switch)
                        .onChange(of: hideDockIcon) { _, hide in DockIcon.apply(hidden: hide) }
                }
                SKRow(title: "Setup assistant", subtitle: "Walk through connecting calendars, choosing them and picking an alert style again.") {
                    Button("Run Setup Again") {
                        onboardingCompleted = false
                        openWindow(id: "main"); NSApp.activate(ignoringOtherApps: true)
                    }
                    .buttonStyle(.sk1Key(size: .small))
                }
            }
            SKGroup(caption: "Shortcuts", note: "These work from any app. Click a key, then type the new shortcut; it must use ⌘, ⌥ or ⌃.") {
                SKRow(title: GlobalShortcut.join.title,
                      subtitle: join.registrationFailed ? "That shortcut is already used by another app. Pick a different one." : "Joins the meeting in progress, or the next one within the look-ahead (Joining).") {
                    HStack(spacing: 8) {
                        if join.registrationFailed { SKLamp(color: .danger, lit: true, label: "Shortcut unavailable") }
                        HotKeyRecorder(combo: $join.hotKey, suspend: join.suspend, resume: join.resume)
                    }
                }
                ForEach(AppShortcuts.managed) { s in
                    SKRow(title: s.title,
                          subtitle: shortcuts.failed.contains(s) ? "That shortcut is already used by another app. Pick a different one." : nil) {
                        HStack(spacing: 8) {
                            if shortcuts.failed.contains(s) { SKLamp(color: .danger, lit: true, label: "Shortcut unavailable") }
                            HotKeyRecorder(combo: Binding(get: { shortcuts.combos[s] }, set: { shortcuts.set($0, for: s) }),
                                           suspend: { shortcuts.suspend(s) }, resume: { shortcuts.resume(s) })
                        }
                    }
                }
            }
            SKGroup(caption: "Sync") {
                SKRow(title: "Refresh calendars", subtitle: "How often Meetball checks Google Calendar and asks Calendar.app to sync its accounts.") {
                    SKKnob("Refresh calendars", selection: $refresh,
                           stops: [("1 min", 60.0), ("2 min", 120.0), ("5 min", 300.0)], defaultValue: 120.0)
                }
            }
        }
    }
}

/// Settings › About: which build is running, to copy into a bug report.
struct AboutSettings: View {
    var body: some View {
        SK1SettingsPane {
            SKGroup(caption: "Meetball", note: "Copy the version into a bug report so it's clear which build you're running.") {
                SKRow(title: "Version", subtitle: AppVersion.current.detail) {
                    HStack(spacing: 8) {
                        Text(AppVersion.current.short).font(.system(.body, design: .monospaced)).textSelection(.enabled)
                        Button("Copy") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(AppVersion.current.full, forType: .string)
                        }
                        .buttonStyle(.sk1Key(size: .small))
                    }
                }
            }
        }
    }
}

/// Menu-bar-only mode: no Dock icon and no app menu while Meetball isn't frontmost.
@MainActor
enum DockIcon {
    static func apply(hidden: Bool) {
        NSApp.setActivationPolicy(hidden ? .accessory : .regular)
        if !hidden { NSApp.activate(ignoringOtherApps: true) }
    }
}

struct AccountsSettings: View {
    @EnvironmentObject var session: SessionManager
    @EnvironmentObject var calendar: CalendarStore
    private let palette = ["#4285F4", "#0B8043", "#D50000", "#F4511E", "#8E24AA", "#039BE5", "#616161"]

    var body: some View {
        SK1SettingsPane {
            SKGroup(caption: "Google accounts", note: session.lastError) {
                if session.accounts.isEmpty {
                    SKRow(title: "No Google accounts", subtitle: "Add one to see its calendars, alerts and accent colour.") {
                        SKLamp(color: .warning, lit: true, label: "No accounts")
                    }
                }
                ForEach(session.accounts, id: \.email) { a in
                    SKRow(title: a.email, subtitle: a.name) {
                        HStack(spacing: 6) {
                            ForEach(palette, id: \.self) { hex in swatch(hex, for: a.email) }
                            Button("Remove", role: .destructive) { session.remove(a) }
                                .buttonStyle(.sk1Key(.charcoal, size: .small))
                                .padding(.leading, 6)
                        }
                    }
                }
                SKRow(title: "Add a Google account", subtitle: "Signs in with Google in your browser.") {
                    Button { Task { await session.addAccount() } } label: { Label("Add", systemImage: "plus") }
                        .buttonStyle(.sk1Key())
                        .disabled(session.state == .signingIn)
                }
            }
            SKGroup(caption: "Apple Calendar",
                    note: calendar.appleAccessDenied ? "Access is denied. Turn on Meetball in System Settings › Privacy & Security › Calendars." : nil) {
                SKRow(title: "Use Apple Calendar", subtitle: "Read-only. Uses the accounts already in the Calendar app (Exchange, iCloud, …).") {
                    HStack(spacing: 8) {
                        if calendar.appleAccessDenied { SKLamp(color: .danger, lit: true, label: "Access denied") }
                        Toggle("Use Apple Calendar", isOn: Binding(get: { calendar.appleEnabled },
                            set: { on in if on { Task { await calendar.enableApple() } } else { calendar.disableApple() } }))
                            .toggleStyle(.sk1Switch)
                    }
                }
            }
        }
    }

    /// One accent colour for the account: a dot, ringed while chosen.
    private func swatch(_ hex: String, for email: String) -> some View {
        let chosen = session.accentHex[email] == hex
        return Button { session.setAccent(hex, for: email) } label: {
            Circle().fill(Color(hex: hex)).frame(width: 16, height: 16)
                .overlay(Circle().stroke(Color.primary, lineWidth: chosen ? 2 : 0).padding(-2))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Accent \(hex)")
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }
}

struct SubscriptionSettings: View {
    var body: some View { SK1SettingsPane { SubscriptionStatusView() } }
}

struct JoinSettingsView: View {
    @EnvironmentObject var join: JoinController
    @EnvironmentObject var guardianStore: MeetingGuardianStore
    @State private var browsers: [InstalledBrowser] = []
    @State private var modes: [MeetingService: String] = [:]
    private let prefs = JoinPreferences()

    var body: some View {
        SK1SettingsPane {
            SKGroup(caption: "Join nearest meeting",
                    note: "The shortcut (Settings › General › Shortcuts) and the menu bar's Join key join the meeting in progress, or the next one starting within the look-ahead.") {
                SKRow(title: "Shortcut") {
                    SKChip(join.hotKey?.display ?? "OFF", minWidth: 64)
                }
                SKRow(title: "Look ahead", subtitle: "For meetings that haven't started yet.") {
                    SKKnob("Look ahead", value: $join.windowMinutes, in: 1...60, defaultValue: 10) { "\($0) min" }
                }
            }
            SKGroup(caption: "Auto-join",
                    note: "Turn auto-join on for a meeting from its details (click it in the menu bar or the calendar). If you haven't joined through Meetball by then, it opens the meeting for you, the way the links below say.") {
                SKRow(title: "Join", subtitle: "Meetings more than 5 minutes past this point are left alone, for example after your Mac wakes up.") {
                    SKPicker(selection: $guardianStore.settings.autoJoinDelayMinutes,
                             options: AutoJoin.delayOptions.map { SKPicker<Int>.Option($0, $0 == 0 ? "At the start" : "\($0) min after the start") })
                }
            }
            SKGroup(caption: "Open meeting links in") {
                ForEach(MeetingService.allCases) { service in
                    SKRow(title: service.displayName,
                          subtitle: service.hasNativeApp ? "The \(service.shortName) app falls back to the browser if it isn't installed." : nil) {
                        SKPicker(selection: binding(for: service), options: openOptions(for: service), stepper: false)
                    }
                }
            }
        }
        .onAppear {
            browsers = MeetingJoiner.installedBrowsers()
            for s in MeetingService.allCases { modes[s] = prefs.mode(for: s).raw }
        }
    }

    /// Where a service's links can open: its app, the default browser, or an installed browser.
    private func openOptions(for service: MeetingService) -> [SKPicker<String>.Option] {
        (service.hasNativeApp ? [SKPicker<String>.Option(JoinOpenMode.nativeApp.raw, "\(service.shortName) app")] : [])
            + [SKPicker<String>.Option(JoinOpenMode.defaultBrowser.raw, "Default browser")]
            + browsers.map { SKPicker<String>.Option(JoinOpenMode.browser(bundleID: $0.bundleID).raw, $0.name) }
    }

    private func binding(for s: MeetingService) -> Binding<String> {
        Binding(get: { modes[s] ?? prefs.mode(for: s).raw },
                set: { modes[s] = $0; prefs.setMode(JoinOpenMode(raw: $0), for: s) })
    }
}

struct MenuBarSettingsView: View {
    @AppStorage(MenuBarTitleSettings.Key.format) private var formatRaw = MenuBarTitleSettings(defaults: .standard).format.rawValue
    @AppStorage(MenuBarTitleSettings.Key.maxTitleLength) private var maxTitleLength = MenuBarTitleSettings().maxTitleLength
    @AppStorage(MenuBarTitleSettings.Key.showServiceIcon) private var showServiceIcon = true
    @AppStorage(MenuBarTitleSettings.Key.hideBeyondHours) private var hideBeyondHours = 0
    @AppStorage(MenuBarTitleSettings.Key.pulseWhenSoon) private var pulseWhenSoon = true
    @AppStorage(MenuBarTitleSettings.Key.style) private var styleRaw = MenuBarStyle.plain.rawValue
    @AppStorage(MenuBarTitleSettings.Key.showDate) private var showDate = false

    private var format: MenuBarTitleFormat { MenuBarTitleFormat(rawValue: formatRaw) ?? .countdown }
    private var showsTitle: Bool { format == .titleCountdown || format == .titleStartTime }

    var body: some View {
        SK1SettingsPane {
            SKGroup(caption: "Look") {
                SKRow(title: "Style", subtitle: styleRaw == MenuBarStyle.lcd.rawValue
                      ? "A small olive LCD, like the one at the top of the menu." : "The system's own menu bar text.") {
                    SKSegmented(selection: $styleRaw, options: MenuBarStyle.allCases.map { SKSegmented<String>.Option($0.rawValue, $0.title) })
                        .frame(width: 160)
                }
                SKRow(title: "Show the day and date", subtitle: "For example \u{201C}\(MenuBarTitleBuilder.dateText(Date()))\u{201D}, before the countdown.") {
                    Toggle("Show the day and date", isOn: $showDate).toggleStyle(.sk1Switch)
                }
                SKRow(title: "Preview") {
                    MenuBarPreview(style: MenuBarStyle(rawValue: styleRaw) ?? .plain, showDate: showDate)
                }
            }
            SKGroup(caption: "Title",
                    note: "While a meeting is in progress the item shows \"now\" and the time left.") {
                SKRow(title: "Show", subtitle: format.example.isEmpty ? "Only the icon." : "For example \u{201C}\(format.example)\u{201D}.") {
                    SKPicker(selection: $formatRaw,
                             options: MenuBarTitleFormat.allCases.map { SKPicker<String>.Option($0.rawValue, $0.title) })
                }
                SKRow(title: "Longest title",
                      subtitle: "Longer titles are cut with \u{2026} so the item never crowds out other menu bar icons.") {
                    SKKnob("Longest title", value: $maxTitleLength, in: MenuBarTitleSettings.titleLengthRange,
                           defaultValue: MenuBarTitleSettings().maxTitleLength) { "\($0) chars" }
                }
                .disabled(!showsTitle)
                SKRow(title: "Show text", subtitle: "Hide the title until a meeting is this close.") {
                    SKPicker(selection: $hideBeyondHours,
                             options: [0, 1, 2, 4, 8, 12].map { SKPicker<Int>.Option($0, $0 == 0 ? "Always" : "Within \($0) h") })
                }
            }
            SKGroup(caption: "Icon", note: "The icon turns orange when a meeting is less than 5 minutes away.") {
                SKRow(title: "Use the meeting's service icon", subtitle: "Meet, Zoom, Teams or Webex, when the meeting has a join link.") {
                    Toggle("Use the meeting's service icon", isOn: $showServiceIcon).toggleStyle(.sk1Switch)
                }
                SKRow(title: "Pulse when a meeting is near", subtitle: "Blinks the icon when a meeting starts in under 5 minutes.") {
                    Toggle("Pulse when a meeting is near", isOn: $pulseWhenSoon).toggleStyle(.sk1Switch)
                }
            }
            WorldClockSettingsGroup()
        }
    }
}

/// What the menu bar item looks like with the chosen style, for a meeting 12 minutes away.
private struct MenuBarPreview: View {
    let style: MenuBarStyle
    let showDate: Bool

    var body: some View {
        let title = MenuBarTitle(text: "12m", symbol: "video.fill", isSoon: false, inProgress: false,
                                 date: showDate ? MenuBarTitleBuilder.dateText(Date()) : nil)
        Group {
            if style == .lcd {
                MenuBarLCDView(title: title, highlighted: false)
            } else {
                HStack(spacing: 5) {
                    Image(systemName: title.symbol)
                    Text(title.plainText)
                }
                .font(.system(size: 13))
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.08)))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Preview: \(title.plainText)")
    }
}
