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
        guard s.notifyChanges, !changes.isEmpty else { return }
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
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            guard panel === p else { return }
            NSAnimationContext.runAnimationGroup({ $0.duration = 0.3; p.animator().alphaValue = 0 }) {
                Task { @MainActor in p.orderOut(nil); if panel === p { panel = nil } }
            }
        }
    }
}

/// Confetti pieces, deterministic per index so every frame agrees.
struct ConfettiPiece {
    let x: Double, delay: Double, speed: Double, drift: Double, spin: Double, size: Double, color: Color, round: Bool

    static let palette: [Color] = [Color(sk1Hex: SK1.orange), Color(sk1Hex: SK1.teal), Color(sk1Hex: SK1.amber),
                                   Color(sk1Hex: SK1.recRed), Color(sk1Hex: SK1.glassTop), Color(hex: "#7C4DFF")]

    static func make(_ count: Int) -> [ConfettiPiece] {
        var rng = SplitMix(seed: 0x5EED)
        return (0..<count).map { i in
            ConfettiPiece(x: rng.next(), delay: rng.next() * 0.9, speed: 0.55 + rng.next() * 0.6, drift: rng.next() * 2 - 1,
                          spin: (rng.next() * 2 - 1) * 9, size: 6 + rng.next() * 7, color: palette[i % palette.count],
                          round: i % 3 == 0)
        }
    }
}

/// A small seeded generator (values in 0..<1).
struct SplitMix {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> Double {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        z ^= z >> 31
        return Double(z >> 11) / Double(1 << 53)
    }
}

struct CelebrationView: View {
    let title: String
    let extra: Int
    let confetti: Bool
    let start: Date
    private let pieces = ConfettiPiece.make(160)

    var body: some View {
        ZStack {
            if confetti {
                TimelineView(.animation) { tl in
                    Canvas { ctx, size in
                        let t = tl.date.timeIntervalSince(start)
                        for p in pieces {
                            let life = t - p.delay
                            guard life > 0 else { continue }
                            // Burst up from the bottom, then fall back down with a sideways drift.
                            let h = size.height
                            let y = h - (p.speed * h * 1.9 * life - 0.5 * 1.6 * h * life * life)
                            guard y < h + 20 else { continue }
                            let x = p.x * size.width + p.drift * 160 * life
                            var piece = ctx
                            piece.translateBy(x: x, y: y)
                            piece.rotate(by: .radians(p.spin * life))
                            piece.opacity = max(0, min(1, (CelebrationOverlay.duration - t) / 0.8))
                            let rect = CGRect(x: -p.size / 2, y: -p.size / 4, width: p.size, height: p.size / (p.round ? 1 : 2))
                            piece.fill(p.round ? Path(ellipseIn: rect) : Path(rect), with: .color(p.color))
                        }
                    }
                }
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
