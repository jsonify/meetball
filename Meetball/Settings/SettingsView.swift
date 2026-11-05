import SwiftUI
import ServiceManagement
import SK1UI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings().tabItem { Label("General", systemImage: "gearshape") }
            MenuBarSettingsView().tabItem { Label("Menu Bar", systemImage: "menubar.rectangle") }
            EventFilterSettingsView().tabItem { Label("Events", systemImage: "line.3.horizontal.decrease.circle") }
            AccountsSettings().tabItem { Label("Accounts", systemImage: "person.crop.circle") }
            MeetingGuardianSettingsView().tabItem { Label("Alerts", systemImage: "bell.badge") }
            JoinSettingsView().tabItem { Label("Joining", systemImage: "video") }
            SubscriptionSettings().tabItem { Label("Pro", systemImage: "star") }
        }.frame(width: 620, height: 560)
    }
}

struct GeneralSettings: View {
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @AppStorage("refreshIntervalSeconds") private var refresh: Double = 120
    var body: some View {
        SK1SettingsPane {
            SKGroup(caption: "App") {
                SKRow(title: "Launch at login", subtitle: "Open Meetball automatically when you sign in to your Mac.") {
                    Toggle("Launch at login", isOn: $launchAtLogin).toggleStyle(.sk1Switch)
                        .onChange(of: launchAtLogin) { _, on in
                            do { if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } } catch { launchAtLogin.toggle() }
                        }
                }
            }
            SKGroup(caption: "Sync") {
                SKRow(title: "Refresh Google Calendar", subtitle: "How often Meetball checks Google Calendar for changes.") {
                    SKKnob("Refresh Google Calendar", selection: $refresh,
                           stops: [("1 min", 60.0), ("2 min", 120.0), ("5 min", 300.0)], defaultValue: 120.0)
                }
            }
        }
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
    @State private var browsers: [InstalledBrowser] = []
    @State private var modes: [MeetingService: String] = [:]
    private let prefs = JoinPreferences()

    var body: some View {
        SK1SettingsPane {
            SKGroup(caption: "Shortcut",
                    note: "Works from anywhere. Joins the meeting in progress, or the next one starting within the look-ahead window.") {
                SKRow(title: "Join nearest meeting",
                      subtitle: join.registrationFailed ? "That shortcut is already used by another app. Pick a different one." : nil) {
                    HStack(spacing: 8) {
                        if join.registrationFailed { SKLamp(color: .danger, lit: true, label: "Shortcut unavailable") }
                        HotKeyRecorder()
                    }
                }
                SKRow(title: "Look ahead", subtitle: "For meetings that haven't started yet.") {
                    SKKnob("Look ahead", value: $join.windowMinutes, in: 1...60, defaultValue: 10) { "\($0) min" }
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
    @AppStorage("menuBar.showWeekNumbers") private var showWeekNumbers = false

    private var format: MenuBarTitleFormat { MenuBarTitleFormat(rawValue: formatRaw) ?? .countdown }
    private var showsTitle: Bool { format == .titleCountdown || format == .titleStartTime }

    var body: some View {
        SK1SettingsPane {
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
            SKGroup(caption: "Popover") {
                SKRow(title: "Show week numbers in the mini calendar") {
                    Toggle("Show week numbers in the mini calendar", isOn: $showWeekNumbers).toggleStyle(.sk1Switch)
                }
            }
        }
    }
}
