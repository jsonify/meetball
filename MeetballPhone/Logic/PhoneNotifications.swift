import Foundation
import UserNotifications

/// Local notifications for the iPhone notifier. Every alert is Time Sensitive: that lets it through Focus (Driving
/// included) and is what lets Siri announce it in CarPlay and on AirPods without Meetball being a CarPlay app.
enum PhoneNotifications {
    static let meetingCategory = "meetball.meeting"
    static let joinAction = "meetball.join"
    static let joinURLKey = "joinURL"
    static let echoCategory = "meetball.echo"
    static let echoAction = "meetball.echo.record"
    static let echoUIDKey = "echoUID"
    static let echoStartKey = "echoStart"
    static let echoEndKey = "echoEnd"
    static let echoTitleKey = "echoTitle"
    static let leaveCategory = "meetball.leave"
    static let directionsAction = "meetball.directions"
    static let directionsURLKey = "directionsURL"
    static let changePrefix = "meetball.change|"
    static let testID = "meetball.test"

    static var center: UNUserNotificationCenter { .current() }

    static func registerCategories() {
        let join = UNNotificationAction(identifier: joinAction, title: "Join", options: [.foreground])
        center.setNotificationCategories([
            UNNotificationCategory(identifier: meetingCategory, actions: [join], intentIdentifiers: [], options: []),
            UNNotificationCategory(identifier: echoCategory,
                                   actions: [UNNotificationAction(identifier: echoAction, title: "Record a note",
                                                                  options: [.foreground],
                                                                  icon: UNNotificationActionIcon(systemImageName: "mic.fill"))],
                                   intentIdentifiers: [], options: []),
            UNNotificationCategory(identifier: leaveCategory,
                                   actions: [UNNotificationAction(identifier: directionsAction, title: "Directions",
                                                                  options: [.foreground],
                                                                  icon: UNNotificationActionIcon(systemImageName: "car.fill"))],
                                   intentIdentifiers: [], options: []),
        ])
    }

    /// Asks once; later calls return the current answer. `.carPlay` only matters if Apple ever grants Meetball the
    /// CarPlay entitlement, and is ignored until then.
    static func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound, .badge, .carPlay])) ?? false
    }

    static func settings() async -> UNNotificationSettings { await center.notificationSettings() }

    /// Replaces every scheduled meeting reminder with `plan`. `directions` opens a trip's place in the chosen maps app
    /// (from a Leave now alert).
    ///
    /// Only what changed is touched: reminders no longer planned are removed, new or changed ones are added (adding
    /// under an existing identifier replaces it), and ones already scheduled exactly as planned are left alone. Most
    /// refreshes change nothing, so this usually does no work at all instead of rescheduling up to 48 reminders.
    static func apply(_ plan: [PlannedReminder], directions: DirectionsApp = .googleMaps) async {
        let wanted = plan.map { request(for: $0, directions: directions) }
        let pending = await center.pendingNotificationRequests().filter { $0.identifier.hasPrefix(ReminderPlanner.idPrefix) }
        let wantedIDs = Set(wanted.map(\.identifier))
        let stale = pending.map(\.identifier).filter { !wantedIDs.contains($0) }
        if !stale.isEmpty { center.removePendingNotificationRequests(withIdentifiers: stale) }
        let current = Dictionary(pending.map { ($0.identifier, $0) }, uniquingKeysWith: { first, _ in first })
        for r in wanted {
            if let existing = current[r.identifier], isSame(existing, r) { continue }
            try? await center.add(r)
        }
    }

    static func request(for r: PlannedReminder, directions: DirectionsApp) -> UNNotificationRequest {
        let c: UNMutableNotificationContent
        switch r.kind {
        case .echo: c = echoContent(r)
        case .leave: c = leaveContent(r, directions: directions)
        case .lead, .start: c = content(title: r.title, body: r.body, joinURL: r.event.meetURL)
        }
        c.threadIdentifier = r.event.uid
        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: r.fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        return UNNotificationRequest(identifier: r.id, content: c, trigger: trigger)
    }

    /// Whether a pending request would fire at the same moment with the same alert. Anything not compared equal is
    /// simply scheduled again, as every refresh used to do.
    static func isSame(_ a: UNNotificationRequest, _ b: UNNotificationRequest) -> Bool {
        guard a.identifier == b.identifier,
              let ta = a.trigger as? UNCalendarNotificationTrigger, let tb = b.trigger as? UNCalendarNotificationTrigger,
              ta.dateComponents == tb.dateComponents, ta.repeats == tb.repeats else { return false }
        let ca = a.content, cb = b.content
        return ca.title == cb.title && ca.body == cb.body
            && ca.categoryIdentifier == cb.categoryIdentifier && ca.threadIdentifier == cb.threadIdentifier
            && ca.interruptionLevel == cb.interruptionLevel && ca.relevanceScore == cb.relevanceScore
            && (ca.sound == nil) == (cb.sound == nil)
            && NSDictionary(dictionary: ca.userInfo).isEqual(to: cb.userInfo)
    }

    /// Shows a change alert now.
    static func postChange(title: String, body: String) async {
        let c = content(title: title, body: body, joinURL: nil)
        c.threadIdentifier = "meetball.changes"
        try? await center.add(UNNotificationRequest(identifier: changePrefix + UUID().uuidString, content: c, trigger: nil))
    }

    /// A sample reminder after `delay` seconds, to check how it sounds in the car.
    static func sendTest(after delay: TimeInterval, now: Date = Date()) async {
        let start = now.addingTimeInterval(10 * 60)
        let c = content(title: "Meetball test", body: "Starts in 10 min · \(start.shortTime). This is how your meeting alerts will sound.",
                        joinURL: nil)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, delay), repeats: false)
        try? await center.add(UNNotificationRequest(identifier: testID, content: c, trigger: trigger))
    }

    /// The Echo nudge as a meeting ends: an ordinary alert (not Time Sensitive, it can wait), opening the recorder.
    static func echoContent(_ r: PlannedReminder) -> UNMutableNotificationContent {
        let c = UNMutableNotificationContent()
        c.title = r.title
        c.body = r.body
        c.sound = .default
        c.interruptionLevel = .active
        c.relevanceScore = 0.5
        c.categoryIdentifier = echoCategory
        c.userInfo = [echoUIDKey: r.event.uid, echoStartKey: r.event.start.timeIntervalSince1970,
                      echoEndKey: r.event.end.timeIntervalSince1970, echoTitleKey: r.event.title]
        return c
    }

    /// Leave now: Time Sensitive like a meeting reminder (Siri reads it in CarPlay); tapping it, or Directions, opens
    /// the drive in the maps app.
    static func leaveContent(_ r: PlannedReminder, directions: DirectionsApp) -> UNMutableNotificationContent {
        let c = content(title: r.title, body: r.body, joinURL: nil)
        if let place = TravelPlanner.physicalLocation(r.event), let url = directions.url(to: place) {
            c.categoryIdentifier = leaveCategory
            c.userInfo = [directionsURLKey: url.absoluteString]
        }
        return c
    }

    static func content(title: String, body: String, joinURL: URL?) -> UNMutableNotificationContent {
        let c = UNMutableNotificationContent()
        c.title = title
        c.body = body
        c.sound = .default
        c.interruptionLevel = .timeSensitive
        c.relevanceScore = 1
        if let joinURL {
            c.categoryIdentifier = meetingCategory
            c.userInfo = [joinURLKey: joinURL.absoluteString]
        }
        return c
    }
}
