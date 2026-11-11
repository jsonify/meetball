import Foundation

/// What the iPhone notifier alerts about (saved in UserDefaults).
struct PhoneSettings: Codable, Equatable {
    /// Minutes before a meeting the reminder fires.
    var leadMinutes: Int = 10
    /// A second alert when the meeting starts.
    var alertAtStart: Bool = false
    /// Alerts when a meeting moves, gets a new join link, or is cancelled.
    var notifyChanges: Bool = true
    /// Calendar keys (`GCalendar.key`) the user switched off.
    var hiddenCalendars: Set<String> = []
    /// Confetti when a meeting is cancelled.
    var celebrateCancellations: Bool = true
    /// The countdown Live Activity (Lock Screen, Dynamic Island) in the hour before a meeting.
    var liveActivity: Bool = true
    /// A full-screen countdown with haptics in the last minute before a meeting, while Meetball is open.
    var countdownMoment: Bool = true
    /// The pre-flight card five minutes before a meeting: who's in it, the last meeting with them, the invite's links.
    var preFlight: Bool = true
    /// Echo: when a meeting ends, offer a voice note (and a notification to tap if Meetball isn't open).
    var echoMode: Bool = true
    /// Echo notes are also added to Reminders as follow-ups.
    var echoToReminders: Bool = true
    /// The Today tab (the MB-1 display and agenda). Off by default: the app opens on the Day grid, which has the next
    /// meeting on top.
    var showTodayTab: Bool = false
    /// Calendar keys whose meetings stay visible but never alert (a family calendar, say).
    var silencedCalendars: Set<String> = []
    /// Meetings on a silenced calendar that alert anyway, keyed by event uid, valued by the meeting's end.
    var alertOnEvents: [String: Date] = [:]
    /// Meetings on any other calendar whose alerts were turned off, keyed by event uid, valued by the meeting's end.
    var mutedEvents: [String: Date] = [:]
    /// The app Directions opens for a meeting's place.
    var directionsApp: DirectionsApp = .googleMaps
    /// Meetings Where's this? stops asking about (`TravelPlanner.tripKey`: a series, or a title like "Soccer").
    var notTrips: Set<String> = []
    /// Drive times and leave-by times for trips, from where the iPhone is (needs location access).
    var driveTimes: Bool = true
    /// A "Leave now" alert at each trip's leave-by time, with a Directions action.
    var leaveAlerts: Bool = true
    /// Minutes added to the drive to park and walk in.
    var leaveBufferMinutes: Int = 5
    /// The Mac's meeting-first rules (hide declined, all-day, no link, only you, ignored keywords; fade tentative), with
    /// per-source overrides. They decide what Today, Up next, alerts, widgets and the Live Activity care about; the Day,
    /// Week and Month grids still show everything.
    var filters = EventFilterSettings()

    /// Whether the meeting-first rules leave `e` out.
    func isFiltered(_ e: CalendarEvent) -> Bool { EventFilter.hideReason(e, settings: filters) != nil }

    static let leadChoices = [1, 5, 10, 15]
    static let storageKey = "phone.settings"

    static func load(_ d: UserDefaults = .standard, now: Date = Date()) -> PhoneSettings {
        guard let data = d.data(forKey: storageKey), var s = try? JSONDecoder().decode(Self.self, from: data) else { return .init() }
        s.alertOnEvents = s.alertOnEvents.filter { $0.value > now }
        s.mutedEvents = s.mutedEvents.filter { $0.value > now }
        return s
    }

    /// Whether `e` alerts: its own choice first, then its calendar's.
    func alerts(for e: CalendarEvent) -> Bool {
        if mutedEvents[e.uid] != nil { return false }
        return !silencedCalendars.contains(e.calendarKey) || alertOnEvents[e.uid] != nil
    }

    func isSilenced(_ e: CalendarEvent) -> Bool { silencedCalendars.contains(e.calendarKey) }

    /// Turns alerts for just `e` on or off, overriding its calendar.
    mutating func setAlerts(_ on: Bool, for e: CalendarEvent) {
        if isSilenced(e) {
            mutedEvents[e.uid] = nil
            alertOnEvents[e.uid] = on ? e.end : nil
        } else {
            alertOnEvents[e.uid] = nil
            mutedEvents[e.uid] = on ? nil : e.end
        }
    }

    func save(_ d: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) { d.set(data, forKey: Self.storageKey) }
    }
}

extension PhoneSettings {
    /// Settings saved by an older build lack the newer keys; each missing one takes its default, so an update keeps
    /// everything else (calendars switched off, say).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = PhoneSettings()
        self.init(leadMinutes: try c.decodeIfPresent(Int.self, forKey: .leadMinutes) ?? d.leadMinutes,
                  alertAtStart: try c.decodeIfPresent(Bool.self, forKey: .alertAtStart) ?? d.alertAtStart,
                  notifyChanges: try c.decodeIfPresent(Bool.self, forKey: .notifyChanges) ?? d.notifyChanges,
                  hiddenCalendars: try c.decodeIfPresent(Set<String>.self, forKey: .hiddenCalendars) ?? d.hiddenCalendars,
                  celebrateCancellations: try c.decodeIfPresent(Bool.self, forKey: .celebrateCancellations)
                    ?? d.celebrateCancellations,
                  liveActivity: try c.decodeIfPresent(Bool.self, forKey: .liveActivity) ?? d.liveActivity,
                  countdownMoment: try c.decodeIfPresent(Bool.self, forKey: .countdownMoment) ?? d.countdownMoment,
                  preFlight: try c.decodeIfPresent(Bool.self, forKey: .preFlight) ?? d.preFlight,
                  echoMode: try c.decodeIfPresent(Bool.self, forKey: .echoMode) ?? d.echoMode,
                  echoToReminders: try c.decodeIfPresent(Bool.self, forKey: .echoToReminders) ?? d.echoToReminders,
                  showTodayTab: try c.decodeIfPresent(Bool.self, forKey: .showTodayTab) ?? d.showTodayTab,
                  silencedCalendars: try c.decodeIfPresent(Set<String>.self, forKey: .silencedCalendars) ?? d.silencedCalendars,
                  alertOnEvents: try c.decodeIfPresent([String: Date].self, forKey: .alertOnEvents) ?? d.alertOnEvents,
                  mutedEvents: try c.decodeIfPresent([String: Date].self, forKey: .mutedEvents) ?? d.mutedEvents,
                  // An app name this build doesn't know (from a newer one) falls back to the default.
                  directionsApp: (try? c.decodeIfPresent(DirectionsApp.self, forKey: .directionsApp)) ?? d.directionsApp,
                  notTrips: try c.decodeIfPresent(Set<String>.self, forKey: .notTrips) ?? d.notTrips,
                  driveTimes: try c.decodeIfPresent(Bool.self, forKey: .driveTimes) ?? d.driveTimes,
                  leaveAlerts: try c.decodeIfPresent(Bool.self, forKey: .leaveAlerts) ?? d.leaveAlerts,
                  leaveBufferMinutes: try c.decodeIfPresent(Int.self, forKey: .leaveBufferMinutes) ?? d.leaveBufferMinutes,
                  filters: (try? c.decodeIfPresent(EventFilterSettings.self, forKey: .filters)) ?? d.filters)
    }
}

/// One local notification to schedule ahead of a meeting.
struct PlannedReminder: Equatable, Identifiable {
    enum Kind: String { case lead, start, echo, leave }

    var kind: Kind
    var event: CalendarEvent
    var fireDate: Date
    var title: String
    var body: String
    var id: String { ReminderPlanner.idPrefix + kind.rawValue + "|" + event.uid }
}

/// A change alert that was shown, kept for the "Recent changes" list.
struct RecentChange: Codable, Equatable, Identifiable {
    var id = UUID()
    var title: String
    var body: String
    var at: Date
}

/// Works out which reminders to schedule. iOS can't run Meetball in the background on demand, so every reminder is
/// handed to the system ahead of time as a local notification; each refresh replaces the whole set.
enum ReminderPlanner {
    static let idPrefix = "meetball.reminder|"
    /// How far ahead reminders are scheduled. Later meetings are picked up by the next refresh.
    static let horizon: TimeInterval = 48 * 3600
    /// iOS keeps at most 64 pending notifications per app; leave room for change alerts and the test alert.
    static let maxPending = 48

    /// Timed, accepted (not declined) meetings on visible calendars that start within `horizon` and pass the event
    /// filters, earliest first, with a meeting that shows up on two calendars (a work calendar mirrored into iCloud, say)
    /// kept once.
    static func meetings(_ events: [CalendarEvent], settings: PhoneSettings, now: Date,
                         horizon: TimeInterval = horizon) -> [CalendarEvent] {
        let end = now.addingTimeInterval(horizon)
        var seen = Set<String>()
        return events
            .filter { !$0.isAllDay && !$0.isDeclined && !settings.hiddenCalendars.contains($0.calendarKey) && $0.end > now && $0.start <= end }
            .filter { !settings.isFiltered($0) }
            .sorted { ($0.start, $0.title) < ($1.start, $1.title) }
            .filter { e in
                let key = "\(Int(e.start.timeIntervalSince1970))|\(MeetingChangeDetector.normalizedTitle(e.title))"
                return seen.insert(key).inserted
            }
    }

    /// The reminders for `events`. `moved` holds the uids of meetings that were rescheduled, so their reminder says so.
    /// `meetings` without those whose alerts are off (a silenced calendar, or muted one by one).
    static func alerting(_ events: [CalendarEvent], settings: PhoneSettings, now: Date,
                         horizon: TimeInterval = horizon) -> [CalendarEvent] {
        meetings(events, settings: settings, now: now, horizon: horizon).filter(settings.alerts(for:))
    }

    /// `etas` holds drive times by event uid: a trip with one also gets a "Leave now" alert at its leave-by time.
    static func plan(_ events: [CalendarEvent], settings: PhoneSettings, moved: Set<String> = [],
                     etas: [String: TripETA] = [:], now: Date) -> [PlannedReminder] {
        var out: [PlannedReminder] = []
        for e in alerting(events, settings: settings, now: now) where e.start > now {
            if let leave = leaveAlert(e, settings: settings, eta: etas[e.uid], now: now) { out.append(leave) }
            let lead = e.start.addingTimeInterval(-Double(settings.leadMinutes) * 60)
            if lead > now {
                out.append(PlannedReminder(kind: .lead, event: e, fireDate: lead, title: e.title,
                                           body: body(e, kind: .lead, settings: settings, moved: moved.contains(e.uid))))
            }
            if settings.alertAtStart {
                out.append(PlannedReminder(kind: .start, event: e, fireDate: e.start, title: e.title,
                                           body: body(e, kind: .start, settings: settings, moved: moved.contains(e.uid))))
            }
        }

        return Array(out.sorted { $0.fireDate < $1.fireDate }.prefix(maxPending))
    }

    /// "Leave now for Soccer" / "24 min drive to Riverside Park · starts 6:00 PM", at the trip's leave-by time. Nil when
    /// leave alerts are off, there's no drive time for the event's current place, or the time has passed.
    static func leaveAlert(_ e: CalendarEvent, settings: PhoneSettings, eta: TripETA?, now: Date) -> PlannedReminder? {
        guard settings.driveTimes, settings.leaveAlerts, let eta, let place = TravelPlanner.physicalLocation(e),
              eta.destination == place else { return nil }
        let at = TravelPlanner.leaveBy(e, travel: eta.travelTime, bufferMinutes: settings.leaveBufferMinutes)
        guard at > now else { return nil }
        return PlannedReminder(kind: .leave, event: e, fireDate: at, title: "Leave now for \(e.title)",
                               body: "\(TravelPlanner.driveText(eta.travelTime)) to \(place) · starts \(e.start.shortTime)")
    }

    /// "Starts in 10 min · 1:00 PM", or "Moved to 1:00 PM · Starts in 10 min" for a rescheduled meeting (which Siri
    /// reads out first, so the move isn't missed).
    static func body(_ e: CalendarEvent, kind: PlannedReminder.Kind, settings: PhoneSettings, moved: Bool) -> String {
        let when = kind == .lead ? "Starts in \(minutes(settings.leadMinutes))" : "Starting now"
        return moved ? "Moved to \(e.start.shortTime) · \(when)" : "\(when) · \(e.start.shortTime)"
    }

    /// Echo: a nudge as each meeting ends to leave a voice note (tapping it opens the recorder). Scheduled with the
    /// reminders, which come first when iOS's limit on pending alerts is reached.
    static func echoes(_ events: [CalendarEvent], settings: PhoneSettings, now: Date, room: Int = maxPending) -> [PlannedReminder] {
        guard settings.echoMode, room > 0 else { return [] }
        let out = alerting(events, settings: settings, now: now)
            .filter { $0.end > now && $0.end.timeIntervalSince($0.start) >= Echo.minMeetingLength }
            .map { PlannedReminder(kind: .echo, event: $0, fireDate: $0.end, title: "\($0.title) just ended", body: echoBody) }
        return Array(out.sorted { $0.fireDate < $1.fireDate }.prefix(room))
    }

    static let echoBody = "How did it go? Tap to leave a voice note for your follow-ups."

    static func minutes(_ n: Int) -> String { n == 1 ? "1 min" : "\(n) min" }

    /// The alert for changes found by a refresh. The Mac's party emoji is left off: Siri reads it aloud.
    static func changeAlert(_ changes: [MeetingChange], now: Date) -> (title: String, body: String)? {
        guard !changes.isEmpty else { return nil }
        if changes.count == 1, let c = changes.first {
            return (spoken(MeetingChangeText.title(c)), MeetingChangeText.body(c, now: now))
        }
        let s = MeetingChangeText.summary(changes)
        return (spoken(s.title), s.body)
    }

    static func spoken(_ s: String) -> String {
        s.replacingOccurrences(of: "\u{1F389}", with: "").trimmingCharacters(in: .whitespaces)
    }

    /// The uids of rescheduled meetings after `changes`, dropping meetings that have ended or are no longer loaded.
    static func movedUIDs(_ previous: [String: Date], changes: [MeetingChange], now: Date) -> [String: Date] {
        var out = previous.filter { $0.value > now }
        for c in changes {
            if case .rescheduled = c.kind { out[c.event.uid] = c.event.end }
        }
        return out
    }
}
