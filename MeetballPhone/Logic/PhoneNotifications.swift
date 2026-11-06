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
        ])
    }

    /// Asks once; later calls return the current answer. `.carPlay` only matters if Apple ever grants Meetball the
    /// CarPlay entitlement, and is ignored until then.
    static func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound, .badge, .carPlay])) ?? false
    }

    static func settings() async -> UNNotificationSettings { await center.notificationSettings() }

    /// Replaces every scheduled meeting reminder with `plan`.
    static func apply(_ plan: [PlannedReminder]) async {
        let pending = await center.pendingNotificationRequests()
        let stale = pending.map(\.identifier).filter { $0.hasPrefix(ReminderPlanner.idPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: stale)
        for r in plan {
            let c = r.kind == .echo ? echoContent(r) : content(title: r.title, body: r.body, joinURL: r.event.meetURL)
            c.threadIdentifier = r.event.uid
            let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: r.fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: r.id, content: c, trigger: trigger))
        }
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
