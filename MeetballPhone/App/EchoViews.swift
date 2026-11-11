import SwiftUI
import SK1Tokens
import SK1UI

/// Echo: a voice note after a meeting, as long as you like, transcribed on the iPhone, saved in Meetball against that
/// meeting and (by Settings, or with its key) put on the to-do list as a follow-up. Recording again adds to the note
/// rather than starting over. It starts recording as soon as it opens, so it's one tap from the banner or
/// the nudge; the words can be fixed up before saving.
struct EchoSheet: View {
    let event: CalendarEvent
    @EnvironmentObject private var store: PhoneStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var recorder = EchoRecorder()
    @State private var text = ""
    @State private var saving = false
    @State private var saved = false
    @State private var problem: String?
    @State private var thunk = 0
    /// The note as it stood when this recording started; what's heard is added after it.
    @State private var before = ""
    /// The saved note, and whether it's on the to-do list.
    @State private var savedNote: EchoNote?

    var body: some View {
        VStack(alignment: .leading, spacing: SK1.Metrics.groupSpacing) {
            header
            TimelineView(.periodic(from: .now, by: 0.25)) { tl in lcd(now: tl.date) }
            if saved { savedCard } else { editor }
            if case .failed(let message) = recorder.state { Text(message).sk1Hint() }
            Spacer(minLength: 0)
            keys
        }
        .padding(16)
        .sk1Chassis()
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(saving)
        .sensoryFeedback(.impact(weight: .heavy), trigger: thunk)
        .task { await record() }
        .onDisappear { recorder.cancel() }
        .onChange(of: recorder.transcript) { _, new in
            if recorder.isRecording || recorder.state == .finishing { text = Echo.joined(before, new) }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Echo").font(.title.bold())
                Text("\(event.title) · ended \(event.end.shortTime)").sk1Hint().lineLimit(2)
            }
            Spacer(minLength: 8)
            Button { dismiss() } label: { Image(systemName: "xmark") }
                .buttonStyle(.sk1Key(.round, size: .small))
                .accessibilityLabel("Close")
        }
    }

    @ViewBuilder
    private func lcd(now: Date) -> some View {
        switch recorder.state {
        case .recording(let started):
            let elapsed = Int(max(0, now.timeIntervalSince(started)))
            SK1CountdownLCD(caption: "Recording · \(meter)", digits: String(format: "%d:%02d", elapsed / 60, elapsed % 60),
                            unit: "TAP STOP", live: true, lamp: .danger, lampBlinking: true, height: 50,
                            accessibilityText: "Recording, \(elapsed) seconds so far")
        case .finishing:
            SK1CountdownLCD(caption: "Echo", text: "Transcribing…", lamp: .warning, lampBlinking: true, height: 50,
                            accessibilityText: "Transcribing")
        default:
            SK1CountdownLCD(caption: "Echo", text: saved ? "Pinned to meeting" : "Ready", lamp: saved ? .success : .teal,
                            lampBlinking: false, height: 50, accessibilityText: saved ? "Saved" : "Ready to record")
        }
    }

    /// A little bar of the mic level, so you can see it hears you.
    private var meter: String {
        String(repeating: "▮", count: Int((recorder.level * 6).rounded())).padding(toLength: 6, withPad: "▯", startingAt: 0)
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: SK1.Metrics.captionToWell) {
            SKCaption(recorder.isRecording ? "Say what needs following up" : "Your note", tone: .soft)
            SKWell {
                TextEditor(text: $text)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .disabled(recorder.isRecording || recorder.state == .finishing)
                    .frame(minHeight: 90)
                    .padding(8)
                    .overlay(alignment: .topLeading) {
                        if text.isEmpty {
                            Text(recorder.isRecording ? "Listening…" : "Tap the mic, or type a note.")
                                .foregroundStyle(.secondary).padding(14).allowsHitTesting(false)
                        }
                    }
            }
            Text(store.settings.echoToReminders
                 ? "Saved here against this meeting and put on your to-do list, due \(Echo.dueDate(after: event.end).formatted(.dateTime.weekday(.wide).hour().minute())). Record again to add more."
                 : "Saved here against this meeting. Record again to add more; once it's saved you can put it on your to-do list.")
                .sk1Hint()
        }
    }

    private var savedCard: some View {
        SKWell {
            VStack(alignment: .leading, spacing: 8) {
                Text(Echo.cleaned(text)).font(.body).fixedSize(horizontal: false, vertical: true)
                Text(problem ?? (savedNote?.reminderID != nil ? "On your to-do list. It shows up in this meeting's pre-flight next time."
                                                              : "It shows up in this meeting's pre-flight next time."))
                    .sk1Hint()
                if let note = savedNote, note.reminderID == nil {
                    Button {
                        Task {
                            problem = await store.addEchoToTodo(note)
                            savedNote = store.echoNotes.first { $0.id == note.id }
                        }
                    } label: {
                        Label("Add to To-do", systemImage: "checklist").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.sk1Key())
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var keys: some View {
        if saved {
            Button("Done") { dismiss() }.buttonStyle(.sk1Key(.orange, size: .large))
        } else {
            HStack(spacing: 10) {
                Button {
                    Task {
                        if recorder.isRecording { await recorder.stop() } else { await record() }
                    }
                } label: {
                    Label(recorder.isRecording ? "Stop" : "Record", systemImage: recorder.isRecording ? "stop.fill" : "mic.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.sk1Key(recorder.isRecording ? .orange : .cream, size: .large))
                .disabled(recorder.state == .finishing || saving)
                Button {
                    Task { await save() }
                } label: {
                    Label("Save", systemImage: "checkmark").frame(maxWidth: .infinity)
                }
                .buttonStyle(.sk1Key(recorder.isRecording ? .cream : .orange, size: .large))
                .disabled(Echo.cleaned(text).isEmpty || saving || recorder.state == .finishing)
            }
        }
    }

    private func record() async {
        guard !saved else { return }
        before = text
        await recorder.start()
    }

    private func save() async {
        if recorder.isRecording { await recorder.stop() }
        saving = true
        let result = await store.saveEcho(text, for: event)
        problem = result.problem
        savedNote = result.note
        saving = false
        saved = true
        thunk += 1
    }
}

/// After a meeting ends (for half an hour, while Meetball is open): "Design review just ended" and the Echo key,
/// above the dock on every screen.
struct EchoBanner: View {
    let event: CalendarEvent
    let record: () -> Void
    let dismiss: () -> Void

    var body: some View {
        SKWell {
            HStack(spacing: 10) {
                SKLamp(color: .orange, lit: true, glow: 0, size: 6)
                VStack(alignment: .leading, spacing: 2) {
                    Text(event.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                    Text("Just ended · leave a note for your follow-ups").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 4)
                Button(action: record) { Label("Echo", systemImage: "mic.fill") }
                    .buttonStyle(.sk1Key(.orange, size: .small))
                    .accessibilityLabel("Record an Echo note for \(event.title)")
                Button(action: dismiss) { Image(systemName: "xmark") }
                    .buttonStyle(.sk1Key(.round, size: .small))
                    .accessibilityLabel("Not now")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
    }
}

/// One Echo note: what you said, when, and whether it's in Reminders.
struct EchoNoteRow: View {
    let note: EchoNote
    var onDelete: (() -> Void)?
    var onAddToTodo: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "waveform").foregroundStyle(Color(sk1Hex: SK1.orange)).padding(.top, 2).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(note.text).font(.callout).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                Text(note.createdAt.formatted(.dateTime.month(.abbreviated).day().hour().minute())
                     + (note.reminderID != nil ? " · On your to-do list" : ""))
                    .sk1Hint()
            }
            Spacer(minLength: 4)
            if note.reminderID == nil, let onAddToTodo {
                Button(action: onAddToTodo) { Image(systemName: "checklist") }
                    .buttonStyle(.sk1Key(.round, size: .small))
                    .accessibilityLabel("Add to the to-do list")
            }
            if let onDelete {
                Button(action: onDelete) { Image(systemName: "trash") }
                    .buttonStyle(.sk1Key(.round, size: .small))
                    .accessibilityLabel("Delete note")
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// The event screen's Echo notes and its Record key (once the meeting has started).
struct EchoNotesGroup: View {
    let event: CalendarEvent
    let record: () -> Void
    @EnvironmentObject private var store: PhoneStore

    var body: some View {
        let notes = store.echoNotes(for: event)
        if !notes.isEmpty || event.start <= Date() {
            SKGroup(caption: "Echo notes") {
                ForEach(notes) { n in
                    EchoNoteRow(note: n, onDelete: { withAnimation { store.deleteEcho(n) } },
                                onAddToTodo: { Task { await store.addEchoToTodo(n) } })
                }
                if event.start <= Date() {
                    Button(action: record) {
                        Label(notes.isEmpty ? "Record a note" : "Record another", systemImage: "mic.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.sk1Key())
                }
            }
        }
    }
}
