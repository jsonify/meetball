import EventKit
import SwiftUI
import UIKit
import SK1Tokens
import SK1UI

/// A meeting's details: when, where, the Join key, who's coming and the notes.
struct EventDetailSheet: View {
    let event: CalendarEvent
    @EnvironmentObject private var store: PhoneStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage("phone.workEmail") private var workEmail = ""
    @State private var copied = 0
    /// The stored event when its calendar can be changed here; nil for a read-only feed such as the work calendar.
    @State private var editable: (event: EKEvent, store: EKEventStore)?
    @State private var editing = false
    /// Set when Apple's editor saved or deleted: this screen closes once the editor has gone, not alongside it.
    @State private var closeAfterEdit = false
    @State private var confirmingDelete = false
    @State private var deleteError: String?
    @State private var brief: PreFlightBrief?
    @State private var recording = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SK1.Metrics.groupSpacing) {
                header
                TimelineView(.periodic(from: .now, by: 15)) { tl in countdown(now: tl.date) }
                if event.meetURL != nil {
                    PhoneJoinButton(event: event, variant: .orange, size: .large, fillsWidth: true)
                }
                whenGroup
                if !event.isAllDay && event.end > Date() { alertsGroup }
                if let loc = event.location, !loc.isEmpty { whereGroup(loc) }
                if !event.participants.isEmpty { peopleGroup }
                if let notes = event.notes.map(EventNotesFormatter.plainText), !notes.isEmpty { notesGroup(notes) }
                // Pre-flight: the last meeting like this one and the invite's links (people and notes are above).
                if let brief { PreFlightSections(brief: brief, showPeople: false, showNotes: false) }
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
                if editable != nil { deleteKey }
            }
            .padding(16)
        }
        .sk1Chassis()
        .presentationDragIndicator(.visible)
        .onAppear {
            editable = store.editableEvent(for: event)
            if !event.isAllDay { brief = store.preFlight(for: event) }
        }
        .sheet(isPresented: $recording) {
            EchoSheet(event: event).environmentObject(store)
        }
        // Closing both sheets in one go leaves the editor up but marked closed, so its ✕ and ✓ stop working: the editor
        // goes first, then this screen (it shows the old details; the calendars reload from the change).
        .sheet(isPresented: $editing, onDismiss: { if closeAfterEdit { dismiss() } }) {
            if let editable {
                EventEditor(event: editable.event, eventStore: editable.store) { action in
                    if action == .deleted { store.noteDeleted(event) }
                    closeAfterEdit = action != .canceled
                    editing = false
                }
                .ignoresSafeArea()
            }
        }
    }

    /// Delete, straight from the event screen as in Apple's Calendar: one confirmation (this one or the rest of the
    /// series for a repeating meeting), then the screen closes.
    private var deleteKey: some View {
        let repeating = event.seriesID != nil || event.recurrence.isRecurring
        return Button(role: .destructive) { confirmingDelete = true } label: {
            Label("Delete Event", systemImage: "trash").frame(maxWidth: .infinity)
        }
        .buttonStyle(.sk1Key(.charcoal, size: .large))
        .accessibilityHint(repeating ? "Asks whether to delete this meeting or every one after it" : "Asks before deleting")
        .confirmationDialog(repeating ? "This is a repeating event." : "Delete this event?",
                            isPresented: $confirmingDelete, titleVisibility: .visible) {
            if repeating {
                Button("Delete This Event Only", role: .destructive) { delete(futureToo: false) }
                Button("Delete All Future Events", role: .destructive) { delete(futureToo: true) }
            } else {
                Button("Delete Event", role: .destructive) { delete(futureToo: false) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(event.title)
        }
        .alert("Couldn\u{2019}t delete the event",
               isPresented: Binding(get: { deleteError != nil }, set: { if !$0 { deleteError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(deleteError ?? "")
        }
    }

    private func delete(futureToo: Bool) {
        do {
            try store.deleteEvent(event, futureToo: futureToo)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            dismiss()
        } catch {
            // Gone already (deleted elsewhere) or its calendar turned read-only: say so rather than fail silently.
            deleteError = store.editableEvent(for: event) == nil
                ? "It may already have been deleted, or its calendar can no longer be changed."
                : error.localizedDescription
        }
    }

    /// Edit: Apple's editor for calendars the phone can change, or the event's edit page in Google Calendar for the
    /// read-only work feed.
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
            Button { dismiss() } label: { Image(systemName: "xmark") }
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

    private func whereGroup(_ loc: String) -> some View {
        SKGroup(caption: "Where") {
            SKRow(title: loc) {
                if let url = mapsURL(loc), !loc.lowercased().hasPrefix("http") {
                    Button { UIApplication.shared.open(url) } label: { Image(systemName: "map") }
                        .buttonStyle(.sk1Key(size: .small))
                        .accessibilityLabel("Open in Maps")
                }
            }
        }
    }

    private func mapsURL(_ loc: String) -> URL? {
        var c = URLComponents(string: "maps://")
        c?.queryItems = [URLQueryItem(name: "q", value: loc)]
        return c?.url
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
