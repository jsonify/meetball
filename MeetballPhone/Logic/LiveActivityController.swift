import ActivityKit
import Foundation
import WidgetKit

/// Keeps Meetball's one Live Activity in line with what it should show: the next meeting, from `leadTime` before it
/// until it ends (Settings › Countdown on the Lock Screen), and the running timer that goes off first. When both are
/// on, the card splits between them. It also hands the widgets the latest meetings.
///
/// iOS only lets an app start a Live Activity while it's on screen, so the meeting countdown appears the next time
/// Meetball is opened within the hour before a meeting (a timer is started in Meetball, so it shows straight away);
/// once running, refreshes in the background keep it up to date (a moved meeting moves its timer, a cancelled one
/// ends it).
@MainActor
enum LiveActivityController {
    nonisolated static let leadTime: TimeInterval = 60 * 60

    /// The meeting the activity should show at `now`: on now or starting within `leadTime`.
    nonisolated static func meeting(from upcoming: [CalendarEvent], now: Date) -> CalendarEvent? {
        guard let e = upcoming.filter({ $0.end > now }).min(by: { $0.start < $1.start }) else { return nil }
        return e.start.timeIntervalSince(now) <= leadTime ? e : nil
    }

    nonisolated static func meetingState(_ e: CalendarEvent) -> MeetingActivityAttributes.Meeting {
        .init(title: e.title, start: e.start, end: e.end, colorHex: e.colorHex, joinURL: e.meetURL)
    }

    /// The timer the activity shows at `now`: the running one that goes off first, with how many others are running.
    /// Its bar starts where its length (or the time it has left, after +1 Min) began.
    nonisolated static func timerRun(_ timers: [MeetballTimer], now: Date) -> MeetingActivityAttributes.TimerRun? {
        let running = timers.filter { $0.state(at: now) == .running }
        guard let t = running.min(by: { $0.remaining(at: now) < $1.remaining(at: now) }), let end = t.endDate else { return nil }
        let length = max(t.duration, t.remaining(at: now))
        return .init(label: t.displayName, start: end.addingTimeInterval(-length), end: end, others: running.count - 1)
    }

    /// What the activity shows; nil when there's nothing to show (it ends).
    nonisolated static func state(meeting: MeetingActivityAttributes.Meeting?, timer: MeetingActivityAttributes.TimerRun?,
                                  now: Date) -> MeetingActivityAttributes.ContentState? {
        let meeting = meeting.flatMap { $0.end > now ? $0 : nil }
        let timer = timer.flatMap { $0.end > now ? $0 : nil }
        guard meeting != nil || timer != nil else { return nil }
        return .init(meeting: meeting, timer: timer)
    }

    /// When the card goes stale: the meeting's end (it then reads ENDED), else the timer's.
    nonisolated static func staleDate(_ state: MeetingActivityAttributes.ContentState) -> Date? {
        state.meeting?.end ?? state.timer?.end
    }

    /// The meeting part, once the calendar has been read since launch; until then the card keeps the meeting it shows.
    private static var meetingPart: MeetingActivityAttributes.Meeting?
    private static var meetingKnown = false
    /// The timers, as last handed over; nil until the timer store has started (a background refresh can come first).
    private static var timers: [MeetballTimer]?
    /// The last update, so updates run one after another and never start two activities.
    private static var last: Task<Void, Never>?

    /// After a calendar refresh: the meeting to count down to (none when `enabled` is off).
    static func reconcile(upcoming: [CalendarEvent], enabled: Bool, now: Date = Date()) async {
        meetingKnown = true
        meetingPart = enabled ? meeting(from: upcoming, now: now).map(meetingState) : nil
        await push()
    }

    /// The timers changed (or one went off).
    static func timersChanged(_ timers: [MeetballTimer]) {
        self.timers = timers
        Task { await push() }
    }

    private static func push() async {
        let previous = last
        let task = Task {
            await previous?.value
            await apply(now: Date())
        }
        last = task
        await task.value
    }

    private static func apply(now: Date) async {
        let running = Activity<MeetingActivityAttributes>.activities
        if !meetingKnown { meetingPart = running.first?.content.state.meeting }
        guard ActivityAuthorizationInfo().areActivitiesEnabled,
              let shown = state(meeting: meetingPart, timer: timerRun(timers ?? TimerStore.shared.timers, now: now), now: now) else {
            for a in running { await a.end(nil, dismissalPolicy: .immediate) }
            return
        }
        let content = ActivityContent(state: shown, staleDate: staleDate(shown))
        guard let kept = running.first else {
            _ = try? Activity.request(attributes: MeetingActivityAttributes(meetingID: "meetball"), content: content, pushType: nil)
            return
        }
        if kept.content.state != shown || kept.content.staleDate != content.staleDate { await kept.update(content) }
        for a in running.dropFirst() { await a.end(nil, dismissalPolicy: .immediate) }
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
