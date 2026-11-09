import Foundation
import AppKit
import SwiftUI
import UserNotifications

public protocol MeetingGuardianSoundPlaying { func play(named: String) }

public final class HardAlertSoundPlayer: MeetingGuardianSoundPlaying {
    public static let shared = HardAlertSoundPlayer()
    private var sound: NSSound?
    public func play(named name: String) {
        sound?.stop()
        sound = NSSound(named: NSSound.Name(name)) ?? NSSound(named: NSSound.Name(AlertSound.defaultName))
        sound?.play()
    }
}

/// The floating alert cards' panel. Borderless panels can't become key by default; alerts need to so Esc and Return
/// reach their buttons. A click anywhere on the card makes it key, so it works even when the card came up without focus
/// ("Still joining?", the change card) while another app is in front.
final class AlertPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// A borderless, transparent panel over every Space at `level`, taking clicks itself rather than letting them fall
    /// through its transparent pixels to the window underneath.
    static func make(frame: NSRect = .zero, level: NSWindow.Level) -> AlertPanel {
        let p = AlertPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.level = level
        p.isOpaque = false; p.backgroundColor = .clear
        p.hasShadow = false // the SwiftUI views draw their own
        p.isReleasedWhenClosed = false
        p.hidesOnDeactivate = false
        // Left to itself, a clear window lets clicks on its see-through pixels reach whatever is behind it.
        p.ignoresMouseEvents = false
        p.becomesKeyOnlyIfNeeded = false
        // Every Space, including over full-screen apps, and stays put when Spaces switch.
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        return p
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown || event.type == .rightMouseDown, !isKeyWindow { makeKey() }
        super.sendEvent(event)
    }
}

/// Hosts an alert card: its keys take the first click, without one click to focus the panel and another to press.
final class AlertHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// What the overlay buttons do. Previews get closures that only close the overlay.
struct AlertActions {
    var join: () -> Void
    var snooze: (Int) -> Void
    var dismiss: () -> Void
    var notJoining: () -> Void
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
    /// Snoozed alerts by event uid: when to show again, and how.
    private var snoozes: [String: (until: Date, style: AlertStyle)] = [:]
    public static let snoozePresets = [1, 5, 10]
    @Published var authorizationDenied = false

    init(store: MeetingGuardianStore, subs: SubscriptionManager) {
        self.store = store; self.subs = subs
        super.init()
        // First launch asks in context, on the setup assistant's alerts step; after that, ask (or re-read) at launch.
        if UserDefaults.standard.bool(forKey: OnboardingState.Key.completed) { requestAuthorization() } else { refreshAuthorization() }
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let join = UNNotificationAction(identifier: Self.joinActionID, title: "Join", options: [.foreground])
        center.setNotificationCategories([UNNotificationCategory(identifier: Self.meetingCategoryID, actions: [join],
                                                                 intentIdentifiers: [], options: [])])
        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(self, selector: #selector(willSleep), name: NSWorkspace.willSleepNotification, object: nil)
        ws.addObserver(self, selector: #selector(willSleep), name: NSWorkspace.willPowerOffNotification, object: nil)
    }

    /// Notification permission: allowed, denied, or not asked yet.
    @Published private(set) var notificationStatus: UNAuthorizationStatus = .notDetermined

    /// Asks for notification permission (macOS only shows the prompt the first time).
    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { [weak self] ok, _ in
            Task { @MainActor in
                self?.authorizationDenied = !ok
                self?.refreshAuthorization()
            }
        }
    }

    /// Re-reads the notification permission without asking.
    func refreshAuthorization() {
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            let status = settings.authorizationStatus
            Task { @MainActor in
                self?.notificationStatus = status
                self?.authorizationDenied = status == .denied
            }
        }
    }

    var policy: AlertPolicy {
        AlertPolicy(defaultStyle: store.settings.style, calendarRules: store.calendarRules,
                    importanceRules: store.importanceRules, isPro: subs.isPremiumActive,
                    alertOnEvents: Set(store.alertOnEvents.keys))
    }

    /// Effective style, enforcing Pro gating, per-calendar intensity and importance rules.
    func effectiveStyle(for e: CalendarEvent) -> AlertStyle? { policy.style(for: e) }

    /// The next alert that will fire across `events`, for the live summary in Settings.
    func nextAlert(in events: [CalendarEvent], now: Date = Date()) -> (event: CalendarEvent, fireDate: Date, style: AlertStyle)? {
        events.flatMap { e in plannedAlerts(for: e).filter { $0.fireDate > now }.map { (event: e, fireDate: $0.fireDate, style: $0.style) } }
            .min { $0.fireDate < $1.fireDate }
    }

    /// Minutes-before-start at which alerts fire, given the current settings and plan.
    var leadMinutes: [Int] {
        let s = store.settings
        var leads = [subs.isPremiumActive ? s.leadMinutes : min(s.leadMinutes, 5)]
        if s.alsoAtFiveMinutes && subs.isPremiumActive { leads.append(5) }
        return Array(Set(leads)).sorted(by: >)
    }

    /// The alerts that will fire for `e` (empty when muted, all-day, or the calendar's rule turns them off).
    func plannedAlerts(for e: CalendarEvent) -> [(fireDate: Date, lead: Int, style: AlertStyle)] {
        guard !e.isAllDay, !store.isMuted(e), let style = effectiveStyle(for: e) else { return [] }
        return leadMinutes.map { (fireDate: e.start.addingTimeInterval(-Double($0) * 60), lead: $0, style: style) }
    }

    func reschedule(events: [CalendarEvent], now: Date = Date()) {
        lastEvents = events
        timers.forEach { $0.invalidate() }; timers = []
        snoozes = snoozes.filter { $0.value.until > now }
        let s = store.settings
        for e in events where !e.isAllDay && e.end > now && !store.isMuted(e) {
            guard let style = effectiveStyle(for: e) else { continue }
            for lead in leadMinutes {
                schedule(e.start.addingTimeInterval(-Double(lead) * 60), key: "\(e.uid)|\(Int(e.start.timeIntervalSince1970))|lead\(lead)", now: now) { [weak self] in
                    self?.present(e, style: style, lead: lead)
                }
            }
            if let z = snoozes[e.uid], z.until > now {
                schedule(z.until, key: "\(e.uid)|snooze\(Int(z.until.timeIntervalSince1970))", now: now) { [weak self] in
                    self?.snoozes[e.uid] = nil
                    self?.present(e, style: z.style, lead: max(0, Int((e.start.timeIntervalSinceNow / 60).rounded(.up))))
                }
            }
            if s.stillJoiningPrompt && subs.isPremiumActive && e.meetURL != nil {
                schedule(e.start.addingTimeInterval(120), key: "\(e.uid)|\(Int(e.start.timeIntervalSince1970))|late", now: now) { [weak self] in
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
        let h = Calendar.app.component(.hour, from: now)
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

    func postNotification(_ e: CalendarEvent, lead: Int, preview: Bool = false) {
        let c = UNMutableNotificationContent()
        c.title = preview ? "Preview: soft reminder" : (lead == 0 ? "It's time for your meeting" : "You have a meeting soon")
        c.body = "\(e.title) — \(lead == 0 ? "starting now" : "in \(lead) min")"
        c.sound = .default
        if store.settings.breakThroughFocus { c.interruptionLevel = .timeSensitive }
        if let u = e.meetURL, !preview { c.userInfo = ["url": u.absoluteString, "uid": e.uid]; c.categoryIdentifier = Self.meetingCategoryID }
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil))
    }

    func showOverlay(_ e: CalendarEvent, hard: Bool, lead: Int) {
        let style: AlertStyle = hard ? .hard : .headsUp
        showOverlay(e, style: style, actions: AlertActions(
            join: { [weak self] in self?.join(e) },
            snooze: { [weak self] m in self?.snooze(e, style: style, minutes: m) },
            dismiss: { [weak self] in self?.dismissOverlays() },
            notJoining: { [weak self] in self?.notJoining(e) }))
    }

    private func showOverlay(_ e: CalendarEvent, style: AlertStyle, actions: AlertActions) {
        dismissOverlays(animated: false)
        if style == .hard {
            if store.settings.playSound { sound.play(named: store.settings.soundName) }
            for screen in NSScreen.screens {
                // Only the screen under the pointer gets keyboard focus; the others mirror it.
                let focused = screen == Self.activeScreen
                present(view: AnyView(HardAlertView(event: e, actions: actions, takesFocus: focused)), on: screen, fullscreen: true, key: focused)
            }
        } else {
            present(view: AnyView(HeadsUpAlertCard(event: e, mode: .upcoming, actions: actions)), on: Self.activeScreen, fullscreen: false, key: false)
        }
    }

    /// Shows a sample alert so the user can see what each style looks like. Buttons only close it.
    func preview(_ style: AlertStyle) {
        let now = Date()
        let sample = CalendarEvent(id: "preview", calendarID: "preview", accountEmail: "preview", title: "Design review",
                                   start: now.addingTimeInterval(2 * 60 + 30), end: now.addingTimeInterval(32 * 60 + 30), isAllDay: false,
                                   meetURL: URL(string: "https://meet.google.com/abc-defg-hij"), location: "Room 4 · 2nd floor",
                                   attendees: ["ana@example.com", "ben@example.com", "chi@example.com"], htmlLink: nil, colorHex: "#7C4DFF",
                                   organizer: "Ana Ruiz")
        let close: () -> Void = { [weak self] in self?.dismissOverlays() }
        let actions = AlertActions(join: close, snooze: { _ in close() }, dismiss: close, notJoining: close)
        switch style {
        case .soft:
            postNotification(sample, lead: 2, preview: true)
        case .headsUp, .hard:
            showOverlay(sample, style: style, actions: actions)
        }
    }

    func previewSound() { sound.play(named: store.settings.soundName) }

    func presentStillJoining(_ e: CalendarEvent) {
        dismissOverlays(animated: false)
        let actions = AlertActions(join: { [weak self] in self?.join(e) }, snooze: { _ in },
                                   dismiss: { [weak self] in self?.dismissOverlays() }, notJoining: { [weak self] in self?.notJoining(e) })
        present(view: AnyView(HeadsUpAlertCard(event: e, mode: .stillJoining, actions: actions)), on: Self.activeScreen, fullscreen: false, key: false)
    }

    func join(_ e: CalendarEvent) {
        joined.insert(e.uid)
        MeetingJoiner.join(e)
        dismissOverlays()
    }

    /// Hide the alert and show it again in `minutes` (same style).
    func snooze(_ e: CalendarEvent, style: AlertStyle, minutes: Int) {
        snoozes[e.uid] = (Date().addingTimeInterval(Double(minutes) * 60), style)
        dismissOverlays()
        reschedule(events: lastEvents)
    }

    /// "I'm not joining": no more alerts or prompts for this meeting.
    func notJoining(_ e: CalendarEvent) {
        snoozes[e.uid] = nil
        store.setMuted(true, for: e)
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

    /// The screen under the pointer (where the user is looking), else the main screen.
    static var activeScreen: NSScreen {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]
    }

    private func present(view: AnyView, on screen: NSScreen, fullscreen: Bool, key: Bool) {
        let host = AlertHostingView(rootView: view)
        let frame: NSRect
        if fullscreen {
            frame = screen.frame
        } else {
            // Top-right corner, just under the menu bar (and clear of the notch on built-in displays).
            let size = host.fittingSize
            let area = screen.visibleFrame
            frame = NSRect(x: area.maxX - size.width - 8, y: area.maxY - size.height - 8, width: size.width, height: size.height)
        }
        let p = AlertPanel.make(frame: frame, level: fullscreen ? .screenSaver : .floating)
        p.contentView = host
        p.setFrame(frame, display: false)
        if key {
            // A non-activating panel can take key focus without bringing Meetball's other windows forward.
            p.makeKeyAndOrderFront(nil)
        } else {
            p.orderFrontRegardless()
        }
        panels.append(p)
    }

    func dismissOverlays() { dismissOverlays(animated: true) }

    private func dismissOverlays(animated: Bool) {
        let closing = panels
        panels = []
        guard animated, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            closing.forEach { $0.orderOut(nil) }
            return
        }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            for p in closing { p.animator().alphaValue = 0 }
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(220))
            closing.forEach { $0.orderOut(nil) }
        }
    }
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
