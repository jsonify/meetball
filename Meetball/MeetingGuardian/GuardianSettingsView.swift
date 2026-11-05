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
                NextAlertSummary()
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
            Section {
                if calendars.calendars.isEmpty {
                    Text("Connect a Google account or Apple Calendar to set alert strength for each calendar.").foregroundStyle(.secondary)
                } else {
                    CalendarIntensityMatrix(calendars: calendars.calendars, defaultStyle: store.settings.style)
                        .disabled(!subs.isPremiumActive)
                        .opacity(subs.isPremiumActive ? 1 : 0.55)
                }
                if !subs.isPremiumActive { ProHint(text: "Set alert strength per calendar with Meetball Pro.") { showPaywall = true } }
            } header: {
                Text("Calendars")
            } footer: {
                Text("Default follows the alert style above. Calendars set to Off never alert, whatever the rules below say.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                ImportanceRulesEditor(rules: $store.importanceRules)
                    .disabled(!subs.isPremiumActive)
                    .opacity(subs.isPremiumActive ? 1 : 0.55)
                if !subs.isPremiumActive { ProHint(text: "Make important meetings louder with Meetball Pro.") { showPaywall = true } }
            } header: {
                Text("Importance rules")
            } footer: {
                Text("Rules are checked from the top; the first one that matches sets the alert strength, overriding the calendar's setting.")
                    .font(.caption).foregroundStyle(.secondary)
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

/// "Next alert: Standup — heads-up in 4m", updated live.
struct NextAlertSummary: View {
    @EnvironmentObject var calendars: CalendarStore
    @EnvironmentObject var manager: MeetingGuardianManager
    @EnvironmentObject var store: MeetingGuardianStore

    var body: some View {
        TimelineView(.periodic(from: .now, by: 15)) { ctx in
            let now = ctx.date
            HStack(spacing: 8) {
                Image(systemName: "alarm").foregroundStyle(Color.accentColor)
                if let next = manager.nextAlert(in: calendars.meetingEvents, now: now) {
                    let reason = manager.policy.reason(for: next.event).map { " · \($0)" } ?? ""
                    (Text("Next alert: ").foregroundStyle(.secondary)
                     + Text(next.event.title).bold()
                     + Text(" — \(next.style.shortTitle.lowercased()) in \(TimeUntilFormatter.string(until: next.fireDate, now: now))\(reason)")
                        .foregroundStyle(.secondary))
                        .lineLimit(1)
                } else {
                    Text("No alerts scheduled in the loaded calendar range.").foregroundStyle(.secondary)
                }
            }
            .font(.callout)
        }
    }
}

/// Inline Pro badge with an upgrade button, shown next to controls free users can see but not change.
struct ProHint: View {
    let text: String
    let upgrade: () -> Void
    var body: some View {
        HStack(spacing: 8) {
            Text("PRO").font(.system(size: 9, weight: .bold)).padding(.horizontal, 4).padding(.vertical, 1)
                .background(Color.orange.opacity(0.2), in: Capsule()).foregroundStyle(.orange)
            Text(text).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Button("Upgrade", action: upgrade).controlSize(.small)
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

/// Ordered list of "condition → intensity" rules.
struct ImportanceRulesEditor: View {
    @Binding var rules: [ImportanceRule]

    var body: some View {
        if rules.isEmpty {
            Text("No rules yet. Add one to make some meetings louder or quieter than their calendar.")
                .font(.callout).foregroundStyle(.secondary)
        }
        ForEach($rules) { $rule in
            HStack(spacing: 8) {
                Toggle("", isOn: $rule.enabled).labelsHidden().toggleStyle(.checkbox).help("Enabled")
                Picker("", selection: $rule.kind) {
                    ForEach(ImportanceKind.allCases) { Text($0.title).tag($0) }
                }
                .labelsHidden().fixedSize()
                if rule.kind == .titleContains {
                    TextField("", text: $rule.text, prompt: Text("Interview, Board"))
                        .textFieldStyle(.roundedBorder).frame(minWidth: 90)
                }
                Image(systemName: "arrow.right").foregroundStyle(.secondary)
                Picker("", selection: $rule.intensity) {
                    ForEach(AlertIntensity.allCases) { Text($0.title).tag($0) }
                }
                .labelsHidden().fixedSize()
                Spacer(minLength: 0)
                Button { move(rule.id, by: -1) } label: { Image(systemName: "chevron.up") }
                    .buttonStyle(.borderless).disabled(rules.first?.id == rule.id).help("Move up")
                Button { move(rule.id, by: 1) } label: { Image(systemName: "chevron.down") }
                    .buttonStyle(.borderless).disabled(rules.last?.id == rule.id).help("Move down")
                Button { rules.removeAll { $0.id == rule.id } } label: { Image(systemName: "minus.circle") }
                    .buttonStyle(.borderless).help("Remove rule")
            }
            .opacity(rule.enabled ? 1 : 0.6)
        }
        Menu("Add rule") {
            ForEach(ImportanceKind.allCases) { k in
                Button("\(k.title) → \(k.suggested.title)") { rules.append(ImportanceRule(kind: k)) }
            }
        }
        .fixedSize()
    }

    private func move(_ id: UUID, by delta: Int) {
        guard let i = rules.firstIndex(where: { $0.id == id }) else { return }
        let j = i + delta
        guard rules.indices.contains(j) else { return }
        rules.swapAt(i, j)
    }
}
