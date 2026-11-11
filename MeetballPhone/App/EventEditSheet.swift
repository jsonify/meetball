import EventKit
import EventKitUI
import SwiftUI
import UIKit
import SK1Tokens
import SK1UI

/// Edits a stored event in the SK-1 look, laid out as the new-meeting composer is: the change read back on an LCD
/// (any clash in red), the day's meetings on a strip, then the day, start and end on keys, the place and calendar, and
/// the notes. Save writes it with EventKit (asking "this one or every one after it" for a repeating meeting).
///
/// A meeting you were invited to shows Going? (Yes / Maybe / No) at the top. On your own events, what EventKit can't do
/// here (invitees) or that needs Apple's full controls (alerts, repeat rules) is one key away: it names what it adds and
/// hands the event, with the changes made so far, to Apple's own editor. Invitations don't get that key: Apple's editor
/// has nothing more for them, and no reply buttons either.
struct EventEditSheet: View {
    let event: CalendarEvent
    let ekEvent: EKEvent
    let eventStore: EKEventStore
    /// What the person did: saved, deleted (only from Apple's editor) or cancelled.
    var onFinish: (EKEventEditViewAction) -> Void

    @EnvironmentObject private var store: PhoneStore
    @State private var draft: Draft
    private let original: Draft
    @State private var confirmingSpan = false
    @State private var showingMore = false
    /// Set when Apple's editor saved or deleted: this sheet finishes once the editor has gone, not alongside it.
    @State private var finishAfterMore: EKEventEditViewAction?
    @State private var error: String?
    @State private var nudged = 0

    /// The fields this sheet edits.
    struct Draft: Equatable {
        var title: String
        var location: String
        var notes: String
        var isAllDay: Bool
        var start: Date
        /// Timed events: the length in minutes. All-day events: unused.
        var minutes: Int
        /// All-day events: how many days it covers.
        var days: Int
        var calendarID: String
    }

    init(event: CalendarEvent, ekEvent: EKEvent, eventStore: EKEventStore,
         onFinish: @escaping (EKEventEditViewAction) -> Void) {
        self.event = event
        self.ekEvent = ekEvent
        self.eventStore = eventStore
        self.onFinish = onFinish
        let cal = Calendar.current
        let start = ekEvent.startDate ?? event.start
        let end = ekEvent.endDate ?? event.end
        let firstDay = cal.startOfDay(for: start)
        let lastDay = cal.startOfDay(for: end.addingTimeInterval(ekEvent.isAllDay ? -1 : 0))
        let d = Draft(title: ekEvent.title ?? event.title,
                      location: ekEvent.location ?? "",
                      notes: ekEvent.notes ?? "",
                      isAllDay: ekEvent.isAllDay,
                      start: ekEvent.isAllDay ? firstDay : start,
                      minutes: ekEvent.isAllDay ? 60 : max(Int(end.timeIntervalSince(start) / 60), 5),
                      days: max((cal.dateComponents([.day], from: firstDay, to: lastDay).day ?? 0) + 1, 1),
                      calendarID: ekEvent.calendar?.calendarIdentifier ?? event.calendarID)
        original = d
        _draft = State(initialValue: d)
    }

    private var isRepeating: Bool { ekEvent.hasRecurrenceRules || event.recurrence.isRecurring }
    private var hasChanges: Bool { draft != original }
    private var cleanTitle: String { draft.title.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var end: Date {
        if draft.isAllDay {
            return Calendar.current.date(byAdding: .day, value: draft.days, to: draft.start) ?? draft.start.addingTimeInterval(86400)
        }
        return draft.start.addingTimeInterval(Double(draft.minutes) * 60)
    }

    var body: some View {
        let dayEvents = store.events(from: draft.start, days: 1).filter { $0.uid != event.uid }
        let clashes = draft.isAllDay ? [] : MeetingComposer.conflicts(start: draft.start, end: end, in: dayEvents)
        ScrollView {
            VStack(alignment: .leading, spacing: SK1.Metrics.groupSpacing) {
                header
                SKTextField("Title", text: $draft.title, prompt: "Title", height: 44)
                    .submitLabel(.done)
                    .textInputAutocapitalization(.sentences)
                readout(clashes: clashes)
                if event.canRespond { ReplyGroup(event: event).environmentObject(store) }
                if !draft.isAllDay {
                    DayStrip(events: dayEvents.filter { !$0.isAllDay }, start: draft.start, end: end,
                             clashing: !clashes.isEmpty)
                }
                whenGroup
                detailsGroup
                notesGroup
                if let error { Text(error).font(.callout).foregroundStyle(Color(sk1Hex: SK1.recRed)) }
                actions
                if isRepeating {
                    Text("This is a repeating event. Save asks whether to change this one or every one after it.").sk1Hint()
                }
            }
            .padding(16)
        }
        .scrollDismissesKeyboard(.interactively)
        .sk1Chassis()
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(hasChanges)
        .sensoryFeedback(.selection, trigger: nudged)
        .confirmationDialog("This is a repeating event.", isPresented: $confirmingSpan, titleVisibility: .visible) {
            Button("Save for This Event Only") { save(span: .thisEvent) }
            Button("Save for Future Events") { save(span: .futureEvents) }
            Button("Cancel", role: .cancel) {}
        }
        // Apple's editor goes first, then this sheet, as on the event screen: closing both at once leaves the editor
        // up but marked closed.
        .sheet(isPresented: $showingMore, onDismiss: {
            if let action = finishAfterMore { onFinish(action) }
        }) {
            EventEditor(event: ekEvent, eventStore: eventStore) { action in
                finishAfterMore = action == .canceled ? nil : action
                if action == .canceled { ekEvent.rollback() }
                showingMore = false
            }
            .ignoresSafeArea()
        }
    }

    private var header: some View {
        HStack {
            Text("Edit event").font(.title.bold())
            Spacer()
            Button { cancel() } label: { Image(systemName: "xmark") }
                .buttonStyle(.sk1Key(.round, size: .small))
                .accessibilityLabel("Cancel")
        }
    }

    // MARK: Readout

    private func readout(clashes: [CalendarEvent]) -> some View {
        let day = draft.start.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        let detail: String
        if draft.isAllDay {
            detail = draft.days == 1 ? "\(day) · All day" : "\(day) · \(draft.days) days"
        } else {
            detail = "\(day) · \(draft.start.shortTime)–\(end.shortTime)"
        }
        let status = MeetingComposer.conflictSummary(clashes) ?? (hasChanges ? "Edited" : "Unchanged")
        return SKDisplay(title: status, detail: detail,
                         message: cleanTitle.isEmpty ? "Type a title" : cleanTitle, height: 56)
            .accessibilityElement(children: .combine)
    }

    // MARK: When

    private var whenGroup: some View {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let dayStart = cal.startOfDay(for: draft.start)
        let offset = cal.dateComponents([.day], from: today, to: dayStart).day ?? 0
        // Three weeks either side of today, and a week either side of the event's own day.
        var dayOffsets = Array(min(-21, offset - 7)...max(21, offset + 7))
        if !dayOffsets.contains(offset) { dayOffsets.append(offset); dayOffsets.sort() }
        let minuteOfDay = Int(draft.start.timeIntervalSince(dayStart) / 60)
        var times = Array(stride(from: 0, to: 24 * 60, by: 15))
        if !times.contains(minuteOfDay) { times.append(minuteOfDay); times.sort() }
        var lengths = MeetingComposer.lengthChoices
        if !lengths.contains(draft.minutes) { lengths.append(draft.minutes); lengths.sort() }

        let allDayBinding = Binding<Bool>(get: { draft.isAllDay }, set: { on in
            if on {
                draft.start = dayStart
                draft.days = max(draft.days, 1)
            } else {
                // Back to a timed event: its old time if it had one, else 9:00 for an hour.
                let wasTimed = !original.isAllDay
                let minute = wasTimed ? Int(original.start.timeIntervalSince(cal.startOfDay(for: original.start)) / 60) : 9 * 60
                draft.start = dayStart.addingTimeInterval(Double(minute) * 60)
                draft.minutes = wasTimed ? original.minutes : 60
            }
            draft.isAllDay = on
            nudged += 1
        })
        let dayBinding = Binding<Int>(get: { offset }, set: { new in
            guard let moved = cal.date(byAdding: .day, value: new - offset, to: draft.start) else { return }
            draft.start = moved
            nudged += 1
        })
        let timeBinding = Binding<Int>(get: { minuteOfDay }, set: { new in
            draft.start = dayStart.addingTimeInterval(Double(new) * 60)
            nudged += 1
        })
        let lengthBinding = Binding<Int>(get: { draft.minutes }, set: { new in
            draft.minutes = new
            nudged += 1
        })
        let daysBinding = Binding<Int>(get: { draft.days }, set: { new in
            draft.days = new
            nudged += 1
        })
        let endLabel = { (m: Int) -> String in
            let end = draft.start.addingTimeInterval(Double(m) * 60)
            return cal.isDate(end.addingTimeInterval(-1), inSameDayAs: draft.start) ? end.shortTime : "\(end.shortTime) +1"
        }
        return SKGroup(caption: "When") {
            SKRow(title: "All day") {
                Toggle("All day", isOn: allDayBinding).labelsHidden().toggleStyle(.sk1Switch)
            }
            SKRow(title: draft.isAllDay ? "Starts" : "Day") {
                ScrollingPicker(selection: dayBinding,
                                options: dayOffsets.map { ($0, Self.dayLabel($0, today: today)) }, name: "Day")
            }
            if draft.isAllDay {
                SKRow(title: "Days") {
                    ScrollingPicker(selection: daysBinding,
                                    options: Array(1...max(14, draft.days)).map { ($0, $0 == 1 ? "1 day" : "\($0) days") },
                                    name: "Days")
                }
            } else {
                SKRow(title: "Starts") {
                    ScrollingPicker(selection: timeBinding,
                                    options: times.map { ($0, dayStart.addingTimeInterval(Double($0) * 60).shortTime) },
                                    name: "Starts")
                }
                SKRow(title: "Ends", subtitle: Self.lengthLabel(draft.minutes)) {
                    ScrollingPicker(selection: lengthBinding,
                                    options: MeetingComposer.endChoices(current: draft.minutes).map { ($0, endLabel($0)) },
                                    name: "Ends")
                }
                SKRow(title: "Length") {
                    SKSegmented(selection: lengthBinding,
                                options: lengths.map { SKSegmented<Int>.Option($0, Self.lengthLabel($0)) })
                }
            }
        }
    }

    static func dayLabel(_ offset: Int, today: Date) -> String {
        switch offset {
        case 0: return "Today"
        case 1: return "Tomorrow"
        case -1: return "Yesterday"
        default:
            let d = Calendar.current.date(byAdding: .day, value: offset, to: today) ?? today
            return d.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        }
    }

    static func lengthLabel(_ m: Int) -> String {
        if m < 60 { return "\(m)m" }
        return m % 60 == 0 ? "\(m / 60)h" : "\(m / 60)h\(m % 60)"
    }

    // MARK: Where and which calendar

    private var detailsGroup: some View {
        var options = store.writableCalendars.map { SKPicker<String>.Option($0.id, $0.summary) }
        if !store.writableCalendars.contains(where: { $0.id == original.calendarID }) {
            options.insert(SKPicker<String>.Option(original.calendarID, ekEvent.calendar?.title ?? "Calendar"), at: 0)
        }
        return SKGroup(caption: "Details") {
            SKRow(title: "Location") {
                SKTextField("Location", text: $draft.location, prompt: "Place, room or link")
                    .textInputAutocapitalization(.words)
                    .frame(maxWidth: 220)
            }
            SKRow(title: "Calendar") {
                SKPicker(selection: $draft.calendarID, options: options, stepper: false)
            }
        }
    }

    private var notesGroup: some View {
        VStack(alignment: .leading, spacing: SK1.Metrics.captionToWell) {
            SKCaption("Notes", tone: .soft)
            SKWell {
                TextEditor(text: $draft.notes)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 90)
                    .padding(8)
                    .overlay(alignment: .topLeading) {
                        if draft.notes.isEmpty {
                            Text("Add notes").foregroundStyle(.secondary).padding(14).allowsHitTesting(false)
                        }
                    }
            }
        }
    }

    // MARK: Actions

    private var actions: some View {
        VStack(spacing: 10) {
            Button { requestSave() } label: {
                Label("Save", systemImage: "checkmark").frame(maxWidth: .infinity)
            }
            .buttonStyle(.sk1Key(.orange, size: .large))
            .disabled(cleanTitle.isEmpty || !hasChanges)
            if !event.canRespond {
                Button { moreOptions() } label: {
                    Label("Invitees, alerts & repeat\u{2026}", systemImage: "person.badge.plus").frame(maxWidth: .infinity)
                }
                .buttonStyle(.sk1Key())
                .accessibilityHint("Opens Apple's editor, with your changes so far")
                Text("Invitees, alerts and repeat rules are set in Apple\u{2019}s editor: iOS doesn\u{2019}t let apps add guests themselves.")
                    .sk1Hint()
            }
        }
    }

    private func requestSave() {
        guard !cleanTitle.isEmpty, hasChanges else { return }
        if isRepeating { confirmingSpan = true } else { save(span: .thisEvent) }
    }

    /// Copies the fields onto the stored event (not yet saved).
    private func apply() {
        ekEvent.title = cleanTitle
        let place = draft.location.trimmingCharacters(in: .whitespacesAndNewlines)
        if place != original.location.trimmingCharacters(in: .whitespacesAndNewlines) {
            ekEvent.structuredLocation = nil
            ekEvent.location = place.isEmpty ? nil : place
        }
        ekEvent.notes = draft.notes.isEmpty ? nil : draft.notes
        ekEvent.isAllDay = draft.isAllDay
        ekEvent.startDate = draft.start
        // EventKit's all-day events end at the last moment of their last day.
        ekEvent.endDate = draft.isAllDay ? end.addingTimeInterval(-1) : end
        if draft.calendarID != original.calendarID, let cal = eventStore.calendar(withIdentifier: draft.calendarID) {
            ekEvent.calendar = cal
        }
    }

    private func save(span: EKSpan) {
        error = nil
        apply()
        do {
            try eventStore.save(ekEvent, span: span, commit: true)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            Task { await store.refresh() }
            onFinish(.saved)
        } catch {
            ekEvent.rollback()
            self.error = "Couldn\u{2019}t save it: \(error.localizedDescription)"
        }
    }

    private func moreOptions() {
        error = nil
        if hasChanges { apply() }
        showingMore = true
    }

    private func cancel() {
        if ekEvent.hasChanges { ekEvent.rollback() }
        onFinish(.canceled)
    }
}
