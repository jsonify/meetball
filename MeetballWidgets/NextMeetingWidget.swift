import SwiftUI
import WidgetKit
import SK1Tokens
import SK1UI

struct NextMeetingEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?

    var meeting: WidgetMeeting? { snapshot?.current(at: date) }
    /// What the display reads: there is one for every state, so no widget is ever blank.
    var readout: WidgetReadout { WidgetReadout.make(snapshot, at: date) }
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

/// The MB-1 as a widget. Small is the LCD itself, glass from edge to edge: a lamp that turns orange as a meeting nears,
/// big seven-segment digits (the start time, then a countdown inside the hour), the title, the tape of the day lit
/// where there are meetings, and a line that keeps count by the second. Medium is the instrument on its chassis, with
/// what comes after. The Lock Screen gets the same display in one
/// colour, and always reads something: all clear, or to open Meetball when what it knows has run out.
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
            .containerBackground(for: .widget) {
                if family == .systemSmall {
                    WidgetGlassFace()
                } else {
                    Color(sk1Hex: SK1.palette(for: scheme).chassis)
                }
            }
            // Tapping never joins: it opens the Day grid on today at the time now.
            .widgetURL(MeetballLink.today)
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

    /// The whole widget as the LCD (its glass and bezel are the background, `WidgetGlassFace`), everything in LCD ink:
    /// as much as the size has room for, the digits as big as they go.
    private var small: some View {
        ViewThatFits(in: .vertical) {
            face(digit: 38, titleLines: 2, footer: true)
            face(digit: 34, titleLines: 1, footer: true)
            face(digit: 30, titleLines: 1, footer: false)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .foregroundStyle(WidgetStyle.lcdInk)
    }

    private func face(digit: CGFloat, titleLines: Int, footer: Bool) -> some View {
        let r = entry.readout
        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 4) {
                Circle().fill(lampColor).frame(width: 6, height: 6)
                Text(r.caption).font(.system(size: 9, weight: .heavy)).tracking(1).fixedSize()
                Spacer(minLength: 0)
            }
            .frame(height: 11)
            HStack(alignment: .bottom, spacing: 4) {
                // A long time ("12:30") steps down a size rather than running off the glass.
                ViewThatFits(in: .horizontal) {
                    SKSevenSegment(r.digits, digitHeight: digit, spacing: 4, color: WidgetStyle.lcdInk)
                    SKSevenSegment(r.digits, digitHeight: digit * 0.82, spacing: 3.5, color: WidgetStyle.lcdInk)
                    SKSevenSegment(r.digits, digitHeight: digit * 0.66, spacing: 3, color: WidgetStyle.lcdInk)
                }
                Text(r.unit).font(.system(size: 10, weight: .heavy)).fixedSize()
            }
            Text(r.message).font(.system(size: 14, weight: .bold)).lineLimit(titleLines)
                .fixedSize(horizontal: false, vertical: true)
            WidgetTape(slots: tape(slots: 16), height: 6, scale: true,
                       idle: WidgetStyle.lcdInk.opacity(0.16), lit: { _ in WidgetStyle.lcdInk })
            if footer { faceFooter(r) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(r.caption.capitalized) \(r.digits) \(r.unit.lowercased()), \(r.message)"))
    }

    /// The tape of the day the next meeting is on (see `WidgetSnapshot.tapeStart`).
    private func tape(slots: Int) -> [WidgetTapeSlot] {
        guard let snapshot = entry.snapshot else { return [] }
        return snapshot.tape(from: snapshot.tapeStart(at: entry.date), slots: slots)
    }

    /// The bottom line of the glass. Left: the count to a meeting further off than an hour, ticking by the second
    /// ("IN 9:51:07"), or its time once the digits count down. Right: a clash, what time the
    /// next one is, or that it's the last.
    private func faceFooter(_ r: WidgetReadout) -> some View {
        HStack(spacing: 3) {
            if let m = r.meeting {
                switch r.phase {
                case .later:
                    footerLabel("IN")
                    Text(m.start, style: .timer).font(.system(size: 10, weight: .bold, design: .monospaced))
                        .multilineTextAlignment(.leading).frame(width: 54, alignment: .leading)
                case .live:
                    footerLabel("TIL")
                    footerValue(shortTime(m.end))
                default:
                    footerLabel("AT")
                    footerValue(shortTime(m.start))
                }
                Spacer(minLength: 2)
                let clashes = entry.snapshot?.overlapping(m, at: entry.date) ?? []
                if !clashes.isEmpty {
                    footerLabel("+\(clashes.count) CLASH")
                } else if let then = entry.snapshot?.following(m) {
                    footerLabel("THEN")
                    footerValue(shortTime(then.start))
                } else {
                    footerLabel("LAST ONE")
                }
            } else if r.phase == .clear, let saved = entry.snapshot?.savedAt {
                footerLabel("CHECKED")
                footerValue(dayTime(saved))
            } else {
                footerLabel("TAP TO OPEN")
            }
        }
        .lineLimit(1)
        .frame(height: 14)
    }

    private func footerLabel(_ text: String) -> some View {
        Text(text).font(.system(size: 8, weight: .heavy)).tracking(0.8).opacity(0.7).fixedSize()
    }

    private func footerValue(_ text: String) -> some View {
        Text(text).font(.system(size: 10, weight: .bold)).monospacedDigit().fixedSize()
    }

    /// The instrument on its chassis, for Medium: the nameplate (how many are left today), the LCD and the tape in
    /// the calendars' colours.
    private var instrument: some View {
        VStack(alignment: .leading, spacing: 6) {
            nameplate
            display(height: 66, digit: 22)
            WidgetTape(slots: tape(slots: 16), height: 6, scale: true,
                       idle: Color.primary.opacity(0.14), lit: { WidgetStyle.color($0) })
        }
    }

    /// "● MB-1" engraved on the chassis, and the count the app's own display shows: "3 LEFT TODAY".
    private var nameplate: some View {
        HStack(spacing: 4) {
            Circle().fill(lampColor).frame(width: 6, height: 6)
            Text("MB-1").font(.system(size: 9, weight: .heavy, design: .monospaced)).tracking(1)
            Spacer(minLength: 4)
            if let snapshot = entry.snapshot, entry.readout.phase != .stale {
                Text("\(snapshot.remainingToday(at: entry.date)) LEFT TODAY")
                    .font(.system(size: 8, weight: .heavy)).tracking(0.8).foregroundStyle(.secondary)
            }
        }
        .lineLimit(1)
        .frame(height: 10)
    }

    private var lampColor: Color {
        entry.meeting.map { WidgetStyle.lamp(for: $0, now: entry.date) } ?? WidgetStyle.teal
    }

    /// The LCD: what the digits are, the digits, and the title on the glass.
    private func display(height: CGFloat, digit: CGFloat) -> some View {
        let r = entry.readout
        return WidgetLCD {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Circle().fill(lampColor).frame(width: 5, height: 5)
                    Text(r.caption).font(.system(size: 8.5, weight: .heavy)).tracking(1)
                }
                .frame(height: 10)
                HStack(alignment: .bottom, spacing: 3) {
                    SKSevenSegment(r.digits, digitHeight: digit, spacing: 3, color: WidgetStyle.lcdInk)
                    Text(r.unit).font(.system(size: 9, weight: .heavy))
                }
                Text(r.message).font(.system(size: 11.5, weight: .bold)).frame(height: 14)
            }
            .lineLimit(1)
            .foregroundStyle(WidgetStyle.lcdInk)
            .padding(.horizontal, 8)
        }
        .frame(height: height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(r.caption.capitalized) \(r.digits) \(r.unit.lowercased()), \(r.message)"))
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
            instrument.frame(maxWidth: .infinity)
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

    private var caption: String {
        guard let m = entry.meeting else { return "All clear" }
        return m.start <= entry.date ? "Now · ends in" : "Starts in"
    }

    // MARK: Lock Screen

    /// The display on a glass plate, in the Lock Screen's one colour: the caption with today's count, the digits beside
    /// the title and a second line (how long until it starts, or when it ends), and the tape of the day (twelve hours of
    /// it) with its hour scale when there's room. Every state reads something, so the plate is never empty.
    private var rectangular: some View {
        ViewThatFits(in: .vertical) {
            plate(scale: true)
            plate(scale: false)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            AccessoryWidgetBackground().clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private func plate(scale: Bool) -> some View {
        let r = entry.readout
        let busy = r.phase == .live || r.phase == .soon
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                // Lit while a meeting is on or within the hour; an empty socket otherwise.
                Circle().strokeBorder(.white, lineWidth: 1).background(Circle().fill(.white.opacity(busy ? 1 : 0)))
                    .frame(width: 6, height: 6)
                Text(r.caption).font(.system(size: 9, weight: .heavy)).tracking(0.8)
                Spacer(minLength: 2)
                if let snapshot = entry.snapshot, r.phase != .stale {
                    Text("\(snapshot.remainingToday(at: entry.date)) LEFT").font(.system(size: 9, weight: .heavy)).tracking(0.8)
                        .opacity(0.7)
                }
            }
            .lineLimit(1)
            .frame(height: 11)
            HStack(alignment: .center, spacing: 7) {
                HStack(alignment: .bottom, spacing: 2) {
                    SKSevenSegment(r.digits, digitHeight: 20, spacing: 2.5, color: .white)
                    Text(r.unit).font(.system(size: 8, weight: .heavy))
                }
                .fixedSize()
                VStack(alignment: .leading, spacing: 0) {
                    Text(r.message).font(.system(size: 12.5, weight: .semibold))
                    plateDetail(r).font(.system(size: 10, weight: .medium)).monospacedDigit().opacity(0.75)
                }
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            WidgetTape(slots: tape(slots: 24), height: 5, scale: scale,
                       idle: .white.opacity(0.28), lit: { _ in .white })
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(r.caption.capitalized) \(r.digits) \(r.unit.lowercased()), \(r.message)"))
    }

    /// Under the title: "in 11 hr, 33 min" (it keeps count by itself) while the digits show the start time, the
    /// meeting's times once they count down, or how fresh an empty display is.
    private func plateDetail(_ r: WidgetReadout) -> Text {
        guard let m = r.meeting else {
            guard r.phase == .clear, let saved = entry.snapshot?.savedAt else { return Text("Tap to open") }
            return Text("checked \(dayTime(saved))")
        }
        let service = WidgetService.name(m.joinURL).map { " · \($0)" } ?? ""
        switch r.phase {
        case .later: return Text("in \(Text(m.start, style: .relative))")
        case .live: return Text("til \(shortTime(m.end))\(service)")
        default: return Text("\(shortTime(m.start)) – \(shortTime(m.end))\(service)")
        }
    }

    /// The digits in a ring of twelve LED ticks, lit as the meeting nears over its last hour, then as it goes by.
    private var circular: some View {
        let r = entry.readout
        let lit = r.meeting.flatMap { WidgetSnapshot.progress(of: $0, at: entry.date) }.map { Int(($0 * 12).rounded()) } ?? 0
        return ZStack {
            AccessoryWidgetBackground()
            GeometryReader { geo in
                let side = min(geo.size.width, geo.size.height)
                ForEach(0..<12, id: \.self) { i in
                    Capsule().fill(.white.opacity(i < lit ? 1 : 0.28))
                        .frame(width: 2.5, height: 5)
                        .offset(y: -(side / 2 - 5))
                        .rotationEffect(.degrees(Double(i) * 30))
                        .position(x: geo.size.width / 2, y: geo.size.height / 2)
                }
            }
            .accessibilityHidden(true)
            VStack(spacing: -1) {
                Text(r.digits).font(.system(size: 15, weight: .bold, design: .rounded)).monospacedDigit()
                    .minimumScaleFactor(0.6).lineLimit(1)
                if !r.unit.isEmpty { Text(r.unit).font(.system(size: 7.5, weight: .heavy)) }
            }
            .padding(.horizontal, 11)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(r.caption.capitalized) \(r.digits) \(r.unit.lowercased())"))
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
