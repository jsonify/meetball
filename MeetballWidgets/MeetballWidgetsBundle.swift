import SwiftUI
import WidgetKit

/// Meetball's widgets: the next meeting on an MB-1 LCD (Home Screen and Lock Screen) and the meeting countdown Live
/// Activity (Lock Screen and Dynamic Island), and the Join Meeting control (Control Center).
@main
struct MeetballWidgetsBundle: WidgetBundle {
    var body: some Widget {
        NextMeetingWidget()
        MeetingLiveActivity()
        JoinMeetingControl()
    }
}
