import SwiftUI
import UIKit
import UserNotifications

/// Meetball for iPhone: the Mac app's calendar in your pocket (Today, Week, Month, quick add) with its SK-1 look and
/// its fun, plus the notifier: Time Sensitive reminders before each meeting, which Siri can announce in CarPlay, and
/// alerts when a meeting moves, gets a new link, or is cancelled.
@main
struct MeetballPhoneApp: App {
    @UIApplicationDelegateAdaptor(PhoneAppDelegate.self) private var appDelegate
    @StateObject private var store = PhoneStore.shared
    @Environment(\.scenePhase) private var phase
    @AppStorage(AppPreferences.Key.theme) private var themeRaw = AppTheme.system.rawValue

    var body: some Scene {
        WindowGroup {
            PhoneRootView()
                .environmentObject(store)
                .preferredColorScheme(colorScheme)
                .task { await store.start() }
                .onChange(of: phase) { _, newPhase in
                    switch newPhase {
                    case .active:
                        store.showPendingCelebration()
                        Task { await store.refresh(fresh: true) }
                    case .background: store.scheduleBackgroundRefresh()
                    default: break
                    }
                }
        }
        .backgroundTask(.appRefresh(PhoneStore.refreshTaskID)) {
            await PhoneStore.shared.backgroundRefresh()
        }
    }

    /// Settings › Appearance › Theme; nil follows the iPhone.
    private var colorScheme: ColorScheme? {
        switch AppTheme(rawValue: themeRaw) ?? .system {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
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
        } else if response.notification.request.content.categoryIdentifier == PhoneNotifications.echoCategory,
                  response.actionIdentifier != UNNotificationDismissActionIdentifier,
                  let uid = info[PhoneNotifications.echoUIDKey] as? String,
                  let start = info[PhoneNotifications.echoStartKey] as? Double,
                  let end = info[PhoneNotifications.echoEndKey] as? Double {
            // Tapping the Echo nudge (or Record a note) opens the recorder for that meeting.
            let request = EchoRequest(uid: uid, start: Date(timeIntervalSince1970: start), end: Date(timeIntervalSince1970: end),
                                      title: info[PhoneNotifications.echoTitleKey] as? String ?? "Meeting")
            Task { @MainActor in PhoneStore.shared.openEcho(request) }
        }
        completionHandler()
    }
}
