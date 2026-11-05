import Foundation
import AppKit
import SwiftUI
import UserNotifications

public protocol MeetingGuardianSoundPlaying { func play() }

public final class HardAlertSoundPlayer: MeetingGuardianSoundPlaying {
    public static let shared = HardAlertSoundPlayer()
    private var sound: NSSound?
    public func play() {
        sound = NSSound(named: "Sosumi") ?? NSSound(named: "Funk")
        sound?.play()
    }
}

/// Schedules and presents alerts for upcoming events. Resets timers whenever events/settings change.
@MainActor
public final class MeetingGuardianManager: NSObject, ObservableObject {
    let store: MeetingGuardianStore
    let subs: SubscriptionManager
    var sound: MeetingGuardianSoundPlaying = HardAlertSoundPlayer.shared
    private var timers: [Timer] = []
    private var fired = Set<String>()
    private var panels: [NSPanel] = []
    private var lastEvents: [CalendarEvent] = []
    private var joined = Set<String>()
    @Published var authorizationDenied = false

    init(store: MeetingGuardianStore, subs: SubscriptionManager) {
        self.store = store; self.subs = subs
        super.init()
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { [weak self] ok, _ in
            Task { @MainActor in self?.authorizationDenied = !ok }
        }
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let join = UNNotificationAction(identifier: Self.joinActionID, title: "Join", options: [.foreground])
        center.setNotificationCategories([UNNotificationCategory(identifier: Self.meetingCategoryID, actions: [join],
                                                                 intentIdentifiers: [], options: [])])
        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(self, selector: #selector(willSleep), name: NSWorkspace.willSleepNotification, object: nil)
        ws.addObserver(self, selector: #selector(willSleep), name: NSWorkspace.willPowerOffNotification, object: nil)
    }

    /// Effective style, enforcing Pro gating and per-calendar rules.
    func effectiveStyle(for e: CalendarEvent) -> AlertStyle? {
        var style = store.settings.style
        if subs.isPremiumActive, let r = store.rule(for: "\(e.accountEmail)|\(e.calendarID)") {
            guard let s = r.style else { return nil }
            style = s
        }
        return subs.isPremiumActive ? style : .soft
    }

    func reschedule(events: [CalendarEvent], now: Date = Date()) {
        lastEvents = events
        timers.forEach { $0.invalidate() }; timers = []
        let s = store.settings
        for e in events where !e.isAllDay && e.end > now {
            guard let style = effectiveStyle(for: e) else { continue }
            var leads = [subs.isPremiumActive ? s.leadMinutes : min(s.leadMinutes, 5)]
            if s.alsoAtFiveMinutes && subs.isPremiumActive { leads.append(5) }
            for lead in Set(leads) {
                schedule(e.start.addingTimeInterval(-Double(lead) * 60), key: "\(e.uid)|lead\(lead)", now: now) { [weak self] in
                    self?.present(e, style: style, lead: lead)
                }
            }
            if s.stillJoiningPrompt && subs.isPremiumActive && e.meetURL != nil {
                schedule(e.start.addingTimeInterval(120), key: "\(e.uid)|late", now: now) { [weak self] in
                    guard let self, !self.joined.contains(e.uid) else { return }
                    self.presentStillJoining(e)
                }
            }
        }
    }

    private func schedule(_ date: Date, key: String, now: Date, _ action: @escaping () -> Void) {
        guard date > now, !fired.contains(key) else { return }
        let t = Timer(fire: date, interval: 0, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.fired.insert(key)
                action()
            }
        }
        RunLoop.main.add(t, forMode: .common)
        timers.append(t)
    }

    private func outsideActiveHours(_ now: Date = Date()) -> Bool {
        let s = store.settings; guard s.limitToActiveHours else { return false }
        let h = Calendar.current.component(.hour, from: now)
        return h < s.activeStartHour || h >= s.activeEndHour
    }

    /// Best-effort heuristic: presence of screen-share indicator windows from common conferencing apps.
    func isScreenSharing() -> Bool {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else { return false }
        return list.contains { w in
            let owner = (w[kCGWindowOwnerName as String] as? String ?? "").lowercased()
            let name = (w[kCGWindowName as String] as? String ?? "").lowercased()
            return name.contains("sharing") || name.contains("you are sharing") || owner == "screensharingd" || name.contains("is sharing your screen")
        }
    }

    func present(_ e: CalendarEvent, style: AlertStyle, lead: Int) {
        var style = style
        if outsideActiveHours() || (store.settings.skipWhileScreenSharing && isScreenSharing()) { style = .soft }
        switch style {
        case .soft: postNotification(e, lead: lead)
        case .headsUp: showOverlay(e, hard: false, lead: lead)
        case .hard: showOverlay(e, hard: true, lead: lead)
        }
    }

    func postNotification(_ e: CalendarEvent, lead: Int) {
        let c = UNMutableNotificationContent()
        c.title = lead == 0 ? "It's time for your meeting" : "You have a meeting soon"
        c.body = "\(e.title) — \(lead == 0 ? "starting now" : "in \(lead) min")"
        c.sound = .default
        if store.settings.breakThroughFocus { c.interruptionLevel = .timeSensitive }
        if let u = e.meetURL { c.userInfo = ["url": u.absoluteString, "uid": e.uid]; c.categoryIdentifier = Self.meetingCategoryID }
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil))
    }

    func showOverlay(_ e: CalendarEvent, hard: Bool, lead: Int) {
        dismissOverlays()
        if hard && store.settings.playSound { sound.play() }
        let view = AlertOverlayHost(event: e, hard: hard, lead: lead,
                                    onJoin: { [weak self] in self?.join(e) }, onDismiss: { [weak self] in self?.dismissOverlays() })
        present(view: AnyView(view), fullscreen: hard)
    }

    func presentStillJoining(_ e: CalendarEvent) {
        let view = StillJoiningPromptView(event: e, onJoin: { [weak self] in self?.join(e) }, onDismiss: { [weak self] in self?.dismissOverlays() })
        present(view: AnyView(view), fullscreen: false)
    }

    func join(_ e: CalendarEvent) {
        joined.insert(e.uid)
        MeetingJoiner.join(e)
        dismissOverlays()
    }

    @objc private func willSleep() {
        guard store.settings.warnBeforeSleep,
              let e = lastEvents.first(where: { !$0.isAllDay && $0.start > Date() && $0.start.timeIntervalSinceNow < 600 }) else { return }
        let c = UNMutableNotificationContent()
        c.title = "Meeting starting soon"
        c.body = "\(e.title) starts in \(TimeUntilFormatter.string(until: e.start)). Your Mac is going to sleep."
        c.interruptionLevel = .timeSensitive
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "sleep", content: c, trigger: nil))
    }

    private func present(view: AnyView, fullscreen: Bool) {
        for screen in (fullscreen ? NSScreen.screens : [NSScreen.main ?? NSScreen.screens[0]]) {
            let frame = fullscreen ? screen.frame : NSRect(x: screen.frame.midX - 220, y: screen.frame.midY - 120, width: 440, height: 240)
            let p = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            p.level = fullscreen ? .screenSaver : .floating
            p.isOpaque = false; p.backgroundColor = .clear; p.hasShadow = true
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            p.contentView = NSHostingView(rootView: view)
            p.orderFrontRegardless()
            panels.append(p)
        }
    }

    func dismissOverlays() { panels.forEach { $0.orderOut(nil) }; panels = [] }
}

extension MeetingGuardianManager: UNUserNotificationCenterDelegate {
    nonisolated static let meetingCategoryID = "MEETING"
    nonisolated static let joinActionID = "JOIN"

    nonisolated public func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                                   withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        if response.actionIdentifier == Self.joinActionID, let s = info["url"] as? String, let url = URL(string: s) {
            let uid = info["uid"] as? String
            Task { @MainActor [weak self] in
                if let uid { self?.joined.insert(uid) }
                MeetingJoiner.join(url)
            }
        }
        completionHandler()
    }

    nonisolated public func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                                   withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
