import SwiftUI
import SK1Tokens
import SK1UI

struct CalendarContainerView: View {
    @EnvironmentObject var store: CalendarStore
    @EnvironmentObject var session: SessionManager
    @AppStorage(OnboardingState.Key.completed) private var onboardingCompleted = false
    @AppStorage(AppPreferences.Key.firstWeekday) private var firstWeekday = 0
    @AppStorage(AppPreferences.Key.clockStyle) private var clockStyle = ClockStyle.system.rawValue

    var body: some View {
        Group {
            if !onboardingCompleted || !store.hasAnySource {
                OnboardingView()
                    .sk1WindowChrome(centered: true) { SK1WindowTitle(text: "Setup") }
                    .sk1Chassis()
            } else {
                // Skreener's editor: no stock title bar or toolbar, "MB-1  CALENDAR — …" centred in the title strip
                // with a grille at the right, then the sidebar beside the content on one chassis.
                HStack(spacing: 0) {
                    CalendarSidebarView().listStyle(.sidebar).scrollContentBackground(.hidden).frame(width: 220)
                    SKGroove(.vertical)
                    detail.scrollContentBackground(.hidden).frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .sk1WindowChrome(centered: true) { SK1WindowTitle(text: windowTitle) }
                .sk1Chassis()
            }
        }
        // Rebuild the calendar views when the first weekday or the clock changes (they read them outside SwiftUI).
        .id("\(firstWeekday)|\(clockStyle)")
        .sheet(item: $store.composer) { composer in
            switch composer {
            case .quickAdd(let range):
                QuickAddView(range: range, onMoreOptions: { store.composer = .form($0) }, onClose: { store.composer = nil })
            case .form(let draft):
                EventFormView(draft: draft)
            }
        }
        .alert("Something went wrong", isPresented: Binding(get: { store.actionError != nil }, set: { if !$0 { store.actionError = nil } })) {
            Button("OK") { store.actionError = nil }
        } message: { Text(store.actionError ?? "") }
        .task { store.startAutoRefresh() }
        .modifier(RegistersWindowOpener())
    }

    @ViewBuilder private var detail: some View {
        if store.section == .upcoming {
            UpcomingView { store.composer = .quickAdd(nil) }
        } else {
            VStack(spacing: 0) {
                header
                SKGroove()
                switch store.viewMode {
                case .month:
                    HSplitView {
                        SKWell { MonthGridView().padding(6) }
                            .padding(12)
                            .frame(minWidth: 520)
                        DayEventsListView().frame(minWidth: 260, idealWidth: 300)
                    }
                case .week, .day:
                    TimeGridView(days: store.displayedDays) { start, end in
                        store.composer = .quickAdd(NewEventDateRange(start: start, end: end))
                    }
                }
            }
            .background(KeyEventMonitor(handler: handleKey))
            // Events the filters hide are drawn at the fade from Settings › Events.
            .environment(\.calendarFilterSettings, store.filters)
        }
    }

    /// Captioned key trays, as Skreener's editor toolbar, over the LCD display.
    var header: some View {
        VStack(spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                SKKeyTray(caption: "View") {
                    ForEach(CalendarViewMode.allCases) { mode in
                        Button(mode.title) { store.viewMode = mode }
                            .buttonStyle(.sk1Key(isOn: store.viewMode == mode))
                            .help("\(mode.title) (⌘\(String(mode.shortcut)))")
                    }
                }
                SKKeyTray(caption: "Go") {
                    Button { store.step(-1) } label: { Image(systemName: "chevron.left") }
                        .buttonStyle(.sk1Key()).help(store.viewMode == .month ? "Previous month (⌘←)" : "Previous (←)")
                        .accessibilityLabel("Previous")
                    Button("Today") { store.goToday() }.buttonStyle(.sk1Key()).help("Today (T)")
                    Button { store.step(1) } label: { Image(systemName: "chevron.right") }
                        .buttonStyle(.sk1Key()).help(store.viewMode == .month ? "Next month (⌘→)" : "Next (→)")
                        .accessibilityLabel("Next")
                }
                SyncKeyTray()
                Spacer(minLength: 8)
                SKKeyTray(caption: "New") {
                    Button { store.composer = .quickAdd(nil) } label: { Label("Event", systemImage: "plus") }
                        .buttonStyle(.sk1Key(.orange)).help("Quick add an event (⌘N)")
                }
            }
            MainStatusDisplay(title: store.viewMode.title,
                              detail: store.selectedDay.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
        }
        .padding(12)
    }

    /// What the title strip says after the nickname: the section, and in the calendar the period shown.
    private var windowTitle: String {
        store.section == .upcoming ? "Upcoming" : "Calendar \u{2014} \(title)"
    }

    private var title: String {
        switch store.viewMode {
        case .month:
            return store.anchor.formatted(.dateTime.month(.wide).year())
        case .day:
            return store.selectedDay.formatted(.dateTime.weekday(.wide).month(.wide).day().year())
        case .week:
            let days = store.displayedDays
            guard let first = days.first, let last = days.last else { return "" }
            let cal = Calendar.app
            if cal.isDate(first, equalTo: last, toGranularity: .month) {
                return "\(first.formatted(.dateTime.month(.wide).day())) – \(last.formatted(.dateTime.day())), \(last.formatted(.dateTime.year()))"
            }
            if cal.isDate(first, equalTo: last, toGranularity: .year) {
                return "\(first.formatted(.dateTime.month(.abbreviated).day())) – \(last.formatted(.dateTime.month(.abbreviated).day())), \(last.formatted(.dateTime.year()))"
            }
            return "\(first.formatted(.dateTime.month(.abbreviated).day().year())) – \(last.formatted(.dateTime.month(.abbreviated).day().year()))"
        }
    }

    /// Keys, ignored while typing or with ⌥/⌃ held:
    /// - Month: arrows move the selected day (↑↓ by a week), ⌘← / ⌘→ change month, Return opens the day.
    /// - Day and week: ← / → previous and next period.
    /// - Everywhere: T today, J / K next and previous day.
    private func handleKey(_ e: NSEvent) -> Bool {
        let mods = e.modifierFlags.intersection([.command, .option, .control])
        guard mods.isEmpty || mods == .command else { return false }
        let command = mods == .command
        let month = store.viewMode == .month
        switch Int(e.keyCode) {
        case 123: if month && !command { store.moveSelectedDay(-1) } else if month || !command { store.step(-1) } else { return false }; return true   // ←
        case 124: if month && !command { store.moveSelectedDay(1) } else if month || !command { store.step(1) } else { return false }; return true     // →
        case 125 where month && !command: store.moveSelectedDay(7); return true   // ↓
        case 126 where month && !command: store.moveSelectedDay(-7); return true  // ↑
        case 36 where month && !command: store.viewMode = .day; return true       // Return
        default: break
        }
        guard !command else { return false }
        switch e.charactersIgnoringModifiers?.lowercased() {
        case "t": store.goToday(); return true
        case "j": store.moveSelectedDay(1); return true
        case "k": store.moveSelectedDay(-1); return true
        default: return false
        }
    }
}

/// The Sync tray: refresh (⌘R), with a lamp that blinks while syncing and turns red after a failed sync. Its help
/// says when the last good sync was.
struct SyncKeyTray: View {
    @EnvironmentObject var store: CalendarStore

    var body: some View {
        SKKeyTray(caption: "Sync") {
            TimelineView(.periodic(from: .now, by: 30)) { ctx in
                Button { store.refresh(.user) } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.clockwise")
                        SKLamp(color: lampColor, lit: true, glow: 0, size: 5, blinking: store.isRefreshing)
                    }
                }
                .buttonStyle(.sk1Key())
                .help(SyncStatusText.help(lastSynced: store.lastSynced, refreshing: store.isRefreshing, failed: failed, now: ctx.date))
                .accessibilityLabel("Refresh")
                .accessibilityValue(SyncStatusText.help(lastSynced: store.lastSynced, refreshing: store.isRefreshing, failed: failed, now: ctx.date))
            }
        }
    }

    private var failed: Bool { if case .failed = store.loadState { return true } else { return false } }
    private var lampColor: SKLampColor { failed ? .danger : (store.isRefreshing ? .teal : .success) }
}

/// "Synced 3 min ago", for the Sync key and the sidebar.
enum SyncStatusText {
    static func help(lastSynced: Date?, refreshing: Bool, failed: Bool, now: Date) -> String {
        if refreshing { return "Syncing\u{2026} (⌘R)" }
        let last = lastSynced.map { "Last synced \(ago($0, now: now))" } ?? "Not synced yet"
        return (failed ? "The last sync failed. " : "") + last + ". Refresh (⌘R)"
    }

    static func ago(_ date: Date, now: Date) -> String {
        let s = max(0, Int(now.timeIntervalSince(date)))
        if s < 60 { return "just now" }
        if s < 3600 { return "\(s / 60) min ago" }
        return "at \(date.shortTime)"
    }
}

/// Installs a local key-down monitor scoped to the hosting window (skips text editing and sheets).
struct KeyEventMonitor: NSViewRepresentable {
    let handler: (NSEvent) -> Bool

    func makeNSView(context: Context) -> MonitorView {
        let v = MonitorView(); v.handler = handler; return v
    }
    func updateNSView(_ v: MonitorView, context: Context) { v.handler = handler }

    final class MonitorView: NSView {
        var handler: ((NSEvent) -> Bool)?
        private var monitor: Any?

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] ev in
                guard let self, let w = self.window, ev.window === w, w.attachedSheet == nil,
                      !(w.firstResponder is NSText) else { return ev }
                return self.handler?(ev) == true ? nil : ev
            }
        }
    }
}

struct CalendarSidebarView: View {
    @EnvironmentObject var store: CalendarStore
    @EnvironmentObject var session: SessionManager
    private var sectionTitles: [String] {
        session.accounts.map(\.email) + Array(Set(store.calendars.map(\.accountEmail).filter(AppleCalendarClient.isApple))).sorted()
    }
    var body: some View {
        List {
            Section {
                SidebarNavRow(title: "Upcoming", symbol: "clock", selected: store.section == .upcoming, shortcut: "⌘0") {
                    store.section = .upcoming
                }
                SidebarNavRow(title: "Calendar", symbol: "calendar", selected: store.section == .calendar, shortcut: "⌘1–3") {
                    store.section = .calendar
                }
            }
            SidebarStatusSection()
            if !store.calendars.isEmpty { workOnlySection }
            ForEach(sectionTitles, id: \.self) { title in
                Section {
                    ForEach(store.calendars.filter { $0.accountEmail == title }) { cal in
                        HStack(spacing: 4) {
                            Toggle(isOn: Binding(get: { !store.hiddenCalendarKeys.contains(cal.key) }, set: { _ in store.toggle(cal) })) {
                                HStack { Circle().fill(Color(hex: cal.colorHex)).frame(width: 9, height: 9).accessibilityHidden(true)
                                    Text(cal.summary).lineLimit(1) }
                            }
                            .toggleStyle(.sk1Square)
                            .help(store.hiddenCalendarKeys.contains(cal.key) ? "Show \(cal.summary)" : "Hide \(cal.summary)")
                            .opacity(store.isShown(cal.key) || store.hiddenCalendarKeys.contains(cal.key) ? 1 : 0.45)
                            Spacer(minLength: 0)
                            workButton(cal)
                        }
                        .contextMenu {
                            Button(store.isWork(cal) ? "Unmark as Work Calendar" : "Mark as Work Calendar") { store.toggleWork(cal) }
                        }
                    }
                } header: {
                    SKCaption(title, tone: .soft)
                }
            }
        }
        .motionAwareAnimation(value: store.calendars)
    }

    /// "Work only" (#52): show just the calendars marked with the briefcase.
    private var workOnlySection: some View {
        Section {
            Toggle(isOn: Binding(get: { store.isWorkOnly }, set: { _ in store.toggleWorkOnly() })) {
                Label("Work only", systemImage: "briefcase")
            }
            .toggleStyle(.sk1Switch)
            .disabled(store.workCalendarKeys.isEmpty)
            .help(store.workCalendarKeys.isEmpty ? "Mark work calendars with the briefcase beside them first"
                                                 : "Show only work calendars (⇧⌘O)")
            if store.workCalendarKeys.isEmpty {
                Text("Click the briefcase beside a calendar to mark it as work.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func workButton(_ cal: GCalendar) -> some View {
        let work = store.isWork(cal)
        return Button { store.toggleWork(cal) } label: {
            Image(systemName: work ? "briefcase.fill" : "briefcase")
                .font(.caption)
                .foregroundStyle(work ? Color(sk1Hex: SK1.orange) : Color.secondary.opacity(0.5))
        }
        .buttonStyle(.plain)
        .help(work ? "Work calendar. Click to unmark." : "Mark \(cal.summary) as a work calendar")
        .accessibilityLabel(work ? "Unmark \(cal.summary) as work" : "Mark \(cal.summary) as work")
    }
}

/// The sidebar's loading, error and permission states, each with the action that fixes it.
private struct SidebarStatusSection: View {
    @EnvironmentObject var store: CalendarStore
    @EnvironmentObject var session: SessionManager

    var body: some View {
        if store.loadState == .loading && store.calendars.isEmpty {
            Section {
                ForEach(0..<4, id: \.self) { i in
                    HStack { Circle().frame(width: 9, height: 9); Text(String(repeating: "x", count: 10 + i * 3)) }
                }
                .redacted(reason: .placeholder)
                .modifier(Shimmer())
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Loading calendars")
            }
        }
        if !session.accounts.isEmpty && session.lastError != nil || !store.expiredAccounts.isEmpty {
            Section {
                notice(lamp: .warning, text: session.lastError ?? "Your Google sign-in has expired.") {
                    Button("Reconnect") { Task { await session.addAccount() } }
                        .buttonStyle(.sk1Key(size: .small)).disabled(session.state == .signingIn)
                }
            }
        }
        if store.appleAccessDenied {
            Section {
                notice(lamp: .danger, text: "Meetball can't read Apple Calendar: access is off.") {
                    Button("Open System Settings") { SystemSettingsLink.open(SystemSettingsLink.calendars) }
                        .buttonStyle(.sk1Key(size: .small))
                }
            }
        } else if case .failed(let message) = store.loadState {
            Section {
                notice(lamp: .danger, text: SyncErrorText.friendly(message)) {
                    Button("Try Again") { store.refresh(.user) }.buttonStyle(.sk1Key(size: .small))
                }
            }
        } else if store.loadState == .loaded && store.calendars.isEmpty {
            Section {
                notice(lamp: .warning, text: "No calendars found on your connected accounts.") {
                    SettingsLink { Text("Accounts\u{2026}") }.buttonStyle(.sk1Key(size: .small))
                }
            }
        }
    }

    private func notice<Action: View>(lamp: SKLampColor, text: String, @ViewBuilder action: () -> Action) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                SKLamp(color: lamp, lit: true, size: 6).accessibilityHidden(true)
                Text(text).font(.caption).fixedSize(horizontal: false, vertical: true)
            }
            action()
        }
        .padding(.vertical, 4)
    }
}

/// Turns raw sync errors into a sentence with what to do.
enum SyncErrorText {
    static func friendly(_ raw: String) -> String {
        let l = raw.lowercased()
        if l.contains("offline") || l.contains("internet") || l.contains("network connection") || l.contains("timed out") {
            return "You're offline. Meetball will sync when the connection is back."
        }
        if l.contains("401") || l.contains("invalid_grant") || l.contains("unauthorized") {
            return "Google needs you to sign in again."
        }
        return "Couldn't sync your calendars. \(raw)"
    }
}

/// A soft sweep of light over placeholder content while it loads; still with Reduce Motion.
struct Shimmer: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = -1

    func body(content: Content) -> some View {
        content
            .overlay {
                if !reduceMotion {
                    GeometryReader { geo in
                        LinearGradient(colors: [.clear, .white.opacity(0.35), .clear], startPoint: .leading, endPoint: .trailing)
                            .frame(width: geo.size.width * 0.5)
                            .offset(x: phase * geo.size.width * 1.5)
                    }
                    .allowsHitTesting(false)
                    .mask(content)
                }
            }
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) { phase = 1 }
            }
    }
}

private struct SidebarNavRow: View {
    let title: String; let symbol: String; let selected: Bool; let shortcut: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .fontWeight(selected ? .semibold : .regular)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 3).padding(.horizontal, 6)
                .background(selected ? Color(sk1Hex: SK1.orange, opacity: 0.16) : .clear, in: RoundedRectangle(cornerRadius: SK1.Metrics.keyRadius))
                .overlay(alignment: .leading) {
                    // The SK-1 "on" bar beside the chosen section.
                    if selected { RoundedRectangle(cornerRadius: 1).fill(Color(sk1Hex: SK1.orange)).frame(width: 3, height: 14) }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("\(title) (\(shortcut))")
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

struct MonthGridView: View {
    @EnvironmentObject var store: CalendarStore
    @AppStorage(AppPreferences.Key.density) private var densityRaw = LayoutDensity.comfortable.rawValue
    @AppStorage(AppPreferences.Key.weekNumbers) private var showWeekNumbers = false
    @AppStorage(AppPreferences.Key.highlightWeekends) private var highlightWeekends = true
    private let headerH: CGFloat = 22
    private var laneH: CGFloat { (LayoutDensity(rawValue: densityRaw) ?? .comfortable).monthLaneHeight }
    private let weekNumberWidth: CGFloat = 26

    var body: some View {
        let d = store.derived
        let cal = Calendar.app
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                if showWeekNumbers { SKCaption("Wk", tone: .soft).frame(width: weekNumberWidth) }
                ForEach(cal.shortWeekdaySymbols.rotated(cal.firstWeekday - 1), id: \.self) {
                    SKCaption($0, tone: .soft).frame(maxWidth: .infinity)
                }
            }.padding(.vertical, 4)
            ForEach(d.weeks, id: \.weekStart) { week in
                HStack(spacing: 0) {
                    if showWeekNumbers {
                        Text("\(cal.component(.weekOfYear, from: week.weekStart))")
                            .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                            .frame(width: weekNumberWidth).frame(maxHeight: .infinity, alignment: .top).padding(.top, 5)
                            .accessibilityLabel("Week \(cal.component(.weekOfYear, from: week.weekStart))")
                    }
                    GeometryReader { geo in
                        let colW = geo.size.width / 7
                        ZStack(alignment: .topLeading) {
                            HStack(spacing: 0) {
                                ForEach(0..<7, id: \.self) { i in
                                    let day = cal.date(byAdding: .day, value: i, to: week.weekStart)!
                                    dayCell(day, segments: d.segmentsByDay[day] ?? [], laneCount: week.laneCount)
                                        .frame(width: colW, height: geo.size.height)
                                }
                            }
                            ForEach(week.spans.filter { $0.lane < 3 }) { span in
                                Text(span.event.title).font(.caption2.weight(.medium)).lineLimit(1).padding(.horizontal, 4)
                                    .frame(width: colW * CGFloat(span.endColumn - span.startColumn + 1) - 7, height: laneH - 2, alignment: .leading)
                                    .eventChip(span.event.colorHex)
                                    .calendarFade(span.event, otherwise: span.event.isDeclined ? 0.5 : 1)
                                    .eventDetailOnClick(span.event, arrowEdge: .bottom)
                                    .help(span.event.title)
                                    .offset(x: colW * CGFloat(span.startColumn) + 2, y: headerH + CGFloat(span.lane) * laneH)
                            }
                        }
                    }
                }
                SKGroove()
            }
        }
        .motionAwareAnimation(value: store.selectedDay)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Month grid. Arrow keys move the selected day; Return opens it.")
    }

    @ViewBuilder func dayCell(_ day: Date, segments: [CalendarEventDaySegment], laneCount: Int) -> some View {
        let cal = Calendar.app
        let isSel = cal.isDate(day, inSameDayAs: store.selectedDay)
        let inMonth = cal.isDate(day, equalTo: store.anchor, toGranularity: .month)
        let isToday = cal.isDateInToday(day)
        let weekend = highlightWeekends && cal.isDateInWeekend(day)
        let timed = segments.filter { !isBar($0.event) }
        VStack(alignment: .leading, spacing: 1) {
            Text("\(cal.component(.day, from: day))").font(.caption.bold())
                .frame(width: 20, height: 20).background(isToday ? Color(sk1Hex: SK1.orange) : .clear, in: Circle())
                .foregroundStyle(isToday ? .white : (inMonth ? .primary : .secondary))
            Spacer().frame(height: CGFloat(min(laneCount, 3)) * laneH - 2)
            ForEach(timed.prefix(2)) { seg in
                HStack(spacing: 3) { Circle().fill(Color(hex: seg.event.colorHex)).frame(width: 5, height: 5)
                    Text(seg.event.title).font(.caption2).lineLimit(1) }
                    .calendarFade(seg.event)
            }
            if timed.count > 2 {
                Text("+\(timed.count - 2) more").font(.caption2).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(3).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(weekend ? Color.secondary.opacity(0.06) : .clear)
        .background(isSel ? Color(sk1Hex: SK1.orange, opacity: 0.10) : .clear)
        .overlay(Rectangle().stroke(Color.secondary.opacity(0.15), lineWidth: 0.5))
        .overlay { if isSel { Rectangle().stroke(Color(sk1Hex: SK1.orange, opacity: 0.6), lineWidth: 1.5) } }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { store.select(day); store.viewMode = .day }
        .onTapGesture { store.selectedDay = day }
        .help("Double-click to open the day")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.accessibilityLabel(day, events: segments.count, today: isToday))
        .accessibilityAddTraits(isSel ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { store.selectedDay = day }
        .accessibilityAction(named: "Open day") { store.select(day); store.viewMode = .day }
    }

    static func accessibilityLabel(_ day: Date, events: Int, today: Bool) -> String {
        let date = day.formatted(.dateTime.weekday(.wide).month(.wide).day())
        let count = events == 0 ? "no events" : events == 1 ? "1 event" : "\(events) events"
        return (today ? "Today, " : "") + "\(date), \(count)"
    }
    private func isBar(_ e: CalendarEvent) -> Bool { e.isBarEvent() }
}

extension Array {
    func rotated(_ n: Int) -> [Element] { isEmpty ? self : Array(self[(n % count)...] + self[..<(n % count)]) }
}

struct DayEventsListView: View {
    @EnvironmentObject var store: CalendarStore
    @AppStorage(AppPreferences.Key.density) private var densityRaw = LayoutDensity.comfortable.rawValue

    var body: some View {
        let segs = store.derived.segmentsByDay[store.selectedDay] ?? []
        let density = LayoutDensity(rawValue: densityRaw) ?? .comfortable
        VStack(alignment: .leading) {
            HStack {
                SKCaption(store.selectedDay.formatted(.dateTime.weekday(.wide).month().day()), tone: .soft)
                Spacer()
                Button { store.composer = .quickAdd(NewEventDateRangeBuilder.build(day: store.selectedDay)) } label: { Image(systemName: "plus") }
                    .buttonStyle(.sk1Key(.round, size: .small))
                    .help("New event on this day").accessibilityLabel("New event on this day")
            }
            .padding([.top, .horizontal], 12)
            if segs.isEmpty {
                EmptyStateView(symbol: "calendar.badge.checkmark", title: "Nothing on this day",
                               detail: store.loadState == .loading ? "Loading\u{2026}" : "A free day. Add something, or pick another day.") {
                    Button("Add Event") { store.composer = .quickAdd(NewEventDateRangeBuilder.build(day: store.selectedDay)) }
                        .buttonStyle(.sk1Key(size: .small))
                }
                Spacer()
            } else {
                List(segs) { seg in
                    HStack(alignment: .top) {
                        RoundedRectangle(cornerRadius: 2).fill(Color(hex: seg.event.colorHex)).frame(width: 4).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(seg.event.title).bold()
                            Text(seg.timeRangeText()).font(.caption).foregroundStyle(.secondary)
                            if let l = seg.event.location, !l.isEmpty { Text(l).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                        }
                        Spacer()
                        JoinButton(event: seg.event, size: .small, key: .cream)
                    }
                    .padding(.vertical, density.rowPadding)
                    .calendarFade(seg.event, otherwise: seg.event.isDeclined ? 0.5 : 1)
                    .eventDetailOnClick(seg.event, arrowEdge: .leading)
                    .contextMenu {
                        MeetingSecondaryActions(event: seg.event)
                        Divider()  // sk1-audit: ignore (a menu item separator)
                        Button("Delete", role: .destructive) { Task { await store.delete(seg.event) } }
                    }
                }
                .motionAwareAnimation(value: segs.map(\.id))
            }
        }
    }
}

/// An empty, offline or error state: a symbol, what's going on, and what to do about it.
struct EmptyStateView<Action: View>: View {
    let symbol: String
    let title: String
    var detail: String?
    @ViewBuilder var action: () -> Action

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 30, weight: .light)).foregroundStyle(.secondary)
                .symbolRenderingMode(.hierarchical).accessibilityHidden(true)
            Text(title).font(.headline)
            if let detail { Text(detail).sk1Hint().multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true) }
            action()
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .accessibilityElement(children: .combine)
    }
}

extension EmptyStateView where Action == EmptyView {
    init(symbol: String, title: String, detail: String? = nil) {
        self.init(symbol: symbol, title: title, detail: detail, action: { EmptyView() })
    }
}

struct EventFormView: View {
    @EnvironmentObject var store: CalendarStore
    @Environment(\.dismiss) private var dismiss
    @State private var draft: NewEventDraft
    @State private var attendeeText = ""
    @State private var attendeeError: String?
    @State private var saving = false

    init(day: Date) {
        let r = NewEventDateRangeBuilder.build(day: day)
        self.init(start: r.start, end: r.end)
    }

    init(start: Date, end: Date) {
        _draft = State(initialValue: NewEventDraft(start: start, end: end))
    }

    /// The full form, filled in from quick add's "More Options".
    init(draft: NewEventDraft) {
        _draft = State(initialValue: draft)
    }
    private var writable: [GCalendar] { store.calendars.filter(\.canWrite) }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: SK1.Metrics.groupSpacing) {
                    SKGroup(caption: "Event") {
                        SKRow(title: "Title") {
                            SKTextField("Title", text: $draft.title, prompt: "Weekly sync with Anna", height: 30).frame(width: 260)
                        }
                        SKRow(title: "Focus block", subtitle: "Time for yourself: no attendees or Meet link.") {
                            Toggle("Focus block", isOn: $draft.isFocusBlock).toggleStyle(.sk1Switch)
                        }
                        SKRow(title: "Starts") {
                            HStack(spacing: 8) {
                                MonthDayPicker(selection: $draft.start, name: "Start day")
                                DatePicker("Starts", selection: $draft.start, displayedComponents: .hourAndMinute).labelsHidden()
                            }
                            .onChange(of: draft.start) { _, s in if draft.end <= s { draft.end = s.addingTimeInterval(1800) } }
                        }
                        SKRow(title: "Ends", subtitle: DurationFormatter.string(from: draft.start, to: draft.end)) {
                            HStack(spacing: 8) {
                                MonthDayPicker(selection: $draft.end, name: "End day")
                                DatePicker("Ends", selection: $draft.end, in: draft.start..., displayedComponents: .hourAndMinute)
                                    .labelsHidden()
                            }
                            .onChange(of: draft.end) { _, e in if e <= draft.start { draft.end = draft.start.addingTimeInterval(1800) } }
                        }
                        SKRow(title: "Calendar") {
                            SKPicker(selection: $draft.calendar,
                                     options: writable.map { SKPicker<GCalendar?>.Option($0, $0.summary) }, stepper: false)
                        }
                        SKRow(title: "Add a Google Meet link",
                              subtitle: meetUnavailable ? "This calendar doesn't allow Google Meet conferences." : nil) {
                            Toggle("Add Google Meet link", isOn: $draft.addMeet).toggleStyle(.sk1Switch).disabled(meetUnavailable)
                        }
                    }
                    SKGroup(caption: "Attendees", note: attendeeError) {
                        SKRow(title: "Invite") {
                            HStack(spacing: 6) {
                                if attendeeError != nil { SKLamp(color: .danger, lit: true, label: "Check the address") }
                                SKTextField("Attendee email", text: $attendeeText, prompt: "name@example.com", height: 30)
                                    .frame(width: 220)
                                    .onSubmit(addAttendee)
                                Button("Add", action: addAttendee).buttonStyle(.sk1Key())
                            }
                        }
                        if !draft.attendees.isEmpty {
                            FlowWrap(spacing: 6) {
                                ForEach(draft.attendees, id: \.self) { a in
                                    Button { draft.attendees.removeAll { $0 == a } } label: { Label(a, systemImage: "xmark") }
                                        .buttonStyle(.sk1Key(size: .small))
                                        .help("Remove \(a)")
                                }
                            }
                            .padding(.vertical, 10)
                        }
                    }
                }
                .padding(SK1.Metrics.paneMargin)
            }
            SKGroove()
            HStack(spacing: 8) {
                Spacer()
                Button("Cancel") { dismiss() }.buttonStyle(.sk1Key())
                Button("Save") { Task { saving = true; if await store.create(draft) { dismiss() }; saving = false } }
                    .buttonStyle(.sk1Key(.orange)).disabled(saving || draft.calendar == nil)
            }
            .padding(12)
        }
        .frame(width: 540, height: 580)
        .sk1Chassis()
        .onAppear { draft.calendar = draft.calendar ?? writable.first(where: \.isPrimary) ?? writable.first }
    }

    private var meetUnavailable: Bool { !(draft.calendar?.allowsMeet ?? false) }

    func addAttendee() {
        let e = attendeeText.trimmingCharacters(in: .whitespaces)
        guard !e.isEmpty else { return }
        if !EmailValidator.isValid(e) { attendeeError = "Enter a valid email address."; return }
        if draft.attendees.contains(e) { attendeeError = "This attendee is already added."; return }
        draft.attendees.append(e); attendeeText = ""; attendeeError = nil
    }
}
