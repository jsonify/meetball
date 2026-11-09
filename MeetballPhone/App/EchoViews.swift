import SwiftUI
import SK1Tokens
import SK1UI

/// Echo: a 20-second voice note after a meeting, transcribed on the iPhone, saved in Meetball against that meeting
/// and added to Reminders as a follow-up. It starts recording as soon as it opens, so it's one tap from the banner or
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
        .onChange(of: recorder.transcript) { _, new in if recorder.isRecording || recorder.state == .finishing { text = new } }
        .onChange(of: recorder.state) { _, new in if new == .done { text = recorder.transcript.isEmpty ? text : recorder.transcript } }
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
            let left = max(0, Echo.maxDuration - now.timeIntervalSince(started))
            SK1CountdownLCD(caption: "Recording · \(meter)", digits: "\(Int(left.rounded(.up)))", unit: "SEC", live: true,
                            lamp: .danger, lampBlinking: true, height: 50,
                            accessibilityText: "Recording, \(Int(left.rounded(.up))) seconds left")
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
                 ? "Saved here against this meeting and added to Reminders, due \(Echo.dueDate(after: event.end).formatted(.dateTime.weekday(.wide).hour().minute()))."
                 : "Saved here against this meeting. Turn on Add to Reminders in Settings to get a follow-up too.")
                .sk1Hint()
        }
    }

    private var savedCard: some View {
        SKWell {
            VStack(alignment: .leading, spacing: 8) {
                Text(Echo.cleaned(text)).font(.body).fixedSize(horizontal: false, vertical: true)
                Text(problem ?? (store.settings.echoToReminders ? "Added to Reminders. It shows up in this meeting's pre-flight next time."
                                                                : "It shows up in this meeting's pre-flight next time."))
                    .sk1Hint()
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
        await recorder.start()
    }

    private func save() async {
        if recorder.isRecording { await recorder.stop() }
        saving = true
        problem = await store.saveEcho(text, for: event)
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

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "waveform").foregroundStyle(Color(sk1Hex: SK1.orange)).padding(.top, 2).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(note.text).font(.callout).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                Text(note.createdAt.formatted(.dateTime.month(.abbreviated).day().hour().minute())
                     + (note.reminderID != nil ? " · In Reminders" : ""))
                    .sk1Hint()
            }
            Spacer(minLength: 4)
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
                    EchoNoteRow(note: n) { withAnimation { store.deleteEcho(n) } }
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
