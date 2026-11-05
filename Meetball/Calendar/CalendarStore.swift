import Foundation
import SwiftUI
import EventKit

public enum CalendarSidebarLoadState: Equatable { case idle, loading, loaded, failed(String) }

@MainActor
public final class CalendarStore: ObservableObject {
    @Published public private(set) var calendars: [GCalendar] = []
    @Published public private(set) var events: [CalendarEvent] = []
    @Published public private(set) var loadState: CalendarSidebarLoadState = .idle
    @Published public var hiddenCalendarKeys: Set<String>
    @Published public var anchor = Date()
    @Published public var selectedDay = Calendar.current.startOfDay(for: Date())
    @Published public var actionError: String?
    @Published public private(set) var appleEnabled: Bool = UserDefaults.standard.bool(forKey: "appleCalendarEnabled")
    @Published public private(set) var appleAccessDenied = false

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

    var visibleRange: DateInterval { CalendarVisibleRangeBuilder.build(anchor: anchor) }
    var visibleCalendars: [GCalendar] { calendars.filter { !hiddenCalendarKeys.contains($0.key) } }
    var derived: CalendarDerivedEvents { CalendarDerivedEventsBuilder.build(events: events, range: visibleRange) }

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
        let r = visibleRange
        let range = DateInterval(start: min(r.start, Date().addingTimeInterval(-86400)), end: max(r.end, Date().addingTimeInterval(7 * 86400)))
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

    /// Upcoming, non-all-day events that haven't ended, across visible calendars.
    func upcoming(limit: Int = 8, now: Date = Date()) -> [CalendarEvent] {
        Array(events.filter { !$0.isAllDay && $0.end > now && !hiddenCalendarKeys.contains("\($0.accountEmail)|\($0.calendarID)") }.prefix(limit))
    }
}
