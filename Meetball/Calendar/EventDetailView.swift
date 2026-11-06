import SwiftUI
import AppKit
import SK1UI

extension View {
    /// Click to show the event's details in a popover (Esc or clicking outside dismisses it).
    func eventDetailOnClick(_ event: CalendarEvent, arrowEdge: Edge = .trailing) -> some View {
        modifier(EventDetailOnClick(event: event, arrowEdge: arrowEdge))
    }
}

private struct EventDetailOnClick: ViewModifier {
    let event: CalendarEvent
    let arrowEdge: Edge
    @EnvironmentObject private var store: CalendarStore
    @EnvironmentObject private var guardianStore: MeetingGuardianStore
    @State private var showing = false

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .onTapGesture { showing = true }
            .popover(isPresented: $showing, arrowEdge: arrowEdge) {
                // Re-inject explicitly: popovers live in their own window and shouldn't rely on inheritance.
                EventDetailPopover(event: event).environmentObject(store).environmentObject(guardianStore)
            }
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(named: "Show details") { showing = true }
    }
}

/// Everything about one event: time, place, join link, notes, attendees with RSVP state, and actions.
struct EventDetailPopover: View {
    let event: CalendarEvent
    @EnvironmentObject var store: CalendarStore
    @EnvironmentObject var guardianStore: MeetingGuardianStore
    @Environment(\.dismiss) private var dismiss
    @State private var showAllAttendees = false
    @State private var confirmingDelete = false
    /// Pre-flight: the last meeting like this one in what's loaded, and the invite's links.
    @State private var brief: PreFlightBrief?
    @AppStorage(AppPreferences.Key.showEventTimeZone) private var showEventTimeZone = true

    private var isApple: Bool { AppleCalendarClient.isApple(event.accountEmail) }
    private var calendarName: String? { store.calendars.first { $0.key == event.calendarKey }?.summary }
    private var notes: String { event.notes.map(EventNotesFormatter.plainText) ?? "" }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Grow with the content; scroll only once it would be taller than the cap.
            ViewThatFits(in: .vertical) {
                content
                ScrollView { content }.frame(height: maxContentHeight)
            }
            .frame(maxHeight: maxContentHeight)
            SKGroove()
            actions.padding(.horizontal, 10).padding(.vertical, 8)
        }
        .frame(width: 340)
        .sk1Chassis()
        .onExitCommand { dismiss() }
        .onAppear { if !event.isAllDay { brief = PreFlight.brief(for: event, history: store.events) } }
    }

    private let maxContentHeight: CGFloat = 460

    private var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            details
            if let url = event.meetURL { joinRow(url) }
            if event.meetURL != nil, !event.isAllDay, event.end > Date() { autoJoinRow }
            if !people.isEmpty || event.organizer != nil { attendeesSection }
            if !notes.isEmpty { notesSection }
            if let brief, brief.lastTime != nil || !brief.links.isEmpty { preFlightSection(brief) }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Sections

    private var header: some View {
        HStack(alignment: .top, spacing: 8) {
            RoundedRectangle(cornerRadius: 3).fill(Color(hex: event.colorHex)).frame(width: 12, height: 12).padding(.top, 4)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title).font(.headline).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                if let calendarName {
                    Text(calendarName).font(.caption).foregroundStyle(.secondary)
                        .accessibilityLabel("Calendar: \(calendarName)")
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(timeText, systemImage: "clock").accessibilityLabel("When: \(timeText)")
            if showEventTimeZone, let tz = event.foreignTimeZone() {
                Label(EventTimeZoneText.there(event, in: tz), systemImage: "globe")
                    .help("This event was set in \(tz.localizedName(for: .generic, locale: .current) ?? tz.identifier). Times above are in your time zone.")
                    .accessibilityLabel("In the event's time zone: \(EventTimeZoneText.there(event, in: tz))")
            }
            if let loc = event.location?.trimmingCharacters(in: .whitespacesAndNewlines), !loc.isEmpty {
                Button { openLocation(loc) } label: {
                    Label(loc, systemImage: "mappin.and.ellipse").lineLimit(2).multilineTextAlignment(.leading)
                }
                .buttonStyle(.sk1Key(size: .small))
                .help(isWebLink(loc) ? "Open link" : "Open in Maps")
                .accessibilityLabel("Location: \(loc)")
                .accessibilityHint(isWebLink(loc) ? "Opens the link" : "Opens in Maps")
            }
            if event.isDeclined {
                Label("You declined", systemImage: "xmark.circle").foregroundStyle(.secondary)
            }
            if guardianStore.isMuted(event) {
                Label("Alerts muted for this event", systemImage: "bell.slash").foregroundStyle(.secondary)
            }
        }
        .font(.callout)
    }

    private func joinRow(_ url: URL) -> some View {
        HStack(spacing: 8) {
            JoinButton(event: event, key: .orange)
            Button { MeetingJoiner.copyLink(url) } label: { Label("Copy link", systemImage: "doc.on.doc") }
                .buttonStyle(.sk1Key())
                .help("Copy meeting link").accessibilityLabel("Copy meeting link")
            Spacer(minLength: 0)
        }
    }

    /// Auto-join (#24): off, this meeting, or (for a recurring one) every meeting in the series.
    private var autoJoinRow: some View {
        let recurring = AutoJoin.seriesKey(event) != nil
        let options: [SKSegmented<String>.Option] = recurring
            ? [.init("off", "Off"), .init(AutoJoinScope.occurrence.rawValue, "This one"), .init(AutoJoinScope.series.rawValue, "Every one")]
            : [.init("off", "Off"), .init(AutoJoinScope.occurrence.rawValue, "On")]
        let selection = Binding<String>(
            get: { guardianStore.autoJoinScope(for: event)?.rawValue ?? "off" },
            set: { guardianStore.setAutoJoin(AutoJoinScope(rawValue: $0), for: event) })
        let delay = guardianStore.settings.autoJoinDelayMinutes
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Label("Auto-join", systemImage: "bolt.circle").font(.callout)
                Spacer(minLength: 0)
                SKSegmented(selection: selection, options: options).frame(width: recurring ? 190 : 110)
            }
            if guardianStore.isAutoJoin(event) {
                Text("Opens at \(AutoJoin.joinTime(event, delayMinutes: delay).shortTime) if you haven't joined yet."
                     + (guardianStore.isAutoJoinByDefault(event) ? " Recurring meetings auto-join by default (Settings › Join)." : ""))
                    .sk1Hint()
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var people: [EventAttendee] {
        if !event.participants.isEmpty {
            return event.participants.sorted { a, b in
                if a.isOrganizer != b.isOrganizer { return a.isOrganizer }
                return a.displayName.localizedCaseInsensitiveCompare(b.displayName) == .orderedAscending
            }
        }
        return event.attendees.map { EventAttendee(email: $0) }
    }

    private var attendeesSection: some View {
        let all = people
        let shown = showAllAttendees ? all : Array(all.prefix(8))
        return VStack(alignment: .leading, spacing: 5) {
            HStack {
                SKCaption(all.isEmpty ? "Organizer" : "\(all.count) guest\(all.count == 1 ? "" : "s")", tone: .soft)
                Spacer()
                if !all.isEmpty { Text(responseSummary(all)).font(.caption).foregroundStyle(.secondary) }
            }
            if let org = event.organizer, !all.contains(where: \.isOrganizer) {
                Label("Organized by \(org)", systemImage: "person.crop.circle").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(Array(shown.enumerated()), id: \.offset) { _, p in attendeeRow(p) }
            if all.count > 8 {
                Button(showAllAttendees ? "Show fewer" : "Show all \(all.count)") { showAllAttendees.toggle() }
                    .buttonStyle(.sk1Key(size: .small))
            }
        }
    }

    private func attendeeRow(_ p: EventAttendee) -> some View {
        HStack(spacing: 6) {
            Image(systemName: p.response.symbol).foregroundStyle(color(for: p.response)).font(.caption)
                .help(p.response.label)
            Text(p.displayName).font(.callout).lineLimit(1).textSelection(.enabled)
            if p.isOrganizer { Text("Organizer").font(.caption2).foregroundStyle(.secondary) }
            if p.isSelf { Text("You").font(.caption2).foregroundStyle(.secondary) }
            Spacer(minLength: 0)
        }
        .help(p.email ?? p.displayName)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(p.displayName)\(p.isOrganizer ? ", organizer" : ""), \(p.response.label)")
    }

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            SKCaption("Notes", tone: .soft)
            Text(EventNotesFormatter.linked(notes)).font(.callout).textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func preFlightSection(_ brief: PreFlightBrief) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let last = brief.lastTime {
                SKCaption(brief.match?.label ?? "Last time", tone: .soft)
                Label("\(last.title) · \(last.start.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())), "
                      + RelativeTimeFormatter.string(for: last.start, relativeTo: Date()), systemImage: "clock.arrow.circlepath")
                    .font(.callout).lineLimit(2)
            }
            if !brief.links.isEmpty {
                SKCaption("From the invite", tone: .soft)
                InviteLinks(links: brief.links)
            }
        }
    }

    private var actions: some View {
        HStack(spacing: 6) {
            if confirmingDelete {
                Text("Delete this event?").font(.callout)
                Spacer()
                Button("Cancel") { confirmingDelete = false }.buttonStyle(.sk1Key(size: .small)).keyboardShortcut(.cancelAction)
                Button("Delete", role: .destructive) {
                    Task { await store.delete(event) }
                    dismiss()
                }
                .buttonStyle(.sk1Key(.charcoal, size: .small))
                .keyboardShortcut(.defaultAction)
            } else {
                if let link = event.htmlLink {
                    Button { NSWorkspace.shared.open(link) } label: { Label("Google Calendar", systemImage: "arrow.up.right.square") }
                        .buttonStyle(.sk1Key(size: .small))
                        .help("Open in Google Calendar")
                } else if isApple {
                    Button { openInAppleCalendar() } label: { Label("Calendar", systemImage: "arrow.up.right.square") }
                        .buttonStyle(.sk1Key(size: .small))
                        .help("Open in Calendar")
                        .accessibilityLabel("Open in Calendar")
                    // A Google calendar subscribed in Calendar (the work feed) is read-only here: edit it in Google.
                    if GoogleEventLink.isFromGoogle(event),
                       let link = GoogleEventLink.editURL(for: event, account: nil)
                        ?? GoogleEventLink.searchURL(for: event, account: nil) {
                        Button { NSWorkspace.shared.open(link) } label: { Label("Edit in Google", systemImage: "pencil") }
                            .buttonStyle(.sk1Key(size: .small))
                            .help("Edit this event in Google Calendar")
                    }
                }
                Spacer()
                if !event.isAllDay {
                    let muted = guardianStore.isMuted(event)
                    Button { guardianStore.setMuted(!muted, for: event) } label: {
                        Image(systemName: muted ? "bell.slash.fill" : "bell")
                    }
                    .buttonStyle(.sk1Key(isOn: muted, size: .small))
                    .help(muted ? "Unmute alerts for this event" : "Mute alerts for this event")
                    .accessibilityLabel(muted ? "Unmute alerts for this event" : "Mute alerts for this event")
                }
                if !isApple {
                    Button { confirmingDelete = true } label: { Image(systemName: "trash") }
                        .buttonStyle(.sk1Key(size: .small))
                        .help("Delete event").accessibilityLabel("Delete event")
                }
            }
        }
    }

    // MARK: Helpers

    private var timeText: String {
        let cal = Calendar.app
        if event.isAllDay {
            let lastDay = event.end.addingTimeInterval(-1)
            if cal.isDate(event.start, inSameDayAs: lastDay) {
                return event.start.formatted(.dateTime.weekday(.wide).month().day()) + " · All day"
            }
            return "\(event.start.formatted(.dateTime.month().day())) – \(lastDay.formatted(.dateTime.month().day())) · All day"
        }
        let duration = DurationFormatter.string(from: event.start, to: event.end)
        let startDay = event.start.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        if cal.isDate(event.start, inSameDayAs: event.end.addingTimeInterval(-1)) {
            return "\(startDay), \(event.start.shortTime) – \(event.end.shortTime) (\(duration))"
        }
        let endDay = event.end.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        return "\(startDay), \(event.start.shortTime) – \(endDay), \(event.end.shortTime) (\(duration))"
    }

    private func responseSummary(_ all: [EventAttendee]) -> String {
        let yes = all.filter { $0.response == .accepted }.count
        let no = all.filter { $0.response == .declined }.count
        let maybe = all.filter { $0.response == .tentative }.count
        let waiting = all.count - yes - no - maybe
        return [yes > 0 ? "\(yes) yes" : nil, no > 0 ? "\(no) no" : nil, maybe > 0 ? "\(maybe) maybe" : nil,
                waiting > 0 ? "\(waiting) awaiting" : nil].compactMap { $0 }.joined(separator: ", ")
    }

    private func color(for r: AttendeeResponse) -> Color {
        switch r {
        case .accepted: return .green
        case .declined: return .red
        case .tentative: return .orange
        case .needsAction: return .secondary
        }
    }

    /// Web/meeting links open as-is; anything else is looked up in Maps.
    private func isWebLink(_ loc: String) -> Bool {
        guard let scheme = URL(string: loc)?.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }

    private func locationURL(_ loc: String) -> URL? {
        if isWebLink(loc) { return URL(string: loc) }
        var c = URLComponents(string: "https://maps.apple.com/")
        c?.queryItems = [URLQueryItem(name: "q", value: loc)]
        return c?.url
    }

    private func openLocation(_ loc: String) {
        if let u = locationURL(loc) { NSWorkspace.shared.open(u) }
    }

    private func openInAppleCalendar() {
        if let u = event.calendarAppURL, NSWorkspace.shared.open(u) { return }
        if let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iCal") {
            NSWorkspace.shared.openApplication(at: app, configuration: NSWorkspace.OpenConfiguration())
        }
    }
}

/// "9:00 – 10:00 AM in London (GMT+1)": an event's times where it was set.
enum EventTimeZoneText {
    static func there(_ e: CalendarEvent, in tz: TimeZone, locale: Locale = AppPreferences.locale) -> String {
        let city = WorldClock.cityName(tz.identifier)
        let abbr = tz.abbreviation(for: e.start).map { " (\($0))" } ?? ""
        return "\(e.start.shortTime(locale: locale, timeZone: tz)) \u{2013} \(e.end.shortTime(locale: locale, timeZone: tz)) in \(city)\(abbr)"
    }
}

/// The invite's links as small keys, one per row.
private struct InviteLinks: View {
    let links: [PreFlightLink]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(links) { link in
                Button { NSWorkspace.shared.open(link.url) } label: {
                    Label(link.label, systemImage: "arrow.up.forward.square").lineLimit(1)
                }
                .buttonStyle(.sk1Key(size: .small))
                .help(link.url.absoluteString)
            }
        }
    }
}
