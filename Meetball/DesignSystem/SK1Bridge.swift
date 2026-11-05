import SwiftUI
import SK1Tokens
import SK1UI

// Meetball's use of the SK-1 look (SK1Kit): the main window, the menu bar popover, the Settings window and the
// heads-up alert card. The full-screen hard alert keeps its own dark overlay.

/// A settings tab on the SK-1 chassis: groups (`SKGroup`) 22 pt apart inside the pane margin, scrolling when tall.
struct SK1SettingsPane<Content: View>: View {
    private let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SK1.Metrics.groupSpacing) { content }
                .padding(SK1.Metrics.paneMargin)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .sk1Chassis()
    }
}

extension View {
    /// A grouped `Form` shown on the SK-1 chassis, for settings tabs not yet built from `SKGroup` rows.
    func sk1FormChassis() -> some View {
        scrollContentBackground(.hidden).sk1Chassis()
    }
}

/// One line of LCD: a lamp and a caption at the left, seven-segment digits (with their unit) or short mono text at the right.
struct SK1CountdownLCD: View {
    let caption: String
    /// Seven-segment text: digits, ":" and "-" only.
    var digits: String?
    var unit: String?
    /// Shown instead of digits ("NOW", "3 MIN AGO").
    var text: String?
    /// Red and blinking while the meeting is under way; teal while waiting.
    var live = false
    var height: CGFloat = 40
    /// What VoiceOver reads for the whole display.
    let accessibilityText: String

    private var ink: Color { Color(sk1Hex: SK1.lcdInk) }

    var body: some View {
        SKLCD {
            HStack(spacing: 6) {
                SKLamp(color: live ? .danger : .success, lit: true, glow: 0, size: 5, blinking: live)
                Text(caption.uppercased())
                    .font(.system(size: 9.5, weight: .heavy)).tracking(1.1)
                    .foregroundStyle(ink).lineLimit(1)
                Spacer(minLength: 6)
                if let digits {
                    HStack(alignment: .bottom, spacing: 3) {
                        SKSevenSegment(digits, digitHeight: max(10, height - 20), spacing: 3)
                        if let unit { Text(unit).font(.system(size: 9, weight: .heavy)).foregroundStyle(ink) }
                    }
                } else if let text {
                    Text(text.uppercased())
                        .font(.sk1(SK1.TypeScale.lcdMono)).tracking(SK1.TypeScale.lcdMono.kern)
                        .foregroundStyle(ink).lineLimit(1)
                }
            }
            .padding(.horizontal, 10)
        }
        .frame(height: height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityText))
    }
}

/// The main window's LCD under the toolbar (as Skreener's editor display): what is shown at the left, the meeting in
/// progress or the next one in the middle, and how many meetings are left today in seven-segment digits, with the
/// LIVE lamp blinking while a meeting is on.
struct MainStatusDisplay: View {
    let title: String
    let detail: String
    @EnvironmentObject var store: CalendarStore

    var body: some View {
        TimelineView(.periodic(from: .now, by: 15)) { ctx in
            let line = MeetingStatusText.line(store.meetingEvents, now: ctx.date)
            SKDisplay(title: title, detail: detail, message: line.message,
                      number: MeetingStatusText.remainingToday(store.meetingEvents, now: ctx.date), digits: 2,
                      unit: "LEFT", live: line.live)
        }
    }
}
