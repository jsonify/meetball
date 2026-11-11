import AppKit
import SwiftUI
import SK1Tokens
import SK1UI

/// The menu bar popover's to-do tray: a line to jot something down, the first few open items, and a key to the whole
/// list in the main window. Until Meetball can use Reminders, just the key to set it up.
struct TodoTray: View {
    @EnvironmentObject var calendar: CalendarStore
    @ObservedObject var todos: TodoStore = .shared
    @Environment(\.openWindow) private var openWindow
    /// Open items shown here; the rest are a click away.
    private let shown = 4

    var body: some View {
        let open = todos.open
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                SKCaption(open.isEmpty ? "To-do" : "To-do \u{00B7} \(open.count)", tone: .soft)
                Spacer()
                Button(todos.access == .granted ? "Open List" : "Set Up") { showList() }
                    .buttonStyle(.sk1Key(size: .small))
                    .help("Show the to-do list in the Meetball window (⌘4)")
            }
            if todos.access == .granted {
                TodoAddLine(prompt: "Jot down a to-do")
                ForEach(open.prefix(shown)) { item in
                    TodoRow(item: item, openMeeting: { m in
                        calendar.showDay(m.start)
                        openMain()
                    })
                }
                if open.count > shown {
                    Text("And \(open.count - shown) more").sk1Hint()
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .onAppear { todos.refresh() }
    }

    private func showList() {
        calendar.section = .todo
        openMain()
    }

    private func openMain() {
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }
}
