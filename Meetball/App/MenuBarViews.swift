import SwiftUI
import SK1Tokens
import SK1UI

/// Menu bar popover (SK-1 look): mini month, hero card for the next meeting, agenda grouped by day with a "now" line.
struct MenuBarContent: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var session: SessionManager
    @EnvironmentObject var calendar: CalendarStore
    @EnvironmentObject var join: JoinController
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @State private var month = Date()
    @State private var scopedDay: Date?
    @State private var contentHeight: CGFloat = 0
    /// "Show anyway": include events hidden by the meeting-first rules.
    @State private var showHidden = false
    private let maxScrollHeight: CGFloat = 440

    var body: some View {
        VStack(spacing: 0) {
            if !calendar.hasAnySource {
                signInPrompt
            } else {
                MiniMonthView(month: $month, selection: $scopedDay, dots: dots)
                    .padding(.horizontal, 12).padding(.top, 12).padding(.bottom, 8)
                SKGroove()
                ScrollView {
                    agenda
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
                }
                .frame(height: min(max(contentHeight, 60), maxScrollHeight))
            }
            SKGroove()
            footer
        }
        .frame(width: 360)
        .sk1Chassis()
        .environment(\.eventFilterSettings, calendar.filters)
        .onChange(of: month) { _, m in calendar.setMenuAnchor(m) }
    }

    private var events: [CalendarEvent] { showHidden ? calendar.visibleEvents : calendar.meetingEvents }

    private var dots: [Date: [String]] {
        MenuAgendaBuilder.dots(events: events, range: CalendarVisibleRangeBuilder.build(anchor: month))
    }

    private var signInPrompt: some View {
        VStack(spacing: 10) {
            Image(systemName: "calendar.badge.plus").font(.system(size: 28)).foregroundStyle(.secondary)
            Text("Connect a calendar").font(.headline)
            Button("Sign in with Google") { Task { await session.addAccount() } }.buttonStyle(.sk1Key(.orange))
            Button("Use Apple Calendar") { Task { await calendar.enableApple() } }.buttonStyle(.sk1Key())
        }
        .frame(maxWidth: .infinity).padding(20)
    }

    @ViewBuilder private var agenda: some View {
        let now = model.now
        let hero = scopedDay == nil ? MenuAgendaBuilder.hero(events, now: now) : nil
        let groups = MenuAgendaBuilder.build(events: events, now: now, scopedDay: scopedDay, excluding: hero?.uid)
        VStack(alignment: .leading, spacing: 12) {
            if let day = scopedDay {
                HStack {
                    Text(day, format: .dateTime.weekday(.wide).month().day()).font(.subheadline.bold())
                    Spacer()
                    Button("Show upcoming") { scopedDay = nil }.buttonStyle(.link).font(.caption)
                }
            }
            if let hero { HeroMeetingCard(event: hero, now: now) }
            if groups.isEmpty && hero == nil {
                Text(scopedDay == nil ? "No upcoming events" : "No events on this day")
                    .foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.vertical, 12)
            }
            ForEach(groups) { AgendaDaySection(group: $0, now: now, showHeader: scopedDay == nil) }
            HiddenEventsToggle(count: hiddenCount(now: now), showing: $showHidden)
        }
        .padding(12)
    }

    /// Hidden events that would otherwise appear in the agenda being shown.
    private func hiddenCount(now: Date) -> Int {
        MenuAgendaBuilder.build(events: calendar.meetingFeed.hidden, now: now, scopedDay: scopedDay, limit: .max)
            .reduce(0) { $0 + $1.allDay.count + $1.timed.count }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            SKKeyTray {
                FooterKey(symbol: "macwindow", help: "Open Meetball (⌘O)") {
                    openWindow(id: "main"); NSApp.activate(ignoringOtherApps: true)
                }.keyboardShortcut("o")
                FooterKey(symbol: "arrow.clockwise", help: "Refresh (⌘R)") { calendar.refresh() }.keyboardShortcut("r")
                FooterKey(symbol: "gearshape", help: "Settings (⌘,)") {
                    openSettings(); NSApp.activate(ignoringOtherApps: true)
                }.keyboardShortcut(",")
            }
            Spacer()
            if let k = join.hotKey {
                HStack(spacing: 5) {
                    SKCaption("Join", tone: .soft)
                    SKChip(k.display)
                }
                .help("Press \(k.display) anywhere to join the nearest meeting")
            }
            // The charcoal key: an action apart from the rest.
            FooterKey(symbol: "power", help: "Quit Meetball (⌘Q)", variant: .charcoal) { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
    }
}

/// A symbol-only SK-1 key for the popover's footer.
private struct FooterKey: View {
    let symbol: String; let help: String
    var variant: SK1KeyVariant = .cream
    let action: () -> Void
    var body: some View {
        Button(action: action) { Image(systemName: symbol) }
            .buttonStyle(.sk1Key(variant))
            .help(help)
            .accessibilityLabel(Text(help))
    }
}

/// Compact month grid with event dots. Click a day to scope the agenda; click again to clear.
struct MiniMonthView: View {
    @Binding var month: Date
    @Binding var selection: Date?
    let dots: [Date: [String]]
    @AppStorage("menuBar.showWeekNumbers") private var showWeekNumbers = false

    var body: some View {
        let cal = Calendar.current
        let range = CalendarVisibleRangeBuilder.build(anchor: month)
        let weekStarts = stride(from: 0, to: cal.dateComponents([.day], from: range.start, to: range.end).day ?? 35, by: 7)
            .compactMap { cal.date(byAdding: .day, value: $0, to: range.start) }
        let symbols = cal.veryShortWeekdaySymbols.rotated(cal.firstWeekday - 1)
        VStack(spacing: 6) {
            HStack(spacing: 2) {
                Text(month, format: .dateTime.month(.wide).year()).font(.headline)
                Spacer()
                HStack(spacing: 4) {
                    navButton("chevron.left", help: "Previous month") { shift(-1) }
                    Button("Today") { month = Date(); selection = nil }.buttonStyle(.sk1Key(size: .small))
                    navButton("chevron.right", help: "Next month") { shift(1) }
                }
            }
            Grid(horizontalSpacing: 0, verticalSpacing: 2) {
                GridRow {
                    if showWeekNumbers { Text("wk").font(.caption2).foregroundStyle(.tertiary) }
                    ForEach(Array(symbols.enumerated()), id: \.offset) { _, s in
                        Text(s).font(.caption2.weight(.medium)).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                    }
                }
                ForEach(weekStarts, id: \.self) { ws in
                    GridRow {
                        if showWeekNumbers {
                            Text("\(cal.component(.weekOfYear, from: ws))").font(.caption2.monospacedDigit()).foregroundStyle(.tertiary)
                        }
                        ForEach(0..<7, id: \.self) { i in
                            if let d = cal.date(byAdding: .day, value: i, to: ws) { dayCell(d) }
                        }
                    }
                }
            }
        }
    }

    private func dayCell(_ day: Date) -> some View {
        let cal = Calendar.current
        let isToday = cal.isDateInToday(day)
        let isSelected = selection.map { cal.isDate($0, inSameDayAs: day) } ?? false
        let inMonth = cal.isDate(day, equalTo: month, toGranularity: .month)
        return Button {
            selection = isSelected ? nil : cal.startOfDay(for: day)
        } label: {
            VStack(spacing: 2) {
                Text("\(cal.component(.day, from: day))")
                    .font(.system(size: 11, weight: isToday ? .bold : .regular).monospacedDigit())
                    .foregroundStyle(isToday ? Color.white : (inMonth ? Color.primary : Color.secondary.opacity(0.6)))
                    .frame(width: 22, height: 22)
                    .background {
                        // Orange marks what is "on": today, and (fainter) the scoped day.
                        if isToday { Circle().fill(Color(sk1Hex: SK1.orange)) }
                        else if isSelected { Circle().fill(Color(sk1Hex: SK1.orange, opacity: 0.22)) }
                    }
                HStack(spacing: 2) {
                    ForEach(dots[cal.startOfDay(for: day)] ?? [], id: \.self) { hex in
                        Circle().fill(Color(hex: hex)).frame(width: 4, height: 4)
                    }
                }.frame(height: 4)
            }
            .frame(maxWidth: .infinity).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(day, format: .dateTime.weekday(.wide).month().day()))
    }

    private func navButton(_ symbol: String, help: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol) }
            .buttonStyle(.sk1Key(.round, size: .small)).help(help).accessibilityLabel(Text(help))
    }

    private func shift(_ n: Int) {
        month = Calendar.current.date(byAdding: .month, value: n, to: month) ?? month
    }
}

/// The next / in-progress meeting in a sunken tray: an LCD countdown, title, time, and the orange Join key.
struct HeroMeetingCard: View {
    let event: CalendarEvent
    let now: Date

    var body: some View {
        let inProgress = event.start <= now
        let target = inProgress ? event.end : event.start
        let countdown = SK1CountdownDigits.compact(target.timeIntervalSince(now))
        SKWell {
            VStack(alignment: .leading, spacing: 8) {
                SK1CountdownLCD(caption: inProgress ? "Now · ends in" : "Starts in",
                                digits: countdown.digits, unit: countdown.unit, live: inProgress,
                                accessibilityText: (inProgress ? "In progress, ends " : "Starts ")
                                    + RelativeTimeFormatter.string(for: target, relativeTo: now))
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Circle().fill(Color(hex: event.colorHex)).frame(width: 7, height: 7)
                    Text(event.title).font(.title3.bold()).lineLimit(2)
                }
                HStack(spacing: 10) {
                    Label(timeRange, systemImage: "clock")
                    if !event.attendees.isEmpty {
                        Label("\(event.attendees.count)", systemImage: "person.2").help("\(event.attendees.count) attendees")
                    }
                }
                .font(.caption).foregroundStyle(.secondary)
                if let loc = event.location, !loc.isEmpty {
                    Label(loc, systemImage: "mappin.and.ellipse").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                if event.meetURL != nil {
                    JoinButton(event: event, size: .large, fillsWidth: true, key: .orange)
                } else {
                    Text("No video link").sk1Hint()
                }
            }
            .padding(10)
        }
        .eventDetailOnClick(event, arrowEdge: .leading)
        .contextMenu { MeetingSecondaryActions(event: event) }
    }

    private var timeRange: String {
        "\(event.start.formatted(date: .omitted, time: .shortened)) – \(event.end.formatted(date: .omitted, time: .shortened))"
    }
}

struct AgendaDaySection: View {
    let group: AgendaDayGroup
    let now: Date
    var showHeader = true
    @Environment(\.eventFilterSettings) private var filters

    private func dimmed(_ e: CalendarEvent) -> Bool { filters.map { EventFilter.isDimmed(e, settings: $0) } ?? false }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if showHeader {
                SKCaption(title, tone: .soft)
            }
            if !group.allDay.isEmpty {
                FlowWrap(spacing: 4) {
                    ForEach(group.allDay, id: \.uid) { e in
                        Text(e.title).font(.caption2.weight(.medium)).lineLimit(1)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color(hex: e.colorHex).opacity(0.22), in: Capsule())
                            .opacity(e.isDeclined || dimmed(e) ? 0.5 : 1)
                            .eventDetailOnClick(e, arrowEdge: .leading)
                            .contextMenu { MeetingSecondaryActions(event: e) }
                    }
                }
            }
            ForEach(Array(group.timed.enumerated()), id: \.element.uid) { i, e in
                if group.nowLineIndex == i { NowLine(now: now) }
                AgendaRow(event: e, now: now, joinKey: .cream)
            }
            if let n = group.nowLineIndex, n == group.timed.count, !group.timed.isEmpty { NowLine(now: now) }
        }
    }

    private var title: String {
        let cal = Calendar.current
        if cal.isDateInToday(group.day) { return "Today" }
        if cal.isDateInTomorrow(group.day) { return "Tomorrow" }
        return group.day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }
}

private struct NowLine: View {
    let now: Date
    var body: some View {
        HStack(spacing: 4) {
            let red = Color(sk1Hex: SK1.recRed)
            Circle().fill(red).frame(width: 6, height: 6)
            Rectangle().fill(red).frame(height: 1)
            Text(now.formatted(date: .omitted, time: .shortened)).font(.caption2.monospacedDigit()).foregroundStyle(red)
        }
        .padding(.vertical, 2)
        .accessibilityLabel("Now")
    }
}

struct AgendaRow: View {
    let event: CalendarEvent
    let now: Date
    /// SK-1 key for the Join button (the popover); nil keeps the native button (main window).
    var joinKey: SK1KeyVariant?
    @Environment(\.eventFilterSettings) private var filters

    private var tentativeDimmed: Bool { filters.map { EventFilter.isDimmed(event, settings: $0) } ?? false }
    private var hideReason: EventHideReason? { filters.flatMap { EventFilter.hideReason(event, settings: $0) } }

    var body: some View {
        let ended = event.end <= now
        let inProgress = event.start <= now && !ended
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2).fill(Color(hex: event.colorHex)).frame(width: 3, height: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(event.title).font(.callout.weight(inProgress ? .semibold : .regular)).lineLimit(1)
                    .strikethrough(event.isDeclined)
                HStack(spacing: 4) {
                    Text("\(event.start.formatted(date: .omitted, time: .shortened)) – \(event.end.formatted(date: .omitted, time: .shortened))")
                    if !ended && !inProgress && event.start.timeIntervalSince(now) < 12 * 3600 {
                        Text("· in \(TimeUntilFormatter.string(until: event.start, now: now))")
                    }
                    if let u = event.meetURL { MeetingServiceBadge(url: u) }
                }
                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            if !ended && !event.isDeclined { JoinButton(event: event, size: .small, key: joinKey) }
        }
        .padding(.vertical, 2)
        .opacity(ended || event.isDeclined || tentativeDimmed ? 0.5 : 1)
        .help(hideReason.map { "Hidden by your filters: \($0.label)" } ?? (tentativeDimmed ? "You replied Maybe" : ""))
        .eventDetailOnClick(event, arrowEdge: .leading)
        .contextMenu { MeetingSecondaryActions(event: event) }
    }
}
