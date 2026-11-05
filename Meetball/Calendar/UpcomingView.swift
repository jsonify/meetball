import SwiftUI
import AppKit

/// "Upcoming" dashboard: the next meeting front and centre, the rest of today, and the week's meeting load.
struct UpcomingView: View {
    @EnvironmentObject var store: CalendarStore
    var onNewEvent: () -> Void
    /// "Show anyway": include events hidden by the meeting-first rules.
    @State private var showHidden = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 15)) { ctx in
            let now = ctx.date
            let feed = store.meetingFeed
            let events = showHidden ? store.visibleEvents : feed.shown
            let hero = Self.nextToday(events, now: now)
            VStack(spacing: 0) {
                header(now: now)
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        if let hero {
                            NextMeetingCard(event: hero, now: now)
                            restOfToday(events, now: now, excluding: hero)
                        } else {
                            NoMoreMeetingsView(preview: Self.nextDayPreview(events, now: now), now: now)
                        }
                        WeekLoadStrip(loads: MeetingLoadBuilder.build(events: events, from: now, days: 7), now: now)
                        HiddenEventsToggle(count: Self.hiddenUpcoming(feed.hidden, now: now), showing: $showHidden)
                    }
                    .padding(20)
                    .frame(maxWidth: 760)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .environment(\.eventFilterSettings, store.filters)
    }

    private func header(now: Date) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 0) {
                Text("Upcoming").font(.title2.bold())
                Text(now, format: .dateTime.weekday(.wide).month(.wide).day()).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            Button { store.refresh() } label: { Image(systemName: "arrow.clockwise") }.help("Refresh")
            Button(action: onNewEvent) { Label("New event", systemImage: "plus") }.buttonStyle(.borderedProminent)
        }
        .padding(12)
    }

    @ViewBuilder private func restOfToday(_ events: [CalendarEvent], now: Date, excluding hero: CalendarEvent) -> some View {
        let rest = Self.laterToday(events, now: now).filter { $0.uid != hero.uid }
        if !rest.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Later today").font(.headline)
                VStack(spacing: 2) {
                    ForEach(rest, id: \.uid) { e in AgendaRow(event: e, now: now).padding(.horizontal, 8) }
                }
                .padding(.vertical, 6)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    // MARK: Selection logic

    /// In-progress meeting, else the next one that starts before the end of today.
    static func nextToday(_ events: [CalendarEvent], now: Date, calendar: Calendar = .current) -> CalendarEvent? {
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
        return MenuAgendaBuilder.hero(events, now: now, horizon: max(0, endOfDay.timeIntervalSince(now) - 1))
    }

    /// Timed, not-declined meetings today that haven't ended.
    static func laterToday(_ events: [CalendarEvent], now: Date, calendar: Calendar = .current) -> [CalendarEvent] {
        events.filter { !$0.isBarEvent(calendar: calendar) && !$0.isDeclined && $0.end > now && calendar.isDate($0.start, inSameDayAs: now) }
            .sorted { $0.start < $1.start }
    }

    /// Hidden timed events in the next week that haven't ended (declined ones never show here anyway).
    static func hiddenUpcoming(_ hidden: [CalendarEvent], now: Date, calendar: Calendar = .current) -> Int {
        let horizon = calendar.date(byAdding: .day, value: 7, to: calendar.startOfDay(for: now)) ?? now
        return hidden.filter { !$0.isBarEvent(calendar: calendar) && !$0.isDeclined && $0.end > now && $0.start < horizon }.count
    }

    /// The first later day (within what's loaded) that has meetings.
    static func nextDayPreview(_ events: [CalendarEvent], now: Date, calendar: Calendar = .current) -> (day: Date, events: [CalendarEvent])? {
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
        let later = events.filter { !$0.isBarEvent(calendar: calendar) && !$0.isDeclined && $0.start >= tomorrow }.sorted { $0.start < $1.start }
        guard let first = later.first else { return nil }
        let day = calendar.startOfDay(for: first.start)
        return (day, later.filter { calendar.isDate($0.start, inSameDayAs: day) })
    }
}

// MARK: - Next meeting card

private struct NextMeetingCard: View {
    let event: CalendarEvent
    let now: Date
    @EnvironmentObject var guardian: MeetingGuardianManager
    @EnvironmentObject var guardianStore: MeetingGuardianStore

    private var inProgress: Bool { event.start <= now }
    private var tint: Color { Color(hex: event.colorHex) }

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            CountdownRing(progress: progress, label: ringLabel, caption: inProgress ? "left" : "to go", tint: inProgress ? .red : tint)
                .frame(width: 110, height: 110)
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(inProgress ? "Happening now" : "Next meeting")
                        .font(.caption.weight(.semibold)).textCase(.uppercase)
                        .foregroundStyle(inProgress ? Color.red : Color.secondary)
                    Text(event.title).font(.title.bold()).lineLimit(2)
                        .eventDetailOnClick(event, arrowEdge: .bottom)
                        .help("Show details")
                    Label("\(timeRange) · \(DurationFormatter.string(from: event.start, to: event.end))", systemImage: "clock")
                        .font(.callout).foregroundStyle(.secondary)
                    if let loc = event.location?.trimmingCharacters(in: .whitespacesAndNewlines), !loc.isEmpty {
                        Label(loc, systemImage: "mappin.and.ellipse").font(.callout).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                if !people.isEmpty { AvatarStack(people: people) }
                HStack(spacing: 8) {
                    if event.meetURL != nil { JoinButton(event: event, size: .large) }
                    if let open = openInCalendar {
                        Button(open.title, action: open.action).controlSize(.large)
                    }
                }
                alertState
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(tint.opacity(0.25)))
        .contextMenu { MeetingSecondaryActions(event: event) }
    }

    private var timeRange: String {
        "\(event.start.formatted(date: .omitted, time: .shortened)) – \(event.end.formatted(date: .omitted, time: .shortened))"
    }

    /// Before the start the ring fills over the last hour; during the meeting it fills with elapsed time.
    private var progress: Double {
        if inProgress {
            let total = event.end.timeIntervalSince(event.start)
            return total > 0 ? min(1, now.timeIntervalSince(event.start) / total) : 1
        }
        return 1 - min(event.start.timeIntervalSince(now), 3600) / 3600
    }

    private var ringLabel: String {
        TimeUntilFormatter.string(until: inProgress ? event.end : event.start, now: now)
    }

    private var people: [EventAttendee] {
        event.participants.isEmpty ? event.attendees.map { EventAttendee(email: $0) } : event.participants
    }

    private var openInCalendar: (title: String, action: () -> Void)? {
        if let link = event.htmlLink { return ("Open in Google Calendar", { NSWorkspace.shared.open(link) }) }
        if let u = event.calendarAppURL { return ("Open in Calendar", { NSWorkspace.shared.open(u) }) }
        return nil
    }

    @ViewBuilder private var alertState: some View {
        let muted = guardianStore.isMuted(event)
        let upcoming = guardian.plannedAlerts(for: event).filter { $0.fireDate > now }
        HStack(spacing: 6) {
            Image(systemName: muted ? "bell.slash" : "bell.badge").foregroundStyle(.secondary)
            if muted {
                Text("Alerts muted for this meeting")
            } else if upcoming.isEmpty {
                Text(inProgress || guardian.plannedAlerts(for: event).isEmpty ? "No more alerts for this meeting" : "Alert already shown")
            } else {
                Text(upcoming.map { a in
                    "\(Self.styleName(a.style)) at \(a.fireDate.formatted(date: .omitted, time: .shortened))"
                        + (a.lead == 0 ? " (start)" : " (\(a.lead) min before)")
                }.joined(separator: ", "))
            }
            if !event.isAllDay && !inProgress {
                Button(muted ? "Unmute" : "Mute") { guardianStore.setMuted(!muted, for: event) }.buttonStyle(.link)
            }
        }
        .font(.caption).foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
    }

    static func styleName(_ s: AlertStyle) -> String {
        switch s {
        case .soft: return "Notification"
        case .headsUp: return "Heads-up overlay"
        case .hard: return "Hard alert"
        }
    }
}

private struct CountdownRing: View {
    let progress: Double
    let label: String
    let caption: String
    let tint: Color

    var body: some View {
        ZStack {
            Circle().stroke(Color.secondary.opacity(0.15), lineWidth: 8)
            Circle().trim(from: 0, to: max(0.001, progress))
                .stroke(tint, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.4), value: progress)
            VStack(spacing: 0) {
                Text(label).font(.title2.bold().monospacedDigit()).minimumScaleFactor(0.6).lineLimit(1)
                Text(caption).font(.caption).foregroundStyle(.secondary)
            }
            .padding(12)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label) \(caption)")
    }
}

/// Overlapping initials avatars, up to five, then "+n".
private struct AvatarStack: View {
    let people: [EventAttendee]
    private let maxShown = 5

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: -8) {
                ForEach(Array(people.prefix(maxShown).enumerated()), id: \.offset) { _, p in
                    Text(p.initials).font(.caption2.bold()).foregroundStyle(.white)
                        .frame(width: 26, height: 26)
                        .background(Self.color(for: p.email ?? p.displayName), in: Circle())
                        .overlay(Circle().strokeBorder(Color(nsColor: .windowBackgroundColor), lineWidth: 2))
                        .opacity(p.response == .declined ? 0.45 : 1)
                        .help("\(p.displayName) · \(p.response.label)")
                }
                if people.count > maxShown {
                    Text("+\(people.count - maxShown)").font(.caption2.bold())
                        .frame(width: 26, height: 26)
                        .background(Color.secondary.opacity(0.25), in: Circle())
                }
            }
            Text("\(people.count) guest\(people.count == 1 ? "" : "s")").font(.caption).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(people.count) guests: \(people.prefix(maxShown).map(\.displayName).joined(separator: ", "))")
    }

    private static let palette = ["#4285F4", "#0B8043", "#D50000", "#F4511E", "#8E24AA", "#039BE5", "#616161", "#E67C73"]

    /// Stable colour per person (String.hashValue is seeded per launch, so use a simple checksum).
    static func color(for key: String) -> Color {
        let sum = key.lowercased().unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0x7FFF_FFFF }
        return Color(hex: palette[sum % palette.count])
    }
}

// MARK: - Empty state

private struct NoMoreMeetingsView: View {
    let preview: (day: Date, events: [CalendarEvent])?
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "sun.max.fill").font(.system(size: 32)).foregroundStyle(.yellow)
                VStack(alignment: .leading, spacing: 2) {
                    Text("No more meetings today").font(.title2.bold())
                    Text("Enjoy the focus time.").foregroundStyle(.secondary)
                }
            }
            if let preview {
                VStack(alignment: .leading, spacing: 6) {
                    Text(dayTitle(preview.day)).font(.headline)
                    VStack(spacing: 2) {
                        ForEach(preview.events.prefix(6), id: \.uid) { e in AgendaRow(event: e, now: now).padding(.horizontal, 8) }
                        if preview.events.count > 6 {
                            Text("+\(preview.events.count - 6) more").font(.caption).foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 8)
                        }
                    }
                    .padding(.vertical, 6)
                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                }
            } else {
                Text("Nothing scheduled in the next few days.").foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
    }

    private func dayTitle(_ d: Date) -> String {
        Calendar.current.isDateInTomorrow(d) ? "Tomorrow" : d.formatted(.dateTime.weekday(.wide).month(.wide).day())
    }
}

// MARK: - Week strip

private struct WeekLoadStrip: View {
    let loads: [DayMeetingLoad]
    let now: Date
    @EnvironmentObject var store: CalendarStore
    private let barHeight: CGFloat = 70

    var body: some View {
        let scale = max(6, loads.map(\.hours).max() ?? 0)
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("This week").font(.headline)
                Spacer()
                Text(String(format: "%.1f h in meetings", loads.reduce(0) { $0 + $1.hours }))
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(loads) { load in
                    Button { open(load.day) } label: { column(load, scale: scale) }
                        .buttonStyle(.plain)
                        .help("Open \(load.day.formatted(.dateTime.weekday(.wide))) in Day view")
                }
            }
        }
    }

    private func column(_ load: DayMeetingLoad, scale: Double) -> some View {
        let isToday = Calendar.current.isDate(load.day, inSameDayAs: now)
        return VStack(spacing: 4) {
            Text(load.hours == 0 ? "–" : String(format: load.hours < 10 ? "%.1fh" : "%.0fh", load.hours))
                .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 4).fill(Color.secondary.opacity(0.1))
                RoundedRectangle(cornerRadius: 4).fill(color(for: load.hours))
                    .frame(height: max(load.hours > 0 ? 3 : 0, barHeight * min(1, load.hours / scale)))
            }
            .frame(height: barHeight)
            Text(load.day, format: .dateTime.weekday(.abbreviated)).font(.caption.weight(isToday ? .bold : .regular))
            Text("\(Calendar.current.component(.day, from: load.day))")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(isToday ? Color.white : Color.secondary)
                .frame(width: 20, height: 20)
                .background(isToday ? Color.accentColor : .clear, in: Circle())
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(load.day.formatted(.dateTime.weekday(.wide).month().day())): "
                            + "\(load.count) meeting\(load.count == 1 ? "" : "s"), \(String(format: "%.1f", load.hours)) hours")
        .accessibilityAddTraits(.isButton)
    }

    /// Green under 3 h, orange under 5 h, red beyond.
    private func color(for hours: Double) -> Color {
        hours < 3 ? .green.opacity(0.7) : hours < 5 ? .orange.opacity(0.8) : .red.opacity(0.8)
    }

    private func open(_ day: Date) {
        store.select(day)
        store.viewMode = .day
        store.section = .calendar
    }
}
