import SwiftUI
import UIKit
import SK1Tokens
import SK1UI

extension Notification.Name {
    static let meetballShake = Notification.Name("meetball.shake")
}

extension UIWindow {
    /// Shaking the phone posts `.meetballShake` (the day readout).
    open override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        super.motionEnded(motion, with: event)
        if motion == .motionShake { NotificationCenter.default.post(name: .meetballShake, object: nil) }
    }
}

/// Shake the phone: the rest of today as an MB-1 readout. Meetings left, hours booked, and your next free stretch.
struct DayReadoutSheet: View {
    @EnvironmentObject private var store: PhoneStore
    @Environment(\.dismiss) private var dismiss
    @State private var buzz = 0

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { tl in
            let now = tl.date
            let stats = PhoneAgenda.dayStats(store.events(from: now, days: 1), now: now)
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Your day").font(.title.bold())
                    Spacer()
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .buttonStyle(.sk1Key(.round, size: .small))
                        .accessibilityLabel("Close")
                }
                row(caption: "Meetings left", digits: "\(stats.left)", unit: stats.left == 1 ? "MTG" : "MTGS",
                    lamp: stats.left == 0 ? .success : .warning)
                row(caption: "Booked today", digits: stats.hoursDigits, unit: "HRS", lamp: stats.hours >= 6 ? .danger : .success)
                if let gap = stats.freeGap {
                    let mins = Int(gap.duration / 60)
                    row(caption: gap.start <= now.addingTimeInterval(60) ? "Free now for" : "Free at \(gap.start.shortTime) for",
                        digits: mins >= 60 ? String(format: "%d:%02d", mins / 60, mins % 60) : "\(mins)",
                        unit: mins >= 60 ? "HR" : "MIN", lamp: .success)
                } else {
                    row(caption: "Free time", text: "None before 6", lamp: .danger)
                }
                Text(stats.verdict).font(.title3.weight(.semibold))
                Text("Shake again any time.").sk1Hint()
            }
            .padding(20)
        }
        .sk1Chassis()
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .sensoryFeedback(.impact(weight: .medium), trigger: buzz)
        .onAppear { buzz += 1 }
    }

    private func row(caption: String, digits: String? = nil, unit: String? = nil, text: String? = nil, lamp: SKLampColor) -> some View {
        SK1CountdownLCD(caption: caption, digits: digits, unit: unit, text: text, lamp: lamp, lampBlinking: false, height: 52,
                        accessibilityText: "\(caption): \(digits ?? text ?? "") \(unit?.lowercased() ?? "")")
    }
}

/// The last minute before a meeting, while Meetball is open: a giant seven-segment countdown with a tick each second
/// for the last ten, a thunk at zero, then "You're up" and the Join key.
struct CountdownMomentView: View {
    let event: CalendarEvent
    let done: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { tl in
            let secs = max(0, Int(event.start.timeIntervalSince(tl.date).rounded(.up)))
            content(secs: secs)
                .sensoryFeedback(.impact(weight: .light), trigger: secs) { _, new in new > 0 && new <= 10 }
                .sensoryFeedback(.impact(weight: .heavy, intensity: 1), trigger: secs == 0) { _, up in up }
        }
        .task {
            // Gone two minutes after the start if nobody taps anything.
            let wait = event.start.timeIntervalSinceNow + 120
            if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
            done()
        }
    }

    private func content(secs: Int) -> some View {
        let up = secs == 0
        return VStack(spacing: 22) {
            Spacer()
            HStack(spacing: 8) {
                SKLamp(color: up ? .danger : .orange, lit: true, size: 9, blinking: true)
                SKCaption(up ? "You're up" : "Starting in", tone: .soft, style: SK1.TypeScale.indicator)
            }
            SKLCD {
                Group {
                    if up {
                        Text("LIVE").font(.system(size: 64, weight: .heavy, design: .monospaced)).foregroundStyle(Color(sk1Hex: SK1.lcdInk))
                    } else {
                        SKSevenSegment("\(secs)", digitHeight: 110, spacing: 10)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
            }
            .frame(height: 170)
            .scaleEffect(!reduceMotion && !up && secs <= 10 ? 1.03 : 1)
            .animation(reduceMotion ? nil : .spring(duration: 0.25), value: secs)
            Text(event.title).font(.title.bold()).multilineTextAlignment(.center).lineLimit(3)
            Text("\(event.start.shortTime) – \(event.end.shortTime)").font(.callout).foregroundStyle(.secondary)
            Spacer()
            PhoneJoinButton(event: event, variant: .orange, size: .large, fillsWidth: true)
            Button("Not now", action: done).buttonStyle(.sk1Key())
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sk1Chassis()
    }
}
