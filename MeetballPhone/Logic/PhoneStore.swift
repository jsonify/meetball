import BackgroundTasks
import CoreLocation
import EventKit
import Foundation
import UIKit
import UserNotifications

/// A tapped Echo nudge: which meeting to record a note for.
struct EchoRequest: Identifiable, Equatable {
    var uid: String
    var start: Date
    var end: Date
    var title: String
    var id: String { uid }
}

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
    /// Echo notes left after meetings, newest first.
    @Published private(set) var echoNotes: [EchoNote] = []
    /// The meeting to open the Echo recorder for (the Echo nudge was tapped).
    @Published var echoRequest: EchoRequest?
    /// Drive times to upcoming trips, by event uid (worked out by refreshes, kept across launches).
    @Published private(set) var etas: [String: TripETA] = [:]
    /// Location access, which drive times need.
    @Published private(set) var locationStatus: CLAuthorizationStatus = .notDetermined
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
    private let travel = TravelTimes()
    private var started = false
    private var debounce: Task<Void, Never>?
    /// Meetings deleted on this phone (an event's id prefix, the earliest start it covers, and when), so refreshes in the
    /// next few minutes don't report their disappearance as a cancellation.
    private var locallyRemoved: [(prefix: String, from: Date, at: Date)] = []
    /// Events per range for the calendar screens, cleared by each refresh.
    private var rangeCache: [String: [CalendarEvent]] = [:]
    private let defaults = UserDefaults.standard
    private enum Key {
        static let moved = "phone.moved"
        static let recent = "phone.recentChanges"
        static let lastBackground = "phone.lastBackgroundRefresh"
        static let cards = "phone.changeCards"
        static let pendingCelebration = "phone.pendingCelebration"
        static let echoNotes = "phone.echoNotes"
        static let etas = "phone.tripETAs"
    }

    private init() {
        settings = PhoneSettings.load()
        recentChanges = (defaults.data(forKey: Key.recent)).flatMap { try? JSONDecoder().decode([RecentChange].self, from: $0) } ?? []
        lastBackgroundRefresh = defaults.object(forKey: Key.lastBackground) as? Date
        changeCards = defaults.data(forKey: Key.cards).flatMap { try? JSONDecoder().decode([ChangeCard].self, from: $0) } ?? []
        echoNotes = defaults.data(forKey: Key.echoNotes).flatMap { try? JSONDecoder().decode([EchoNote].self, from: $0) } ?? []
        etas = defaults.data(forKey: Key.etas).flatMap { try? JSONDecoder().decode([String: TripETA].self, from: $0) } ?? [:]
        updateAccess()
        locationStatus = travel.authorization
        travel.onAuthorizationChange = { [weak self] in self?.locationChanged() }
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
            let ignoring = Set(previous.events.values.filter { e in
                locallyRemoved.contains { e.uid.hasPrefix($0.prefix) && e.start >= $0.from }
            }.map(\.uid))
            locallyRemoved.removeAll { now.timeIntervalSince($0.at) > 600 }
            // As on the Mac, changes to meetings the event filters leave out aren't reported.
            let changes = MeetingChangeDetector.diff(old: previous, new: snapshot, now: now, ignoring: ignoring)
                .filter { !settings.isFiltered($0.event) }
            moved = ReminderPlanner.movedUIDs(moved, changes: changes, now: now)
            if !changes.isEmpty {
                setCards(ChangeCard.merged(changeCards, changes.map { ChangeCard($0, now: now) }, now: now))
                if settings.celebrateCancellations, let party = Celebration(changes) { celebrate(party) }
            }
            // A silenced calendar stays quiet about changes too (the in-app cards above still show them).
            if settings.notifyChanges, let alert = ReminderPlanner.changeAlert(changes.filter { settings.alerts(for: $0.event) }, now: now) {
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
        if settings.driveTimes { await updateDriveTimes(events, now: now) }
        scheduled = ReminderPlanner.plan(events, settings: settings, moved: Set(moved.keys),
                                         etas: settings.driveTimes ? etas : [:], now: now)
        let echoes = ReminderPlanner.echoes(events, settings: settings, now: now, room: ReminderPlanner.maxPending - scheduled.count)
        await PhoneNotifications.apply(scheduled + echoes, directions: settings.directionsApp)
        LiveActivityController.updateWidgets(upcoming: upcoming, now: now)
        await LiveActivityController.reconcile(upcoming: upcoming.filter(settings.alerts(for:)), enabled: settings.liveActivity, now: now)
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

    /// Sources (Apple Calendar accounts) that have calendars, in Settings order, for the per-source filter rules.
    var sources: [String] {
        var seen: [String] = []
        for c in calendars where !seen.contains(c.accountEmail) { seen.append(c.accountEmail) }
        return seen
    }

    /// `events` split by the event filters (Settings › Events).
    func meetingFeed(_ events: [CalendarEvent]) -> EventFilterResult {
        EventFilter.apply(events, settings: settings.filters)
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

    /// The stored event behind `event` with the store to edit it in, for Apple's event editor. Nil when its calendar is
    /// read-only (a subscribed work feed), which edits in Google Calendar instead.
    func editableEvent(for event: CalendarEvent) -> (event: EKEvent, store: EKEventStore)? {
        guard let e = client.editableEvent(for: event) else { return nil }
        return (e, client.eventStore)
    }

    /// The stored event behind `event` on any calendar, for Apple's invitation screen (the only way to send a reply).
    func storedEvent(for event: CalendarEvent) -> (event: EKEvent, store: EKEventStore)? {
        guard let e = client.storedEvent(for: event) else { return nil }
        return (e, client.eventStore)
    }

    /// Whether the calendar's copy of `event` belongs to a repeating series (Delete then asks: this one or all after it).
    func isRepeating(_ event: CalendarEvent) -> Bool { client.isRepeating(event) }

    /// Your reply to `event` as the calendar holds it now, which can be newer than `event` itself.
    func currentResponse(for event: CalendarEvent) -> AttendeeResponse? { client.selfResponse(for: event) }

    /// Deletes `event` (and, with `futureToo`, the rest of its series) at once, then refreshes in the background so the
    /// event screen can close straight away.
    func deleteEvent(_ event: CalendarEvent, futureToo: Bool) throws {
        try client.deleteEvent(event, futureToo: futureToo)
        noteDeleted(event)
        Task { await refresh() }
    }

    /// Records that `event` was deleted here (by the Delete key or Apple's editor), so it isn't announced as cancelled.
    /// Later meetings of its series are covered too: if they're still there, nothing is reported for them anyway.
    func noteDeleted(_ event: CalendarEvent) {
        // An Apple event's id is "<eventIdentifier>@<start>", shared by every occurrence up to the last "@".
        let base = event.id.lastIndex(of: "@").map { String(event.id[..<$0]) } ?? event.id
        locallyRemoved.append((prefix: "\(event.accountEmail)|\(event.calendarID)|\(base)@", from: event.start, at: Date()))
    }

    /// The calendar quick add picks first: the Calendar app's default for new events when Meetball can write to it.
    var defaultCalendarForNewEvents: GCalendar? {
        let id = client.defaultCalendarID
        return writableCalendars.first { $0.id == id } ?? writableCalendars.first
    }

    // MARK: Trips

    /// Whether `event` is somewhere to drive to (Directions), looks like one with no place yet (Where's this?), or
    /// neither.
    func tripStatus(for event: CalendarEvent, now: Date = Date()) -> TravelPlanner.Status {
        TravelPlanner.status(event, notTrips: settings.notTrips, now: now)
    }

    /// Places earlier or later meetings like `event` were at, nearest in time first.
    func placeSuggestions(for event: CalendarEvent) -> [String] {
        TravelPlanner.suggestions(for: event, history: events(in: TravelPlanner.historyRange(for: event)))
    }

    /// Whether a place picked for `event` can be saved to it (not on a read-only feed such as the work calendar).
    func canSavePlace(for event: CalendarEvent) -> Bool { client.editableEvent(for: event) != nil }

    /// Saves `place` as `event`'s location (and, with `futureToo`, the rest of its series'), then refreshes.
    func savePlace(_ place: TripPlace, for event: CalendarEvent, futureToo: Bool) throws {
        try client.setLocation(place.locationText, latitude: place.latitude, longitude: place.longitude,
                               for: event, futureToo: futureToo)
        Task { await refresh() }
    }

    /// Where's this? stops asking about `event` and meetings like it.
    func markNotTrip(_ event: CalendarEvent) {
        settings.notTrips.insert(TravelPlanner.tripKey(event))
    }

    /// Driving directions to `destination` in the app chosen in Settings (Google Maps unless changed).
    func openDirections(to destination: String) {
        if let url = settings.directionsApp.url(to: destination) { UIApplication.shared.open(url) }
    }

    /// The drive time to `event`'s place (`place` when it was just picked and the event hasn't reloaded yet). Nil
    /// when drive times are off or not worked out for that place.
    func eta(for event: CalendarEvent, place: String? = nil) -> TripETA? {
        guard settings.driveTimes, let eta = etas[event.uid],
              eta.destination == (place ?? TravelPlanner.physicalLocation(event)) else { return nil }
        return eta
    }

    /// When to leave for `event`: its start, less the drive and the time to park (Settings › Trips).
    func leaveBy(for event: CalendarEvent, place: String? = nil) -> Date? {
        eta(for: event, place: place).map { TravelPlanner.leaveBy(event, travel: $0.travelTime, bufferMinutes: settings.leaveBufferMinutes) }
    }

    /// Asks for location access (While Using), for drive times.
    func requestLocation() { travel.requestAccess() }

    /// Works out drive times for the next trips that have none, or an old one (every 10 minutes in the two hours before,
    /// so traffic is current), and drops those for trips that have gone. Asks for location the first time there's a trip
    /// while Meetball is open.
    private func updateDriveTimes(_ events: [CalendarEvent], now: Date) async {
        let trips = TravelPlanner.tripsNeedingTimes(events, now: now)
        var next = etas.filter { entry in trips.contains { $0.uid == entry.key } }
        defer { setETAs(next) }
        guard !trips.isEmpty else { return }
        if travel.authorization == .notDetermined {
            if UIApplication.shared.applicationState == .active { travel.requestAccess() }
            return
        }
        let stale = trips.filter { !TravelPlanner.isFresh(next[$0.uid], for: $0, now: now) }
        guard !stale.isEmpty, let origin = await travel.currentLocation() else { return }
        for e in stale {
            guard let place = TravelPlanner.physicalLocation(e) else { continue }
            // Traffic for when you'd leave: from the last drive time, or a guess of half an hour.
            let depart = TravelPlanner.leaveBy(e, travel: next[e.uid]?.travelTime ?? 30 * 60, bufferMinutes: settings.leaveBufferMinutes)
            if let time = await travel.travelTime(to: e, place: place, from: origin, departure: max(depart, now)) {
                next[e.uid] = TripETA(destination: place, travelTime: time, computedAt: now)
            }
        }
    }

    private func setETAs(_ new: [String: TripETA]) {
        guard new != etas else { return }
        etas = new
        if let data = try? JSONEncoder().encode(new) { defaults.set(data, forKey: Key.etas) }
    }

    private func locationChanged() {
        locationStatus = travel.authorization
        Task { await refresh() }
    }

    // MARK: Pre-flight and Echo

    /// The pre-flight brief for `event`: its people and links, and the last meeting like it in the past 90 days.
    func preFlight(for event: CalendarEvent) -> PreFlightBrief {
        PreFlight.brief(for: event, history: events(in: PreFlight.historyRange(for: event)))
    }

    /// The Echo notes left for `event`, newest first.
    func echoNotes(for event: CalendarEvent) -> [EchoNote] { Echo.notes(for: event, in: echoNotes) }

    /// Saves an Echo note for `event` and, when Settings says so, puts it on the to-do list. Returns the note as saved
    /// and why the to-do list failed, if it did; the note is kept in Meetball either way.
    @discardableResult
    func saveEcho(_ text: String, for event: CalendarEvent, now: Date = Date()) async -> (note: EchoNote?, problem: String?) {
        var note = Echo.note(for: event, text: text, now: now)
        guard !note.text.isEmpty else { return (nil, nil) }
        var problem: String?
        if settings.echoToReminders {
            do { note.reminderID = try await EchoReminders.add(note) } catch { problem = error.localizedDescription }
        }
        setEchoNotes([note] + echoNotes)
        // The nudge for this meeting has done its job.
        PhoneNotifications.center.removeDeliveredNotifications(withIdentifiers: [ReminderPlanner.idPrefix + "echo|" + event.uid])
        return (note, problem)
    }

    /// Puts a saved Echo note on the to-do list. Returns why it couldn't, if it couldn't.
    @discardableResult
    func addEchoToTodo(_ note: EchoNote) async -> String? {
        guard note.reminderID == nil else { return nil }
        do {
            let id = try await EchoReminders.add(note)
            setEchoNotes(echoNotes.map { n in
                guard n.id == note.id else { return n }
                var n = n
                n.reminderID = id
                return n
            })
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    /// Deletes an Echo note and the to-do made from it.
    func deleteEcho(_ note: EchoNote) {
        if let id = note.reminderID { EchoReminders.remove(id) }
        setEchoNotes(echoNotes.filter { $0.id != note.id })
    }

    /// Opens the recorder for the meeting an Echo nudge was about.
    func openEcho(_ request: EchoRequest) {
        echoRequest = request
    }

    /// The meeting behind an Echo nudge: the loaded event if it's still there, else one rebuilt from the nudge.
    func event(for request: EchoRequest) -> CalendarEvent {
        let around = DateInterval(start: request.start.addingTimeInterval(-3600), end: max(request.end, request.start).addingTimeInterval(3600))
        if let e = events(in: around).first(where: { $0.uid == request.uid }) { return e }
        let parts = request.uid.split(separator: "|", maxSplits: 2).map(String.init)
        return CalendarEvent(id: parts.count == 3 ? parts[2] : request.uid, calendarID: parts.count == 3 ? parts[1] : "",
                             accountEmail: parts.first ?? "", title: request.title, start: request.start, end: request.end,
                             isAllDay: false, meetURL: nil, location: nil, attendees: [], htmlLink: nil)
    }

    private func setEchoNotes(_ notes: [EchoNote]) {
        echoNotes = Array(notes.sorted { $0.createdAt > $1.createdAt }.prefix(Echo.keep))
        if let data = try? JSONEncoder().encode(echoNotes) { defaults.set(data, forKey: Key.echoNotes) }
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
