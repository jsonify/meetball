import Foundation
import SwiftUI
import EventKit

public enum CalendarSidebarLoadState: Equatable { case idle, loading, loaded, failed(String) }

public enum CalendarViewMode: String, CaseIterable, Identifiable {
    case day, week, month
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .day: return "Day"
        case .week: return "Week"
        case .month: return "Month"
        }
    }
    /// ⌘1 / ⌘2 / ⌘3
    public var shortcut: Character {
        switch self {
        case .day: return "1"
        case .week: return "2"
        case .month: return "3"
        }
    }
}

/// What the main window's detail area shows.
public enum MainSection: String { case upcoming, calendar }

@MainActor
public final class CalendarStore: ObservableObject {
    /// Upcoming dashboard (default) or the calendar views; remembered across launches.
    @Published public var section: MainSection = MainSection(rawValue: UserDefaults.standard.string(forKey: "mainSection") ?? "") ?? .upcoming {
        didSet { if oldValue != section { UserDefaults.standard.set(section.rawValue, forKey: "mainSection") } }
    }
    @Published public private(set) var calendars: [GCalendar] = []
    @Published public private(set) var events: [CalendarEvent] = []
    @Published public private(set) var loadState: CalendarSidebarLoadState = .idle
    @Published public var hiddenCalendarKeys: Set<String>
    @Published public var anchor = Date()
    @Published public var selectedDay = Calendar.current.startOfDay(for: Date())
    @Published public var actionError: String?
    @Published public var viewMode: CalendarViewMode = .month {
        didSet {
            guard oldValue != viewMode else { return }
            UserDefaults.standard.set(viewMode.rawValue, forKey: "calendarViewMode")
            anchor = selectedDay
            refresh()
        }
    }
    /// Month shown by the menu bar's mini calendar; included in the fetch range so its event dots are populated.
    @Published public var menuAnchor = Date()
    @Published public private(set) var appleEnabled: Bool = UserDefaults.standard.bool(forKey: "appleCalendarEnabled")
    @Published public private(set) var appleAccessDenied = false
    /// Meeting-first rules (Settings › Events).
    @Published public var filters = EventFilterSettings.load() {
        didSet { if oldValue != filters { filters.save() } }
    }

    let session: SessionManager
    private var client: GoogleCalendarClient
    private let apple = AppleCalendarClient()
    private var storeObserver: NSObjectProtocol?
    private var timer: Timer?
    private var refreshTask: Task<Void, Never>?
    @AppStorage("refreshIntervalSeconds") var refreshInterval: Double = 120

    init(session: SessionManager) {
        self.session = session
        self.client = GoogleCalendarClient(session: session)
        hiddenCalendarKeys = Set(UserDefaults.standard.stringArray(forKey: "hiddenCalendars") ?? [])
        viewMode = CalendarViewMode(rawValue: UserDefaults.standard.string(forKey: "calendarViewMode") ?? "") ?? .month
        storeObserver = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in if self?.appleEnabled == true { self?.refresh() } }
        }
    }

    var hasAnySource: Bool { !session.accounts.isEmpty || appleEnabled }

    /// Ask macOS for Calendar access and, if granted, start reading calendars configured in Calendar.app.
    func enableApple() async {
        let ok = await apple.requestAccess()
        appleAccessDenied = !ok
        appleEnabled = ok
        UserDefaults.standard.set(ok, forKey: "appleCalendarEnabled")
        refresh()
    }

    func disableApple() {
        appleEnabled = false
        UserDefaults.standard.set(false, forKey: "appleCalendarEnabled")
        refresh()
    }

    /// Range the main window shows: full weeks of the month, or the week containing the selected day.
    var visibleRange: DateInterval {
        switch viewMode {
        case .month: return CalendarVisibleRangeBuilder.build(anchor: anchor)
        case .week, .day: return Calendar.current.dateInterval(of: .weekOfYear, for: selectedDay)!
        }
    }

    /// Days shown as columns in the day/week time grid.
    var displayedDays: [Date] {
        switch viewMode {
        case .day: return [selectedDay]
        case .week, .month:
            let start = Calendar.current.dateInterval(of: .weekOfYear, for: selectedDay)!.start
            return (0..<7).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: start) }
        }
    }

    /// Loaded events on calendars that are currently visible.
    var visibleEvents: [CalendarEvent] { events.filter { !hiddenCalendarKeys.contains($0.calendarKey) } }
    var visibleCalendars: [GCalendar] { calendars.filter { !hiddenCalendarKeys.contains($0.key) } }
    /// Visible events split by the meeting-first rules.
    var meetingFeed: EventFilterResult { EventFilter.apply(visibleEvents, settings: filters) }
    /// Events the menu bar title, join shortcut and Meeting Guardian act on.
    var meetingEvents: [CalendarEvent] { meetingFeed.shown }
    /// Sources (Google accounts, Apple Calendar accounts) that have calendars, in sidebar order.
    var sources: [String] {
        var seen: [String] = []
        for c in calendars where !seen.contains(c.accountEmail) { seen.append(c.accountEmail) }
        return seen
    }
    var derived: CalendarDerivedEvents { CalendarDerivedEventsBuilder.build(events: visibleEvents, range: visibleRange) }

    func startAutoRefresh() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: max(30, refreshInterval), repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        refresh()
    }

    func refresh() {
        refreshTask?.cancel()
        refreshTask = Task { await load() }
    }

    func load() async {
        guard hasAnySource else { calendars = []; events = []; loadState = .idle; return }
        if calendars.isEmpty { loadState = .loading }
        var cals: [GCalendar] = []; var evs: [CalendarEvent] = []; var firstError: String?
        // fetch a wider window so the menu bar / guardian always has upcoming events
        let r = visibleRange, m = CalendarVisibleRangeBuilder.build(anchor: menuAnchor)
        let range = DateInterval(start: min(r.start, m.start, Date().addingTimeInterval(-86400)),
                                 end: max(r.end, m.end, Date().addingTimeInterval(7 * 86400)))
        for acct in session.accounts {
            do {
                let c = try await client.calendars(email: acct.email)
                cals += c
                for cal in c where !hiddenCalendarKeys.contains(cal.key) {
                    if Task.isCancelled { return }
                    evs += try await client.events(for: cal, range: range)
                }
            } catch {
                if case MeetySessionError.noAccount = error { session.invalidate(email: acct.email) }
                firstError = error.localizedDescription
            }
        }
        if appleEnabled {
            if apple.isAuthorized {
                let c = apple.calendars()
                cals += c
                for cal in c where !hiddenCalendarKeys.contains(cal.key) { evs += apple.events(for: cal, range: range) }
            } else {
                appleAccessDenied = true
                firstError = firstError ?? "Calendar access is off. Enable Meetball in System Settings › Privacy & Security › Calendars."
            }
        }
        calendars = cals
        events = evs.sorted { $0.start < $1.start }
        loadState = firstError.map { .failed($0) } ?? .loaded
    }

    func toggle(_ cal: GCalendar) {
        if hiddenCalendarKeys.contains(cal.key) { hiddenCalendarKeys.remove(cal.key) } else { hiddenCalendarKeys.insert(cal.key) }
        UserDefaults.standard.set(Array(hiddenCalendarKeys), forKey: "hiddenCalendars")
        refresh()
    }

    func create(_ draft: NewEventDraft) async -> Bool {
        do { try await client.create(draft); refresh(); return true }
        catch { actionError = draft.isFocusBlock ? "Could not add focus block: \(error.localizedDescription)" : "Could not create event: \(error.localizedDescription)"; return false }
    }

    func delete(_ e: CalendarEvent) async {
        if AppleCalendarClient.isApple(e.accountEmail) { actionError = "Apple Calendar events are read-only in Meetball."; return }
        do { try await client.delete(e); events.removeAll { $0.uid == e.uid } }
        catch { actionError = "Could not delete event: \(error.localizedDescription)" }
    }

    func shiftMonth(_ n: Int) {
        anchor = Calendar.current.date(byAdding: .month, value: n, to: anchor) ?? anchor
        refresh()
    }

    /// Previous/next period for the current view mode (← / →).
    func step(_ n: Int) {
        switch viewMode {
        case .month: shiftMonth(n)
        case .week: select(Calendar.current.date(byAdding: .day, value: 7 * n, to: selectedDay) ?? selectedDay)
        case .day: moveSelectedDay(n)
        }
    }

    /// Moves the selected day (J / K); the visible month/week follows.
    func moveSelectedDay(_ n: Int) {
        select(Calendar.current.date(byAdding: .day, value: n, to: selectedDay) ?? selectedDay)
    }

    func goToday() {
        select(Date())
        refresh()
    }

    /// Selects a day and refetches only when the visible range changed.
    func select(_ day: Date) {
        let before = visibleRange
        selectedDay = Calendar.current.startOfDay(for: day)
        anchor = selectedDay
        if visibleRange != before { refresh() }
    }

    func setMenuAnchor(_ month: Date) {
        let cal = Calendar.current
        guard !cal.isDate(month, equalTo: menuAnchor, toGranularity: .month) else { return }
        menuAnchor = month
        refresh()
    }

    /// Upcoming, non-all-day events that haven't ended, across visible calendars.
    func upcoming(limit: Int = 8, now: Date = Date()) -> [CalendarEvent] {
        Array(meetingEvents.filter { !$0.isAllDay && !$0.isDeclined && $0.end > now }.prefix(limit))
    }
}
