import ActivityKit
import SwiftUI
import WidgetKit
import SK1Tokens
import SK1UI

/// The countdown to the next meeting: the MB-1's LCD across the Lock Screen (see `LockScreenMeetingView`), and the
/// Dynamic Island's lamp and timer. The timer counts down to the start, then counts up while the meeting is on.
struct MeetingLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: MeetingActivityAttributes.self) { context in
            LockScreenMeetingView(state: context.state, stale: context.isStale)
                .activityBackgroundTint(Color(sk1Hex: 0x2b2a27))
                .activitySystemActionForegroundColor(.white)
                .widgetURL(MeetballLink.today)
        } dynamicIsland: { context in
            let s = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 6) {
                        Circle().fill(WidgetStyle.color(s.colorHex)).frame(width: 10, height: 10)
                        Text("MB-1").font(.system(size: 12, weight: .heavy, design: .monospaced))
                    }
                    .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(s.start, style: .timer)
                        .font(.system(size: 22, weight: .bold, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(WidgetStyle.orange)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 110, alignment: .trailing)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(alignment: .center, spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(s.title).font(.headline).lineLimit(1)
                            Text("\(Text(s.start, style: .time)) – \(Text(s.end, style: .time))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 6)
                        if let url = s.joinURL {
                            Link(destination: MeetballLink.join(url)) {
                                Label("Join", systemImage: "video.fill")
                                    .font(.callout.weight(.bold))
                                    .padding(.horizontal, 14).padding(.vertical, 8)
                                    .background(WidgetStyle.orange, in: Capsule())
                                    .foregroundStyle(.white)
                            }
                        }
                    }
                    .padding(.horizontal, 4)
                }
            } compactLeading: {
                Circle().fill(WidgetStyle.orange).frame(width: 9, height: 9)
                    .padding(.leading, 2)
            } compactTrailing: {
                Text(s.start, style: .timer)
                    .monospacedDigit()
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundStyle(WidgetStyle.orange)
                    .frame(width: 56, alignment: .trailing)
            } minimal: {
                Image(systemName: "calendar.badge.clock").foregroundStyle(WidgetStyle.orange)
            }
            .widgetURL(MeetballLink.today)
            .keylineTint(WidgetStyle.orange)
        }
    }
}

/// The Lock Screen card: a dark bezel around LCD glass as wide as the card. On the glass, the meeting's times, its
/// title beside the timer, and the run: two bars that fill by themselves, the hour before the meeting and then the
/// meeting, with the start marked between them, so the timer reads as "until" left of the mark and "into" right of it.
/// Under the glass, the orange Join key when there's a link: only the key joins; tapping the rest of the card opens
/// the Day grid at the time now.
struct LockScreenMeetingView: View {
    let state: MeetingActivityAttributes.ContentState
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
            if let url = state.joinURL, !stale {
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
        ProgressView(timerInterval: span, countsDown: false, label: { EmptyView() }, currentValueLabel: { EmptyView() })
            .progressViewStyle(.linear)
            .tint(WidgetStyle.lcdInk)
            .frame(maxWidth: .infinity)
    }
}
