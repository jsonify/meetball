import SwiftUI

struct AlertOverlayHost: View {
    let event: CalendarEvent; let hard: Bool; let lead: Int
    let onJoin: () -> Void; let onDismiss: () -> Void
    var body: some View {
        if hard { HardAlertOverlayView(event: event, lead: lead, onJoin: onJoin, onDismiss: onDismiss) }
        else { HeadsUpOverlayView(event: event, lead: lead, onJoin: onJoin, onDismiss: onDismiss) }
    }
}

struct HeadsUpOverlayView: View {
    let event: CalendarEvent; let lead: Int
    let onJoin: () -> Void; let onDismiss: () -> Void
    var body: some View {
        VStack(spacing: 12) {
            Text(lead == 0 ? "It's time for your meeting" : "You have a meeting soon").font(.subheadline).foregroundStyle(.secondary)
            Text(event.title).font(.title2.bold()).multilineTextAlignment(.center).lineLimit(2)
            Text(event.start, style: .time).font(.title3.monospacedDigit())
            HStack {
                JoinButton(event: event, action: onJoin).keyboardShortcut(.defaultAction)
                Button("Dismiss", action: onDismiss)
            }
        }
        .padding(24).frame(width: 440, height: 240)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
    }
}

struct HardAlertOverlayView: View {
    let event: CalendarEvent; let lead: Int
    let onJoin: () -> Void; let onDismiss: () -> Void
    var body: some View {
        ZStack {
            Color.black.opacity(0.75)
            VStack(spacing: 24) {
                Text(lead == 0 ? "It's time for your meeting" : "Starting in \(lead) min").font(.title).foregroundStyle(.white.opacity(0.8))
                Text(event.title).font(.system(size: 56, weight: .bold)).foregroundStyle(.white).multilineTextAlignment(.center).lineLimit(3)
                Text(event.start, style: .time).font(.system(size: 28).monospacedDigit()).foregroundStyle(.white.opacity(0.8))
                HStack(spacing: 16) {
                    JoinButton(event: event, size: .large, action: onJoin)
                    Button("Dismiss", action: onDismiss).buttonStyle(.bordered).controlSize(.large)
                }
            }.padding(60)
        }
    }
}

struct StillJoiningPromptView: View {
    let event: CalendarEvent
    let onJoin: () -> Void; let onDismiss: () -> Void
    var body: some View {
        VStack(spacing: 12) {
            Text("Are you still joining?").font(.title3.bold())
            Text("\(event.title) started 2 minutes ago.").foregroundStyle(.secondary)
            HStack { JoinButton(event: event, action: onJoin); Button("I'm not joining", action: onDismiss) }
        }
        .padding(24).frame(width: 440, height: 240)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
    }
}

struct SleepWarningOverlayView: View {
    let event: CalendarEvent
    var body: some View {
        Label("\(event.title) starts in \(TimeUntilFormatter.string(until: event.start))", systemImage: "moon.zzz.fill").padding()
    }
}

struct MeetingGuardianStatusRow: View {
    @ObservedObject var store: MeetingGuardianStore
    @EnvironmentObject var subs: SubscriptionManager
    var body: some View {
        HStack {
            Image(systemName: subs.isPremiumActive ? "shield.checkered" : "bell")
            Text(subs.isPremiumActive ? "Active for your important meetings." : "Basic reminders only. Upgrade to Meetball Pro for advanced alerts.")
        }.font(.callout).foregroundStyle(.secondary)
    }
}

struct MeetingGuardianSettingsView: View {
    @EnvironmentObject var store: MeetingGuardianStore
    @EnvironmentObject var subs: SubscriptionManager
    @EnvironmentObject var calendars: CalendarStore
    @EnvironmentObject var manager: MeetingGuardianManager
    @State private var showPaywall = false

    var body: some View {
        Form {
            Section {
                MeetingGuardianStatusRow(store: store)
                if !subs.isPremiumActive {
                    Text("Meeting Guardian is a Pro feature. You can preview settings, but alerts will only use the basic notification until you upgrade.").font(.caption)
                    Button("Upgrade to Meetball Pro") { showPaywall = true }
                }
            }
            Section("Alert style") {
                Picker("Style", selection: $store.settings.style) {
                    ForEach(AlertStyle.allCases) { s in Text(s.title + (s.isPro ? " — Pro" : "")).tag(s) }
                }.pickerStyle(.radioGroup)
                Text(store.settings.style.detail).font(.caption).foregroundStyle(.secondary)
                Toggle("Play sound with hard alerts", isOn: $store.settings.playSound)
            }
            Section("Timing") {
                Picker("Remind me", selection: $store.settings.leadMinutes) {
                    ForEach(TimingOption.all) { o in Text(o.title + (o.isPro && !subs.isPremiumActive ? " (Pro)" : "")).tag(o.minutes) }
                }
                Toggle("Also show at 5 minutes before", isOn: $store.settings.alsoAtFiveMinutes)
                Toggle("Repeat if I haven't joined", isOn: $store.settings.repeatIfNotJoined)
                Toggle("Ask \"Are you still joining?\" if I haven't joined after 2 minutes", isOn: $store.settings.stillJoiningPrompt)
                if !subs.isPremiumActive { Text("More reminder timings are available in Meetball Pro.").font(.caption).foregroundStyle(.secondary) }
            }
            Section("Control when alerts show") {
                Toggle("Show alerts even when macOS Focus mode is on", isOn: $store.settings.breakThroughFocus)
                Text("Meetball will request the necessary permission so it can break through Focus mode for calendar alerts only.").font(.caption).foregroundStyle(.secondary)
                Toggle("Don't show hard alerts when I'm screen-sharing or presenting", isOn: $store.settings.skipWhileScreenSharing)
                Toggle("Warn me before sleep or shutdown", isOn: $store.settings.warnBeforeSleep)
                Text("If a meeting starts in the next 10 minutes and you try to sleep or shut down your Mac, Meetball will show a warning.").font(.caption).foregroundStyle(.secondary)
                Toggle("Only use strong alerts during active hours", isOn: $store.settings.limitToActiveHours)
                if store.settings.limitToActiveHours {
                    Stepper("From \(store.settings.activeStartHour):00", value: $store.settings.activeStartHour, in: 0...23)
                    Stepper("Until \(store.settings.activeEndHour):00", value: $store.settings.activeEndHour, in: 1...24)
                    Text("Outside of these hours, Meetball will only use soft reminders.").font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("Per-calendar rules (Pro)") {
                if calendars.calendars.isEmpty {
                    Text("Connect your Google account to customize rules for each calendar.").foregroundStyle(.secondary)
                } else {
                    ForEach(calendars.calendars) { cal in
                        HStack {
                            Circle().fill(Color(hex: cal.colorHex)).frame(width: 10, height: 10)
                            Text(cal.summary)
                            Spacer()
                            Picker("", selection: Binding<String>(
                                get: { guard let r = store.rule(for: cal.key) else { return "default" }; return r.style?.rawValue ?? "off" },
                                set: { v in
                                    if v == "default" { store.calendarRules.removeAll { $0.calendarKey == cal.key } }
                                    else { store.upsert(CalendarRule(calendarKey: cal.key, style: AlertStyle(rawValue: v))) }
                                })) {
                                Text("Default").tag("default")
                                Text("No Meeting Guardian actions for this calendar").tag("off")
                                ForEach(AlertStyle.allCases) { Text($0.title).tag($0.rawValue) }
                            }.labelsHidden().frame(width: 220).disabled(!subs.isPremiumActive)
                        }
                    }
                    if !subs.isPremiumActive { Text("Unlock per-calendar control with Meetball Pro.").font(.caption).foregroundStyle(.secondary) }
                }
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showPaywall) { PaywallView() }
        .onChange(of: store.settings) { _, _ in manager.reschedule(events: calendars.events) }
    }
}
