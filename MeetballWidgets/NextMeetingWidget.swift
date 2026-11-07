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
            WidgetMeeting(id: "a", title: "Design review", start: now.addingTimeInterval(8 * 60),
                          end: now.addingTimeInterval(38 * 60), colorHex: "#E8743B", joinURL: URL(string: "https://meet.google.com/abc")),
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
    /// Draws this size instead of the environment's, for previews and renders outside WidgetKit.
    var previewFamily: WidgetFamily? = nil
    @Environment(\.widgetFamily) private var environmentFamily
    private var family: WidgetFamily { previewFamily ?? environmentFamily }
    @Environment(\.colorScheme) private var scheme
    /// False in StandBy (the phone on its side on a charger), where the widget fills the half screen as a desk clock.
    @Environment(\.showsWidgetContainerBackground) private var showsBackground

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
        default: if showsBackground { small } else { standBy }
        }
    }

    // MARK: Home Screen

    /// The LCD (countdown and an LED bar for how far along), the meeting with its calendar colour, time, service and a
    /// lit Join key when it's time, then a footer: what clashes with it, what comes after, or when you're free.
    private var small: some View { smallCard(footer: true) }

    private func smallCard(footer: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            lcd(height: 54)
            if let m = entry.meeting {
                ViewThatFits(in: .vertical) {
                    meetingBlock(m, titleLines: 2, footer: footer)
                    meetingBlock(m, titleLines: 1, footer: footer)
                }
            } else {
                Text(entry.snapshot == nil ? "Open Meetball once to set up." : "Nothing in the next two days.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    private func meetingBlock(_ m: WidgetMeeting, titleLines: Int, footer: Bool) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .top, spacing: 6) {
                RoundedRectangle(cornerRadius: 1.5).fill(WidgetStyle.color(m.colorHex)).frame(width: 3)
                VStack(alignment: .leading, spacing: 3) {
                    Text(m.title).font(.system(size: 14, weight: .bold)).lineLimit(titleLines)
                        .fixedSize(horizontal: false, vertical: true)
                    detailRow(m)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            if footer { footerLine(m) }
        }
    }

    /// "2:00 – 2:30 · Meet", or the time and a lit JOIN key once it can be joined (on now, or within 10 minutes).
    private func detailRow(_ m: WidgetMeeting) -> some View {
        HStack(spacing: 4) {
            // The full range when it fits; beside the JOIN key, just the start ("5:25 PM") or, while on, the end
            // ("til 5:55 PM").
            ViewThatFits(in: .horizontal) {
                Text(timeRange(m))
                Text(m.start <= entry.date ? "til \(shortTime(m.end))" : shortTime(m.start))
            }
            .font(.system(size: 11, weight: .medium)).monospacedDigit()
            .foregroundStyle(.secondary).lineLimit(1)
            if m.joinURL != nil && m.start.timeIntervalSince(entry.date) < 10 * 60 {
                Spacer(minLength: 2)
                HStack(spacing: 2) {
                    Image(systemName: "video.fill").font(.system(size: 7, weight: .bold))
                    Text("JOIN").font(.system(size: 8.5, weight: .heavy)).tracking(0.6)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 5).padding(.vertical, 2)
                .background(WidgetStyle.orange, in: Capsule())
            } else if let service = WidgetService.name(m.joinURL) {
                Text("· \(service)").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }

    /// A clash first ("+1 AT THE SAME TIME"), else the next meeting that day ("THEN 1:1 with Sam 3:30"), else when the
    /// day frees up ("FREE AFTER 2:30").
    @ViewBuilder private func footerLine(_ m: WidgetMeeting) -> some View {
        let clashes = entry.snapshot?.overlapping(m, at: entry.date) ?? []
        HStack(spacing: 4) {
            if let first = clashes.first {
                Image(systemName: "rectangle.on.rectangle").font(.system(size: 8, weight: .bold)).foregroundStyle(WidgetStyle.orange)
                Text("+\(clashes.count)").font(.system(size: 9, weight: .heavy)).foregroundStyle(WidgetStyle.orange)
                Text(first.title).font(.system(size: 10, weight: .semibold)).lineLimit(1)
            } else if let then = entry.snapshot?.following(m) {
                Text("THEN").font(.system(size: 8, weight: .heavy)).tracking(0.8).foregroundStyle(.secondary)
                Circle().fill(WidgetStyle.color(then.colorHex)).frame(width: 5, height: 5)
                Text(then.title).font(.system(size: 10, weight: .semibold)).lineLimit(1)
                Spacer(minLength: 2)
                Text(shortTime(then.start)).font(.system(size: 10, weight: .medium)).monospacedDigit()
                    .foregroundStyle(.secondary).layoutPriority(1)
            } else {
                Text("FREE AFTER").font(.system(size: 8, weight: .heavy)).tracking(0.8).foregroundStyle(.secondary)
                Text(shortTime(m.end)).font(.system(size: 10, weight: .semibold)).monospacedDigit()
            }
        }
        .lineLimit(1)
    }

    /// StandBy: the countdown as big as it goes, the title under it, like an MB-1 desk clock.
    private var standBy: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Circle().fill(entry.meeting.map { WidgetStyle.lamp(for: $0, now: entry.date) } ?? WidgetStyle.teal)
                    .frame(width: 10, height: 10)
                Text(caption.uppercased()).font(.system(size: 13, weight: .heavy)).tracking(1.5)
            }
            if let m = entry.meeting {
                let target = m.start <= entry.date ? m.end : m.start
                let c = WidgetCountdown.digits(target.timeIntervalSince(entry.date))
                HStack(alignment: .bottom, spacing: 6) {
                    SKSevenSegment(c.digits, digitHeight: 64, spacing: 6, color: WidgetStyle.orange)
                    Text(c.unit).font(.system(size: 16, weight: .heavy)).foregroundStyle(WidgetStyle.orange)
                }
                Text(m.title).font(.system(size: 18, weight: .bold)).lineLimit(1)
            } else {
                Text(entry.date, style: .time).font(.system(size: 54, weight: .bold, design: .monospaced))
                Text("All clear").font(.headline).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var medium: some View {
        HStack(alignment: .top, spacing: 12) {
            smallCard(footer: false).frame(maxWidth: .infinity)
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
                        SKSevenSegment(c.digits, digitHeight: 22, spacing: 3, color: WidgetStyle.lcdInk)
                        Text(c.unit).font(.system(size: 9, weight: .heavy)).foregroundStyle(WidgetStyle.lcdInk)
                    } else {
                        Text("MB-1").font(.system(size: 18, weight: .heavy, design: .monospaced)).foregroundStyle(WidgetStyle.lcdInk)
                    }
                }
                if let m = entry.meeting, let p = WidgetSnapshot.progress(of: m, at: entry.date) {
                    ledBar(p)
                }
            }
            .padding(.horizontal, 8)
        }
        .frame(height: height)
    }

    /// Ten LED segments on the glass: how much of the meeting has gone by, or how close the last hour has brought it.
    private func ledBar(_ progress: Double) -> some View {
        let lit = Int((progress * 10).rounded())
        return HStack(spacing: 2) {
            ForEach(0..<10, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1)
                    .fill(WidgetStyle.lcdInk.opacity(i < lit ? 0.85 : 0.15))
                    .frame(height: 3)
            }
        }
        .accessibilityHidden(true)
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

    /// "2:00 – 2:30", with the weekday first when it isn't today ("Tue 9:00 – 9:30").
    private func timeRange(_ m: WidgetMeeting) -> String {
        let day = Calendar.current.isDate(m.start, inSameDayAs: entry.date) ? "" : m.start.formatted(.dateTime.weekday(.abbreviated)) + " "
        return "\(day)\(shortTime(m.start)) – \(shortTime(m.end))"
    }

    private func shortTime(_ d: Date) -> String { d.formatted(date: .omitted, time: .shortened) }

    private func dayTime(_ d: Date) -> String {
        Calendar.current.isDateInToday(d) ? d.formatted(date: .omitted, time: .shortened)
            : d.formatted(.dateTime.weekday(.abbreviated).hour().minute())
    }
}

#Preview("Small") {
    NextMeetingWidgetView(entry: NextMeetingEntry(date: .now, snapshot: NextMeetingProvider.sample(.now)), previewFamily: .systemSmall)
        .padding(16).frame(width: 170, height: 170)
}

#Preview("Medium") {
    NextMeetingWidgetView(entry: NextMeetingEntry(date: .now, snapshot: NextMeetingProvider.sample(.now)), previewFamily: .systemMedium)
        .padding(16).frame(width: 364, height: 170)
}
