import SwiftUI
import SK1Tokens
import SK1UI

// Meetball's use of the SK-1 look (SK1Kit): the main window, the menu bar popover, the Settings window and the
// heads-up alert card. The full-screen hard alert keeps its own dark overlay.

/// A settings pane: groups (`SKGroup`) 22 pt apart inside the pane margin, scrolling when tall. It sits on the Settings
/// window's chassis (`SettingsView`), so it draws none of its own.
struct SK1SettingsPane<Content: View>: View {
    private let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SK1.Metrics.groupSpacing) { content }
                .padding(SK1.Metrics.paneMargin)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
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
