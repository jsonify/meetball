import SwiftUI
import SK1Tokens
import SK1UI

/// The running timer that goes off first, on a small MT-1 LCD at the top of the Day grid: its name, the time left
/// ticking each second, and its progress strip, with "+N" when more are running. A timer that has gone off and not
/// been stopped shows DONE, its 0:00 flashing. A tap opens Timers.
///
/// Only the chip ticks each second, not the grid around it. Shown while any timer is running or done
/// (`ActiveTimerChip.shows`), so it takes no room otherwise.
struct ActiveTimerChip: View {
    @EnvironmentObject private var timers: TimerStore
    let open: () -> Void

    /// Whether there's a timer for the chip to show.
    nonisolated static func shows(_ timers: [MeetballTimer]) -> Bool { timers.contains { $0.endDate != nil } }

    /// The timer to show at `now`: the running one that goes off first, else one that's done; and how many others run.
    nonisolated static func pick(_ timers: [MeetballTimer], now: Date) -> (timer: MeetballTimer, others: Int)? {
        let running = timers.filter { $0.state(at: now) == .running }
        if let next = running.min(by: { $0.remaining(at: now) < $1.remaining(at: now) }) { return (next, running.count - 1) }
        return timers.first { $0.state(at: now) == .done }.map { ($0, 0) }
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { tl in
            if let pick = Self.pick(timers.timers, now: tl.date) {
                Button(action: open) { chip(pick.timer, others: pick.others, now: tl.date) }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(TimerLCD.spoken(pick.timer, now: tl.date)
                                             + (pick.others > 0 ? ", and \(pick.others) more running" : "")))
                    .accessibilityHint("Opens Timers")
                    .accessibilityAddTraits(.isButton)
            }
        }
    }

    private func chip(_ t: MeetballTimer, others: Int, now: Date) -> some View {
        let done = t.state(at: now) == .done
        let ink = Color(sk1Hex: SK1.lcdInk)
        return SKLCD(radius: 6, inset: 2) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    SKLamp(color: done ? .danger : .success, lit: true, glow: 3, size: 5, blinking: done)
                    Text(t.displayName.uppercased()).lineLimit(1)
                    Spacer(minLength: 4)
                    Text(done ? "DONE" : (others > 0 ? "+\(others)" : "MT-1")).fixedSize()
                }
                .font(.system(size: 9, weight: .heavy, design: .monospaced)).tracking(0.6)
                .foregroundStyle(ink)
                HStack(spacing: 6) {
                    Image(systemName: "timer").font(.system(size: 12, weight: .bold)).foregroundStyle(ink)
                    SKSevenSegment(TimerFormat.clock(t.remaining(at: now)), digitHeight: 18)
                        .opacity(done && Int(now.timeIntervalSince1970) % 2 == 1 ? 0.25 : 1)
                    Spacer(minLength: 0)
                }
                TimerProgressStrip(progress: t.progress(at: now), urgency: TimerUrgency.of(t, at: now))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
        }
        .frame(width: 150, height: 58)
        .contentShape(Rectangle())
    }
}
