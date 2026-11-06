import ActivityKit
import SwiftUI
import WidgetKit
import SK1Tokens
import SK1UI

/// The countdown to the next meeting: an MB-1 LCD card on the Lock Screen, and the Dynamic Island's lamp and timer.
/// The timer counts down to the start, then counts up while the meeting is on.
struct MeetingLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: MeetingActivityAttributes.self) { context in
            LockScreenMeetingView(state: context.state, stale: context.isStale)
                .activityBackgroundTint(Color(sk1Hex: SK1.palette(dark: false).chassis))
                .activitySystemActionForegroundColor(WidgetStyle.lcdInk)
                .widgetURL(context.state.joinURL.map(MeetballLink.join) ?? MeetballLink.today)
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
            .widgetURL(s.joinURL.map(MeetballLink.join) ?? MeetballLink.today)
            .keylineTint(WidgetStyle.orange)
        }
    }
}

struct LockScreenMeetingView: View {
    let state: MeetingActivityAttributes.ContentState
    let stale: Bool

    var body: some View {
        HStack(spacing: 12) {
            WidgetLCD(radius: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Circle().fill(WidgetStyle.orange).frame(width: 6, height: 6)
                        Text(stale ? "ENDED" : "MB-1 · \(state.start.formatted(date: .omitted, time: .shortened))")
                            .font(.system(size: 9, weight: .heavy)).tracking(1)
                            .foregroundStyle(WidgetStyle.lcdInk)
                    }
                    Text(state.start, style: .timer)
                        .font(.system(size: 26, weight: .bold, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(WidgetStyle.lcdInk)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                .padding(.horizontal, 10)
            }
            .frame(width: 140, height: 64)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Circle().fill(WidgetStyle.color(state.colorHex)).frame(width: 8, height: 8)
                    Text(state.title).font(.headline).lineLimit(2).foregroundStyle(Color(sk1Hex: SK1.palette(dark: false).ink))
                }
                Text("\(Text(state.start, style: .time)) – \(Text(state.end, style: .time))")
                    .font(.caption).foregroundStyle(Color(sk1Hex: SK1.palette(dark: false).inkSoft))
                if state.joinURL != nil {
                    Text("Tap to join").font(.caption2.weight(.bold)).foregroundStyle(WidgetStyle.orange)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
    }
}
