import ActivityKit
import SwiftUI
import WidgetKit
import SK1Tokens
import SK1UI

/// Meetball's Live Activity: the countdown to the next meeting (the MB-1's LCD across the Lock Screen, see
/// `LockScreenMeetingView`), the running timer (the MT-1's, `LockScreenTimerView`), or the two side by side when a
/// timer runs during a meeting (`LockScreenSplitView`). In the Dynamic Island, a running timer takes the compact view;
/// expanded, both show. The meeting's timer counts down to the start, then counts up while the meeting is on.
struct MeetingLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: MeetingActivityAttributes.self) { context in
            LockScreenActivityView(state: context.state, stale: context.isStale)
                .activityBackgroundTint(Color(sk1Hex: 0x2b2a27))
                .activitySystemActionForegroundColor(.white)
                .widgetURL(MeetballLink.today)
        } dynamicIsland: { context in
            let s = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 6) {
                        if let m = s.meeting {
                            Circle().fill(WidgetStyle.color(m.colorHex)).frame(width: 10, height: 10)
                            Text("MB-1").font(.system(size: 12, weight: .heavy, design: .monospaced))
                        } else {
                            Image(systemName: "timer").foregroundStyle(WidgetStyle.orange)
                            Text("MT-1").font(.system(size: 12, weight: .heavy, design: .monospaced))
                        }
                    }
                    .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Group {
                        if let m = s.meeting {
                            Text(m.start, style: .timer)
                        } else if let t = s.timer {
                            ActivityTimerText(timer: t)
                        }
                    }
                    .font(.system(size: 22, weight: .bold, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(WidgetStyle.orange)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 110, alignment: .trailing)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        if let m = s.meeting { islandMeeting(m) }
                        if let t = s.timer { islandTimer(t, withMeeting: s.meeting != nil) }
                    }
                    .padding(.horizontal, 4)
                }
            } compactLeading: {
                if s.timer != nil {
                    Image(systemName: "timer").font(.system(size: 13, weight: .semibold)).foregroundStyle(WidgetStyle.orange)
                        .padding(.leading, 2)
                } else {
                    Circle().fill(WidgetStyle.orange).frame(width: 9, height: 9)
                        .padding(.leading, 2)
                }
            } compactTrailing: {
                Group {
                    if let t = s.timer {
                        ActivityTimerText(timer: t)
                    } else if let m = s.meeting {
                        Text(m.start, style: .timer)
                    }
                }
                .monospacedDigit()
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundStyle(WidgetStyle.orange)
                .frame(width: 56, alignment: .trailing)
            } minimal: {
                Image(systemName: s.timer != nil ? "timer" : "calendar.badge.clock").foregroundStyle(WidgetStyle.orange)
            }
            .widgetURL(MeetballLink.today)
            .keylineTint(WidgetStyle.orange)
        }
    }

    private func islandMeeting(_ m: MeetingActivityAttributes.Meeting) -> some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(m.title).font(.headline).lineLimit(1)
                Text("\(Text(m.start, style: .time)) – \(Text(m.end, style: .time))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 6)
            if let url = m.joinURL {
                Link(destination: MeetballLink.join(url)) {
                    Label("Join", systemImage: "video.fill")
                        .font(.callout.weight(.bold))
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(WidgetStyle.orange, in: Capsule())
                        .foregroundStyle(.white)
                }
            }
        }
    }

    /// The timer's row: its name (and how many more run), its countdown when the meeting has the big one, and its bar.
    private func islandTimer(_ t: MeetingActivityAttributes.TimerRun, withMeeting: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "timer").font(.caption.weight(.bold)).foregroundStyle(WidgetStyle.orange)
                Text(t.others > 0 ? "\(t.label) · +\(t.others) more" : t.label).font(.subheadline.weight(.semibold)).lineLimit(1)
                Spacer(minLength: 6)
                if withMeeting {
                    ActivityTimerText(timer: t)
                        .font(.system(size: 15, weight: .bold, design: .monospaced)).monospacedDigit()
                        .foregroundStyle(WidgetStyle.orange)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80, alignment: .trailing)
                }
            }
            ProgressView(timerInterval: t.start...t.end, countsDown: false, label: { EmptyView() }, currentValueLabel: { EmptyView() })
                .progressViewStyle(.linear)
                .tint(WidgetStyle.orange)
        }
    }
}

/// A running timer's time left, counting down by itself and stopping at 0:00.
struct ActivityTimerText: View {
    let timer: MeetingActivityAttributes.TimerRun

    var body: some View {
        Text(timerInterval: timer.start...timer.end, countsDown: true)
    }
}

/// The Lock Screen card for whatever the activity carries: the meeting, the timer, or both side by side.
struct LockScreenActivityView: View {
    let state: MeetingActivityAttributes.ContentState
    let stale: Bool

    var body: some View {
        if let m = state.meeting, let t = state.timer {
            LockScreenSplitView(meeting: m, timer: t, stale: stale)
        } else if let m = state.meeting {
            LockScreenMeetingView(state: m, stale: stale)
        } else if let t = state.timer {
            LockScreenTimerView(timer: t, stale: stale)
        }
    }
}

/// A running timer across the Lock Screen, as the MT-1: its name and end time, the time left beside it, and the
/// progress bar filling as time runs out. Stale once it has gone off.
struct LockScreenTimerView: View {
    let timer: MeetingActivityAttributes.TimerRun
    let stale: Bool

    var body: some View {
        WidgetLCD(radius: 12) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 5) {
                    Image(systemName: "timer").font(.system(size: 10, weight: .heavy))
                    Text(stale ? "DONE" : "ENDS \(timer.end.formatted(date: .omitted, time: .shortened))".uppercased())
                        .font(.system(size: 10, weight: .heavy)).tracking(1)
                    if timer.others > 0 {
                        Text("· +\(timer.others) MORE").font(.system(size: 10, weight: .heavy)).tracking(1).opacity(0.7)
                    }
                    Spacer(minLength: 4)
                    Text("MT-1").font(.system(size: 9, weight: .heavy, design: .monospaced)).tracking(1).opacity(0.55)
                }
                .lineLimit(1)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(timer.label).font(.system(size: 17, weight: .bold)).lineLimit(1)
                    Spacer(minLength: 0)
                    ActivityTimerText(timer: timer)
                        .font(.system(size: 26, weight: .bold, design: .monospaced))
                        .monospacedDigit()
                        .multilineTextAlignment(.trailing)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .frame(width: 108, alignment: .trailing)
                }
                LockScreenRunBar(span: timer.start...timer.end)
            }
            .foregroundStyle(WidgetStyle.lcdInk)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
        }
        .padding(10)
    }
}

/// A timer running during a meeting: the card splits into the meeting's LCD and the timer's, side by side, each with
/// its own countdown and bar, and the meeting's Join key under both.
struct LockScreenSplitView: View {
    let meeting: MeetingActivityAttributes.Meeting
    let timer: MeetingActivityAttributes.TimerRun
    let stale: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                half(tag: "MB-1", caption: stale ? "ENDED" : meeting.start.formatted(date: .omitted, time: .shortened).uppercased(),
                     dot: WidgetStyle.color(meeting.colorHex), title: meeting.title,
                     time: Text(meeting.start, style: .timer),
                     span: meeting.start...max(meeting.end, meeting.start.addingTimeInterval(60)))
                half(tag: "MT-1", caption: timer.others > 0 ? "TIMER +\(timer.others)" : "TIMER", dot: nil, title: timer.label,
                     time: Text(timerInterval: timer.start...timer.end, countsDown: true),
                     span: timer.start...timer.end)
            }
            if let url = meeting.joinURL, !stale { LockScreenJoinKey(url: url) }
        }
        .padding(10)
    }

    private func half(tag: String, caption: String, dot: Color?, title: String, time: Text, span: ClosedRange<Date>) -> some View {
        WidgetLCD(radius: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    if let dot { Circle().fill(dot).frame(width: 6, height: 6) } else {
                        Image(systemName: "timer").font(.system(size: 9, weight: .heavy))
                    }
                    Text(caption).font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    Spacer(minLength: 2)
                    Text(tag).font(.system(size: 8, weight: .heavy, design: .monospaced)).tracking(0.8).opacity(0.55)
                }
                .lineLimit(1)
                Text(title).font(.system(size: 14, weight: .bold)).lineLimit(1)
                time
                    .font(.system(size: 22, weight: .bold, design: .monospaced))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                LockScreenRunBar(span: span)
            }
            .foregroundStyle(WidgetStyle.lcdInk)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
    }
}

/// A bar that fills on its own clock across `span`, with no update from the app.
struct LockScreenRunBar: View {
    let span: ClosedRange<Date>

    var body: some View {
        ProgressView(timerInterval: span, countsDown: false, label: { EmptyView() }, currentValueLabel: { EmptyView() })
            .progressViewStyle(.linear)
            .tint(WidgetStyle.lcdInk)
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)
    }
}

/// The orange Join key under the glass: only the key joins; tapping the rest of the card opens the Day grid.
struct LockScreenJoinKey: View {
    let url: URL

    var body: some View {
        Link(destination: MeetballLink.join(url)) {
            HStack(spacing: 6) {
                Image(systemName: "video.fill").font(.system(size: 11, weight: .bold))
                Text(WidgetService.name(url).map { "JOIN \($0.uppercased())" } ?? "JOIN")
                    .font(.system(size: 12, weight: .heavy)).tracking(1)
                Spacer(minLength: 0)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .frame(height: 26)
            .background(WidgetStyle.orange, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }
}

/// The Lock Screen card: a dark bezel around LCD glass as wide as the card. On the glass, the meeting's times, its
/// title beside the timer, and the run: two bars that fill by themselves, the hour before the meeting and then the
/// meeting, with the start marked between them, so the timer reads as "until" left of the mark and "into" right of it.
/// Under the glass, the orange Join key when there's a link: only the key joins; tapping the rest of the card opens
/// the Day grid at the time now.
struct LockScreenMeetingView: View {
    let state: MeetingActivityAttributes.Meeting
    let stale: Bool

    private var times: String {
        "\(state.start.formatted(date: .omitted, time: .shortened)) – \(state.end.formatted(date: .omitted, time: .shortened))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            WidgetLCD(radius: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 5) {
                        Circle().fill(WidgetStyle.color(state.colorHex)).frame(width: 7, height: 7)
                        Text(stale ? "ENDED" : times.uppercased()).font(.system(size: 10, weight: .heavy)).tracking(1)
                        if let service = WidgetService.name(state.joinURL), !stale {
                            Text("· \(service.uppercased())").font(.system(size: 10, weight: .heavy)).tracking(1).opacity(0.7)
                        }
                        Spacer(minLength: 4)
                        Text("MB-1").font(.system(size: 9, weight: .heavy, design: .monospaced)).tracking(1).opacity(0.55)
                    }
                    .lineLimit(1)
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(state.title).font(.system(size: 17, weight: .bold)).lineLimit(1)
                        Spacer(minLength: 0)
                        Text(state.start, style: .timer)
                            .font(.system(size: 26, weight: .bold, design: .monospaced))
                            .monospacedDigit()
                            .multilineTextAlignment(.trailing)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .frame(width: 108, alignment: .trailing)
                    }
                    run
                }
                .foregroundStyle(WidgetStyle.lcdInk)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
            }
            if let url = state.joinURL, !stale { LockScreenJoinKey(url: url) }
        }
        // The whole card stays under the 160 points a Live Activity gets.
        .padding(10)
    }

    /// The hour before, the start mark, the meeting: each bar fills on its own clock, with no update from the app.
    private var run: some View {
        let lead = state.start.addingTimeInterval(-3600)
        let end = max(state.end, state.start.addingTimeInterval(60))
        return VStack(spacing: 2) {
            HStack(spacing: 4) {
                bar(lead...state.start)
                RoundedRectangle(cornerRadius: 1).frame(width: 2, height: 10)
                bar(state.start...end)
            }
            HStack(spacing: 0) {
                Text("1 HR BEFORE").frame(maxWidth: .infinity, alignment: .leading)
                Text(state.start.formatted(date: .omitted, time: .shortened)).fixedSize()
                Text(state.end.formatted(date: .omitted, time: .shortened)).frame(maxWidth: .infinity, alignment: .trailing)
            }
            .font(.system(size: 8, weight: .heavy)).monospacedDigit().opacity(0.65).lineLimit(1)
        }
        .accessibilityHidden(true)
    }

    private func bar(_ span: ClosedRange<Date>) -> some View {
        LockScreenRunBar(span: span)
    }
}
