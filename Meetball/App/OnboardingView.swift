import SwiftUI
import ServiceManagement
import UserNotifications
import SK1Tokens
import SK1UI

/// Whether the setup assistant has been finished. Settings › General › Run Setup Again clears it.
enum OnboardingState {
    enum Key { static let completed = "onboarding.completed" }

    /// People who already had a calendar connected before the assistant existed skip it.
    static func migrate(hasSource: Bool, defaults: UserDefaults = .standard) {
        if defaults.object(forKey: Key.completed) == nil { defaults.set(hasSource, forKey: Key.completed) }
    }

    /// Calendars that are hidden by default: birthdays, holidays and other subscribed noise.
    static func hiddenByDefault(_ c: GCalendar) -> Bool {
        let id = c.id.lowercased(), name = c.summary.lowercased()
        if id.contains("#holiday@") || id.contains("#contacts@") || id.contains("#weeknum@") { return true }
        return ["birthday", "holiday", "week numbers", "siri suggestions", "found in mail", "scheduled reminders"]
            .contains { name.contains($0) }
    }
}

/// Deep links into System Settings, for permissions that were turned down.
enum SystemSettingsLink {
    static let calendars = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!
    static let notifications = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!
    static func open(_ url: URL) { NSWorkspace.shared.open(url) }
}

/// First-run setup in three steps: connect a calendar, choose which calendars to show, pick how Meeting Guardian alerts.
struct OnboardingView: View {
    @EnvironmentObject var session: SessionManager
    @EnvironmentObject var store: CalendarStore
    @EnvironmentObject var guardianStore: MeetingGuardianStore
    @EnvironmentObject var guardian: MeetingGuardianManager
    @EnvironmentObject var subs: SubscriptionManager
    @AppStorage(OnboardingState.Key.completed) private var completed = false
    @State private var step = 0
    @State private var appliedDefaults = false
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    private let titles = ["Connect", "Calendars", "Alerts"]

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                HStack {
                    Text("Welcome to Meetball").font(.title2.bold())
                    Spacer()
                    StepIndicator(count: titles.count, current: step)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Step \(step + 1) of \(titles.count): \(titles[step])")
                }
                SKStatusStrip(title: "Step \(step + 1) of \(titles.count)", detail: titles[step].uppercased())
            }
            .padding(16)
            SKGroove()
            ScrollView {
                VStack(alignment: .leading, spacing: SK1.Metrics.groupSpacing) {
                    switch step {
                    case 0: connectStep
                    case 1: calendarsStep
                    default: alertsStep
                    }
                }
                .padding(SK1.Metrics.paneMargin)
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
            }
            SKGroove()
            HStack(spacing: 8) {
                if step > 0 {
                    Button { step -= 1 } label: { Label("Back", systemImage: "chevron.left") }.buttonStyle(.sk1Key())
                }
                Spacer()
                if step < titles.count - 1 {
                    // Until a calendar is connected, Sign In is the orange key.
                    Button { advance() } label: { Label("Continue", systemImage: "chevron.right") }
                        .buttonStyle(.sk1Key(step > 0 || store.hasAnySource ? .orange : .cream))
                        .disabled(step == 0 && !store.hasAnySource)
                        .help(step == 0 && !store.hasAnySource ? "Connect a calendar first" : "")
                } else {
                    Button("Start Using Meetball") { completed = true }.buttonStyle(.sk1Key(.orange))
                }
            }
            .padding(12)
        }
        .onAppear { guardian.refreshAuthorization() }
    }

    private func advance() {
        if step == 0 && !appliedDefaults { applyCalendarDefaults() }
        step += 1
        if step == 2 { guardian.refreshAuthorization() }
    }

    /// Hides birthday and holiday calendars the first time the list is shown.
    private func applyCalendarDefaults() {
        appliedDefaults = true
        for c in store.calendars where OnboardingState.hiddenByDefault(c) && !store.hiddenCalendarKeys.contains(c.key) {
            store.toggle(c)
        }
    }

    // MARK: Step 1: connect

    @ViewBuilder private var connectStep: some View {
        Text("Meetball shows your meetings in the menu bar, counts down to the next one and makes sure you join on time. Start by connecting a calendar.")
            .fixedSize(horizontal: false, vertical: true)
        SKGroup(caption: "Google Calendar", note: session.lastError) {
            SKRow(title: "Sign in with Google", subtitle: "Read and add events. Your sign-in stays in your Mac's Keychain; Meetball talks to Google directly, with no server in between.") {
                Button("Sign In") { Task { await session.addAccount() } }
                    .buttonStyle(.sk1Key(store.hasAnySource ? .cream : .orange))
                    .disabled(session.state == .signingIn)
            }
            ForEach(session.accounts, id: \.email) { a in
                SKRow(title: a.email, subtitle: "Connected") { SKLamp(color: .success, lit: true, label: "Connected") }
            }
        }
        SKGroup(caption: "Apple Calendar",
                note: "If your company blocks sign-in from apps like Meetball, add the work account in System Settings › Internet Accounts (or keep using Calendar's Exchange account) and connect it here instead.") {
            SKRow(title: "Use Apple Calendar", subtitle: "Read-only. Uses the accounts already in the Calendar app: iCloud, Exchange, Google and others. macOS asks for access first.") {
                HStack(spacing: 8) {
                    if store.appleEnabled { SKLamp(color: .success, lit: true, label: "Connected") }
                    Toggle("Use Apple Calendar", isOn: Binding(get: { store.appleEnabled },
                        set: { on in if on { Task { await store.enableApple() } } else { store.disableApple() } }))
                        .toggleStyle(.sk1Switch)
                }
            }
            if store.appleAccessDenied {
                SKRow(title: "Calendar access is off", subtitle: "Turn on Meetball in Privacy & Security › Calendars, then come back.") {
                    HStack(spacing: 8) {
                        SKLamp(color: .danger, lit: true, label: "Access denied")
                        Button("Open System Settings") { SystemSettingsLink.open(SystemSettingsLink.calendars) }
                            .buttonStyle(.sk1Key(size: .small))
                    }
                }
            }
        }
    }

    // MARK: Step 2: calendars

    @ViewBuilder private var calendarsStep: some View {
        Text("Choose the calendars to show. Birthdays and holidays start hidden; you can change this any time from the sidebar.")
            .fixedSize(horizontal: false, vertical: true)
        if store.calendars.isEmpty {
            SKGroup(caption: "Calendars") {
                SKRow(title: store.loadState == .loading ? "Loading calendars\u{2026}" : "No calendars yet",
                      subtitle: store.loadState == .loading ? nil : "Meetball found no calendars on this account.") {
                    if store.loadState == .loading { SKLamp(color: .teal, lit: true, label: "Loading", blinking: true) }
                    else { Button("Try Again") { store.refresh(.user) }.buttonStyle(.sk1Key(size: .small)) }
                }
            }
        }
        ForEach(store.sources, id: \.self) { source in
            SKGroup(caption: source) {
                ForEach(store.calendars.filter { $0.accountEmail == source }) { cal in
                    SKRow(title: cal.summary, subtitle: OnboardingState.hiddenByDefault(cal) ? "Hidden by default" : nil) {
                        HStack(spacing: 8) {
                            Circle().fill(Color(hex: cal.colorHex)).frame(width: 10, height: 10).accessibilityHidden(true)
                            Toggle("Show \(cal.summary)", isOn: Binding(get: { !store.hiddenCalendarKeys.contains(cal.key) },
                                                                    set: { _ in store.toggle(cal) }))
                                .toggleStyle(.sk1Switch)
                        }
                    }
                }
            }
        }
    }

    // MARK: Step 3: alerts

    @ViewBuilder private var alertsStep: some View {
        Text("Meeting Guardian makes sure you don't miss a meeting. Pick how loud it should be; Settings › Alerts has more, per calendar.")
            .fixedSize(horizontal: false, vertical: true)
        SKGroup(caption: "Alert style", note: guardianStore.settings.style.detail) {
            EscalationLadder(selection: $guardianStore.settings.style, isPro: subs.isPremiumActive)
            SKRow(title: "Preview", subtitle: "Show the \(guardianStore.settings.style.shortTitle.lowercased()) alert now.") {
                Button { guardian.preview(guardianStore.settings.style) } label: { Label("Preview", systemImage: "play.fill") }
                    .buttonStyle(.sk1Key())
            }
        }
        SKGroup(caption: "Permissions") {
            SKRow(title: "Notifications", subtitle: notificationSubtitle) {
                HStack(spacing: 8) {
                    SKLamp(color: notificationLamp, lit: true, label: notificationLabel)
                    switch guardian.notificationStatus {
                    case .notDetermined:
                        Button("Allow Notifications") { guardian.requestAuthorization() }.buttonStyle(.sk1Key(size: .small))
                    case .denied:
                        Button("Open System Settings") { SystemSettingsLink.open(SystemSettingsLink.notifications) }
                            .buttonStyle(.sk1Key(size: .small))
                    default:
                        EmptyView()
                    }
                }
            }
            SKRow(title: "Launch at login", subtitle: "Keep the countdown and alerts running after you restart your Mac.") {
                Toggle("Launch at login", isOn: $launchAtLogin).toggleStyle(.sk1Switch)
                    .onChange(of: launchAtLogin) { _, on in
                        do { if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } } catch { launchAtLogin.toggle() }
                    }
            }
        }
    }

    private var notificationSubtitle: String {
        switch guardian.notificationStatus {
        case .denied: return "Turned off. Soft reminders need them; turn on Meetball in System Settings › Notifications."
        case .notDetermined: return "Soft reminders and the join button in them use macOS notifications."
        default: return "Allowed."
        }
    }
    private var notificationLamp: SKLampColor {
        switch guardian.notificationStatus {
        case .denied: return .danger
        case .notDetermined: return .warning
        default: return .success
        }
    }
    private var notificationLabel: String {
        switch guardian.notificationStatus {
        case .denied: return "Notifications off"
        case .notDetermined: return "Not asked yet"
        default: return "Notifications allowed"
        }
    }
}
