import SwiftUI
import SK1Tokens
import SK1UI

/// Menu bar popover, laid out as Skreener's launcher: an LCD strip (the next meeting, or the key under the pointer),
/// big keys for the main actions, the mini month and agenda, and a tray of captioned keys.
struct MenuBarContent: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var session: SessionManager
    @EnvironmentObject var calendar: CalendarStore
    @EnvironmentObject var join: JoinController
    @EnvironmentObject var shortcuts: AppShortcuts
    @EnvironmentObject var guardianStore: MeetingGuardianStore
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @State private var month = Date()
    @State private var scopedDay: Date?
    @State private var contentHeight: CGFloat = 0
    /// "Show anyway": include events hidden by the meeting-first rules.
    @State private var showHidden = false
    /// The key under the pointer, for the LCD strip: its name and its shortcut or what it would do.
    @State private var hovered: (name: String, detail: String)?
    private let maxScrollHeight: CGFloat = 400

    var body: some View {
        VStack(spacing: 0) {
            if !calendar.hasAnySource {
                signInPrompt
            } else {
                VStack(spacing: 8) {
                    statusStrip
                    WorldClockStrip(now: model.now)
                    tiles
                }
                .padding([.horizontal, .top], 12)
                MiniMonthView(month: $month, selection: $scopedDay, dots: dots, ribbons: ribbons)
                    .padding(.horizontal, 12).padding(.top, 10).padding(.bottom, 8)
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
        .modifier(RegistersWindowOpener())
    }

    private var events: [CalendarEvent] { showHidden ? calendar.visibleEvents : calendar.meetingEvents }

    private var ribbons: [Date: [MiniMonthRibbon]] {
        MiniMonthRibbonBuilder.build(events: events, range: CalendarVisibleRangeBuilder.build(anchor: month))
    }

    /// Dots for everything not already drawn as a ribbon.
    private var dots: [Date: [String]] {
        let spanned = MiniMonthRibbonBuilder.uids(ribbons)
        return MenuAgendaBuilder.dots(events: events.filter { !spanned.contains($0.uid) },
                                      range: CalendarVisibleRangeBuilder.build(anchor: month))
    }

    private var signInPrompt: some View {
        EmptyStateView(symbol: "calendar.badge.plus", title: "Connect a calendar",
                       detail: "Meetball shows your next meeting here once a Google account or Apple Calendar is connected.") {
            Button("Set Up Meetball") { openWindow(id: "main"); NSApp.activate(ignoringOtherApps: true) }
                .buttonStyle(.sk1Key(.orange))
        }
    }

    @ViewBuilder private var agenda: some View {
        let now = model.now
        let hero = scopedDay == nil ? MenuAgendaBuilder.hero(events, now: now) : nil
        let overlapping = hero.map { MenuAgendaBuilder.overlapping($0, in: events, now: now) } ?? []
        let shownInHero = Set(([hero].compactMap { $0 } + overlapping).map(\.uid))
        let groups = MenuAgendaBuilder.build(events: events, now: now, scopedDay: scopedDay, excluding: shownInHero)
        VStack(alignment: .leading, spacing: 12) {
            if let day = scopedDay {
                HStack {
                    Text(day, format: .dateTime.weekday(.wide).month().day()).font(.subheadline.bold())
                    Spacer()
                    Button("Show upcoming") { scopedDay = nil }.buttonStyle(.sk1Key(size: .small))
                }
            }
            if let hero {
                HeroMeetingCard(event: hero, now: now, overlapping: overlapping,
                                autoJoinAt: guardianStore.isAutoJoin(hero) && hero.meetURL != nil
                                    ? AutoJoin.joinTime(hero, delayMinutes: guardianStore.settings.autoJoinDelayMinutes) : nil)
            }
            if groups.isEmpty && hero == nil {
                if calendar.loadState == .loading && calendar.events.isEmpty {
                    EmptyStateView(symbol: "arrow.triangle.2.circlepath", title: "Loading your calendars\u{2026}")
                } else if case .failed(let message) = calendar.loadState, calendar.events.isEmpty {
                    EmptyStateView(symbol: "wifi.exclamationmark", title: "Couldn't sync", detail: SyncErrorText.friendly(message)) {
                        Button("Try Again") { calendar.refresh(.user) }.buttonStyle(.sk1Key(size: .small))
                    }
                } else {
                    EmptyStateView(symbol: "cup.and.saucer",
                                   title: scopedDay == nil ? "No upcoming meetings" : "Nothing on this day",
                                   detail: scopedDay == nil ? "Enjoy the quiet. New meetings show up here as soon as they're added." : nil)
                }
            }
            ForEach(groups) { AgendaDaySection(group: $0, now: now, showHeader: scopedDay == nil) }
        }
        .padding(12)
    }

    /// Hidden events that would otherwise appear in the agenda being shown.
    private func hiddenCount(now: Date) -> Int {
        MenuAgendaBuilder.build(events: calendar.meetingFeed.hidden, now: now, scopedDay: scopedDay, limit: .max)
            .reduce(0) { $0 + $1.allDay.count + $1.timed.count }
    }

    /// The LCD strip: the meeting in progress or the next one, or the name of the key under the pointer.
    private var statusStrip: some View {
        let resting = MeetingStatusText.strip(calendar.meetingEvents, now: model.now)
        return SKStatusStrip(title: hovered?.name ?? "Meetball", detail: hovered?.detail ?? resting.detail,
                             lamp: hovered == nil && resting.live ? .danger : nil)
    }

    /// The main actions as big keys in a tray; Join is the orange one, lit up when there is something to join.
    private var tiles: some View {
        let next = NearestMeetingPicker.pick(calendar.meetingEvents, now: model.now, window: TimeInterval(join.windowMinutes * 60))
        let symbol = next?.meetURL.map { MeetingService.detect($0).symbol } ?? "video"
        let shortcut = join.hotKey?.display
        return SKWell {
            HStack(alignment: .top, spacing: 4) {
                SKTile("Join", systemImage: symbol, legend: shortcut, variant: .orange,
                       onHover: hover(next.map { "Join \($0.title)" } ?? "Join", next == nil ? "NOTHING TO JOIN" : (shortcut ?? ""))) {
                    join.joinNearest()
                }
                .disabled(next == nil)
                SKTile("Calendar", systemImage: "macwindow", legend: "⌘O", onHover: hover("Open Meetball", "⌘O")) {
                    openWindow(id: "main"); NSApp.activate(ignoringOtherApps: true)
                }
                .keyboardShortcut("o")
                SKTile("Refresh", systemImage: "arrow.clockwise", legend: "⌘R", onHover: hover("Refresh calendars", "⌘R")) {
                    calendar.refresh(.user)
                }
                .keyboardShortcut("r")
            }
            .padding(6)
        }
    }

    /// The footer tray: back to today, show filtered events (lit while shown), and the charcoal Settings and Quit.
    private var footer: some View {
        let hidden = hiddenCount(now: model.now)
        return SKKeyGroup {
            SKCaptionedKey("Today", systemImage: "calendar.circle", onHover: hover("Back to today", "")) {
                month = Date(); scopedDay = nil
            }
            SKCaptionedKey("New", systemImage: "plus", onHover: hover("Quick add an event", shortcuts.combos[.quickAdd]?.display ?? "")) {
                QuickAddPanel.show(store: calendar)
            }
            SKCaptionedKey("Filtered", systemImage: "line.3.horizontal.decrease.circle", lamp: showHidden,
                           onHover: hover(showHidden ? "Hide filtered events" : "Show filtered events", "\(hidden) HIDDEN")) {
                showHidden.toggle()
            }
            if !calendar.workCalendarKeys.isEmpty {
                SKCaptionedKey("Work", systemImage: "briefcase", lamp: calendar.isWorkOnly,
                               onHover: hover(calendar.isWorkOnly ? "Show all calendars" : "Show work calendars only", "⇧⌘O")) {
                    calendar.toggleWorkOnly()
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])
            }
            SKCaptionedKey("Settings", systemImage: "gearshape", variant: .charcoal, onHover: hover("Settings", "⌘,")) {
                openSettings(); NSApp.activate(ignoringOtherApps: true)
            }
            .keyboardShortcut(",")
            SKCaptionedKey("Quit", systemImage: "power", variant: .charcoal, onHover: hover("Quit Meetball", "⌘Q")) {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .padding(12)
    }

    /// Shows a key's name and detail on the strip while the pointer is over it.
    private func hover(_ name: String, _ detail: String) -> (Bool) -> Void {
        { inside in
            if inside { hovered = (name, detail) } else if hovered?.name == name { hovered = nil }
        }
    }
}

/// Compact month grid with event dots, and ribbons across the days of multi-day events (#28): away and on-call
/// stretches also tint the dates they cover. Click a day to scope the agenda; click again to clear.
struct MiniMonthView: View {
    @Binding var month: Date
    @Binding var selection: Date?
    let dots: [Date: [String]]
    var ribbons: [Date: [MiniMonthRibbon]] = [:]
    static let numberSize: CGFloat = 22
    static let laneHeight: CGFloat = 5
    @AppStorage(AppPreferences.Key.weekNumbers) private var showWeekNumbers = false
    @AppStorage(AppPreferences.Key.highlightWeekends) private var highlightWeekends = true

    var body: some View {
        let cal = Calendar.app
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
                        weekRow(ws)
                            .gridCellColumns(7)
                    }
                }
            }
        }
    }

    /// A week's seven days, with its ribbons drawn over them.
    private func weekRow(_ weekStart: Date) -> some View {
        let cal = Calendar.app
        let row = ribbons[weekStart] ?? []
        let lanes = (row.map(\.lane).max() ?? -1) + 1
        return HStack(spacing: 0) {
            ForEach(0..<7, id: \.self) { i in
                if let d = cal.date(byAdding: .day, value: i, to: weekStart) { dayCell(d, column: i, lanes: lanes, ribbons: row) }
            }
        }
        .overlay(alignment: .topLeading) {
            GeometryReader { geo in
                let colW = geo.size.width / 7
                ForEach(row) { r in ribbon(r, colW: colW) }
            }
        }
    }

    /// A rounded bar under the dates (square where it carries on into the next or previous week).
    private func ribbon(_ r: MiniMonthRibbon, colW: CGFloat) -> some View {
        let inset: CGFloat = 3
        let x = colW * CGFloat(r.startColumn) + (r.continuesBefore ? 0 : inset)
        let w = colW * CGFloat(r.endColumn - r.startColumn + 1) - (r.continuesBefore ? 0 : inset) - (r.continuesAfter ? 0 : inset)
        let radius: CGFloat = 2
        let shape = UnevenRoundedRectangle(topLeadingRadius: r.continuesBefore ? 0 : radius, bottomLeadingRadius: r.continuesBefore ? 0 : radius,
                                           bottomTrailingRadius: r.continuesAfter ? 0 : radius, topTrailingRadius: r.continuesAfter ? 0 : radius)
        return shape.fill(Color(hex: r.event.colorHex).opacity(r.callout == nil ? 0.75 : 1))
            .frame(width: max(4, w), height: Self.laneHeight - 1)
            .help(ribbonHelp(r))
            .eventDetailOnClick(r.event, arrowEdge: .bottom)
            .accessibilityLabel(ribbonHelp(r))
            .offset(x: x, y: Self.numberSize + 2 + CGFloat(r.lane) * Self.laneHeight)
    }

    private func ribbonHelp(_ r: MiniMonthRibbon) -> String {
        let e = r.event
        let last = e.end > e.start ? e.end.addingTimeInterval(-1) : e.start
        let dates = "\(e.start.formatted(.dateTime.month(.abbreviated).day())) \u{2013} \(last.formatted(.dateTime.month(.abbreviated).day()))"
        return "\(r.callout.map { "\($0.label): " } ?? "")\(e.title), \(dates)"
    }

    private func dayCell(_ day: Date, column: Int, lanes: Int, ribbons row: [MiniMonthRibbon]) -> some View {
        // An away or on-call stretch tints the dates it covers, like a highlighter across the week.
        let callout = row.first { $0.callout != nil && $0.startColumn <= column && column <= $0.endColumn }
        let cal = Calendar.app
        let isToday = cal.isDateInToday(day)
        let isSelected = selection.map { cal.isDate($0, inSameDayAs: day) } ?? false
        let inMonth = cal.isDate(day, equalTo: month, toGranularity: .month)
        let dayDots = dots[cal.startOfDay(for: day)] ?? []
        // Built apart from the view: as one expression with it, Release builds timed out type-checking it.
        let numberColor: Color = isToday ? .white : (inMonth ? .primary : Color.secondary.opacity(0.6))
        let weekendTint: Color = highlightWeekends && cal.isDateInWeekend(day) ? Color.secondary.opacity(0.07) : .clear
        var label = isToday ? "Today, " : ""
        label += day.formatted(.dateTime.weekday(.wide).month(.wide).day())
        if let callout { label += ", \(callout.callout?.label ?? ""): \(callout.event.title)" }
        if !dayDots.isEmpty { label += ", has events" }
        return Button {
            selection = isSelected ? nil : cal.startOfDay(for: day)
        } label: {
            VStack(spacing: 2) {
                Text("\(cal.component(.day, from: day))")
                    .font(.system(size: 11, weight: isToday ? .bold : .regular).monospacedDigit())
                    .foregroundStyle(numberColor)
                    .frame(width: Self.numberSize, height: Self.numberSize)
                    .background {
                        // Orange marks what is "on": today, and (fainter) the scoped day.
                        if isToday { Circle().fill(Color(sk1Hex: SK1.orange)) }
                        else if isSelected { Circle().fill(Color(sk1Hex: SK1.orange, opacity: 0.22)) }
                    }
                    .frame(maxWidth: .infinity)
                    .background { if let callout { calloutBand(callout, column: column) } }
                if lanes > 0 { Color.clear.frame(height: CGFloat(lanes) * Self.laneHeight - 2) }
                HStack(spacing: 2) {
                    ForEach(dayDots, id: \.self) { hex in
                        Circle().fill(Color(hex: hex)).frame(width: 4, height: 4)
                    }
                }.frame(height: 4)
            }
            .frame(maxWidth: .infinity)
            .background(weekendTint)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// The tint behind the dates of an away or on-call stretch, rounded where the stretch starts and ends.
    private func calloutBand(_ r: MiniMonthRibbon, column: Int) -> some View {
        let first = column == r.startColumn && !r.continuesBefore, last = column == r.endColumn && !r.continuesAfter
        let radius = Self.numberSize / 2
        return UnevenRoundedRectangle(topLeadingRadius: first ? radius : 0, bottomLeadingRadius: first ? radius : 0,
                                      bottomTrailingRadius: last ? radius : 0, topTrailingRadius: last ? radius : 0)
            .fill(Color(hex: r.event.colorHex).opacity(0.2))
            .frame(height: Self.numberSize)
            .overlay(alignment: .topTrailing) {
                if first, let c = r.callout {
                    Image(systemName: c.symbol).font(.system(size: 6, weight: .bold)).foregroundStyle(Color(hex: r.event.colorHex))
                        .offset(x: -1, y: 1).accessibilityHidden(true)
                }
            }
    }

    private func navButton(_ symbol: String, help: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol) }
            .buttonStyle(.sk1Key(.round, size: .small)).help(help).accessibilityLabel(Text(help))
    }

    private func shift(_ n: Int) {
        month = Calendar.app.date(byAdding: .month, value: n, to: month) ?? month
    }
}

/// The next / in-progress meeting in a sunken tray: a large LCD countdown, title, time, and the Join key. Its edge
/// turns from teal to a glowing orange as the meeting nears (`HeroUrgency`), so it stands apart from the agenda.
struct HeroMeetingCard: View {
    let event: CalendarEvent
    let now: Date
    /// Other meetings at the same time (`MenuAgendaBuilder.overlapping`), listed under the Join key.
    var overlapping: [CalendarEvent] = []
    /// When auto-join opens this meeting, if it's set to.
    var autoJoinAt: Date? = nil

    var body: some View {
        let inProgress = event.start <= now
        let target = inProgress ? event.end : event.start
        let countdown = SK1CountdownDigits.compact(target.timeIntervalSince(now))
        let urgency = HeroUrgency.of(event, now: now)
        let shape = RoundedRectangle(cornerRadius: SK1.Metrics.wellRadius, style: .continuous)
        SKWell {
            VStack(alignment: .leading, spacing: 8) {
                SK1CountdownLCD(caption: inProgress ? "Now · ends in" : "Starts in",
                                digits: countdown.digits, unit: countdown.unit, live: inProgress,
                                lamp: urgency.lamp, lampBlinking: urgency.lampBlinks, height: 50,
                                accessibilityText: (inProgress ? "In progress, ends " : "Starts ")
                                    + RelativeTimeFormatter.string(for: target, relativeTo: now))
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Circle().fill(Color(hex: event.colorHex)).frame(width: 8, height: 8)
                    Text(event.title).font(.title2.bold()).lineLimit(2)
                }
                HStack(spacing: 10) {
                    Label(timeRange, systemImage: "clock")
                    if !event.attendees.isEmpty {
                        Label("\(event.attendees.count)", systemImage: "person.2").help("\(event.attendees.count) attendees")
                    }
                }
                .font(.callout).foregroundStyle(.secondary)
                if let loc = event.location, !loc.isEmpty {
                    Label(loc, systemImage: "mappin.and.ellipse").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                if let at = autoJoinAt, at > now {
                    Label("Auto-joins at \(at.shortTime)", systemImage: "bolt.circle").font(.caption).foregroundStyle(.secondary)
                }
                if event.meetURL != nil {
                    // Cream: the popover's one orange key is Join in the tray above.
                    JoinButton(event: event, size: .large, fillsWidth: true, key: .cream)
                } else {
                    Text("No video link").sk1Hint()
                }
                if !overlapping.isEmpty {
                    OverlappingMeetingsList(events: overlapping, now: now, joinKey: .cream)
                }
            }
            .padding(12)
            .background(shape.fill(urgency.edgeColor.opacity(urgency.washOpacity)))
        }
        .overlay(
            shape.strokeBorder(urgency.edgeColor.opacity(urgency.edgeOpacity), lineWidth: urgency.edgeWidth)
                .shadow(color: urgency.edgeColor.opacity(urgency.glow > 0 ? 0.6 : 0), radius: urgency.glow)
                .allowsHitTesting(false)
        )
        .animation(.easeInOut(duration: 0.4), value: urgency)
        .eventDetailOnClick(event, arrowEdge: .leading)
        .contextMenu { MeetingSecondaryActions(event: event) }
    }

    private var timeRange: String {
        "\(event.start.shortTime) – \(event.end.shortTime)"
    }
}

/// The meetings that overlap the featured one, under a "Also on now" / "Overlaps" caption, each with its own Join.
struct OverlappingMeetingsList: View {
    let events: [CalendarEvent]
    let now: Date
    var joinKey: SK1KeyVariant?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            SKGroove().padding(.vertical, 2)
            HStack(spacing: 5) {
                Image(systemName: "rectangle.on.rectangle").font(.caption2)
                SKCaption(OverlapCaption.text(events, now: now), tone: .soft)
            }
            .foregroundStyle(.secondary)
            ForEach(events, id: \.uid) { AgendaRow(event: $0, now: now, joinKey: joinKey) }
        }
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
                            .eventChip(e.colorHex)
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
        let cal = Calendar.app
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
            Text(now.shortTime).font(.caption2.monospacedDigit()).foregroundStyle(red)
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
                    Text("\(event.start.shortTime) – \(event.end.shortTime)")
                    if !ended && !inProgress && event.start.timeIntervalSince(now) < 12 * 3600 {
                        Text("· in \(TimeUntilFormatter.string(until: event.start, now: now))")
                    }
                    if let u = event.meetURL { MeetingServiceBadge(url: u) }
                    if let tz = event.foreignTimeZone() {
                        Image(systemName: "globe").help(EventTimeZoneText.there(event, in: tz))
                            .accessibilityLabel(EventTimeZoneText.there(event, in: tz))
                    }
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

/// The world clocks from Settings › Menu Bar, under the status strip: each city's time on LCD glass, and the day when it
/// differs from here.
struct WorldClockStrip: View {
    let now: Date
    @AppStorage(AppPreferences.Key.worldClocks) private var raw = ""
    @AppStorage(AppPreferences.Key.clockStyle) private var clockRaw = ClockStyle.system.rawValue

    var body: some View {
        let clocks = WorldClock.decode(raw)
        if !clocks.isEmpty {
            let locale = AppPreferences.locale(clock: ClockStyle(rawValue: clockRaw) ?? .system)
            SKLCD {
                HStack(spacing: 0) {
                    ForEach(Array(clocks.enumerated()), id: \.element.id) { i, clock in
                        if i > 0 { Rectangle().fill(Color(sk1Hex: SK1.lcdInk, opacity: 0.2)).frame(width: 1).padding(.vertical, 5) }
                        VStack(spacing: 0) {
                            Text(clock.displayLabel.uppercased())
                                .font(.system(size: 8.5, weight: .heavy)).tracking(0.8).lineLimit(1)
                            HStack(spacing: 3) {
                                Text(now.shortTime(locale: locale, timeZone: clock.timeZone))
                                    .font(.sk1(SK1.TypeScale.lcdMono)).monospacedDigit()
                                if let shift = clock.dayShift(at: now) {
                                    Text(shift == "Tomorrow" ? "+1" : "\u{2212}1").font(.system(size: 8, weight: .heavy))
                                }
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .help("\(clock.displayLabel): \(clock.offsetText(from: .current))\(clock.dayShift(at: now).map { ", \($0.lowercased())" } ?? "")")
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(clock.displayLabel), \(now.shortTime(locale: locale, timeZone: clock.timeZone))\(clock.dayShift(at: now).map { ", \($0.lowercased())" } ?? "")")
                    }
                }
                .foregroundStyle(Color(sk1Hex: SK1.lcdInk))
                .padding(.horizontal, 6)
            }
            .frame(height: 34)
        }
    }
}
