import AppIntents
import Foundation

// Compiled into both the app (Siri, Shortcuts, the Action Button) and the widget extension (the Control Center button).
// Both read the meetings the app last saved for the widgets (WidgetSnapshot), so they answer without opening Meetball.

/// "Join my meeting": opens the meeting that's on now or starts within 10 minutes.
struct JoinNextMeetingIntent: AppIntent {
    static let title: LocalizedStringResource = "Join Meeting"
    static let description = IntentDescription("Joins the meeting that's on now or starts within 10 minutes.")

    func perform() async throws -> some IntentResult & ProvidesDialog & OpensIntent {
        let now = Date()
        let snapshot = WidgetSnapshot.load()
        if let m = snapshot?.joinable(at: now), let url = m.joinURL {
            return .result(opensIntent: OpenURLIntent(url), dialog: "Joining \(m.title).")
        }
        // Nothing to join: say what's next, and open Today.
        return .result(opensIntent: OpenURLIntent(MeetballLink.today),
                       dialog: IntentDialog("\(NextMeetingIntent.sentence(snapshot, now: now, joinable: false))"))
    }
}

/// "What's my next meeting": Siri says it (handy in the car).
struct NextMeetingIntent: AppIntent {
    static let title: LocalizedStringResource = "Next Meeting"
    static let description = IntentDescription("Tells you your next meeting and how long until it starts.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: IntentDialog("\(Self.sentence(WidgetSnapshot.load(), now: Date()))"))
    }

    /// "Design review starts in 20 minutes, at 3:00 PM.", "You're in Standup until 10:30 AM." and so on.
    static func sentence(_ snapshot: WidgetSnapshot?, now: Date, joinable: Bool = true) -> String {
        guard let snapshot else { return "Open Meetball once so it can read your calendar." }
        guard let m = snapshot.current(at: now) else { return "No meetings in the next two days. Enjoy it." }
        let time = m.start.formatted(date: .omitted, time: .shortened)
        if m.start <= now {
            let end = m.end.formatted(date: .omitted, time: .shortened)
            return joinable || m.joinURL != nil ? "You're in \(m.title) until \(end)." : "\(m.title) is on until \(end), with no video link."
        }
        let mins = Int((m.start.timeIntervalSince(now) / 60).rounded(.up))
        let when: String
        if mins < 60 { when = mins == 1 ? "in 1 minute" : "in \(mins) minutes" }
        else if Calendar.current.isDate(m.start, inSameDayAs: now) { when = "at \(time)" }
        else { when = "\(m.start.formatted(.dateTime.weekday(.wide))) at \(time)" }
        let lead = joinable ? "" : "Nothing to join yet. "
        return mins < 60 ? "\(lead)\(m.title) starts \(when), at \(time)." : "\(lead)Your next meeting is \(m.title), \(when)."
    }
}
