import AppKit
import SwiftUI
import SK1Tokens
import SK1UI

/// A card in the top-right corner listing meetings that moved, got a new link or were cancelled. Unlike a notification
/// banner it stays until dismissed, so a change can't slip by while you're away from the screen. Changes that arrive
/// while it's open are added to it.
@MainActor
enum MeetingChangeCardPanel {
    private static var panel: NSPanel?
    private(set) static var showing: [MeetingChange] = []
    /// Most changes listed on the card; the rest are counted.
    static let maxRows = 4

    static func show(_ changes: [MeetingChange]) {
        guard !changes.isEmpty else { return }
        showing = merged(showing, changes)
        present()
    }

    /// A sample card, from Settings › Alerts.
    static func preview() {
        let start = Calendar.app.date(bySettingHour: 15, minute: 0, second: 0, of: Date().addingTimeInterval(86400)) ?? Date()
        let e = CalendarEvent(id: "preview", calendarID: "preview", accountEmail: "preview", title: "Design review",
                              start: start, end: start.addingTimeInterval(1800), isAllDay: false, meetURL: nil,
                              location: nil, attendees: [], htmlLink: nil, colorHex: "#E8743B")
        showing = []
        show([MeetingChange(kind: .rescheduled(from: start.addingTimeInterval(-5400), to: start), event: e)])
    }

    static func dismiss() {
        showing = []
        guard let p = panel else { return }
        panel = nil
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion { p.orderOut(nil); return }
        NSAnimationContext.runAnimationGroup({ $0.duration = 0.18; p.animator().alphaValue = 0 }) {
            Task { @MainActor in p.orderOut(nil) }
        }
    }

    /// Newest change per meeting first; a meeting that changes again replaces its older row.
    static func merged(_ old: [MeetingChange], _ new: [MeetingChange]) -> [MeetingChange] {
        let ids = Set(new.map { MeetingChangeDetector.baseID($0.event.id) + "|" + $0.event.calendarKey })
        return new + old.filter { !ids.contains(MeetingChangeDetector.baseID($0.event.id) + "|" + $0.event.calendarKey) }
    }

    private static func present() {
        let host = AlertHostingView(rootView: MeetingChangeCard(changes: showing, now: Date(), dismiss: { dismiss() }))
        let screen = MeetingGuardianManager.activeScreen
        let size = host.fittingSize
        let area = screen.visibleFrame
        let frame = NSRect(x: area.maxX - size.width - 8, y: area.maxY - size.height - 8, width: size.width, height: size.height)
        let p = panel ?? makePanel()
        p.contentView = host
        p.setFrame(frame, display: true)
        p.alphaValue = 1
        p.orderFrontRegardless()
        panel = p
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                             userInfo: [.announcement: showing.map { MeetingChangeText.title($0) }.joined(separator: ". "),
                                        .priority: NSAccessibilityPriorityLevel.high.rawValue])
    }

    private static func makePanel() -> NSPanel { AlertPanel.make(level: .floating) }
}

struct MeetingChangeCard: View {
    let changes: [MeetingChange]
    let now: Date
    let dismiss: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    var body: some View {
        card
            .frame(width: 360)
            .padding(18) // room for the shadow and the slide
            .offset(x: shown || reduceMotion ? 0 : 80)
            .opacity(shown ? 1 : 0)
            .onAppear {
                withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.38, dampingFraction: 0.82)) { shown = true }
            }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                SKLCD {
                    HStack(spacing: 8) {
                        SKLamp(color: .orange, lit: true, label: "Changed")
                        Text(header).font(.system(size: 13, weight: .bold, design: .monospaced)).tracking(1)
                            .foregroundStyle(Color(sk1Hex: SK1.lcdInk))
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 12)
                }
                .frame(height: 34)
                Button(action: dismiss) { Image(systemName: "xmark") }
                    .buttonStyle(.sk1Key(.round, size: .small))
                    .help("Dismiss")
                    .accessibilityLabel("Dismiss")
            }
            ForEach(Array(changes.prefix(MeetingChangeCardPanel.maxRows).enumerated()), id: \.offset) { _, c in row(c) }
            if changes.count > MeetingChangeCardPanel.maxRows {
                Text("And \(changes.count - MeetingChangeCardPanel.maxRows) more").font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button("Got it", action: dismiss).buttonStyle(.sk1Key(.orange))
            }
        }
        .padding(14)
        .background(SKPlate { Color.clear })
        .clipShape(RoundedRectangle(cornerRadius: SK1.Metrics.plateRadius, style: .continuous))
        .shadow(color: .black.opacity(0.25), radius: 14, y: 6)
        .accessibilityElement(children: .contain)
    }

    private var header: String {
        if changes.count > 1 { return "\(changes.count) MEETINGS CHANGED" }
        switch changes.first?.kind {
        case .cancelled: return "MEETING CANCELED"
        case .linkChanged: return "NEW JOIN LINK"
        default: return "MEETING MOVED"
        }
    }

    private func row(_ c: MeetingChange) -> some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 2).fill(Color(hex: c.event.colorHex)).frame(width: 4)
            VStack(alignment: .leading, spacing: 3) {
                Text(c.event.title).font(.headline).lineLimit(2)
                    .strikethrough(c.isCancellation)
                Label(MeetingChangeText.body(c, now: now), systemImage: symbol(c))
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func symbol(_ c: MeetingChange) -> String {
        switch c.kind {
        case .cancelled: return "calendar.badge.minus"
        case .rescheduled: return "clock.arrow.circlepath"
        case .linkChanged: return "link"
        }
    }
}
