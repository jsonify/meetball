import EventKit
import SwiftUI
import UIKit
import SK1Tokens
import SK1UI

/// A meeting's details: when, where, the Join key, who's coming and the notes.
///
/// Not a sheet: the root view lays it over the app as a full panel that grows out of the event you tapped and shrinks
/// back into it (`EventOpenTransition`). Close with ✕ or a swipe to the right. Edit turns the panel over to the editor
/// on its back; Cancel turns it back.
struct EventDetailSheet: View {
    let event: CalendarEvent
    /// Closes the panel.
    var onClose: () -> Void
    @EnvironmentObject private var store: PhoneStore
    @AppStorage("phone.workEmail") private var workEmail = ""
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var copied = 0
    /// The stored event when its calendar can be changed here; nil for a read-only feed such as the work calendar.
    @State private var editable: (event: EKEvent, store: EKEventStore)?
    @State private var editing = false
    @State private var confirmingDelete = false
    @State private var deleteError: String?
    @State private var brief: PreFlightBrief?
    @State private var recording = false
    /// How far a swipe to close has pulled the panel to the right.
    @State private var pull: CGFloat = 0

    var body: some View {
        ZStack {
            if editing, let editable {
                EventEditSheet(event: event, ekEvent: editable.event, eventStore: editable.store) { action in
                    switch action {
                    case .canceled: editing = false
                    case .deleted: store.noteDeleted(event); onClose()
                    default: onClose()
                    }
                }
                .environmentObject(store)
                .transition(reduceMotion ? .opacity : CardTurn.transition(back: true))
            } else {
                details.transition(reduceMotion ? .opacity : CardTurn.transition(back: false))
            }
        }
        .animation(.easeInOut(duration: 0.5), value: editing)
        .onAppear {
            editable = store.editableEvent(for: event)
            if !event.isAllDay { brief = store.preFlight(for: event) }
        }
        .sheet(isPresented: $recording) {
            EchoSheet(event: event).environmentObject(store)
        }
    }

    private var details: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SK1.Metrics.groupSpacing) {
                header
                TimelineView(.periodic(from: .now, by: 15)) { tl in countdown(now: tl.date) }
                if event.meetURL != nil {
                    PhoneJoinButton(event: event, variant: .orange, size: .large, fillsWidth: true)
                }
                whenGroup
                // Yes / Maybe / No for a meeting you were invited to.
                if event.canRespond { ReplyGroup(event: event).environmentObject(store) }
                if !event.isAllDay && event.end > Date() { alertsGroup }
                // The place with Directions, Where's this? for a trip with no place, or a room or link as it is.
                TripWhereSection(event: event)
                if !event.participants.isEmpty { peopleGroup }
                if let notes = event.notes.map(EventNotesFormatter.plainText), !notes.isEmpty { notesGroup(notes) }
                // Pre-flight: the last meeting like this one and the invite's links (people and notes are above).
                if let brief { PreFlightSections(brief: brief, showPeople: false, showNotes: false) }
                MeetingFollowUps(event: event, notes: event.notes.map(EventNotesFormatter.plainText) ?? "")
                if store.settings.echoMode || !store.echoNotes(for: event).isEmpty {
                    EchoNotesGroup(event: event) { recording = true }
                }
                editKey
                HStack(spacing: 10) {
                    Button("Open in Calendar") { PhoneJoin.openInCalendar(event) }.buttonStyle(.sk1Key())
                    if let url = event.meetURL {
                        Button("Copy link") {
                            UIPasteboard.general.string = url.absoluteString
                            copied += 1
                        }
                        .buttonStyle(.sk1Key())
                        .sensoryFeedback(.success, trigger: copied)
                    }
                }
                if editable != nil { deleteSection }
            }
            .padding(16)
        }
        .sk1Chassis()
        .offset(x: pull)
        .simultaneousGesture(
            DragGesture(minimumDistance: 24)
                .onChanged { g in
                    // Mostly sideways and to the right: the panel follows the finger.
                    guard g.translation.width > 0, abs(g.translation.width) > abs(g.translation.height) * 1.5 else { return }
                    pull = g.translation.width
                }
                .onEnded { g in
                    if pull > 110 || g.predictedEndTranslation.width > 260 && pull > 0 {
                        onClose()
                    } else {
                        withAnimation(.spring(duration: 0.3)) { pull = 0 }
                    }
                }
        )
        .accessibilityAction(.escape) { onClose() }
    }

    /// The meeting repeats, judged by the calendar's own copy too (an edited occurrence can lose its repeat details).
    private var isRepeating: Bool {
        event.seriesID != nil || event.recurrence.isRecurring || store.isRepeating(event)
    }

    /// Delete Event, then, in place of the key, the choice: just this one, this and every one after it (for a repeating
    /// meeting), or keep it. Nothing is deleted until one of them is tapped.
    @ViewBuilder
    private var deleteSection: some View {
        if confirmingDelete {
            let repeating = isRepeating
            let day = event.start.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
            VStack(alignment: .leading, spacing: SK1.Metrics.captionToWell) {
                SKCaption(repeating ? "Delete a repeating event" : "Delete this event", tone: .soft)
                SKWell {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(repeating
                             ? "\u{201C}\(event.title)\u{201D} repeats. Delete only \(day)\u{2019}s, or this one and every one after it?"
                             : "Delete \u{201C}\(event.title)\u{201D} on \(day)?")
                            .font(.callout)
                            .fixedSize(horizontal: false, vertical: true)
                        Button(role: .destructive) { delete(futureToo: false) } label: {
                            Label(repeating ? "Only this one" : "Delete", systemImage: "trash").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.sk1Key(.charcoal, size: .large))
                        if repeating {
                            Button(role: .destructive) { delete(futureToo: true) } label: {
                                Label("This and all future ones", systemImage: "trash.fill").frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.sk1Key(.charcoal, size: .large))
                        }
                        Button { withAnimation(.snappy) { confirmingDelete = false } } label: {
                            Text("Keep it").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.sk1Key(size: .large))
                    }
                    .padding(12)
                }
            }
            .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .bottom)))
        } else {
            Button(role: .destructive) { withAnimation(.snappy) { confirmingDelete = true } } label: {
                Label("Delete Event", systemImage: "trash").frame(maxWidth: .infinity)
            }
            .buttonStyle(.sk1Key(.charcoal, size: .large))
            .accessibilityHint(isRepeating ? "Asks whether to delete this meeting or every one after it" : "Asks before deleting")
            .alert("Couldn\u{2019}t delete the event",
                   isPresented: Binding(get: { deleteError != nil }, set: { if !$0 { deleteError = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(deleteError ?? "")
            }
        }
    }

    private func delete(futureToo: Bool) {
        do {
            try store.deleteEvent(event, futureToo: futureToo)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            onClose()
        } catch {
            confirmingDelete = false
            // Gone already (deleted elsewhere) or its calendar turned read-only: say so rather than fail silently.
            deleteError = store.editableEvent(for: event) == nil
                ? "It may already have been deleted, or its calendar can no longer be changed."
                : error.localizedDescription
        }
    }

    /// Edit: the SK-1 editor (EventEditSheet) for calendars the phone can change, or the event's edit page in Google
    /// Calendar for the read-only work feed.
    @ViewBuilder
    private var editKey: some View {
        if editable != nil {
            Button { editing = true } label: {
                Label("Edit", systemImage: "pencil").frame(maxWidth: .infinity)
            }
            .buttonStyle(.sk1Key(size: .large))
        } else if GoogleEventLink.isFromGoogle(event) {
            let account = workEmail.trimmingCharacters(in: .whitespaces)
            let url = GoogleEventLink.editURL(for: event, account: account)
                ?? GoogleEventLink.searchURL(for: event, account: account)
            if let url {
                VStack(alignment: .leading, spacing: 6) {
                    Button { UIApplication.shared.open(url) } label: {
                        Label("Edit in Google Calendar", systemImage: "arrow.up.forward.app").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.sk1Key(size: .large))
                    Text(account.isEmpty
                         ? "This calendar is read-only here. Set your work email in New meeting so Google opens the right account."
                         : "This calendar is read-only here, so changes are made in Google Calendar.")
                        .sk1Hint()
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle().fill(Color(hex: event.colorHex)).frame(width: 12, height: 12).padding(.top, 9)
            VStack(alignment: .leading, spacing: 4) {
                Text(event.title).font(.title.bold()).fixedSize(horizontal: false, vertical: true)
                    .strikethrough(event.isDeclined)
                if let cal = store.calendars.first(where: { $0.key == event.calendarKey }) {
                    Text(cal.summary).sk1Hint()
                }
            }
            Spacer(minLength: 8)
            Button { onClose() } label: { Image(systemName: "xmark") }
                .buttonStyle(.sk1Key(.round, size: .small))
                .accessibilityLabel("Close")
        }
    }

    @ViewBuilder
    private func countdown(now: Date) -> some View {
        if event.end > now && !event.isAllDay {
            let live = event.start <= now
            let target = live ? event.end : event.start
            let c = SK1CountdownDigits.compact(target.timeIntervalSince(now))
            let urgency = HeroUrgency.of(event, now: now)
            SK1CountdownLCD(caption: live ? "Now · ends in" : "Starts in", digits: c.digits, unit: c.unit, live: live,
                            lamp: urgency.lamp, lampBlinking: urgency.lampBlinks, height: 50,
                            accessibilityText: (live ? "In progress, ends " : "Starts ")
                                + RelativeTimeFormatter.string(for: target, relativeTo: now))
        }
    }

    private var whenGroup: some View {
        SKGroup(caption: "When") {
            SKRow(title: event.start.formatted(.dateTime.weekday(.wide).month(.wide).day()),
                  subtitle: event.isAllDay ? "All day" : "\(event.start.shortTime) – \(event.end.shortTime)") {
                SKChip(DurationFormatter.string(from: event.start, to: event.end), minWidth: 60)
            }
            if let tz = event.foreignTimeZone() {
                SKRow(title: "Set in \(tz.localizedName(for: .generic, locale: .current) ?? tz.identifier)",
                      subtitle: "\(event.start.shortTime(locale: AppPreferences.locale, timeZone: tz)) there") { EmptyView() }
            }
            if event.recurrence.isRecurring {
                SKRow(title: "Repeats", subtitle: recurrenceText) { Image(systemName: "repeat").foregroundStyle(.secondary) }
            }
        }
    }

    /// This meeting's alerts, which can differ from its calendar's: on for one meeting of a silenced calendar, or off
    /// for one meeting of any other.
    private var alertsGroup: some View {
        let silenced = store.settings.isSilenced(event)
        return SKGroup(caption: "Alerts") {
            SKRow(title: "Alert me",
                  subtitle: silenced ? "Alerts are off for this calendar; this turns them on for just this meeting."
                                     : "Turn off to skip the reminders for just this meeting.") {
                Toggle("Alert me", isOn: Binding(get: { store.settings.alerts(for: event) },
                                                 set: { store.settings.setAlerts($0, for: event) }))
                    .labelsHidden().toggleStyle(.sk1Switch)
            }
        }
    }

    private var recurrenceText: String {
        switch event.recurrence {
        case .daily: return "Every day"
        case .weekly: return "Every week"
        default: return "On a schedule"
        }
    }

    private var peopleGroup: some View {
        let people = event.participants.sorted { ($0.isOrganizer ? 0 : 1, $0.displayName) < ($1.isOrganizer ? 0 : 1, $1.displayName) }
        let going = people.filter { $0.response == .accepted }.count
        return SKGroup(caption: "People", note: "\(going) of \(people.count) going") {
            ForEach(Array(people.prefix(30).enumerated()), id: \.offset) { _, p in
                SKRow(title: p.displayName + (p.isSelf ? " (you)" : ""), subtitle: p.isOrganizer ? "Organizer" : p.response.label) {
                    Image(systemName: p.response.symbol)
                        .foregroundStyle(color(p.response))
                        .accessibilityLabel(p.response.label)
                }
            }
        }
    }

    private func color(_ r: AttendeeResponse) -> Color {
        switch r {
        case .accepted: return Color(sk1Hex: SK1.teal)
        case .declined: return Color(sk1Hex: SK1.recRed)
        case .tentative: return Color(sk1Hex: SK1.amber)
        case .needsAction: return .secondary
        }
    }

    private func notesGroup(_ notes: String) -> some View {
        VStack(alignment: .leading, spacing: SK1.Metrics.captionToWell) {
            SKCaption("Notes", tone: .soft)
            SKWell {
                Text(EventNotesFormatter.linked(notes))
                    .font(.callout)
                    .tint(Color(sk1Hex: SK1.teal))
                    .textSelection(.enabled)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
