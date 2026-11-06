import AppKit
import SwiftUI
import UserNotifications
import SK1Tokens
import SK1UI

/// Tells the user when an upcoming meeting moves, gets a new link, or is cancelled, and celebrates cancellations (#30).
@MainActor
final class MeetingChangeNotifier {
    private let store: MeetingGuardianStore

    init(store: MeetingGuardianStore) { self.store = store }

    func handle(_ changes: [MeetingChange], now: Date = Date()) {
        let s = store.settings
        // A silenced calendar (set to Off) stays quiet about changes too, unless that event was turned back on.
        let changes = changes.filter { !store.isCalendarSilenced($0.event) || store.isAlertOn($0.event) }
        guard s.notifyChanges, !changes.isEmpty else { return }
        if s.changeCard { MeetingChangeCardPanel.show(changes) }
        let c = UNMutableNotificationContent()
        if changes.count == 1, let change = changes.first {
            c.title = MeetingChangeText.title(change)
            c.body = MeetingChangeText.body(change, now: now)
        } else {
            let summary = MeetingChangeText.summary(changes)
            c.title = summary.title; c.body = summary.body
        }
        c.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil))
        if s.celebrateCancellations, let cancelled = changes.first(where: \.isCancellation) {
            CelebrationOverlay.show(title: cancelled.event.title,
                                    extra: changes.filter(\.isCancellation).count - 1)
        }
    }
}

/// Confetti over the screen under the pointer and an LCD card saying the meeting is off. Click-through, and gone after a
/// few seconds; with Reduce Motion only the card shows.
@MainActor
enum CelebrationOverlay {
    private static var panel: NSPanel?
    static let duration: TimeInterval = 4.5

    static func show(title: String, extra: Int = 0) {
        panel?.orderOut(nil)
        let screen = MeetingGuardianManager.activeScreen
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let host = NSHostingView(rootView: CelebrationView(title: title, extra: extra, confetti: !reduceMotion, start: Date()))
        let p = NSPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.level = .statusBar
        p.isOpaque = false; p.backgroundColor = .clear; p.hasShadow = false
        p.ignoresMouseEvents = true
        p.isReleasedWhenClosed = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        p.contentView = host
        p.setFrame(screen.frame, display: false)
        p.orderFrontRegardless()
        panel = p
        NSSound(named: NSSound.Name("Glass"))?.play()
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                             userInfo: [.announcement: "Meeting canceled: \(title)", .priority: NSAccessibilityPriorityLevel.high.rawValue])
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(duration))
            guard panel === p else { return }
            NSAnimationContext.runAnimationGroup({ $0.duration = 0.3; p.animator().alphaValue = 0 }) {
                Task { @MainActor in p.orderOut(nil); if panel === p { panel = nil } }
            }
        }
    }
}

struct CelebrationView: View {
    let title: String
    let extra: Int
    let confetti: Bool
    let start: Date

    var body: some View {
        ZStack {
            if confetti {
                ConfettiBurst(start: start, duration: CelebrationOverlay.duration)
            }
            card
        }
        .ignoresSafeArea()
    }

    private var card: some View {
        VStack(spacing: 10) {
            SKLCD {
                HStack(spacing: 8) {
                    SKLamp(color: .orange, lit: true, label: "Canceled")
                    Text("MEETING CANCELED").font(.system(size: 15, weight: .bold, design: .monospaced)).tracking(1)
                        .foregroundStyle(Color(sk1Hex: SK1.lcdInk))
                }
                .padding(.horizontal, 14)
            }
            .frame(width: 300, height: 44)
            Text(title).font(.title2.bold()).multilineTextAlignment(.center).lineLimit(2)
            Text(extra > 0 ? "And \(extra) more. Enjoy the free time!" : "Enjoy the free time!")
                .font(.callout).foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(width: 360)
        .sk1Chassis()
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.3), radius: 24, y: 10)
        .accessibilityElement(children: .combine)
    }
}
