import SwiftUI

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
            Section {
                EscalationLadder(selection: $store.settings.style, isPro: subs.isPremiumActive) { manager.preview($0) }
                Text(store.settings.style.detail).font(.caption).foregroundStyle(.secondary)
                Toggle("Play sound with hard alerts", isOn: $store.settings.playSound)
                if store.settings.playSound {
                    LabeledContent("Sound") {
                        HStack {
                            Picker("", selection: $store.settings.soundName) {
                                ForEach(AlertSound.available, id: \.self) { Text($0).tag($0) }
                            }
                            .labelsHidden().frame(width: 160)
                            Button { manager.previewSound() } label: { Image(systemName: "play.fill") }.help("Play sound")
                        }
                    }
                    .onChange(of: store.settings.soundName) { _, _ in manager.previewSound() }
                }
            } header: {
                Text("Alert style")
            } footer: {
                Text("Pick how strongly Meetball interrupts you. Use Preview to see each one now.").font(.caption).foregroundStyle(.secondary)
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
        .onChange(of: store.settings) { _, _ in manager.reschedule(events: calendars.meetingEvents) }
    }
}

/// Soft → Heads-up → Hard as cards with arrows between; click a card to make it the default, Preview to try it.
struct EscalationLadder: View {
    @Binding var selection: AlertStyle
    let isPro: Bool
    let preview: (AlertStyle) -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(AlertStyle.allCases.enumerated()), id: \.element) { i, style in
                if i > 0 { Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(.tertiary) }
                card(style)
            }
        }
        .padding(.vertical, 4)
    }

    private func card(_ style: AlertStyle) -> some View {
        let selected = selection == style
        return VStack(spacing: 8) {
            Image(systemName: style.symbol).font(.system(size: 24)).foregroundStyle(selected ? Color.accentColor : .secondary)
                .frame(height: 28)
            HStack(spacing: 4) {
                Text(style.shortTitle).font(.callout.weight(.semibold))
                if style.isPro && !isPro {
                    Text("PRO").font(.system(size: 9, weight: .bold)).padding(.horizontal, 4).padding(.vertical, 1)
                        .background(Color.orange.opacity(0.2), in: Capsule()).foregroundStyle(.orange)
                }
            }
            Text(Self.blurb(style)).font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button("Preview") { preview(style) }.controlSize(.small)
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 130)
        .background(selected ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 1.5))
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .onTapGesture { selection = style }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
        .accessibilityLabel(style.title)
    }

    static func blurb(_ s: AlertStyle) -> String {
        switch s {
        case .soft: return "macOS notification"
        case .headsUp: return "Corner card with countdown"
        case .hard: return "Full screen on every display"
        }
    }
}
