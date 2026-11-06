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
    /// Echo: when a meeting ends, offer a 20-second voice note (and a notification to tap if Meetball isn't open).
    var echoMode: Bool = true
    /// Echo notes are also added to Reminders as follow-ups.
    var echoToReminders: Bool = true

    static let leadChoices = [1, 5, 10, 15]
    static let storageKey = "phone.settings"

    static func load(_ d: UserDefaults = .standard) -> PhoneSettings {
        guard let data = d.data(forKey: storageKey), let s = try? JSONDecoder().decode(Self.self, from: data) else { return .init() }
        return s
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
                  echoToReminders: try c.decodeIfPresent(Bool.self, forKey: .echoToReminders) ?? d.echoToReminders)
    }
}

/// One local notification to schedule ahead of a meeting.
struct PlannedReminder: Equatable, Identifiable {
    enum Kind: String { case lead, start, echo }

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

    /// Timed, accepted (not declined) meetings on visible calendars that start within `horizon`, earliest first, with a
    /// meeting that shows up on two calendars (a work calendar mirrored into iCloud, say) kept once.
    static func meetings(_ events: [CalendarEvent], settings: PhoneSettings, now: Date,
                         horizon: TimeInterval = horizon) -> [CalendarEvent] {
        let end = now.addingTimeInterval(horizon)
        var seen = Set<String>()
        return events
            .filter { !$0.isAllDay && !$0.isDeclined && !settings.hiddenCalendars.contains($0.calendarKey) && $0.end > now && $0.start <= end }
            .sorted { ($0.start, $0.title) < ($1.start, $1.title) }
            .filter { e in
                let key = "\(Int(e.start.timeIntervalSince1970))|\(MeetingChangeDetector.normalizedTitle(e.title))"
                return seen.insert(key).inserted
            }
    }

    /// The reminders for `events`. `moved` holds the uids of meetings that were rescheduled, so their reminder says so.
    static func plan(_ events: [CalendarEvent], settings: PhoneSettings, moved: Set<String> = [], now: Date) -> [PlannedReminder] {
        var out: [PlannedReminder] = []
        for e in meetings(events, settings: settings, now: now) where e.start > now {
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
        let out = meetings(events, settings: settings, now: now)
            .filter { $0.end > now && $0.end.timeIntervalSince($0.start) >= Echo.minMeetingLength }
            .map { PlannedReminder(kind: .echo, event: $0, fireDate: $0.end, title: "\($0.title) just ended", body: echoBody) }
        return Array(out.sorted { $0.fireDate < $1.fireDate }.prefix(room))
    }

    static let echoBody = "How did it go? Tap to leave a 20-second voice note for your follow-ups."

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
