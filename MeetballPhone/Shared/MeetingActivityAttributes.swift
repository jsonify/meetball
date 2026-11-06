import ActivityKit
import Foundation

// Compiled into both the app (which starts, updates and ends the activity) and the widget extension (which draws it).

/// The Live Activity counting down to the next meeting on the Lock Screen and in the Dynamic Island.
struct MeetingActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var title: String
        var start: Date
        var end: Date
        var colorHex: String
        var joinURL: URL?
    }

    /// The meeting's uid, so a refresh updates the same activity rather than starting another.
    var meetingID: String
}
