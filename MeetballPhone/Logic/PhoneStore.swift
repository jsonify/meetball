import BackgroundTasks
import EventKit
import Foundation
import UIKit
import UserNotifications

/// Reads Apple Calendar, schedules meeting reminders, and alerts on changes.
///
/// iOS doesn't let an app watch the calendar all the time, so Meetball checks for changes whenever it gets to run:
/// when it's opened, when Calendar data changes while it's still in memory, and when iOS grants it a background app
/// refresh (requested every 15 minutes; iOS decides how often, usually less often when the phone is idle or in Low
/// Power Mode). Reminders themselves are scheduled ahead with iOS, so they fire on time even if Meetball never runs.
@MainActor
final class PhoneStore: ObservableObject {
    static let shared = PhoneStore()
    static let refreshTaskID = "app.meetball.MeetballPhone.refresh"
    static let refreshInterval: TimeInterval = 15 * 60

    enum Access { case notDetermined, granted, denied }

    @Published private(set) var calendarAccess: Access = .notDetermined
    @Published private(set) var calendars: [GCalendar] = []
    @Published private(set) var upcoming: [CalendarEvent] = []
    @Published private(set) var scheduled: [PlannedReminder] = []
    @Published private(set) var recentChanges: [RecentChange] = []
    @Published private(set) var lastRefresh: Date?
    @Published private(set) var lastBackgroundRefresh: Date?
    @Published private(set) var notificationSettings: UNNotificationSettings?
    /// Bumped by every refresh, so the calendar screens load their events again.
    @Published private(set) var revision = 0
    /// Moved, re-linked and cancelled meetings, shown on Today until dismissed.
    @Published private(set) var changeCards: [ChangeCard] = []
    /// Confetti on screen now.
    @Published var celebration: Celebration?
    /// Calendars quick add can write to.
    @Published private(set) var writableCalendars: [GCalendar] = []
    @Published var settings: PhoneSettings {
        didSet {
            guard settings != oldValue else { return }
            settings.save()
            Task { await refresh() }
        }
    }

    private let client = AppleCalendarClient()
    private var started = false
    private var debounce: Task<Void, Never>?
    /// Events per range for the calendar screens, cleared by each refresh.
    private var rangeCache: [String: [CalendarEvent]] = [:]
    private let defaults = UserDefaults.standard
    private enum Key {
        static let moved = "phone.moved"
        static let recent = "phone.recentChanges"
        static let lastBackground = "phone.lastBackgroundRefresh"
        static let cards = "phone.changeCards"
        static let pendingCelebration = "phone.pendingCelebration"
    }

    private init() {
        settings = PhoneSettings.load()
        recentChanges = (defaults.data(forKey: Key.recent)).flatMap { try? JSONDecoder().decode([RecentChange].self, from: $0) } ?? []
        lastBackgroundRefresh = defaults.object(forKey: Key.lastBackground) as? Date
        changeCards = defaults.data(forKey: Key.cards).flatMap { try? JSONDecoder().decode([ChangeCard].self, from: $0) } ?? []
        updateAccess()
    }

    /// First launch: asks for calendar and notification access, then refreshes. Later calls just refresh.
    func start() async {
        guard !started else { return await refresh(fresh: true) }
        started = true
        PhoneNotifications.registerCategories()
        NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.calendarChanged() }
        }
        _ = await PhoneNotifications.requestAuthorization()
        if calendarAccess == .notDetermined { _ = await client.requestAccess() }
        updateAccess()
        await refresh(fresh: true)
    }

    func requestCalendarAccess() async {
        _ = await client.requestAccess()
        updateAccess()
        await refresh(fresh: true)
    }

    /// Loads the next two days, alerts on changes since the last check, and reschedules every reminder.
    func refresh(fresh: Bool = false, now: Date = Date()) async {
        updateAccess()
        notificationSettings = await PhoneNotifications.settings()
        guard client.isAuthorized else { return }
        client.sync(fresh: fresh)

        let all = client.calendars().sorted { ($0.accountEmail, $0.summary) < ($1.accountEmail, $1.summary) }
        calendars = all
        let writable = client.writableCalendarIDs()
        writableCalendars = all.filter { writable.contains($0.id) && !settings.hiddenCalendars.contains($0.key) }
        rangeCache.removeAll()
        revision &+= 1
        let visible = all.filter { !settings.hiddenCalendars.contains($0.key) }
        let range = DateInterval(start: now.addingTimeInterval(-2 * 3600), end: now.addingTimeInterval(ReminderPlanner.horizon + 2 * 3600))
        let events = visible.flatMap { client.events(for: $0, range: range) }
        let snapshot = EventSnapshot(events: events, calendars: Set(visible.map(\.key)), range: range)

        var moved = defaults.dictionary(forKey: Key.moved) as? [String: Date] ?? [:]
        if let previous = StoredEventSnapshot.load()?.snapshot(now: now) {
            let changes = MeetingChangeDetector.diff(old: previous, new: snapshot, now: now)
            moved = ReminderPlanner.movedUIDs(moved, changes: changes, now: now)
            if !changes.isEmpty {
                setCards(ChangeCard.merged(changeCards, changes.map { ChangeCard($0, now: now) }, now: now))
                if settings.celebrateCancellations, let party = Celebration(changes) { celebrate(party) }
            }
            if settings.notifyChanges, let alert = ReminderPlanner.changeAlert(changes, now: now) {
                await PhoneNotifications.postChange(title: alert.title, body: alert.body)
                recentChanges = Array(([RecentChange(title: alert.title, body: alert.body, at: now)] + recentChanges).prefix(10))
                if let data = try? JSONEncoder().encode(recentChanges) { defaults.set(data, forKey: Key.recent) }
            }
        } else {
            moved = moved.filter { $0.value > now }
        }
        defaults.set(moved, forKey: Key.moved)
        StoredEventSnapshot(snapshot, savedAt: now).save()

        upcoming = ReminderPlanner.meetings(events, settings: settings, now: now)
        scheduled = ReminderPlanner.plan(events, settings: settings, moved: Set(moved.keys), now: now)
        await PhoneNotifications.apply(scheduled)
        LiveActivityController.updateWidgets(upcoming: upcoming, now: now)
        await LiveActivityController.reconcile(upcoming: upcoming, enabled: settings.liveActivity, now: now)
        lastRefresh = now
    }

    /// The visible calendars' events overlapping `range`, a meeting on two calendars kept once. Cached until the next
    /// refresh, so the screens can ask on every redraw.
    func events(in range: DateInterval) -> [CalendarEvent] {
        let key = "\(revision)|\(range.start.timeIntervalSince1970)|\(range.end.timeIntervalSince1970)"
        if let hit = rangeCache[key] { return hit }
        guard client.isAuthorized else { return [] }
        let visible = calendars.filter { !settings.hiddenCalendars.contains($0.key) }
        let loaded = PhoneAgenda.dedupe(visible.flatMap { client.events(for: $0, range: range) })
        if rangeCache.count > 32 { rangeCache.removeAll() }
        rangeCache[key] = loaded
        return loaded
    }

    /// Events from the start of `day` for `days` days.
    func events(from day: Date, days: Int) -> [CalendarEvent] {
        let start = Calendar.app.startOfDay(for: day)
        let end = Calendar.app.date(byAdding: .day, value: days, to: start) ?? start.addingTimeInterval(Double(days) * 86400)
        return events(in: DateInterval(start: start, end: end))
    }

    /// Quick add: saves the event to `calendar` and refreshes.
    func addEvent(title: String, start: Date, end: Date, calendar: GCalendar) async throws {
        try client.addEvent(title: title, start: start, end: end, calendarID: calendar.id)
        await refresh()
    }

    /// An unsaved event for Apple's event editor (Invite people), with the store the editor must save it in.
    func draftEvent(title: String, start: Date, end: Date, calendar: GCalendar?) -> (event: EKEvent, store: EKEventStore)? {
        guard let e = client.draftEvent(title: title, start: start, end: end, calendarID: calendar?.id) else { return nil }
        return (e, client.eventStore)
    }

    /// The calendar quick add picks first: the Calendar app's default for new events when Meetball can write to it.
    var defaultCalendarForNewEvents: GCalendar? {
        let id = client.defaultCalendarID
        return writableCalendars.first { $0.id == id } ?? writableCalendars.first
    }

    func dismissCard(_ card: ChangeCard) {
        setCards(changeCards.filter { $0.id != card.id })
    }

    func dismissAllCards() { setCards([]) }

    private func setCards(_ cards: [ChangeCard]) {
        changeCards = cards
        if let data = try? JSONEncoder().encode(cards) { defaults.set(data, forKey: Key.cards) }
    }

    /// Confetti now if Meetball is on screen, else the next time it is (a cancellation found by a background check).
    private func celebrate(_ party: Celebration) {
        if UIApplication.shared.applicationState == .active {
            celebration = party
        } else if let data = try? JSONEncoder().encode(party) {
            defaults.set(data, forKey: Key.pendingCelebration)
        }
    }

    /// Shows confetti saved while Meetball was in the background.
    func showPendingCelebration() {
        guard let data = defaults.data(forKey: Key.pendingCelebration) else { return }
        defaults.removeObject(forKey: Key.pendingCelebration)
        guard settings.celebrateCancellations, let party = try? JSONDecoder().decode(Celebration.self, from: data) else { return }
        celebration = party
    }

    /// A sample of the cancellation confetti (Settings).
    func previewCelebration() {
        celebration = Celebration(title: "Design review", extra: 0)
    }

    /// Run by iOS in the background (`.backgroundTask(.appRefresh)`).
    func backgroundRefresh() async {
        scheduleBackgroundRefresh()
        await refresh(fresh: true)
        lastBackgroundRefresh = Date()
        defaults.set(lastBackgroundRefresh, forKey: Key.lastBackground)
    }

    /// Asks iOS for the next background refresh. Submitting again replaces the earlier request.
    func scheduleBackgroundRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: Self.refreshTaskID)
        request.earliestBeginDate = Date().addingTimeInterval(Self.refreshInterval)
        try? BGTaskScheduler.shared.submit(request)
    }

    func sendTestAlert(after delay: TimeInterval) async {
        await PhoneNotifications.sendTest(after: delay)
    }

    /// EventKit posts several of these in a row while a sync lands; refresh once they settle.
    private func calendarChanged() {
        debounce?.cancel()
        debounce = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await self?.refresh()
        }
    }

    private func updateAccess() {
        let status = EKEventStore.authorizationStatus(for: .event)
        switch status {
        case .fullAccess: calendarAccess = .granted
        case .notDetermined: calendarAccess = .notDetermined
        default: calendarAccess = .denied
        }
    }
}
