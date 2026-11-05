import SwiftUI

/// Menu bar popover: mini month, hero card for the next meeting, agenda grouped by day with a "now" line.
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
    private let maxScrollHeight: CGFloat = 440

    var body: some View {
        VStack(spacing: 0) {
            if !calendar.hasAnySource {
                signInPrompt
            } else {
                MiniMonthView(month: $month, selection: $scopedDay, dots: dots)
                    .padding(.horizontal, 12).padding(.top, 12).padding(.bottom, 8)
                Divider()
                ScrollView {
                    agenda
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
                }
                .frame(height: min(max(contentHeight, 60), maxScrollHeight))
            }
            Divider()
            footer
        }
        .frame(width: 360)
        .onChange(of: month) { _, m in calendar.setMenuAnchor(m) }
    }

    private var events: [CalendarEvent] { calendar.visibleEvents }

    private var dots: [Date: [String]] {
        MenuAgendaBuilder.dots(events: events, range: CalendarVisibleRangeBuilder.build(anchor: month))
    }

    private var signInPrompt: some View {
        VStack(spacing: 10) {
            Image(systemName: "calendar.badge.plus").font(.system(size: 28)).foregroundStyle(.secondary)
            Text("Connect a calendar").font(.headline)
            Button("Sign in with Google") { Task { await session.addAccount() } }.buttonStyle(.borderedProminent)
            Button("Use Apple Calendar") { Task { await calendar.enableApple() } }
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
        }
        .padding(12)
    }

    private var footer: some View {
        HStack(spacing: 4) {
            FooterIconButton(symbol: "macwindow", help: "Open Meetball (⌘O)") {
                openWindow(id: "main"); NSApp.activate(ignoringOtherApps: true)
            }.keyboardShortcut("o")
            FooterIconButton(symbol: "arrow.clockwise", help: "Refresh (⌘R)") { calendar.refresh() }.keyboardShortcut("r")
            FooterIconButton(symbol: "gearshape", help: "Settings (⌘,)") {
                openSettings(); NSApp.activate(ignoringOtherApps: true)
            }.keyboardShortcut(",")
            Spacer()
            if let k = join.hotKey {
                Text("\(k.display) join").font(.caption2).foregroundStyle(.tertiary)
                    .help("Press \(k.display) anywhere to join the nearest meeting")
            }
            FooterIconButton(symbol: "power", help: "Quit Meetball (⌘Q)") { NSApp.terminate(nil) }.keyboardShortcut("q")
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
    }
}

private struct FooterIconButton: View {
    let symbol: String; let help: String; let action: () -> Void
    @State private var hovering = false
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 13, weight: .medium))
                .frame(width: 28, height: 24)
                .background(hovering ? Color.primary.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain).foregroundStyle(.secondary)
        .onHover { hovering = $0 }
        .help(help)
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
                navButton("chevron.left", help: "Previous month") { shift(-1) }
                Button("Today") { month = Date(); selection = nil }
                    .buttonStyle(.plain).font(.caption.weight(.medium)).foregroundStyle(.secondary).padding(.horizontal, 4)
                navButton("chevron.right", help: "Next month") { shift(1) }
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
                        if isToday { Circle().fill(Color.accentColor) }
                        else if isSelected { Circle().fill(Color.accentColor.opacity(0.22)) }
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
        Button(action: action) { Image(systemName: symbol).font(.caption.weight(.semibold)).frame(width: 22, height: 22) }
            .buttonStyle(.plain).foregroundStyle(.secondary).help(help)
    }

    private func shift(_ n: Int) {
        month = Calendar.current.date(byAdding: .month, value: n, to: month) ?? month
    }
}

/// The next / in-progress meeting: title, time, countdown and a big Join button.
struct HeroMeetingCard: View {
    let event: CalendarEvent
    let now: Date

    var body: some View {
        let inProgress = event.start <= now
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Circle().fill(inProgress ? Color.red : Color(hex: event.colorHex)).frame(width: 7, height: 7)
                Text(inProgress ? "Now · ends in \(TimeUntilFormatter.string(until: event.end, now: now))"
                                : "Starts in \(TimeUntilFormatter.string(until: event.start, now: now))")
                    .font(.caption.weight(.semibold)).foregroundStyle(inProgress ? Color.red : Color.secondary)
                Spacer()
            }
            Text(event.title).font(.title3.bold()).lineLimit(2)
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
                JoinButton(event: event, size: .large, fillsWidth: true)
            } else {
                Text("No video link").font(.caption).foregroundStyle(.tertiary)
            }
        }
        .padding(12)
        .background(Color(hex: event.colorHex).opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color(hex: event.colorHex).opacity(0.25)))
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

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if showHeader {
                Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary).textCase(.uppercase)
            }
            if !group.allDay.isEmpty {
                FlowWrap(spacing: 4) {
                    ForEach(group.allDay, id: \.uid) { e in
                        Text(e.title).font(.caption2.weight(.medium)).lineLimit(1)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color(hex: e.colorHex).opacity(0.22), in: Capsule())
                            .opacity(e.isDeclined ? 0.5 : 1)
                            .contextMenu { MeetingSecondaryActions(event: e) }
                    }
                }
            }
            ForEach(Array(group.timed.enumerated()), id: \.element.uid) { i, e in
                if group.nowLineIndex == i { NowLine(now: now) }
                AgendaRow(event: e, now: now)
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
            Circle().fill(Color.red).frame(width: 6, height: 6)
            Rectangle().fill(Color.red).frame(height: 1)
            Text(now.formatted(date: .omitted, time: .shortened)).font(.caption2.monospacedDigit()).foregroundStyle(.red)
        }
        .padding(.vertical, 2)
        .accessibilityLabel("Now")
    }
}

struct AgendaRow: View {
    let event: CalendarEvent
    let now: Date

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
            if !ended && !event.isDeclined { JoinButton(event: event, size: .small) }
        }
        .padding(.vertical, 2)
        .opacity(ended || event.isDeclined ? 0.5 : 1)
        .contentShape(Rectangle())
        .contextMenu { MeetingSecondaryActions(event: event) }
    }
}
