import SwiftUI
import SK1Tokens
import SK1UI

struct MeetingGuardianSettingsView: View {
    @EnvironmentObject var store: MeetingGuardianStore
    @EnvironmentObject var subs: SubscriptionManager
    @EnvironmentObject var calendars: CalendarStore
    @EnvironmentObject var manager: MeetingGuardianManager
    @State private var showPaywall = false

    var body: some View {
        SK1SettingsPane {
            VStack(alignment: .leading, spacing: 8) {
                NextAlertSummary()
                if !subs.isPremiumActive {
                    ProHint(text: "Meeting Guardian is a Pro feature. You can preview every setting; until you upgrade, alerts use the basic notification.") {
                        showPaywall = true
                    }
                }
            }
            SKGroup(caption: "Alert style", note: store.settings.style.detail) {
                EscalationLadder(selection: $store.settings.style, isPro: subs.isPremiumActive)
                SKRow(title: "Preview", subtitle: "Show the \(store.settings.style.shortTitle.lowercased()) alert now.") {
                    Button { manager.preview(store.settings.style) } label: { Label("Preview", systemImage: "play.fill") }
                        .buttonStyle(.sk1Key())
                }
                SKRow(title: "Play sound with hard alerts") {
                    Toggle("Play sound with hard alerts", isOn: $store.settings.playSound).toggleStyle(.sk1Switch)
                }
                if store.settings.playSound {
                    SKRow(title: "Sound") {
                        HStack(spacing: 6) {
                            SKPicker(selection: $store.settings.soundName,
                                     options: AlertSound.available.map { SKPicker<String>.Option($0, $0) })
                            Button { manager.previewSound() } label: { Image(systemName: "speaker.wave.2.fill") }
                                .buttonStyle(.sk1Key(.round, size: .small)).help("Play sound").accessibilityLabel("Play sound")
                        }
                    }
                }
            }
            SKGroup(caption: "Timing", note: subs.isPremiumActive ? nil : "1 and 5 minutes before are free; the other timings are Pro.") {
                SKRow(title: "Remind me") {
                    SKKnob("Remind me", selection: $store.settings.leadMinutes,
                           stops: TimingOption.all.map { (title: $0.minutes == 0 ? "At start" : "\($0.minutes) min", value: $0.minutes) },
                           defaultValue: 1)
                }
                SKRow(title: "Also at 5 minutes before") {
                    Toggle("Also show at 5 minutes before", isOn: $store.settings.alsoAtFiveMinutes).toggleStyle(.sk1Switch)
                }
                SKRow(title: "Repeat if I haven't joined") {
                    Toggle("Repeat if I haven't joined", isOn: $store.settings.repeatIfNotJoined).toggleStyle(.sk1Switch)
                }
                SKRow(title: "Ask \u{201C}Are you still joining?\u{201D}", subtitle: "If you haven't joined 2 minutes after the start.") {
                    Toggle("Ask if I'm still joining", isOn: $store.settings.stillJoiningPrompt).toggleStyle(.sk1Switch)
                }
            }
            SKGroup(caption: "When alerts show") {
                SKRow(title: "Break through Focus", subtitle: "Meetball asks for permission to show calendar alerts while a Focus is on.") {
                    Toggle("Show alerts even when Focus is on", isOn: $store.settings.breakThroughFocus).toggleStyle(.sk1Switch)
                }
                SKRow(title: "Quiet while screen-sharing", subtitle: "No hard alerts while you share your screen or present.") {
                    Toggle("Don't show hard alerts while screen-sharing", isOn: $store.settings.skipWhileScreenSharing).toggleStyle(.sk1Switch)
                }
                SKRow(title: "Warn before sleep or shutdown", subtitle: "When a meeting starts in the next 10 minutes.") {
                    Toggle("Warn me before sleep or shutdown", isOn: $store.settings.warnBeforeSleep).toggleStyle(.sk1Switch)
                }
                SKRow(title: "Strong alerts only in active hours", subtitle: "Outside them, only soft reminders.") {
                    Toggle("Only use strong alerts during active hours", isOn: $store.settings.limitToActiveHours).toggleStyle(.sk1Switch)
                }
                if store.settings.limitToActiveHours {
                    SKRow(title: "Active hours") {
                        HStack(alignment: .top, spacing: 16) {
                            SKKnob("From", value: $store.settings.activeStartHour, in: 0...23, defaultValue: 8) { "\($0):00" }
                            SKKnob("Until", value: $store.settings.activeEndHour, in: 1...24, defaultValue: 19) { "\($0):00" }
                        }
                    }
                }
            }
            VStack(alignment: .leading, spacing: SK1.Metrics.captionToWell) {
                SKCaption("Calendars", tone: .soft).accessibilityAddTraits(.isHeader)
                SKWell {
                    Group {
                        if calendars.calendars.isEmpty {
                            Text("Connect a Google account or Apple Calendar to set alert strength for each calendar.").sk1Hint()
                        } else {
                            CalendarIntensityMatrix(calendars: calendars.calendars, defaultStyle: store.settings.style)
                                .disabled(!subs.isPremiumActive)
                                .opacity(subs.isPremiumActive ? 1 : 0.55)
                        }
                    }
                    .padding(SK1.Metrics.rowInset)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                if !subs.isPremiumActive { ProHint(text: "Set alert strength per calendar with Meetball Pro.") { showPaywall = true } }
                Text("Default follows the alert style above. Calendars set to Off never alert, whatever the rules below say.").sk1Hint()
            }
            SKGroup(caption: "Importance rules",
                    note: "Rules are checked from the top; the first one that matches sets the alert strength, overriding the calendar's setting.") {
                ImportanceRulesEditor(rules: $store.importanceRules)
                    .disabled(!subs.isPremiumActive)
                    .opacity(subs.isPremiumActive ? 1 : 0.55)
                if !subs.isPremiumActive { ProHint(text: "Make important meetings louder with Meetball Pro.") { showPaywall = true } }
            }
        }
        .sheet(isPresented: $showPaywall) { PaywallView() }
        .onChange(of: store.settings) { _, _ in manager.reschedule(events: calendars.meetingEvents) }
    }
}

/// Soft → Heads-up → Hard as tiles in a tray; the chosen one keeps its lamp lit. Pro styles carry a PRO legend for
/// free users.
struct EscalationLadder: View {
    @Binding var selection: AlertStyle
    let isPro: Bool

    var body: some View {
        SKWell {
            HStack(alignment: .top, spacing: 4) {
                ForEach(AlertStyle.allCases) { style in
                    SKTile(style.shortTitle, systemImage: style.symbol,
                           legend: style.isPro && !isPro ? "PRO" : Self.blurb(style), isOn: selection == style) {
                        selection = style
                    }
                    .accessibilityLabel(Text(style.title))
                }
            }
            .padding(6)
        }
        .padding(.vertical, 8)
    }

    static func blurb(_ s: AlertStyle) -> String {
        switch s {
        case .soft: return "notification"
        case .headsUp: return "corner card"
        case .hard: return "full screen"
        }
    }
}

/// "Next alert: Standup — heads-up in 4m" on an LCD strip, updated live.
struct NextAlertSummary: View {
    @EnvironmentObject var calendars: CalendarStore
    @EnvironmentObject var manager: MeetingGuardianManager
    @EnvironmentObject var store: MeetingGuardianStore
    @EnvironmentObject var subs: SubscriptionManager

    var body: some View {
        TimelineView(.periodic(from: .now, by: 15)) { ctx in
            let now = ctx.date
            if let next = manager.nextAlert(in: calendars.meetingEvents, now: now) {
                let reason = manager.policy.reason(for: next.event).map { " · \($0)" } ?? ""
                SKStatusStrip(title: "Next alert · \(next.event.title)",
                              detail: "\(next.style.shortTitle.uppercased()) IN \(TimeUntilFormatter.string(until: next.fireDate, now: now).uppercased())\(reason.uppercased())",
                              lamp: subs.isPremiumActive ? .success : .warning)
            } else {
                SKStatusStrip(title: "Meeting Guardian", detail: "NO ALERTS SCHEDULED", lamp: subs.isPremiumActive ? .success : .warning)
            }
        }
    }
}

/// Inline Pro badge with an upgrade button, shown next to controls free users can see but not change.
struct ProHint: View {
    let text: String
    let upgrade: () -> Void
    var body: some View {
        HStack(spacing: 8) {
            SKChip("PRO", minWidth: 32, height: 16)
            Text(text).sk1Hint()
            Spacer()
            Button("Upgrade", action: upgrade).buttonStyle(.sk1Key(size: .small))
        }
    }
}

/// Calendars (grouped by account) × Default / Off / Soft / Heads-up / Hard.
struct CalendarIntensityMatrix: View {
    let calendars: [GCalendar]
    let defaultStyle: AlertStyle
    @EnvironmentObject var store: MeetingGuardianStore

    private var groups: [(source: String, calendars: [GCalendar])] {
        var order: [String] = []; var by: [String: [GCalendar]] = [:]
        for c in calendars {
            if by[c.accountEmail] == nil { order.append(c.accountEmail) }
            by[c.accountEmail, default: []].append(c)
        }
        return order.map { ($0, by[$0] ?? []) }
    }

    /// nil = Default column.
    private let columns: [AlertIntensity?] = [nil] + AlertIntensity.allCases.map { Optional($0) }

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 6, verticalSpacing: 6) {
            GridRow {
                Text("")
                ForEach(Array(columns.enumerated()), id: \.offset) { _, c in
                    Text(c?.title ?? "Default").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        .frame(width: 62).gridColumnAlignment(.center)
                }
            }
            ForEach(groups, id: \.source) { group in
                GridRow {
                    Label(Self.sourceName(group.source), systemImage: AppleCalendarClient.isApple(group.source) ? "apple.logo" : "envelope")
                        .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        .gridCellColumns(columns.count + 1)
                        .padding(.top, 4)
                }
                ForEach(group.calendars) { cal in
                    GridRow {
                        HStack(spacing: 6) {
                            Circle().fill(Color(hex: cal.colorHex)).frame(width: 10, height: 10)
                            Text(cal.summary).lineLimit(1).truncationMode(.tail)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        ForEach(Array(columns.enumerated()), id: \.offset) { _, c in cell(cal, c) }
                    }
                }
            }
        }
    }

    private func cell(_ cal: GCalendar, _ column: AlertIntensity?) -> some View {
        let current = store.intensity(for: cal.key)
        let selected = current == column
        // The Default column also hints at what it resolves to.
        return Button { store.setIntensity(column, for: cal.key) } label: {
            Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                .font(.system(size: 14))
                .foregroundStyle(selected ? Self.tint(column ?? AlertIntensity(defaultStyle)) : Color.secondary.opacity(0.6))
                .frame(width: 62, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(column.map { "\($0.title) for \(cal.summary)" } ?? "Use the default (\(defaultStyle.shortTitle)) for \(cal.summary)")
        .accessibilityLabel("\(cal.summary): \(column?.title ?? "Default")")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    static func tint(_ i: AlertIntensity) -> Color {
        switch i {
        case .off: return .gray
        case .soft: return .blue
        case .headsUp: return .orange
        case .hard: return .red
        }
    }

    static func sourceName(_ s: String) -> String {
        AppleCalendarClient.isApple(s) ? "Apple Calendar · " + s.dropFirst(AppleCalendarClient.sourcePrefix.count) : s
    }
}

/// Ordered list of "condition → intensity" rules, one settings row each, with keys to add one of each kind.
struct ImportanceRulesEditor: View {
    @Binding var rules: [ImportanceRule]

    var body: some View {
        if rules.isEmpty {
            SKRow(title: "No rules yet", subtitle: "Add one to make some meetings louder or quieter than their calendar.") {
                SKLamp(color: .warning, lit: false, label: "No rules")
            }
        }
        ForEach($rules) { $rule in
            HStack(spacing: 8) {
                Toggle("On", isOn: $rule.enabled).toggleStyle(.sk1Square).help("Enabled")
                SKPicker(selection: $rule.kind, options: ImportanceKind.allCases.map { SKPicker<ImportanceKind>.Option($0, $0.title) },
                         stepper: false)
                if rule.kind == .titleContains {
                    SKTextField("Words", text: $rule.text, prompt: "Interview, Board", height: 28).frame(minWidth: 110)
                }
                Image(systemName: "arrow.right").foregroundStyle(.secondary).accessibilityHidden(true)
                SKPicker(selection: $rule.intensity, options: AlertIntensity.allCases.map { SKPicker<AlertIntensity>.Option($0, $0.title) },
                         stepper: false)
                Spacer(minLength: 0)
                Button { move(rule.id, by: -1) } label: { Image(systemName: "chevron.up") }
                    .buttonStyle(.sk1Key(.round, size: .small)).disabled(rules.first?.id == rule.id).help("Move up")
                    .accessibilityLabel("Move up")
                Button { move(rule.id, by: 1) } label: { Image(systemName: "chevron.down") }
                    .buttonStyle(.sk1Key(.round, size: .small)).disabled(rules.last?.id == rule.id).help("Move down")
                    .accessibilityLabel("Move down")
                Button { rules.removeAll { $0.id == rule.id } } label: { Image(systemName: "minus") }
                    .buttonStyle(.sk1Key(.round, size: .small)).help("Remove rule").accessibilityLabel("Remove rule")
            }
            .frame(minHeight: SK1.Metrics.rowMinHeight)
            .opacity(rule.enabled ? 1 : 0.6)
        }
        SKRow(title: "Add a rule") {
            HStack(spacing: 4) {
                ForEach(ImportanceKind.allCases) { k in
                    Button { rules.append(ImportanceRule(kind: k)) } label: { Label(Self.shortName(k), systemImage: "plus") }
                        .buttonStyle(.sk1Key(size: .small))
                        .help("\(k.title) → \(k.suggested.title)")
                }
            }
        }
    }

    static func shortName(_ k: ImportanceKind) -> String {
        switch k {
        case .externalAttendees: return "External"
        case .organizerIsMe: return "Mine"
        case .titleContains: return "Title"
        case .recurringDaily: return "Daily"
        }
    }

    private func move(_ id: UUID, by delta: Int) {
        guard let i = rules.firstIndex(where: { $0.id == id }) else { return }
        let j = i + delta
        guard rules.indices.contains(j) else { return }
        rules.swapAt(i, j)
    }
}
