import SwiftUI
import AppKit
import SK1Tokens
import SK1UI

/// What the main window's event sheet shows: the one-line quick add, or the full form ("More Options").
enum EventComposer: Identifiable {
    /// A dragged time range, if any, used when the line names no day or time.
    case quickAdd(NewEventDateRange?)
    case form(NewEventDraft)

    var id: String {
        switch self {
        case .quickAdd(let r): return "quick|\(r?.start.timeIntervalSince1970 ?? 0)"
        case .form(let d): return "form|\(d.start.timeIntervalSince1970)|\(d.title)"
        }
    }
}

/// One line of natural language ("Lunch with Anna tomorrow 12:30-1:30 +meet"), a live preview on the LCD, and Add.
/// The full form stays one key away as More Options.
struct QuickAddView: View {
    @EnvironmentObject var store: CalendarStore
    /// A range dragged out on the day/week grid.
    var range: NewEventDateRange?
    var onMoreOptions: (NewEventDraft) -> Void
    var onClose: () -> Void

    @State private var line = ""
    @State private var calendar: GCalendar?
    @State private var saving = false
    @FocusState private var focused: Bool

    private var writable: [GCalendar] { store.calendars.filter(\.canWrite) }

    var body: some View {
        let parsed = result
        VStack(alignment: .leading, spacing: 12) {
            SKTextField("Quick add", text: $line, prompt: "Lunch with Anna tomorrow 12:30\u{2013}1:30 +meet")
                .focused($focused)
                .onSubmit { add(parsed) }
            preview(parsed)
            if !parsed.attendees.isEmpty {
                FlowWrap(spacing: 6) {
                    ForEach(parsed.attendees, id: \.self) { a in
                        Label(a, systemImage: "person").font(.caption).padding(.horizontal, 6).padding(.vertical, 2)
                            .background(SKGlass(.chip, radius: SK1.Metrics.chipRadius))
                            .foregroundStyle(Color(sk1Hex: SK1.lcdInk))
                    }
                }
                .accessibilityLabel("Guests: \(parsed.attendees.joined(separator: ", "))")
            }
            if writable.count > 1 {
                HStack {
                    SKCaption("Calendar", tone: .soft)
                    Spacer()
                    SKPicker(selection: $calendar, options: writable.map { SKPicker<GCalendar?>.Option($0, $0.summary) }, stepper: false)
                }
            }
            if writable.isEmpty {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    SKLamp(color: .warning, lit: true, label: "Read-only")
                    Text("Apple Calendar is read-only in Meetball. Add a Google account in Settings › Accounts to create events.")
                        .sk1Hint().fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text("Try \u{201C}fri 3pm for 45 min\u{201D}, \u{201C}next mon 9-10\u{201D}, an email to invite someone, or +meet for a video link.")
                    .sk1Hint().fixedSize(horizontal: false, vertical: true)
            }
            SKGroove()
            HStack(spacing: 8) {
                Spacer()
                Button("Cancel", action: onClose).buttonStyle(.sk1Key()).keyboardShortcut(.cancelAction)
                Button("More Options\u{2026}") { onMoreOptions(draft(parsed)) }.buttonStyle(.sk1Key())
                    .help("Open the full form with what you typed")
                Button("Add") { add(parsed) }.buttonStyle(.sk1Key(.orange))
                    .disabled(saving || writable.isEmpty || parsed.title.isEmpty)
                    .help(writable.isEmpty ? "No calendar you can add events to" : "Add the event (↩)")
            }
        }
        .padding(16)
        .frame(width: 480)
        .sk1Chassis()
        .onAppear {
            calendar = calendar ?? writable.first(where: \.isPrimary) ?? writable.first
            focused = true
        }
    }

    /// The parsed line, with a dragged range standing in when the line names no day or time.
    private var result: QuickAddResult {
        var r = QuickAddParser.parse(line)
        if let range, !r.hasDate && !r.hasTime { r.start = range.start; r.end = range.end }
        return r
    }

    private func preview(_ r: QuickAddResult) -> some View {
        let when = QuickAddPreview.when(r)
        let extras = [r.addMeet ? "MEET" : nil, r.attendees.isEmpty ? nil : "\(r.attendees.count) GUEST\(r.attendees.count == 1 ? "" : "S")"]
            .compactMap { $0 }.joined(separator: " · ")
        return SKLCD {
            HStack(spacing: 8) {
                SKLamp(color: r.title.isEmpty ? .warning : .success, lit: true, glow: 0, size: 5)
                Text(r.title.isEmpty ? "TYPE A TITLE" : r.title)
                    .font(.system(size: 11, weight: .heavy)).lineLimit(1)
                Spacer(minLength: 6)
                Text(extras.isEmpty ? when : "\(when) · \(extras)")
                    .font(.sk1(SK1.TypeScale.lcdMono)).lineLimit(1)
            }
            .foregroundStyle(Color(sk1Hex: SK1.lcdInk))
            .padding(.horizontal, 10)
        }
        .frame(height: 32)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(r.title.isEmpty ? "No title yet" : "\(r.title), \(when)\(extras.isEmpty ? "" : ", \(extras.lowercased())")")
    }

    private func draft(_ r: QuickAddResult) -> NewEventDraft {
        var d = NewEventDraft(start: r.start, end: r.end)
        d.title = r.title
        d.calendar = calendar
        d.attendees = r.attendees
        d.addMeet = r.addMeet && (calendar?.allowsMeet ?? false)
        return d
    }

    private func add(_ r: QuickAddResult) {
        guard !saving, !r.title.isEmpty, calendar != nil else { return }
        saving = true
        Task {
            if await store.create(draft(r)) { onClose() }
            saving = false
        }
    }
}

enum QuickAddPreview {
    /// "Today 3:00 – 3:45 PM", "Fri, Dec 6 9:00 – 10:00 AM".
    static func when(_ r: QuickAddResult, now: Date = Date(), calendar: Calendar = .app) -> String {
        let day: String
        if calendar.isDateInToday(r.start) { day = "Today" }
        else if calendar.isDateInTomorrow(r.start) { day = "Tomorrow" }
        else { day = r.start.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()) }
        return "\(day) \(r.start.shortTime) \u{2013} \(r.end.shortTime)"
    }
}

// MARK: - Floating quick add (global shortcut)

/// The quick-add line as a floating panel, for the global shortcut: it opens over whatever app is in front.
@MainActor
enum QuickAddPanel {
    private static var panel: NSPanel?
    private static var resignObserver: NSObjectProtocol?

    static func show(store: CalendarStore) {
        close()
        let view = QuickAddView(range: nil, onMoreOptions: { draft in
            close()
            WindowOpener.openMain()
            store.composer = .form(draft)
        }, onClose: close)
            .environmentObject(store)
        let host = NSHostingView(rootView: view)
        let p = KeyPanel(contentRect: NSRect(origin: .zero, size: host.fittingSize),
                         styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
        p.titleVisibility = .hidden
        p.titlebarAppearsTransparent = true
        p.isMovableByWindowBackground = true
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.contentView = host
        p.setContentSize(host.fittingSize)
        if let screen = NSScreen.main {
            let f = screen.visibleFrame
            p.setFrameTopLeftPoint(NSPoint(x: f.midX - p.frame.width / 2, y: f.maxY - f.height * 0.2))
        }
        NSApp.activate(ignoringOtherApps: true)
        p.makeKeyAndOrderFront(nil)
        panel = p
        resignObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: p, queue: .main) { _ in
            Task { @MainActor in close() }
        }
    }

    static func close() {
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        resignObserver = nil
        panel?.orderOut(nil)
        panel = nil
    }

    private final class KeyPanel: NSPanel {
        override var canBecomeKey: Bool { true }
        override func cancelOperation(_ sender: Any?) { QuickAddPanel.close() }
    }
}

// MARK: - Opening windows from outside a view

/// Opens the main window from code that isn't a view (global shortcuts, the quick-add panel). Views that can open
/// windows register the action as they appear.
@MainActor
enum WindowOpener {
    static var openMainAction: (() -> Void)?

    static func openMain() {
        if let w = NSApp.windows.first(where: { $0.title == "Meetball" && $0.canBecomeMain }) {
            w.makeKeyAndOrderFront(nil)
        } else {
            openMainAction?()
        }
        NSApp.activate(ignoringOtherApps: true)
    }
}

/// Registers `openWindow(id: "main")` with `WindowOpener` while this view is on screen.
struct RegistersWindowOpener: ViewModifier {
    @Environment(\.openWindow) private var openWindow
    func body(content: Content) -> some View {
        content.onAppear { WindowOpener.openMainAction = { openWindow(id: "main") } }
    }
}

/// Opens the menu bar popover by clicking Meetball's status item, for the global shortcut.
@MainActor
enum StatusItemOpener {
    static func toggle() {
        for w in NSApp.windows where w.className.contains("StatusBarWindow") {
            if let button = find(in: w.contentView) {
                NSApp.activate(ignoringOtherApps: true)
                button.performClick(nil)
                return
            }
        }
    }

    private static func find(in view: NSView?) -> NSStatusBarButton? {
        guard let view else { return nil }
        if let b = view as? NSStatusBarButton { return b }
        for sub in view.subviews { if let b = find(in: sub) { return b } }
        return nil
    }
}
