import SwiftUI
import WidgetKit
import SK1Tokens
import SK1UI

struct NextMeetingEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?

    var meeting: WidgetMeeting? { snapshot?.current(at: date) }
}

struct NextMeetingProvider: TimelineProvider {
    func placeholder(in context: Context) -> NextMeetingEntry {
        NextMeetingEntry(date: Date(), snapshot: Self.sample(Date()))
    }

    func getSnapshot(in context: Context, completion: @escaping (NextMeetingEntry) -> Void) {
        let now = Date()
        completion(NextMeetingEntry(date: now, snapshot: context.isPreview ? Self.sample(now) : WidgetSnapshot.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NextMeetingEntry>) -> Void) {
        let now = Date()
        let snapshot = WidgetSnapshot.load()
        let dates = snapshot?.timelineDates(from: now) ?? [now]
        let entries = dates.map { NextMeetingEntry(date: $0, snapshot: snapshot) }
        completion(Timeline(entries: entries, policy: .after(dates.last ?? now.addingTimeInterval(3600))))
    }

    static func sample(_ now: Date) -> WidgetSnapshot {
        WidgetSnapshot(meetings: [
            WidgetMeeting(id: "a", title: "Design review", start: now.addingTimeInterval(12 * 60),
                          end: now.addingTimeInterval(42 * 60), colorHex: "#E8743B", joinURL: URL(string: "https://meet.google.com/abc")),
            WidgetMeeting(id: "b", title: "1:1 with Sam", start: now.addingTimeInterval(90 * 60),
                          end: now.addingTimeInterval(120 * 60), colorHex: "#1F9E86", joinURL: nil),
        ], savedAt: now)
    }
}

/// The next meeting on an MB-1 LCD: a lamp that turns orange as it nears, the countdown in seven-segment digits, and
/// the title. Medium adds what comes after; the Lock Screen gets compact text versions.
struct NextMeetingWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NextMeeting", provider: NextMeetingProvider()) { entry in
            NextMeetingWidgetView(entry: entry)
        }
        .configurationDisplayName("Next meeting")
        .description("Counts down to your next meeting.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryCircular, .accessoryInline])
    }
}

struct NextMeetingWidgetView: View {
    let entry: NextMeetingEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        content
            .containerBackground(for: .widget) { Color(sk1Hex: SK1.palette(for: scheme).chassis) }
            .widgetURL(link)
    }

    /// Tapping joins a meeting that's on or starts within 10 minutes; otherwise it opens Today.
    private var link: URL {
        guard let m = entry.meeting, let url = m.joinURL, m.start.timeIntervalSince(entry.date) < 10 * 60 else {
            return MeetballLink.today
        }
        return MeetballLink.join(url)
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .accessoryInline: inline
        case .accessoryCircular: circular
        case .accessoryRectangular: rectangular
        case .systemMedium: medium
        default: small
        }
    }

    // MARK: Home Screen

    private var small: some View {
        VStack(alignment: .leading, spacing: 8) {
            lcd(height: 58)
            if let m = entry.meeting {
                Text(m.title).font(.system(size: 14, weight: .bold)).lineLimit(2)
                Text(timeRange(m)).font(.caption2).foregroundStyle(.secondary)
            } else {
                Text(entry.snapshot == nil ? "Open Meetball once to set up." : "Nothing in the next two days.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    private var medium: some View {
        HStack(alignment: .top, spacing: 12) {
            small.frame(maxWidth: .infinity)
            VStack(alignment: .leading, spacing: 6) {
                Text("LATER").font(.system(size: 9, weight: .heavy)).tracking(1).foregroundStyle(.secondary)
                let later = entry.snapshot?.later(than: entry.meeting, now: entry.date, limit: 3) ?? []
                if later.isEmpty {
                    Text("Nothing else.").font(.caption).foregroundStyle(.secondary)
                }
                ForEach(later, id: \.id) { m in
                    HStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 1.5).fill(WidgetStyle.color(m.colorHex)).frame(width: 3, height: 26)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(m.title).font(.caption.weight(.semibold)).lineLimit(1)
                            Text(dayTime(m.start)).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func lcd(height: CGFloat) -> some View {
        WidgetLCD {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Circle().fill(entry.meeting.map { WidgetStyle.lamp(for: $0, now: entry.date) } ?? WidgetStyle.teal)
                        .frame(width: 6, height: 6)
                    Text(caption).font(.system(size: 9, weight: .heavy)).tracking(1).foregroundStyle(WidgetStyle.lcdInk)
                        .lineLimit(1)
                }
                HStack(alignment: .bottom, spacing: 3) {
                    if let m = entry.meeting {
                        let target = m.start <= entry.date ? m.end : m.start
                        let c = WidgetCountdown.digits(target.timeIntervalSince(entry.date))
                        SKSevenSegment(c.digits, digitHeight: 24, spacing: 3, color: WidgetStyle.lcdInk)
                        Text(c.unit).font(.system(size: 9, weight: .heavy)).foregroundStyle(WidgetStyle.lcdInk)
                    } else {
                        Text("MB-1").font(.system(size: 18, weight: .heavy, design: .monospaced)).foregroundStyle(WidgetStyle.lcdInk)
                    }
                }
            }
            .padding(.horizontal, 8)
        }
        .frame(height: height)
    }

    private var caption: String {
        guard let m = entry.meeting else { return "All clear" }
        return m.start <= entry.date ? "Now · ends in" : "Starts in"
    }

    // MARK: Lock Screen

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            if let m = entry.meeting {
                Text(m.start <= entry.date ? "NOW" : "NEXT").font(.caption2.weight(.heavy))
                Text(m.title).font(.headline).lineLimit(1)
                if m.start <= entry.date {
                    Text("ends \(Text(m.end, style: .relative))").font(.caption).lineLimit(1)
                } else {
                    Text("\(Text(m.start, style: .time)) · in \(Text(m.start, style: .relative))").font(.caption).lineLimit(1)
                }
            } else {
                Text("MB-1").font(.caption2.weight(.heavy))
                Text("All clear").font(.headline)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            if let m = entry.meeting {
                let target = m.start <= entry.date ? m.end : m.start
                let c = WidgetCountdown.digits(target.timeIntervalSince(entry.date))
                VStack(spacing: -2) {
                    Text(c.digits).font(.system(size: 18, weight: .bold, design: .rounded)).minimumScaleFactor(0.6)
                    Text(c.unit).font(.system(size: 8, weight: .heavy))
                }
            } else {
                Image(systemName: "checkmark")
            }
        }
    }

    private var inline: some View {
        Group {
            if let m = entry.meeting {
                if m.start <= entry.date {
                    Text("\(m.title) · ends \(Text(m.end, style: .time))")
                } else {
                    Text("\(m.title) · \(Text(m.start, style: .time))")
                }
            } else {
                Text("No meetings ahead")
            }
        }
    }

    // MARK: Text

    private func timeRange(_ m: WidgetMeeting) -> String {
        "\(m.start.formatted(date: .omitted, time: .shortened)) – \(m.end.formatted(date: .omitted, time: .shortened))"
    }

    private func dayTime(_ d: Date) -> String {
        Calendar.current.isDateInToday(d) ? d.formatted(date: .omitted, time: .shortened)
            : d.formatted(.dateTime.weekday(.abbreviated).hour().minute())
    }
}
