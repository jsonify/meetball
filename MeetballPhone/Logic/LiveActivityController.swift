import ActivityKit
import Foundation
import WidgetKit

/// Keeps one Live Activity counting down to the next meeting, from `leadTime` before it until it ends, and hands the
/// widgets the latest meetings.
///
/// iOS only lets an app start a Live Activity while it's on screen, so the countdown appears the next time Meetball is
/// opened within the hour before a meeting; once running, refreshes in the background keep it up to date (a moved
/// meeting moves its timer, a cancelled one ends it).
@MainActor
enum LiveActivityController {
    static let leadTime: TimeInterval = 60 * 60

    /// The meeting the activity should show at `now`: on now or starting within `leadTime`.
    nonisolated static func meeting(from upcoming: [CalendarEvent], now: Date) -> CalendarEvent? {
        guard let e = upcoming.filter({ $0.end > now }).min(by: { $0.start < $1.start }) else { return nil }
        return e.start.timeIntervalSince(now) <= leadTime ? e : nil
    }

    nonisolated static func state(_ e: CalendarEvent) -> MeetingActivityAttributes.ContentState {
        .init(title: e.title, start: e.start, end: e.end, colorHex: e.colorHex, joinURL: e.meetURL)
    }

    static func reconcile(upcoming: [CalendarEvent], enabled: Bool, now: Date = Date()) async {
        let running = Activity<MeetingActivityAttributes>.activities
        guard enabled, ActivityAuthorizationInfo().areActivitiesEnabled, let e = meeting(from: upcoming, now: now) else {
            for a in running { await a.end(nil, dismissalPolicy: .immediate) }
            return
        }
        let content = ActivityContent(state: state(e), staleDate: e.end)
        var kept = false
        for a in running {
            if a.attributes.meetingID == e.uid && !kept {
                kept = true
                if a.content.state != content.state { await a.update(content) }
            } else {
                await a.end(nil, dismissalPolicy: .immediate)
            }
        }
        if !kept {
            _ = try? Activity.request(attributes: MeetingActivityAttributes(meetingID: e.uid), content: content, pushType: nil)
        }
    }

    /// Saves the next two days for the widgets, reloading them when the meetings changed.
    static func updateWidgets(upcoming: [CalendarEvent], now: Date = Date()) {
        let meetings = upcoming.map {
            WidgetMeeting(id: $0.uid, title: $0.title, start: $0.start, end: $0.end, colorHex: $0.colorHex, joinURL: $0.meetURL)
        }
        if WidgetSnapshot(meetings: meetings, savedAt: now).save() {
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
}
