import BackgroundTasks
import EventKit
import Foundation
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
    private let defaults = UserDefaults.standard
    private enum Key {
        static let moved = "phone.moved"
        static let recent = "phone.recentChanges"
        static let lastBackground = "phone.lastBackgroundRefresh"
    }

    private init() {
        settings = PhoneSettings.load()
        recentChanges = (defaults.data(forKey: Key.recent)).flatMap { try? JSONDecoder().decode([RecentChange].self, from: $0) } ?? []
        lastBackgroundRefresh = defaults.object(forKey: Key.lastBackground) as? Date
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
        let visible = all.filter { !settings.hiddenCalendars.contains($0.key) }
        let range = DateInterval(start: now.addingTimeInterval(-2 * 3600), end: now.addingTimeInterval(ReminderPlanner.horizon + 2 * 3600))
        let events = visible.flatMap { client.events(for: $0, range: range) }
        let snapshot = EventSnapshot(events: events, calendars: Set(visible.map(\.key)), range: range)

        var moved = defaults.dictionary(forKey: Key.moved) as? [String: Date] ?? [:]
        if let previous = StoredEventSnapshot.load()?.snapshot(now: now) {
            let changes = MeetingChangeDetector.diff(old: previous, new: snapshot, now: now)
            moved = ReminderPlanner.movedUIDs(moved, changes: changes, now: now)
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
        lastRefresh = now
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
