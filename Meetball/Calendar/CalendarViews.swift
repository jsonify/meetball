import SwiftUI
import SK1Tokens
import SK1UI

struct CalendarContainerView: View {
    @EnvironmentObject var store: CalendarStore
    @EnvironmentObject var session: SessionManager
    @State private var showForm = false
    @State private var formRange: NewEventDateRange?

    var body: some View {
        NavigationSplitView {
            // The sidebar column draws its own material, so the chassis goes on each column, not behind the split view.
            CalendarSidebarView().scrollContentBackground(.hidden).sk1Chassis()
        } detail: {
            detail.scrollContentBackground(.hidden).sk1Chassis()
        }
        .sheet(isPresented: $showForm, onDismiss: { formRange = nil }) {
            if let r = formRange { EventFormView(start: r.start, end: r.end) } else { EventFormView(day: store.selectedDay) }
        }
        .alert("Something went wrong", isPresented: Binding(get: { store.actionError != nil }, set: { if !$0 { store.actionError = nil } })) {
            Button("OK") { store.actionError = nil }
        } message: { Text(store.actionError ?? "") }
        .task { store.startAutoRefresh() }
    }

    @ViewBuilder private var detail: some View {
        if !store.hasAnySource {
            ConnectPrompt()
        } else if store.section == .upcoming {
            UpcomingView { formRange = nil; showForm = true }
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
                        DayEventsListView(showForm: $showForm).frame(minWidth: 260, idealWidth: 300)
                    }
                case .week, .day:
                    TimeGridView(days: store.displayedDays) { start, end in
                        formRange = NewEventDateRange(start: start, end: end)
                        showForm = true
                    }
                }
            }
            .background(KeyEventMonitor(handler: handleKey))
        }
    }

    /// Captioned key trays, as Skreener's editor toolbar, over the LCD display.
    var header: some View {
        VStack(spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Text(title).font(.title2.bold()).lineLimit(1).padding(.top, 3)
                Spacer(minLength: 8)
                SKKeyTray(caption: "View") {
                    ForEach(CalendarViewMode.allCases) { mode in
                        Button(mode.title) { store.viewMode = mode }
                            .buttonStyle(.sk1Key(isOn: store.viewMode == mode))
                            .help("\(mode.title) (⌘\(String(mode.shortcut)))")
                    }
                }
                SKKeyTray(caption: "Go") {
                    Button { store.step(-1) } label: { Image(systemName: "chevron.left") }
                        .buttonStyle(.sk1Key()).help("Previous (←)").accessibilityLabel("Previous")
                    Button("Today") { store.goToday() }.buttonStyle(.sk1Key()).help("Today (T)")
                    Button { store.step(1) } label: { Image(systemName: "chevron.right") }
                        .buttonStyle(.sk1Key()).help("Next (→)").accessibilityLabel("Next")
                }
                SKKeyTray(caption: "New") {
                    Button { formRange = nil; showForm = true } label: { Label("Event", systemImage: "plus") }
                        .buttonStyle(.sk1Key(.orange)).help("New event")
                }
            }
            MainStatusDisplay(title: store.viewMode.title,
                              detail: store.selectedDay.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
        }
        .padding(12)
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
            let cal = Calendar.current
            if cal.isDate(first, equalTo: last, toGranularity: .month) {
                return "\(first.formatted(.dateTime.month(.wide).day())) – \(last.formatted(.dateTime.day())), \(last.formatted(.dateTime.year()))"
            }
            if cal.isDate(first, equalTo: last, toGranularity: .year) {
                return "\(first.formatted(.dateTime.month(.abbreviated).day())) – \(last.formatted(.dateTime.month(.abbreviated).day())), \(last.formatted(.dateTime.year()))"
            }
            return "\(first.formatted(.dateTime.month(.abbreviated).day().year())) – \(last.formatted(.dateTime.month(.abbreviated).day().year()))"
        }
    }

    /// ←/→ previous/next period, T today, J/K next/previous day. Ignored while typing or with ⌘/⌥/⌃ held.
    private func handleKey(_ e: NSEvent) -> Bool {
        guard e.modifierFlags.intersection([.command, .option, .control]).isEmpty else { return false }
        switch Int(e.keyCode) {
        case 123: store.step(-1); return true   // ←
        case 124: store.step(1); return true    // →
        default: break
        }
        switch e.charactersIgnoringModifiers?.lowercased() {
        case "t": store.goToday(); return true
        case "j": store.moveSelectedDay(1); return true
        case "k": store.moveSelectedDay(-1); return true
        default: return false
        }
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

struct ConnectPrompt: View {
    @EnvironmentObject var session: SessionManager
    @EnvironmentObject var store: CalendarStore
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "calendar.badge.plus").font(.system(size: 44)).foregroundStyle(.secondary)
            Text("Connect your Google Calendar").font(.title2.bold())
            Text("A fast, privacy-first Google Calendar app for your Mac.").foregroundStyle(.secondary)
            Button("Sign in with Google") { Task { await session.addAccount() } }.buttonStyle(.sk1Key(.orange)).disabled(session.state == .signingIn)
            Button("Use Apple Calendar instead") { Task { await store.enableApple() } }.buttonStyle(.sk1Key())
            Text("Reads calendars already set up in the Calendar app (Exchange, iCloud, …). No sign-in needed.").font(.caption).foregroundStyle(.secondary)
            if store.appleAccessDenied { Text("Calendar access was denied. Enable Meetball in System Settings › Privacy & Security › Calendars.").font(.caption).foregroundStyle(.red).frame(maxWidth: 360) }
            if let e = session.lastError { Text(e).font(.caption).foregroundStyle(.red).frame(maxWidth: 360) }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
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
            switch store.loadState {
            case .loading: HStack { ProgressView().controlSize(.small); Text("Loading calendars") }
            case .failed(let m):
                Text("Unable to load calendars. \(m)").font(.caption).foregroundStyle(.red)
                Button("Try loading calendars again") { store.refresh() }
            case .idle where store.calendars.isEmpty: Text("Calendars have not been loaded yet.").foregroundStyle(.secondary)
            default:
                if store.calendars.isEmpty { Text("No calendars found").foregroundStyle(.secondary) }
            }
            ForEach(sectionTitles, id: \.self) { title in
                Section(title) {
                    ForEach(store.calendars.filter { $0.accountEmail == title }) { cal in
                        Toggle(isOn: Binding(get: { !store.hiddenCalendarKeys.contains(cal.key) }, set: { _ in store.toggle(cal) })) {
                            HStack { Circle().fill(Color(hex: cal.colorHex)).frame(width: 9, height: 9); Text(cal.summary).lineLimit(1) }
                        }
                        .toggleStyle(.sk1Square)
                    }
                }
            }
        }.navigationSplitViewColumnWidth(min: 190, ideal: 220)
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
    private let laneH: CGFloat = 18, headerH: CGFloat = 22
    var body: some View {
        let d = store.derived
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(Calendar.current.shortWeekdaySymbols.rotated(Calendar.current.firstWeekday - 1), id: \.self) {
                    SKCaption($0, tone: .soft).frame(maxWidth: .infinity)
                }
            }.padding(.vertical, 4)
            ForEach(d.weeks, id: \.weekStart) { week in
                GeometryReader { geo in
                    let colW = geo.size.width / 7
                    ZStack(alignment: .topLeading) {
                        HStack(spacing: 0) {
                            ForEach(0..<7, id: \.self) { i in
                                let day = Calendar.current.date(byAdding: .day, value: i, to: week.weekStart)!
                                dayCell(day, segments: d.segmentsByDay[day] ?? [], laneCount: week.laneCount)
                                    .frame(width: colW, height: geo.size.height)
                            }
                        }
                        ForEach(week.spans.filter { $0.lane < 3 }) { span in
                            Text(span.event.title).font(.caption2).lineLimit(1).padding(.horizontal, 4)
                                .frame(width: colW * CGFloat(span.endColumn - span.startColumn + 1) - 4, height: laneH - 2, alignment: .leading)
                                .background(Color(hex: span.event.colorHex).opacity(0.85), in: RoundedRectangle(cornerRadius: 4))
                                .foregroundStyle(.white)
                                .eventDetailOnClick(span.event, arrowEdge: .bottom)
                                .offset(x: colW * CGFloat(span.startColumn) + 2, y: headerH + CGFloat(span.lane) * laneH)
                        }
                    }
                }
                SKGroove()
            }
        }
    }

    @ViewBuilder func dayCell(_ day: Date, segments: [CalendarEventDaySegment], laneCount: Int) -> some View {
        let isSel = Calendar.current.isDate(day, inSameDayAs: store.selectedDay)
        let inMonth = Calendar.current.isDate(day, equalTo: store.anchor, toGranularity: .month)
        let isToday = Calendar.current.isDateInToday(day)
        VStack(alignment: .leading, spacing: 1) {
            Text("\(Calendar.current.component(.day, from: day))").font(.caption.bold())
                .frame(width: 20, height: 20).background(isToday ? Color(sk1Hex: SK1.orange) : .clear, in: Circle())
                .foregroundStyle(isToday ? .white : (inMonth ? .primary : .secondary))
            Spacer().frame(height: CGFloat(min(laneCount, 3)) * laneH - 2)
            ForEach(segments.filter { !isBar($0.event) }.prefix(2)) { seg in
                HStack(spacing: 3) { Circle().fill(Color(hex: seg.event.colorHex)).frame(width: 5, height: 5)
                    Text(seg.event.title).font(.caption2).lineLimit(1) }
            }
            Spacer(minLength: 0)
        }
        .padding(3).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(isSel ? Color(sk1Hex: SK1.orange, opacity: 0.10) : .clear)
        .overlay(Rectangle().stroke(Color.secondary.opacity(0.15), lineWidth: 0.5))
        .contentShape(Rectangle())
        .onTapGesture { store.selectedDay = day }
    }
    private func isBar(_ e: CalendarEvent) -> Bool { e.isBarEvent() }
}

extension Array {
    func rotated(_ n: Int) -> [Element] { isEmpty ? self : Array(self[(n % count)...] + self[..<(n % count)]) }
}

struct DayEventsListView: View {
    @EnvironmentObject var store: CalendarStore
    @Binding var showForm: Bool
    var body: some View {
        let segs = store.derived.segmentsByDay[store.selectedDay] ?? []
        VStack(alignment: .leading) {
            SKCaption(store.selectedDay.formatted(.dateTime.weekday(.wide).month().day()), tone: .soft).padding([.top, .horizontal], 12)
            if segs.isEmpty { Text("No events for this day").sk1Hint().padding(12); Spacer() }
            else {
                List(segs) { seg in
                    HStack(alignment: .top) {
                        RoundedRectangle(cornerRadius: 2).fill(Color(hex: seg.event.colorHex)).frame(width: 4)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(seg.event.title).bold()
                            Text(seg.timeRangeText()).font(.caption).foregroundStyle(.secondary)
                            if let l = seg.event.location, !l.isEmpty { Text(l).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                        }
                        Spacer()
                        JoinButton(event: seg.event, size: .small, key: .cream)
                    }
                    .opacity(seg.event.isDeclined ? 0.5 : 1)
                    .eventDetailOnClick(seg.event, arrowEdge: .leading)
                    .contextMenu {
                        MeetingSecondaryActions(event: seg.event)
                        Divider()  // sk1-audit: ignore (a menu item separator)
                        Button("Delete", role: .destructive) { Task { await store.delete(seg.event) } }
                    }
                }
            }
        }
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
                            DatePicker("Starts", selection: $draft.start).labelsHidden()
                                .onChange(of: draft.start) { _, s in if draft.end <= s { draft.end = s.addingTimeInterval(1800) } }
                        }
                        SKRow(title: "Ends", subtitle: DurationFormatter.string(from: draft.start, to: draft.end)) {
                            DatePicker("Ends", selection: $draft.end, in: draft.start...).labelsHidden()
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
