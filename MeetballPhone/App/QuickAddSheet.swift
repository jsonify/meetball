import EventKit
import EventKitUI
import MessageUI
import SwiftUI
import UIKit
import SK1Tokens
import SK1UI

/// The new-meeting composer. One line of plain English ("1:1 with Sam fri 2pm") fills everything in, read back on an
/// LCD as you type; then the day, start and length can be nudged with keys instead of retyped, the day's meetings show
/// on a strip with any clash in red, and free times that fit are one tap away.
///
/// It saves to a calendar Meetball can write to, or, for a work calendar it can only read (a subscribed feed), emails
/// the meeting as an .ics file to your work address to add from Outlook, optionally keeping a hold on a personal
/// calendar. Invite people hands the meeting to Apple's own editor, since EventKit can't add invitees.
struct QuickAddSheet: View {
    @EnvironmentObject private var store: PhoneStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage("phone.workEmail") private var workEmail = ""
    @State private var text = ""
    @State private var destination = ""
    @State private var holdCalendarID = ""
    /// Set by the keys; cleared when the typed line names a different time or length.
    @State private var startOverride: Date?
    @State private var lengthOverride: Int?
    @State private var handoff: Handoff?
    @State private var error: String?
    @State private var saved = 0
    @State private var nudged = 0

    static let workDestination = "meetball.work-invite"

    private var parsed: QuickAddResult { QuickAddParser.parse(text) }

    var body: some View {
        let r = parsed
        let now = Date()
        let start = startOverride ?? r.start
        let minutes = lengthOverride ?? max(Int(r.end.timeIntervalSince(r.start) / 60), 5)
        let end = start.addingTimeInterval(Double(minutes) * 60)
        let dayEvents = store.events(from: start, days: 1)
        let clashes = MeetingComposer.conflicts(start: start, end: end, in: dayEvents)
        ScrollView {
            VStack(alignment: .leading, spacing: SK1.Metrics.groupSpacing) {
                header
                SKTextField("Event", text: $text, prompt: "1:1 with Sam fri 2pm for 45 min", height: 44)
                    .submitLabel(.done)
                    .onSubmit { primary(r, start: start, end: end) }
                readout(r, start: start, end: end, clashes: clashes)
                DayStrip(events: dayEvents.filter { !$0.isAllDay }, start: start, end: end, clashing: !clashes.isEmpty)
                tune(start: start, minutes: minutes, now: now)
                slots(minutes: minutes, start: start, now: now)
                destinationGroup
                hints(r)
                if let error { Text(error).font(.callout).foregroundStyle(Color(sk1Hex: SK1.recRed)) }
                actions(r, start: start, end: end)
                Text("Try: \u{201C}Dentist fri 3pm\u{201D}, \u{201C}Standup tomorrow 9:15 for 15 min\u{201D}, \u{201C}Offsite dec 3\u{201D}.")
                    .sk1Hint()
            }
            .padding(16)
        }
        .scrollDismissesKeyboard(.interactively)
        .sk1Chassis()
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .sensoryFeedback(.selection, trigger: nudged)
        .onAppear {
            if destination.isEmpty { destination = store.defaultCalendarForNewEvents?.id ?? Self.workDestination }
        }
        .onChange(of: text) { old, new in
            let a = QuickAddParser.parse(old), b = QuickAddParser.parse(new)
            if a.start != b.start || a.hasDate != b.hasDate || a.hasTime != b.hasTime { startOverride = nil }
            if a.end.timeIntervalSince(a.start) != b.end.timeIntervalSince(b.start) { lengthOverride = nil }
        }
        .sheet(item: $handoff) { h in
            switch h.kind {
            case .mail(let to, let subject, let body, let ics):
                MailComposer(to: to, subject: subject, body: body, ics: ics) { sent in
                    handoff = nil
                    if sent { finish() }
                }
                .ignoresSafeArea()
            case .share(let url):
                ShareSheet(items: [url]) { done in
                    handoff = nil
                    if done { finish() }
                }
            case .editor(let event, let eventStore):
                EventEditor(event: event, eventStore: eventStore) { saved in
                    handoff = nil
                    if saved { Task { await store.refresh() }; finish() }
                }
                .ignoresSafeArea()
            }
        }
    }

    private var header: some View {
        HStack {
            Text("New meeting").font(.title.bold())
            Spacer()
            Button { dismiss() } label: { Image(systemName: "xmark") }
                .buttonStyle(.sk1Key(.round, size: .small))
                .accessibilityLabel("Close")
        }
    }

    // MARK: Readout

    private func readout(_ r: QuickAddResult, start: Date, end: Date, clashes: [CalendarEvent]) -> some View {
        let day = start.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        let title = cleanTitle(r)
        let status = MeetingComposer.conflictSummary(clashes) ?? (text.isEmpty ? "Waiting" : "Free")
        return SKDisplay(title: status,
                         detail: "\(day) · \(start.shortTime)–\(end.shortTime)",
                         message: title.isEmpty ? "Type a title, a day and a time" : title,
                         height: 56)
            .accessibilityElement(children: .combine)
    }

    // MARK: Day, start, length

    private func tune(start: Date, minutes: Int, now: Date) -> some View {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        let dayStart = cal.startOfDay(for: start)
        let offset = cal.dateComponents([.day], from: today, to: dayStart).day ?? 0
        let minuteOfDay = Int(start.timeIntervalSince(dayStart) / 60)
        var dayOffsets = Array(0..<21)
        if !dayOffsets.contains(offset) { dayOffsets.append(offset); dayOffsets.sort() }
        var times = Array(stride(from: 0, to: 24 * 60, by: 15))
        if !times.contains(minuteOfDay) { times.append(minuteOfDay); times.sort() }
        var lengths = MeetingComposer.lengthChoices
        if !lengths.contains(minutes) { lengths.append(minutes); lengths.sort() }

        let dayBinding = Binding<Int>(get: { offset }, set: { new in
            guard let moved = cal.date(byAdding: .day, value: new - offset, to: start) else { return }
            startOverride = moved
            nudged += 1
        })
        let timeBinding = Binding<Int>(get: { minuteOfDay }, set: { new in
            startOverride = dayStart.addingTimeInterval(Double(new) * 60)
            nudged += 1
        })
        let lengthBinding = Binding<Int>(get: { minutes }, set: { new in
            lengthOverride = new
            nudged += 1
        })
        return SKGroup(caption: "When") {
            SKRow(title: "Day") {
                SKPicker(selection: dayBinding,
                         options: dayOffsets.map { SKPicker<Int>.Option($0, dayLabel($0, today: today)) })
            }
            SKRow(title: "Starts") {
                SKPicker(selection: timeBinding,
                         options: times.map { SKPicker<Int>.Option($0, dayStart.addingTimeInterval(Double($0) * 60).shortTime) })
            }
            SKRow(title: "Length") {
                SKSegmented(selection: lengthBinding, options: lengths.map { SKSegmented<Int>.Option($0, lengthLabel($0)) })
            }
        }
    }

    private func dayLabel(_ offset: Int, today: Date) -> String {
        switch offset {
        case 0: return "Today"
        case 1: return "Tomorrow"
        default:
            let d = Calendar.current.date(byAdding: .day, value: offset, to: today) ?? today
            return d.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        }
    }

    private func lengthLabel(_ m: Int) -> String {
        if m < 60 { return "\(m)m" }
        return m % 60 == 0 ? "\(m / 60)h" : "\(m / 60)h\(m % 60)"
    }

    // MARK: Free times

    @ViewBuilder
    private func slots(minutes: Int, start: Date, now: Date) -> some View {
        let upcoming = store.events(from: now, days: 7)
        let free = MeetingComposer.freeSlots(length: Double(minutes) * 60, events: upcoming, now: now)
        if !free.isEmpty {
            VStack(alignment: .leading, spacing: SK1.Metrics.captionToWell) {
                SKCaption("Free for \(lengthLabel(minutes))", tone: .soft)
                SKKeyTray {
                    ForEach(free, id: \.self) { slot in
                        Button {
                            startOverride = slot
                            nudged += 1
                        } label: {
                            Text(MeetingComposer.slotLabel(slot, now: now)).lineLimit(1).minimumScaleFactor(0.7)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.sk1Key(isOn: slot == start, size: .small))
                    }
                }
            }
        }
    }

    // MARK: Where it goes

    private var isWork: Bool { destination == Self.workDestination }

    private var destinationGroup: some View {
        let options = store.writableCalendars.map { SKPicker<String>.Option($0.id, $0.summary) }
            + [SKPicker<String>.Option(Self.workDestination, "Work · email to Outlook")]
        return SKGroup(caption: "Add to",
                       note: isWork ? "Meetball emails the meeting to your work address. Open the attachment in Outlook to add it to your work calendar." : nil) {
            SKRow(title: "Calendar") {
                SKPicker(selection: $destination, options: options, stepper: false)
            }
            if isWork {
                SKRow(title: "Work email") {
                    SKTextField("Work email", text: $workEmail, prompt: "you@company.com")
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .frame(maxWidth: 220)
                }
                if !store.writableCalendars.isEmpty {
                    SKRow(title: "Also hold on", subtitle: "Shows it on your phone right away") {
                        SKPicker(selection: $holdCalendarID,
                                 options: [SKPicker<String>.Option("", "None")]
                                    + store.writableCalendars.map { SKPicker<String>.Option($0.id, $0.summary) },
                                 stepper: false)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func hints(_ r: QuickAddResult) -> some View {
        if !r.attendees.isEmpty && !isWork {
            Text("Emails in the line aren't invited automatically. Use Invite people to send the invites.").sk1Hint()
        } else if r.addMeet {
            Text("Add the video link in Invite people, or from the meeting app.").sk1Hint()
        }
    }

    // MARK: Actions

    private func actions(_ r: QuickAddResult, start: Date, end: Date) -> some View {
        let title = cleanTitle(r)
        let workReady = EmailValidator.isValid(workEmail.trimmingCharacters(in: .whitespaces))
        return VStack(spacing: 10) {
            Button { primary(r, start: start, end: end) } label: {
                Label(isWork ? "Email to work" : "Add to calendar",
                      systemImage: isWork ? "envelope.badge" : "calendar.badge.plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.sk1Key(.orange, size: .large))
            .disabled(title.isEmpty || destination.isEmpty || (isWork && !workReady))
            .sensoryFeedback(.success, trigger: saved)
            if !isWork {
                Button { invitePeople(title: title, start: start, end: end) } label: {
                    Label("Invite people…", systemImage: "person.badge.plus").frame(maxWidth: .infinity)
                }
                .buttonStyle(.sk1Key())
                .disabled(title.isEmpty)
            }
        }
    }

    private func cleanTitle(_ r: QuickAddResult) -> String {
        r.title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func primary(_ r: QuickAddResult, start: Date, end: Date) {
        let title = cleanTitle(r)
        guard !title.isEmpty else { return }
        error = nil
        if isWork { return sendToWork(title: title, start: start, end: end) }
        guard let cal = store.writableCalendars.first(where: { $0.id == destination }) else { return }
        Task {
            do {
                try await store.addEvent(title: title, start: start, end: end, calendar: cal)
                finish()
            } catch {
                self.error = "Couldn't save it: \(error.localizedDescription)"
            }
        }
    }

    private func sendToWork(title: String, start: Date, end: Date) {
        let to = workEmail.trimmingCharacters(in: .whitespaces)
        guard EmailValidator.isValid(to) else { return }
        Task {
            if let hold = store.writableCalendars.first(where: { $0.id == holdCalendarID }) {
                do { try await store.addEvent(title: title, start: start, end: end, calendar: hold) } catch {
                    self.error = "Couldn't save the hold: \(error.localizedDescription)"
                    return
                }
            }
            let ics = MeetingComposer.icsInvite(title: title, start: start, end: end)
            let when = "\(start.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())), \(start.shortTime)–\(end.shortTime)"
            let body = "\(title)\n\(when)\n\nOpen the attached invite to add it to your calendar.\n\nSent from Meetball."
            if MFMailComposeViewController.canSendMail() {
                handoff = Handoff(kind: .mail(to: to, subject: title, body: body, ics: Data(ics.utf8)))
            } else {
                let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(Self.fileName(title)).ics")
                do {
                    try Data(ics.utf8).write(to: url, options: .atomic)
                    handoff = Handoff(kind: .share(url))
                } catch {
                    self.error = "Couldn't make the invite: \(error.localizedDescription)"
                }
            }
        }
    }

    private func invitePeople(title: String, start: Date, end: Date) {
        let cal = store.writableCalendars.first { $0.id == destination }
        guard let draft = store.draftEvent(title: title, start: start, end: end, calendar: cal) else {
            error = "Meetball needs calendar access to do that."
            return
        }
        handoff = Handoff(kind: .editor(draft.event, draft.store))
    }

    private func finish() {
        saved += 1
        dismiss()
    }

    /// A title safe to use as a file name.
    static func fileName(_ title: String) -> String {
        let cleaned = title.components(separatedBy: CharacterSet(charactersIn: "/\\:?%*|\"<>")).joined()
            .trimmingCharacters(in: .whitespaces)
        return cleaned.isEmpty ? "Meeting" : String(cleaned.prefix(60))
    }
}

/// What the composer hands the meeting to.
private struct Handoff: Identifiable {
    enum Kind {
        case mail(to: String, subject: String, body: String, ics: Data)
        case share(URL)
        case editor(EKEvent, EKEventStore)
    }
    let id = UUID()
    let kind: Kind
}

/// The proposed meeting over the day's others on an LCD strip, from 8 to 7 (wider if either runs outside that),
/// with hour ticks every three hours. A clash turns the new block red.
struct DayStrip: View {
    let events: [CalendarEvent]
    let start: Date
    let end: Date
    let clashing: Bool

    var body: some View {
        let cal = Calendar.current
        let day = cal.startOfDay(for: start)
        let hour: (Date) -> Double = { $0.timeIntervalSince(day) / 3600 }
        let lo = floor(min(8, hour(start), events.map { hour($0.start) }.min() ?? 8)).clamped(0, 23)
        let hi = ceil(max(19, hour(end), events.map { hour($0.end) }.max() ?? 19)).clamped(lo + 1, 24)
        let span = hi - lo
        SKLCD {
            GeometryReader { geo in
                let w = geo.size.width
                let x: (Double) -> CGFloat = { CGFloat(($0 - lo) / span) * w }
                ZStack(alignment: .topLeading) {
                    ForEach(Array(stride(from: Int(lo), through: Int(hi), by: 3)), id: \.self) { h in
                        Rectangle().fill(Color(sk1Hex: SK1.lcdInk).opacity(0.25))
                            .frame(width: 1, height: 26).offset(x: x(Double(h)))
                        Text(Self.hourLabel(h, day: day))
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color(sk1Hex: SK1.lcdInk).opacity(0.7))
                            .fixedSize()
                            .offset(x: x(Double(h)) + 2, y: 26)
                    }
                    ForEach(events, id: \.uid) { e in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color(sk1Hex: SK1.lcdInk).opacity(e.isDeclined ? 0.15 : 0.4))
                            .frame(width: max(x(hour(e.end)) - x(hour(e.start)), 2), height: 10)
                            .offset(x: x(hour(e.start)), y: 3)
                    }
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color(sk1Hex: clashing ? SK1.recRed : SK1.orange))
                        .frame(width: max(x(hour(end)) - x(hour(start)), 3), height: 10)
                        .offset(x: x(hour(start)), y: 14)
                }
            }
            .frame(height: 38)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
        }
        .accessibilityElement()
        .accessibilityLabel(clashing ? "Clashes with another meeting" : "\(events.count) other meetings that day, no clash")
    }

    private static func hourLabel(_ h: Int, day: Date) -> String {
        let d = day.addingTimeInterval(Double(h) * 3600)
        return d.formatted(.dateTime.hour())
    }
}

private extension Double {
    func clamped(_ lo: Double, _ hi: Double) -> Double { Swift.min(Swift.max(self, lo), hi) }
}

/// Mail with the meeting's .ics attached. `onFinish(true)` when it was sent (or saved to send later).
struct MailComposer: UIViewControllerRepresentable {
    let to: String
    let subject: String
    let body: String
    let ics: Data
    var onFinish: (Bool) -> Void

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let vc = MFMailComposeViewController()
        vc.mailComposeDelegate = context.coordinator
        vc.setToRecipients([to])
        vc.setSubject(subject)
        vc.setMessageBody(body, isHTML: false)
        vc.addAttachmentData(ics, mimeType: "text/calendar", fileName: "\(QuickAddSheet.fileName(subject)).ics")
        return vc
    }

    func updateUIViewController(_ vc: MFMailComposeViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let onFinish: (Bool) -> Void
        init(onFinish: @escaping (Bool) -> Void) { self.onFinish = onFinish }
        func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult,
                                   error: Error?) {
            onFinish(result == .sent || result == .saved)
        }
    }
}

/// The share sheet, for when Mail isn't set up: the .ics can go to Outlook, Gmail or Files instead.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    var onFinish: (Bool) -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let vc = UIActivityViewController(activityItems: items, applicationActivities: nil)
        vc.completionWithItemsHandler = { _, completed, _, _ in onFinish(completed) }
        return vc
    }

    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

/// Apple's event editor, filled in with the composer's meeting: it can add invitees and a location on calendars that
/// support them (iCloud, Exchange, CalDAV). `onFinish(true)` when it saved.
struct EventEditor: UIViewControllerRepresentable {
    let event: EKEvent
    let eventStore: EKEventStore
    var onFinish: (Bool) -> Void

    func makeUIViewController(context: Context) -> EKEventEditViewController {
        let vc = EKEventEditViewController()
        vc.eventStore = eventStore
        vc.event = event
        vc.editViewDelegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ vc: EKEventEditViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    final class Coordinator: NSObject, EKEventEditViewDelegate {
        let onFinish: (Bool) -> Void
        init(onFinish: @escaping (Bool) -> Void) { self.onFinish = onFinish }
        func eventEditViewController(_ controller: EKEventEditViewController, didCompleteWith action: EKEventEditViewAction) {
            onFinish(action == .saved)
        }
    }
}
