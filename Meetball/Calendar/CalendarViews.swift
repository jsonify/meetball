import SwiftUI

struct CalendarContainerView: View {
    @EnvironmentObject var store: CalendarStore
    @EnvironmentObject var session: SessionManager
    @State private var showForm = false

    var body: some View {
        NavigationSplitView {
            CalendarSidebarView()
        } detail: {
            if session.accounts.isEmpty {
                ConnectPrompt()
            } else {
                VStack(spacing: 0) {
                    header
                    Divider()
                    HSplitView {
                        MonthGridView().frame(minWidth: 520)
                        DayEventsListView(showForm: $showForm).frame(minWidth: 260, idealWidth: 300)
                    }
                }
            }
        }
        .sheet(isPresented: $showForm) { EventFormView(day: store.selectedDay) }
        .alert("Something went wrong", isPresented: Binding(get: { store.actionError != nil }, set: { if !$0 { store.actionError = nil } })) {
            Button("OK") { store.actionError = nil }
        } message: { Text(store.actionError ?? "") }
        .task { store.startAutoRefresh() }
    }

    var header: some View {
        HStack {
            Text(store.anchor, format: .dateTime.month(.wide).year()).font(.title2.bold())
            Spacer()
            Button { store.shiftMonth(-1) } label: { Image(systemName: "chevron.left") }
            Button("Today") { store.anchor = Date(); store.selectedDay = Calendar.current.startOfDay(for: Date()); store.refresh() }
            Button { store.shiftMonth(1) } label: { Image(systemName: "chevron.right") }
            Button { showForm = true } label: { Label("New event", systemImage: "plus") }.buttonStyle(.borderedProminent)
        }.padding(12)
    }
}

struct ConnectPrompt: View {
    @EnvironmentObject var session: SessionManager
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "calendar.badge.plus").font(.system(size: 44)).foregroundStyle(.secondary)
            Text("Connect your Google Calendar").font(.title2.bold())
            Text("A fast, privacy-first Google Calendar app for your Mac.").foregroundStyle(.secondary)
            Button("Sign in with Google") { Task { await session.addAccount() } }.buttonStyle(.borderedProminent).disabled(session.state == .signingIn)
            if let e = session.lastError { Text(e).font(.caption).foregroundStyle(.red).frame(maxWidth: 360) }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct CalendarSidebarView: View {
    @EnvironmentObject var store: CalendarStore
    @EnvironmentObject var session: SessionManager
    var body: some View {
        List {
            switch store.loadState {
            case .loading: HStack { ProgressView().controlSize(.small); Text("Loading calendars") }
            case .failed(let m):
                Text("Unable to load calendars. \(m)").font(.caption).foregroundStyle(.red)
                Button("Try loading calendars again") { store.refresh() }
            case .idle where store.calendars.isEmpty: Text("Calendars have not been loaded yet.").foregroundStyle(.secondary)
            default:
                if store.calendars.isEmpty { Text("No calendars found").foregroundStyle(.secondary) }
            }
            ForEach(session.accounts) { acct in
                Section(acct.email) {
                    ForEach(store.calendars.filter { $0.accountEmail == acct.email }) { cal in
                        Toggle(isOn: Binding(get: { !store.hiddenCalendarKeys.contains(cal.key) }, set: { _ in store.toggle(cal) })) {
                            HStack { Circle().fill(Color(hex: cal.colorHex)).frame(width: 9, height: 9); Text(cal.summary).lineLimit(1) }
                        }
                    }
                }
            }
        }.navigationSplitViewColumnWidth(min: 190, ideal: 220)
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
                    Text($0).font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity)
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
                                .offset(x: colW * CGFloat(span.startColumn) + 2, y: headerH + CGFloat(span.lane) * laneH)
                        }
                    }
                }
                Divider()
            }
        }
    }

    @ViewBuilder func dayCell(_ day: Date, segments: [CalendarEventDaySegment], laneCount: Int) -> some View {
        let isSel = Calendar.current.isDate(day, inSameDayAs: store.selectedDay)
        let inMonth = Calendar.current.isDate(day, equalTo: store.anchor, toGranularity: .month)
        let isToday = Calendar.current.isDateInToday(day)
        VStack(alignment: .leading, spacing: 1) {
            Text("\(Calendar.current.component(.day, from: day))").font(.caption.bold())
                .frame(width: 20, height: 20).background(isToday ? Color.accentColor : .clear, in: Circle())
                .foregroundStyle(isToday ? .white : (inMonth ? .primary : .secondary))
            Spacer().frame(height: CGFloat(min(laneCount, 3)) * laneH - 2)
            ForEach(segments.filter { !isBar($0.event) }.prefix(2)) { seg in
                HStack(spacing: 3) { Circle().fill(Color(hex: seg.event.colorHex)).frame(width: 5, height: 5)
                    Text(seg.event.title).font(.caption2).lineLimit(1) }
            }
            Spacer(minLength: 0)
        }
        .padding(3).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(isSel ? Color.accentColor.opacity(0.12) : .clear)
        .overlay(Rectangle().stroke(Color.secondary.opacity(0.15), lineWidth: 0.5))
        .contentShape(Rectangle())
        .onTapGesture { store.selectedDay = day }
    }
    private func isBar(_ e: CalendarEvent) -> Bool { e.isAllDay || !Calendar.current.isDate(e.start, inSameDayAs: e.end.addingTimeInterval(-1)) }
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
            Text(store.selectedDay, format: .dateTime.weekday(.wide).month().day()).font(.headline).padding([.top, .horizontal], 12)
            if segs.isEmpty { Text("No events for this day").foregroundStyle(.secondary).padding(12); Spacer() }
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
                        if let u = seg.event.meetURL { Button("Join") { NSWorkspace.shared.open(u) }.controlSize(.small) }
                    }
                    .contextMenu {
                        if let l = seg.event.htmlLink { Button("Open in Google Calendar") { NSWorkspace.shared.open(l) } }
                        Button("Delete", role: .destructive) { Task { await store.delete(seg.event) } }
                    }
                }
            }
        }
    }
}

struct MenubarEventRow: View {
    let event: CalendarEvent
    var body: some View {
        HStack {
            Circle().fill(Color(hex: event.colorHex)).frame(width: 8, height: 8)
            VStack(alignment: .leading) {
                Text(event.title).lineLimit(1)
                Text("\(event.start.formatted(date: .omitted, time: .shortened)) · in \(TimeUntilFormatter.string(until: event.start))").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if let u = event.meetURL { Button("Join") { NSWorkspace.shared.open(u) } }
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
        _draft = State(initialValue: NewEventDraft(start: r.start, end: r.end))
    }
    private var writable: [GCalendar] { store.calendars.filter(\.canWrite) }

    var body: some View {
        Form {
            TextField("Title", text: $draft.title, prompt: Text("e.g. Weekly sync with Anna"))
            Toggle("Focus block", isOn: $draft.isFocusBlock)
            DatePicker("Starts", selection: $draft.start).onChange(of: draft.start) { _, s in if draft.end <= s { draft.end = s.addingTimeInterval(1800) } }
            DatePicker("Ends", selection: $draft.end, in: draft.start...)
            Picker("Calendar", selection: $draft.calendar) {
                ForEach(writable) { Text($0.summary).tag(Optional($0)) }
            }
            Toggle("Add Google Meet link", isOn: $draft.addMeet).disabled(!(draft.calendar?.allowsMeet ?? false))
            if let c = draft.calendar, !c.allowsMeet { Text("This calendar doesn't allow Google Meet conferences.").font(.caption).foregroundStyle(.secondary) }
            Section("Attendees") {
                HStack {
                    TextField("Add attendee email", text: $attendeeText).onSubmit(addAttendee)
                    Button("Add", action: addAttendee)
                }
                if let attendeeError { Text(attendeeError).font(.caption).foregroundStyle(.red) }
                FlowWrap { ForEach(draft.attendees, id: \.self) { a in
                    Button { draft.attendees.removeAll { $0 == a } } label: { Label(a, systemImage: "xmark.circle.fill") }.buttonStyle(.bordered).controlSize(.small)
                } }
            }
            HStack { Spacer(); Button("Cancel") { dismiss() }
                Button("Save") { Task { saving = true; if await store.create(draft) { dismiss() }; saving = false } }
                    .buttonStyle(.borderedProminent).disabled(saving || draft.calendar == nil)
            }
        }
        .formStyle(.grouped).frame(width: 480, height: 520)
        .onAppear { draft.calendar = draft.calendar ?? writable.first(where: \.isPrimary) ?? writable.first }
    }

    func addAttendee() {
        let e = attendeeText.trimmingCharacters(in: .whitespaces)
        guard !e.isEmpty else { return }
        if !EmailValidator.isValid(e) { attendeeError = "Enter a valid email address."; return }
        if draft.attendees.contains(e) { attendeeError = "This attendee is already added."; return }
        draft.attendees.append(e); attendeeText = ""; attendeeError = nil
    }
}
