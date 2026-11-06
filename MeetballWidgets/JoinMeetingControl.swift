import AppIntents
import SwiftUI
import WidgetKit

/// A Control Center (and Lock Screen) button that joins the meeting that's on or about to start.
struct JoinMeetingControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "app.meetball.MeetballPhone.join") {
            ControlWidgetButton(action: JoinNextMeetingIntent()) {
                Label("Join Meeting", systemImage: "video.fill")
            }
        }
        .displayName("Join Meeting")
        .description("Joins the meeting that's on now or starts within 10 minutes.")
    }
}
