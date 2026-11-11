import Combine
import CoreGraphics
import EventKit
import Foundation

// Shared with the iPhone app (MeetballPhone): no AppKit or UIKit here.

/// The to-do list, kept as a "Meetball" list in Reminders, so iCloud syncs it between the Mac and the iPhone and it
/// shows in the Reminders app and Siri too. Meetball's own order and the meeting an item came from ride in each
/// reminder's URL field (`TodoLink`), since EventKit doesn't share Reminders' manual order.
@MainActor
public final class TodoStore: ObservableObject {
    public static let shared = TodoStore()
    /// The Reminders list Meetball keeps.
    public static let listTitle = "Meetball"

    public enum Access: Equatable { case notDetermined, granted, denied }

    @Published public private(set) var access: Access
    /// Every item: open ones and those done in the past week.
    @Published public private(set) var items: [TodoItem] = []
    @Published public private(set) var loaded = false
    /// The last thing that went wrong saving, for the list to show.
    @Published public var problem: String?
    /// Why asking for Reminders didn't work, when it didn't (no prompt came up, or it failed).
    @Published public private(set) var accessProblem: String?

    public var open: [TodoItem] { Todos.arrange(items).open }
    public var done: [TodoItem] { Todos.arrange(items).done }

    private let store = EKEventStore()
    private var observer: NSObjectProtocol?
    private var activeObservers: [NSObjectProtocol] = []
    private var reload: Task<Void, Never>?
    private let listKey = "todo.listIdentifier"

    public init() {
        access = Self.currentAccess()
        observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.scheduleLoad() }
        }
        // Access granted in System Settings while Meetball was open shows up when it's next brought forward (the names
        // of AppKit's and UIKit's notifications, so this file needs neither).
        for name in ["NSApplicationDidBecomeActiveNotification", "UIApplicationDidBecomeActiveNotification"] {
            activeObservers.append(NotificationCenter.default.addObserver(forName: Notification.Name(name), object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.refresh() }
            })
        }
        if access == .granted { scheduleLoad(delay: 0) }
    }

    private static func currentAccess() -> Access {
        switch EKEventStore.authorizationStatus(for: .reminder) {
        case .fullAccess: return .granted
        case .notDetermined: return .notDetermined
        default: return .denied
        }
    }

    /// Asks for Reminders the first time; true once Meetball has it.
    @discardableResult
    public func requestAccess() async -> Bool {
        var failure: Error?
        if Self.currentAccess() != .granted {
            do { _ = try await store.requestFullAccessToReminders() } catch { failure = error }
        }
        access = Self.currentAccess()
        switch access {
        case .granted:
            accessProblem = nil
            // A store made before access was given can miss the lists; start it over.
            store.reset()
            await load()
        case .notDetermined:
            accessProblem = "No Reminders prompt came up"
                + (failure.map { " (\($0.localizedDescription))" } ?? "")
                + ". " + (Failure.denied.errorDescription ?? "")
        case .denied:
            accessProblem = nil
        }
        return access == .granted
    }

    /// Reads the list again (opening the app, pull to refresh).
    public func refresh() {
        let was = access
        access = Self.currentAccess()
        guard access == .granted else { return }
        if was != .granted {
            accessProblem = nil
            store.reset()
        }
        store.refreshSourcesIfNecessary()
        scheduleLoad(delay: 0)
    }

    private func scheduleLoad(delay: Double = 0.3) {
        reload?.cancel()
        reload = Task { [weak self] in
            if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
            guard !Task.isCancelled else { return }
            await self?.load()
        }
    }

    // MARK: Reading

    /// Every list called Meetball: one per device can appear if two made it before iCloud caught up, so all are read
    /// and new items go into the first (the one this device made, when it made one).
    private func lists() -> [EKCalendar] {
        let all = store.calendars(for: .reminder).filter {
            $0.title.compare(Self.listTitle, options: [.caseInsensitive]) == .orderedSame
        }
        let mine = UserDefaults.standard.string(forKey: listKey)
        return all.sorted { a, b in
            if (a.calendarIdentifier == mine) != (b.calendarIdentifier == mine) { return a.calendarIdentifier == mine }
            return a.calendarIdentifier < b.calendarIdentifier
        }
    }

    /// The list to add to, made the first time.
    private func listForNewItems() throws -> EKCalendar {
        if let list = lists().first(where: \.allowsContentModifications) { return list }
        let list = EKCalendar(for: .reminder, eventStore: store)
        list.title = Self.listTitle
        list.cgColor = CGColor(red: 0.93, green: 0.42, blue: 0.13, alpha: 1)
        guard let source = store.defaultCalendarForNewReminders()?.source
                ?? store.sources.first(where: { $0.sourceType == .calDAV })
                ?? store.sources.first(where: { $0.sourceType == .local }) else { throw Failure.noList }
        list.source = source
        try store.saveCalendar(list, commit: true)
        UserDefaults.standard.set(list.calendarIdentifier, forKey: listKey)
        return list
    }

    private func load() async {
        guard Self.currentAccess() == .granted else { access = Self.currentAccess(); return }
        let found = lists()
        guard !found.isEmpty else { items = []; loaded = true; return }
        let openNow = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: found)
        let doneLately = store.predicateForCompletedReminders(withCompletionDateStarting: Date().addingTimeInterval(-Todos.keepDone),
                                                              ending: nil, calendars: found)
        let fetched = await fetch(openNow) + fetch(doneLately)
        var seen = Set<String>()
        items = fetched.filter { seen.insert($0.id).inserted }
        loaded = true
    }

    private func fetch(_ predicate: NSPredicate) async -> [TodoItem] {
        await withCheckedContinuation { c in
            store.fetchReminders(matching: predicate) { reminders in
                c.resume(returning: (reminders ?? []).map(TodoItem.init(reminder:)))
            }
        }
    }

    // MARK: Changing

    public enum Failure: LocalizedError {
        case denied, noList

        public var errorDescription: String? {
            switch self {
            case .denied:
                #if os(macOS)
                return "Meetball can't use Reminders. Turn it on in System Settings › Privacy & Security › Reminders."
                #else
                return "Meetball can't use Reminders. Turn it on in Settings › Meetball › Reminders."
                #endif
            case .noList: return "Reminders has no account to keep the Meetball list in."
            }
        }
    }

    /// Adds an item at the bottom of the list and returns its id. `due` also sets an alert then.
    @discardableResult
    public func add(_ title: String, meeting: TodoMeeting? = nil, notes: String? = nil, due: Date? = nil) async throws -> String {
        let title = Echo.cleaned(title)
        guard !title.isEmpty else { return "" }
        if access != .granted { guard await requestAccess() else { throw Failure.denied } }
        let list = try listForNewItems()
        let r = EKReminder(eventStore: store)
        r.calendar = list
        r.title = title
        r.notes = notes ?? meeting.map { Todos.notes(for: $0) }
        let rank = Todos.rankForNew(after: open)
        r.url = TodoLink.url(rank: rank, meeting: meeting)
        if let due {
            r.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: due)
            r.addAlarm(EKAlarm(absoluteDate: due))
        }
        try store.save(r, commit: true)
        let item = TodoItem(reminder: r)
        items.removeAll { $0.id == item.id }
        items.append(item)
        return item.id
    }

    /// Adds `title` and shows any failure on the list rather than throwing.
    public func addShowingProblems(_ title: String, meeting: TodoMeeting? = nil) {
        Task {
            do { try await add(title, meeting: meeting) } catch { problem = error.localizedDescription }
        }
    }

    public func setDone(_ item: TodoItem, _ done: Bool) {
        change(item.id) { r in r.isCompleted = done }
        update(item.id) {
            $0.isDone = done
            $0.completedAt = done ? Date() : nil
        }
    }

    public func rename(_ item: TodoItem, to title: String) {
        let title = Echo.cleaned(title)
        guard !title.isEmpty, title != item.title else { return }
        change(item.id) { $0.title = title }
        update(item.id) { $0.title = title }
    }

    public func delete(_ item: TodoItem) { delete(id: item.id) }

    public func delete(id: String) {
        items.removeAll { $0.id == id }
        guard Self.currentAccess() == .granted,
              let r = store.calendarItem(withIdentifier: id) as? EKReminder else { return }
        do { try store.remove(r, commit: true) } catch { problem = error.localizedDescription }
    }

    /// Reorders the open items, as `List.onMove` reports it.
    public func move(from offsets: IndexSet, to destination: Int) {
        let current = open
        let order = Todos.moving(current, from: offsets, to: destination)
        var changes: [String: Double] = [:]
        for i in offsets {
            let id = current[i].id
            // Rank each moved item against the order with the earlier changes in place.
            let ranked = order.map { item in changes[item.id].map { var c = item; c.rank = $0; return c } ?? item }
            changes.merge(Todos.ranks(for: ranked, moved: id)) { $1 }
        }
        for (id, rank) in changes {
            update(id) { $0.rank = rank }
            change(id) { r in
                let link = TodoLink.parse(r.url)
                r.url = TodoLink.url(rank: rank, meeting: link.meeting)
            }
        }
    }

    /// Deletes every checked-off item (Clear Done).
    public func clearDone() {
        let finished = items.filter(\.isDone)
        items.removeAll(where: \.isDone)
        guard Self.currentAccess() == .granted else { return }
        do {
            for item in finished {
                if let r = store.calendarItem(withIdentifier: item.id) as? EKReminder { try store.remove(r, commit: false) }
            }
            try store.commit()
        } catch {
            store.reset()
            problem = error.localizedDescription
            scheduleLoad(delay: 0)
        }
    }

    public func isDone(id: String) -> Bool? { items.first { $0.id == id }?.isDone }

    private func update(_ id: String, _ body: (inout TodoItem) -> Void) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        body(&items[i])
    }

    private func change(_ id: String, _ body: (EKReminder) -> Void) {
        guard let r = store.calendarItem(withIdentifier: id) as? EKReminder else { return }
        body(r)
        do { try store.save(r, commit: true) } catch { problem = error.localizedDescription }
    }
}

extension TodoItem {
    init(reminder r: EKReminder) {
        let link = TodoLink.parse(r.url)
        self.init(id: r.calendarItemIdentifier, title: r.title ?? "", isDone: r.isCompleted, completedAt: r.completionDate,
                  createdAt: r.creationDate, due: r.dueDateComponents.flatMap { Calendar.current.date(from: $0) },
                  rank: link.rank, meeting: link.meeting)
    }
}
