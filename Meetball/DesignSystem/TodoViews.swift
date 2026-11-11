import SwiftUI
import SK1Tokens
import SK1UI

// Shared with the iPhone app (MeetballPhone): no AppKit or UIKit here.

/// The tick box: a small sunken square, filled orange with a check once the item is done.
struct TodoCheck: View {
    let done: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(done ? Color(sk1Hex: SK1.orange) : Color.primary.opacity(0.06))
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(done ? Color(sk1Hex: SK1.orange) : Color.primary.opacity(0.35), lineWidth: 1.5)
                if done {
                    Image(systemName: "checkmark").font(.system(size: 11, weight: .heavy)).foregroundStyle(.white)
                }
            }
            .frame(width: 20, height: 20)
            .padding(6)
            .contentShape(Rectangle())
        }
        .buttonStyle(TodoPressStyle())
        .accessibilityLabel(done ? "Done" : "Not done")
        .accessibilityHint(done ? "Marks it not done" : "Marks it done")
    }
}

/// Plain, fading a touch while held: for the tick box and a to-do's meeting link.
struct TodoPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.55 : 1)
    }
}

/// The meeting a to-do came from, as a small teal link: its name and day. Opens it.
struct TodoMeetingLink: View {
    let meeting: TodoMeeting
    let open: (TodoMeeting) -> Void

    var body: some View {
        Button { open(meeting) } label: {
            HStack(spacing: 4) {
                Image(systemName: "person.2.fill").font(.system(size: 9, weight: .semibold))
                Text(meeting.title.isEmpty ? "Meeting" : meeting.title).lineLimit(1)
                Text("· \(meeting.start.formatted(.dateTime.month(.abbreviated).day()))").foregroundStyle(.secondary)
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(Color(sk1Hex: SK1.teal))
        }
        .buttonStyle(TodoPressStyle())
        .accessibilityLabel("From \(meeting.title)")
        .accessibilityHint("Opens the meeting")
    }
}

/// One to-do: the tick box, the words (tap to change them), and the meeting it came from.
struct TodoRow: View {
    let item: TodoItem
    /// Nil hides the meeting link (on the meeting's own screen).
    var openMeeting: ((TodoMeeting) -> Void)?
    @ObservedObject var todos: TodoStore = .shared
    @State private var editing = false
    @State private var draft = ""

    var body: some View {
        HStack(alignment: .top, spacing: 4) {
            TodoCheck(done: item.isDone) {
                withAnimation(.snappy) { todos.setDone(item, !item.isDone) }
            }
            VStack(alignment: .leading, spacing: 3) {
                if editing {
                    SKTextField("To-do", text: $draft, height: 30)
                        .onSubmit(commit)
                        .submitLabel(.done)
                } else {
                    Text(item.title)
                        .font(.body)
                        .strikethrough(item.isDone)
                        .foregroundStyle(item.isDone ? .secondary : .primary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .onTapGesture { startEditing() }
                        .accessibilityAddTraits(.isButton)
                        .accessibilityHint("Edits it")
                }
                if openMeeting != nil || (!item.isDone && item.due != nil) {
                    HStack(spacing: 8) {
                        if let m = item.meeting, let openMeeting { TodoMeetingLink(meeting: m, open: openMeeting) }
                        if !item.isDone, let due = item.due {
                            Text("Due \(due.formatted(.dateTime.weekday(.abbreviated).hour().minute()))")
                                .font(.caption)
                                .foregroundStyle(due < Date() ? Color(sk1Hex: SK1.recRed) : .secondary)
                        }
                    }
                }
            }
            .padding(.top, 7)
            if editing {
                Button("Save", action: commit).buttonStyle(.sk1Key(size: .small)).padding(.top, 4)
            }
        }
        .contextMenu {
            Button("Edit") { startEditing() }
            Button(item.isDone ? "Mark Not Done" : "Mark Done") { todos.setDone(item, !item.isDone) }
            Button("Delete", role: .destructive) { withAnimation { todos.delete(item) } }
        }
    }

    private func startEditing() {
        guard !item.isDone else { return }
        draft = item.title
        editing = true
    }

    private func commit() {
        todos.rename(item, to: draft)
        editing = false
    }
}

/// The line new to-dos are typed into, with its Add key.
struct TodoAddLine: View {
    var prompt = "Add a to-do"
    var meeting: TodoMeeting?
    @ObservedObject var todos: TodoStore = .shared
    @State private var text = ""

    var body: some View {
        HStack(spacing: 8) {
            SKTextField("New to-do", text: $text, prompt: prompt, height: 34)
                .onSubmit(add)
                .submitLabel(.done)
            Button(action: add) { Image(systemName: "plus").font(.system(size: 13, weight: .bold)) }
                .buttonStyle(.sk1Key(size: .small))
                .disabled(Echo.cleaned(text).isEmpty)
                .accessibilityLabel("Add")
        }
    }

    private func add() {
        let line = Echo.cleaned(text)
        guard !line.isEmpty else { return }
        text = ""
        todos.addShowingProblems(line, meeting: meeting)
    }
}

/// In place of the list until Meetball can use Reminders, where the list is kept.
struct TodoAccessCard: View {
    @ObservedObject var todos: TodoStore = .shared
    @Environment(\.openURL) private var openURL
    @State private var asking = false

    var body: some View {
        SKWell {
            VStack(alignment: .leading, spacing: 10) {
                Text("Your to-do list lives in Reminders").font(.headline)
                Text(todos.access == .denied ? deniedText
                     : "Meetball keeps it as a list called \u{201C}Meetball\u{201D} in Reminders, so it syncs between your Mac and iPhone through iCloud.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if let why = todos.accessProblem {
                    Text(why).font(.callout).foregroundStyle(Color(sk1Hex: SK1.recRed)).fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 8) {
                    if todos.access == .notDetermined {
                        Button(asking ? "Asking\u{2026}" : "Turn On To-do List") {
                            asking = true
                            Task {
                                await todos.requestAccess()
                                asking = false
                            }
                        }
                        .buttonStyle(.sk1Key(.orange))
                        .disabled(asking)
                    }
                    if todos.access == .denied || todos.accessProblem != nil {
                        Button("Open Settings") { openURL(Self.settingsURL) }.buttonStyle(.sk1Key())
                        Button("Check Again") { todos.refresh() }.buttonStyle(.sk1Key())
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Where Reminders access is turned on.
    static var settingsURL: URL {
        #if os(macOS)
        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders")!
        #else
        URL(string: "app-settings:")!
        #endif
    }

    private var deniedText: String {
        TodoStore.Failure.denied.errorDescription ?? ""
    }
}

/// The whole to-do list: the add line, open items (drag to reorder, swipe or right-click to delete), and what was
/// done this past week, folded away under Done.
struct TodoListView: View {
    let openMeeting: (TodoMeeting) -> Void
    @ObservedObject var todos: TodoStore = .shared
    @AppStorage("todo.showDone") private var showDone = false
    @State private var confirmingClear = false

    var body: some View {
        Group {
            if todos.access != .granted {
                ScrollView { TodoAccessCard().padding(16) }
            } else {
                list
            }
        }
        .onAppear { todos.refresh() }
        .alert("Couldn't change the to-do list", isPresented: Binding(get: { todos.problem != nil }, set: { if !$0 { todos.problem = nil } })) {
            Button("OK") { todos.problem = nil }
        } message: { Text(todos.problem ?? "") }
    }

    private var list: some View {
        let (open, done) = Todos.arrange(todos.items)
        return List {
            TodoAddLine()
                .padding(.vertical, 6)
                .plainRow()
            if open.isEmpty && todos.loaded {
                Text(done.isEmpty ? "Nothing to do. Type above to add something, or add a follow-up from a meeting."
                                  : "All done.")
                    .font(.callout).foregroundStyle(.secondary)
                    .padding(.vertical, 12)
                    .plainRow()
            }
            ForEach(open) { item in
                TodoRow(item: item, openMeeting: openMeeting).plainRow()
            }
            .onMove { todos.move(from: $0, to: $1) }
            .onDelete { offsets in offsets.map { open[$0] }.forEach { todos.delete($0) } }
            if !done.isEmpty {
                HStack(spacing: 8) {
                    Button {
                        withAnimation(.snappy) { showDone.toggle() }
                    } label: {
                        Label("Done (\(done.count))", systemImage: showDone ? "chevron.down" : "chevron.right")
                    }
                    .buttonStyle(.sk1Key(isOn: showDone, size: .small))
                    Spacer()
                    Button("Clear Done") { confirmingClear = true }
                        .buttonStyle(.sk1Key(size: .small))
                        .accessibilityHint("Deletes the \(done.count) checked-off items")
                }
                .padding(.top, 10)
                .plainRow()
                .confirmationDialog("Delete \(done.count) checked-off item\(done.count == 1 ? "" : "s")?",
                                    isPresented: $confirmingClear, titleVisibility: .visible) {
                    Button("Clear Done", role: .destructive) { withAnimation(.snappy) { todos.clearDone() } }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("They're removed from the Meetball list in Reminders too, on all your devices.")
                }
                if showDone {
                    ForEach(done) { item in
                        TodoRow(item: item, openMeeting: openMeeting).plainRow()
                    }
                    .onDelete { offsets in offsets.map { done[$0] }.forEach { todos.delete($0) } }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .animation(.snappy, value: todos.items)
    }
}

/// A meeting's follow-ups on its own screen: what's on the list from it, a line to add one, and lines in its notes
/// that read as things to do, one tap each to add.
struct MeetingFollowUps: View {
    let event: CalendarEvent
    /// The meeting's notes as plain text.
    var notes: String = ""
    @ObservedObject var todos: TodoStore = .shared

    var body: some View {
        let mine = Todos.followUps(for: event, in: todos.items)
        let suggested = todos.access == .granted ? Todos.newSuggestions(for: event, notes: notes, items: todos.items) : []
        VStack(alignment: .leading, spacing: SK1.Metrics.captionToWell) {
            SKCaption("Follow-ups", tone: .soft)
            if todos.access != .granted {
                TodoAccessCard()
            } else {
                SKWell {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(mine) { TodoRow(item: $0) }
                        TodoAddLine(prompt: "Add a follow-up", meeting: TodoMeeting(event))
                            .padding(.vertical, 4)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                }
                if !suggested.isEmpty {
                    SKCaption("From the notes", tone: .soft).padding(.top, 4)
                    SKWell {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(suggested.enumerated()), id: \.element) { i, line in
                                if i > 0 { SKGroove() }
                                HStack(spacing: 8) {
                                    Text(line).font(.callout).fixedSize(horizontal: false, vertical: true)
                                    Spacer(minLength: 6)
                                    Button {
                                        todos.addShowingProblems(line, meeting: TodoMeeting(event))
                                    } label: { Image(systemName: "plus").font(.system(size: 12, weight: .bold)) }
                                        .buttonStyle(.sk1Key(size: .small))
                                        .accessibilityLabel("Add \u{201C}\(line)\u{201D} to the to-do list")
                                }
                                .padding(.vertical, 6)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .onAppear { todos.refresh() }
    }
}

extension View {
    /// A list row with nothing of the list's own look: no background, no separator, the chassis showing through.
    func plainRow() -> some View {
        listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 2, leading: 12, bottom: 2, trailing: 12))
    }
}
