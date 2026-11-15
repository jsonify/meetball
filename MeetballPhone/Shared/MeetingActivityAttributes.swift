import ActivityKit
import Foundation

// Compiled into both the app (which starts, updates and ends the activity) and the widget extension (which draws it).

/// Meetball's Live Activity on the Lock Screen and in the Dynamic Island: the countdown to the next meeting, the
/// running timer that goes off first, or both side by side when a timer runs during a meeting.
struct MeetingActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// The meeting on now or starting within the hour.
        var meeting: Meeting?
        /// The running timer that goes off first.
        var timer: TimerRun?

        init(meeting: Meeting? = nil, timer: TimerRun? = nil) {
            self.meeting = meeting
            self.timer = timer
        }

        private enum CodingKeys: String, CodingKey {
            case meeting, timer
            // Before timers: the meeting's fields sat at the top level.
            case title, start, end, colorHex, joinURL
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            timer = try c.decodeIfPresent(TimerRun.self, forKey: .timer)
            if c.contains(.meeting) {
                meeting = try c.decodeIfPresent(Meeting.self, forKey: .meeting)
            } else if let title = try c.decodeIfPresent(String.self, forKey: .title) {
                // An activity started by an older build, still on the Lock Screen after an update.
                meeting = Meeting(title: title, start: try c.decode(Date.self, forKey: .start),
                                  end: try c.decode(Date.self, forKey: .end),
                                  colorHex: try c.decode(String.self, forKey: .colorHex),
                                  joinURL: try c.decodeIfPresent(URL.self, forKey: .joinURL))
            } else {
                meeting = nil
            }
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encodeIfPresent(meeting, forKey: .meeting)
            try c.encodeIfPresent(timer, forKey: .timer)
        }
    }

    struct Meeting: Codable, Hashable {
        var title: String
        var start: Date
        var end: Date
        var colorHex: String
        var joinURL: URL?
    }

    /// A running timer: it counts down to `end`; `start` is where its progress bar begins.
    struct TimerRun: Codable, Hashable {
        var label: String
        var start: Date
        var end: Date
        /// Other timers running behind this one.
        var others: Int
    }

    /// Kept from when each meeting had its own activity; one activity now carries whatever is showing.
    var meetingID: String
}
