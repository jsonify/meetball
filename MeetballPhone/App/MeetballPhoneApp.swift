import SwiftUI
import UIKit
import UserNotifications

/// Meetball for iPhone: a meeting notifier. It reads Apple Calendar and schedules Time Sensitive reminders before each
/// meeting, so Siri can announce them in CarPlay, and alerts when a meeting moves, gets a new link, or is cancelled.
@main
struct MeetballPhoneApp: App {
    @UIApplicationDelegateAdaptor(PhoneAppDelegate.self) private var appDelegate
    @StateObject private var store = PhoneStore.shared
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            PhoneHomeView()
                .environmentObject(store)
                .task { await store.start() }
                .onChange(of: phase) { _, newPhase in
                    switch newPhase {
                    case .active: Task { await store.refresh(fresh: true) }
                    case .background: store.scheduleBackgroundRefresh()
                    default: break
                    }
                }
        }
        .backgroundTask(.appRefresh(PhoneStore.refreshTaskID)) {
            await PhoneStore.shared.backgroundRefresh()
        }
    }
}

/// Shows alerts while Meetball is open, and opens the meeting for the Join action.
final class PhoneAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        if response.actionIdentifier == PhoneNotifications.joinAction,
           let link = info[PhoneNotifications.joinURLKey] as? String, let url = URL(string: link) {
            DispatchQueue.main.async { UIApplication.shared.open(url) }
        }
        completionHandler()
    }
}
