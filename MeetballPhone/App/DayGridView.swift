import SwiftUI
import SK1Tokens
import SK1UI

/// The day on a time grid, one day or three side by side: an hour scale down the left, meetings as tinted blocks with
/// overlapping ones packed into columns (the Mac's `TimeGridLayoutBuilder`), all-day and multi-day bars pinned above
/// and folded to "+N more" past two lanes, a meeting-load LED row under each date, and the red now line. Tap an empty
/// slot to pencil in a meeting there, tap the pencilled block to compose it; swipe sideways to page, pinch to zoom.
/// The next meeting rides on top as a slim Up Next card, so this is the home screen.
struct DayGridView: View {
    @EnvironmentObject private var store: PhoneStore
    var open: (CalendarEvent) -> Void
    var add: (Date?) -> Void

    @SceneStorage("grid.span") private var span = 1
    @AppStorage("phone.grid.hourHeight") private var hourHeight: Double = DayGridMetrics.defaultHourHeight
    @State private var anchor = Calendar.app.startOfDay(for: Date())
    @State private var allDayOpen = false
    @State private var pencil: Date?
    @State private var zoomBase: Double?
    @State private var scrollRequest = 0
    @State private var paged = 0

    private var dayCount: Int { span == 3 ? 3 : 1 }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { tl in
            content(now: tl.date)
        }
        .onChange(of: span) { _, _ in pencil = nil; scrollRequest += 1 }
        .sensoryFeedback(.selection, trigger: paged)
    }

    private func content(now: Date) -> some View {
        let cal = Calendar.app
        let days = TimeGridLayoutBuilder.days(from: anchor, count: dayCount, calendar: cal)
        let events = store.events(from: anchor, days: dayCount)
        let range = DateInterval(start: days.first ?? anchor,
                                 end: cal.date(byAdding: .day, value: dayCount, to: anchor) ?? anchor)
        let derived = CalendarDerivedEventsBuilder.build(events: events, range: range, calendar: cal)
        let bars = TimeGridLayoutBuilder.allDayBars(events: events, firstDay: anchor, dayCount: dayCount, calendar: cal)
        let strip = TimeGridLayoutBuilder.collapse(bars, dayCount: dayCount, maxLanes: allDayOpen ? 8 : 2)
        let loads = MeetingLoadBuilder.build(events: events, from: anchor, days: dayCount, calendar: cal)
        return VStack(spacing: 12) {
            header(now: now, days: days)
                .padding(.horizontal, 16)
            if let next = MenuAgendaBuilder.hero(store.events(from: now, days: 2), now: now, horizon: 24 * 3600) {
                DayGridUpNext(event: next, now: now, open: open)
                    .padding(.horizontal, 10)
            }
            SKWell {
                VStack(spacing: 0) {
                    DayGridDateRow(days: days, loads: loads, now: now, span: dayCount) { day in
                        anchor = day
                        span = 1
                    }
                    if !bars.isEmpty {
                        SKGroove()
                        DayGridAllDayStrip(strip: strip, dayCount: dayCount, expanded: allDayOpen, open: open) {
                            withAnimation(.easeInOut(duration: 0.2)) { allDayOpen.toggle() }
                        }
                    }
                    SKGroove()
                    grid(days: days, derived: derived, now: now)
                }
            }
            .padding(.horizontal, 10)
        }
        .padding(.top, 8)
    }

    // MARK: Header

    private func header(now: Date, days: [Date]) -> some View {
        let cal = Calendar.app
        let showsToday = days.contains { cal.isDate($0, inSameDayAs: now) }
        return VStack(alignment: .leading, spacing: 10) {
            PhoneScreenHeader(title: anchor.formatted(.dateTime.month(.wide)), detail: detail(days: days, now: now)) {
                HStack(spacing: 6) {
                    Button { page(-1) } label: { Image(systemName: "chevron.left") }
                        .buttonStyle(.sk1Key()).accessibilityLabel(dayCount == 1 ? "Previous day" : "Previous three days")
                    Button("Today") {
                        anchor = cal.startOfDay(for: now)
                        pencil = nil
                        scrollRequest += 1
                    }
                    .buttonStyle(.sk1Key(isOn: showsToday))
                    Button { page(1) } label: { Image(systemName: "chevron.right") }
                        .buttonStyle(.sk1Key()).accessibilityLabel(dayCount == 1 ? "Next day" : "Next three days")
                }
            }
            // Full width and key height, so the 3-day view can't be missed.
            SKSegmented(selection: $span, options: [SKSegmented<Int>.Option(1, "Day"), SKSegmented<Int>.Option(3, "3 Day")],
                        height: 30)
                .frame(maxWidth: .infinity)
        }
    }

    private func detail(days: [Date], now: Date) -> String {
        guard let first = days.first, let last = days.last else { return "" }
        if days.count == 1 { return PhoneAgenda.dayTitle(first, now: now) + " · " + first.formatted(.dateTime.weekday(.wide).day()) }
        let a = first.formatted(.dateTime.month(.abbreviated).day())
        let b = last.formatted(Calendar.app.isDate(first, equalTo: last, toGranularity: .month)
                               ? .dateTime.day() : .dateTime.month(.abbreviated).day())
        return "\(a) – \(b) · \(first.formatted(.dateTime.year()))"
    }

    private func page(_ direction: Int) {
        guard let next = Calendar.app.date(byAdding: .day, value: direction * dayCount, to: anchor) else { return }
        anchor = next
        pencil = nil
        paged += 1
    }

    // MARK: Grid

    private func grid(days: [Date], derived: CalendarDerivedEvents, now: Date) -> some View {
        let h = CGFloat(hourHeight)
        return ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                HStack(alignment: .top, spacing: 0) {
                    DayGridHourScale(hourHeight: h, now: now, showsNow: days.contains { Calendar.app.isDate($0, inSameDayAs: now) })
                    ForEach(days, id: \.self) { day in
                        DayGridColumn(day: day, segments: timed(derived, day), now: now, hourHeight: h,
                                      pencil: pencil.flatMap { Calendar.app.isDate($0, inSameDayAs: day) ? $0 : nil },
                                      open: { pencil = nil; open($0) },
                                      tapEmpty: { pencil = $0 },
                                      compose: { start in pencil = nil; add(start) })
                            .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: h * 24)
                .padding(.bottom, 12)
            }
            .simultaneousGesture(swipe)
            .simultaneousGesture(zoom)
            .onAppear { scroll(proxy, days: days, now: now, animated: false) }
            .onChange(of: anchor) { _, _ in scroll(proxy, days: TimeGridLayoutBuilder.days(from: anchor, count: dayCount), now: Date(), animated: true) }
            .onChange(of: scrollRequest) { _, _ in scroll(proxy, days: TimeGridLayoutBuilder.days(from: anchor, count: dayCount), now: Date(), animated: true) }
        }
    }

    private func timed(_ derived: CalendarDerivedEvents, _ day: Date) -> [CalendarEventDaySegment] {
        (derived.segmentsByDay[Calendar.app.startOfDay(for: day)] ?? []).filter { !$0.event.isBarEvent() }
    }

    private func scroll(_ proxy: ScrollViewProxy, days: [Date], now: Date, animated: Bool) {
        let hour = TimeGridLayoutBuilder.openingHour(days: days, now: now)
        DispatchQueue.main.async {
            if animated {
                withAnimation(.easeInOut(duration: 0.3)) { proxy.scrollTo(DayGridHourScale.anchorID(hour), anchor: .top) }
            } else {
                proxy.scrollTo(DayGridHourScale.anchorID(hour), anchor: .top)
            }
        }
    }

    /// A sideways swipe pages by the days shown; a mostly vertical one is left to the scroll view.
    private var swipe: some Gesture {
        DragGesture(minimumDistance: 30).onEnded { v in
            let dx = v.translation.width, dy = v.translation.height
            guard abs(dx) > 60, abs(dx) > abs(dy) * 2 else { return }
            page(dx < 0 ? 1 : -1)
        }
    }

    private var zoom: some Gesture {
        MagnifyGesture()
            .onChanged { v in
                let base = zoomBase ?? hourHeight
                zoomBase = base
                hourHeight = min(DayGridMetrics.maxHourHeight, max(DayGridMetrics.minHourHeight, base * v.magnification))
            }
            .onEnded { _ in zoomBase = nil }
    }
}

enum DayGridMetrics {
    /// Wide enough for the now tag's "10:21 PM" on one line.
    static let gutterWidth: CGFloat = 60
    static let defaultHourHeight: Double = 56
    static let minHourHeight: Double = 36
    static let maxHourHeight: Double = 120
    static let laneHeight: CGFloat = 24
}

// MARK: - Up next

/// The Today tab's "Up next" card, slimmed to one row for the top of the grid: the countdown on an LCD, the title and
/// time, and the Join key. Its edge warms from teal to a glowing orange as the meeting nears (`HeroUrgency`).
struct DayGridUpNext: View {
    let event: CalendarEvent
    let now: Date
    let open: (CalendarEvent) -> Void

    var body: some View {
        let inProgress = event.start <= now
        let target = inProgress ? event.end : event.start
        let countdown = SK1CountdownDigits.compact(target.timeIntervalSince(now))
        let urgency = HeroUrgency.of(event, now: now)
        let shape = RoundedRectangle(cornerRadius: SK1.Metrics.wellRadius, style: .continuous)
        SKWell {
            HStack(spacing: 10) {
                SK1CountdownLCD(caption: inProgress ? "Ends in" : "Up next",
                                digits: countdown.digits, unit: countdown.unit, live: inProgress,
                                lamp: urgency.lamp, lampBlinking: urgency.lampBlinks, height: 44,
                                accessibilityText: (inProgress ? "On now, ends " : "Up next, starts ")
                                    + RelativeTimeFormatter.string(for: target, relativeTo: now))
                    .frame(width: 118)
                Button { open(event) } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 5) {
                            Circle().fill(Color(hex: event.colorHex)).frame(width: 7, height: 7)
                            Text(event.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                        }
                        Text(when).font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                PhoneJoinButton(event: event, size: .small)
            }
            .padding(8)
            .background(shape.fill(urgency.edgeColor.opacity(urgency.washOpacity)))
        }
        .overlay(
            shape.strokeBorder(urgency.edgeColor.opacity(urgency.edgeOpacity), lineWidth: urgency.edgeWidth + 0.5)
                .shadow(color: urgency.edgeColor.opacity(urgency.glow > 0 ? 0.6 : 0), radius: urgency.glow * 1.5)
                .allowsHitTesting(false)
        )
        .animation(.easeInOut(duration: 0.4), value: urgency)
        .sensoryFeedback(.warning, trigger: urgency) { _, new in new == .imminent }
    }

    private var when: String {
        let day = Calendar.app.isDate(event.start, inSameDayAs: now) ? "" : PhoneAgenda.dayTitle(event.start, now: now) + " "
        return "\(day)\(event.start.shortTime) – \(event.end.shortTime)"
    }
}

// MARK: - Date row

/// The dates across the top: weekday, the day number (today's on a lit LCD tile), and an LED row of the day's
/// meeting load, as on the Week tab's meter. In the 3-day view a tap opens that day on its own.
struct DayGridDateRow: View {
    let days: [Date]
    let loads: [DayMeetingLoad]
    let now: Date
    let span: Int
    let pick: (Date) -> Void

    var body: some View {
        HStack(spacing: 0) {
            SKCaption(weekLabel, tone: .soft)
                .frame(width: DayGridMetrics.gutterWidth)
            ForEach(Array(days.enumerated()), id: \.element) { i, day in
                let load = i < loads.count ? loads[i] : nil
                Group {
                    if span > 1 {
                        Button { pick(day) } label: { cell(day, load: load) }
                            .buttonStyle(.plain)
                            .accessibilityHint("Opens this day")
                    } else {
                        cell(day, load: load)
                    }
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(accessibility(day, load: load)))
                .accessibilityAddTraits(span > 1 ? .isButton : [])
            }
        }
        .padding(.vertical, 8)
    }

    private var weekLabel: String {
        guard let first = days.first else { return "" }
        return "W\(Calendar.app.component(.weekOfYear, from: first))"
    }

    private func cell(_ day: Date, load: DayMeetingLoad?) -> some View {
        let isToday = Calendar.app.isDate(day, inSameDayAs: now)
        let ink = Color(sk1Hex: SK1.lcdInk)
        let number = Text("\(Calendar.app.component(.day, from: day))")
            .font(.system(size: 20, weight: .heavy, design: .monospaced))
        return VStack(spacing: 4) {
            HStack(spacing: 4) {
                if isToday { SKLamp(color: .orange, lit: true, glow: 3, size: 5) }
                SKCaption(day.formatted(.dateTime.weekday(.abbreviated)), tone: isToday ? .ink : .soft)
            }
            Group {
                if isToday {
                    SKLCD(radius: 6, inset: 2) {
                        number.foregroundStyle(ink).padding(.horizontal, 8)
                    }
                    .fixedSize()
                } else {
                    number.foregroundStyle(.primary)
                }
            }
            .frame(height: 30)
            DayGridLoadLEDs(hours: load?.hours ?? 0)
        }
        .frame(maxWidth: .infinity, alignment: span == 1 ? .leading : .center)
        .padding(.leading, span == 1 ? 8 : 0)
        .contentShape(Rectangle())
    }

    private func accessibility(_ day: Date, load: DayMeetingLoad?) -> String {
        let name = (Calendar.app.isDate(day, inSameDayAs: now) ? "Today, " : "")
            + day.formatted(.dateTime.weekday(.wide).month(.wide).day())
        guard let load, load.count > 0 else { return name + ", no meetings" }
        return name + ", \(load.count) meetings, " + String(format: "%.1f hours", load.hours)
    }
}

/// Eight tiny LEDs lit by hours in meetings: teal, amber past five hours, red past seven.
struct DayGridLoadLEDs: View {
    let hours: Double
    static let segments = 8

    var body: some View {
        let lit = PhoneAgenda.loadSegments(hours, segments: Self.segments)
        HStack(spacing: 2) {
            ForEach(0..<Self.segments, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1)
                    .fill(i < lit ? color(i) : Color.secondary.opacity(0.15))
                    .frame(width: 5, height: 3)
            }
        }
        .accessibilityHidden(true)
    }

    private func color(_ i: Int) -> Color {
        if i >= 7 { return Color(sk1Hex: SK1.recRed) }
        if i >= 5 { return Color(sk1Hex: SK1.orange) }
        return Color(sk1Hex: SK1.teal)
    }
}

// MARK: - All-day strip

/// All-day and multi-day bars pinned over the grid, two lanes at most until opened; what's folded away shows as an
/// LCD chip per day ("+2 MORE"), and the round key in the gutter opens or folds the strip.
struct DayGridAllDayStrip: View {
    let strip: AllDayStrip
    let dayCount: Int
    let expanded: Bool
    let open: (CalendarEvent) -> Void
    let toggle: () -> Void

    var body: some View {
        let lanes = strip.shownLaneCount
        let foldable = strip.laneCount > 2
        HStack(alignment: .top, spacing: 0) {
            VStack {
                if foldable {
                    Button(action: toggle) { Image(systemName: expanded ? "chevron.up" : "chevron.down") }
                        .buttonStyle(.sk1Key(.round, size: .mini))
                        .accessibilityLabel(expanded ? "Fold all-day events" : "Show all all-day events")
                } else {
                    SKCaption("All", tone: .soft)
                }
            }
            .frame(width: DayGridMetrics.gutterWidth)
            .padding(.top, 5)
            GeometryReader { geo in
                let colW = geo.size.width / CGFloat(max(1, dayCount))
                ZStack(alignment: .topLeading) {
                    ForEach(strip.shown) { bar in
                        Button { open(bar.event) } label: { DayGridAllDayBar(bar: bar) }
                            .buttonStyle(.plain)
                            .frame(width: max(0, colW * CGFloat(bar.endIndex - bar.startIndex + 1) - 4),
                                   height: DayGridMetrics.laneHeight - 3)
                            .offset(x: colW * CGFloat(bar.startIndex) + 2, y: CGFloat(bar.lane) * DayGridMetrics.laneHeight + 3)
                    }
                    if strip.isFolded {
                        ForEach(Array(strip.hiddenPerDay.enumerated()), id: \.offset) { i, n in
                            if n > 0 {
                                Button(action: toggle) { SKChip("+\(n) MORE", minWidth: 0, height: 18) }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("\(n) more all-day events")
                                    .offset(x: colW * CGFloat(i) + 2, y: CGFloat(lanes) * DayGridMetrics.laneHeight + 4)
                            }
                        }
                    }
                }
            }
        }
        .frame(height: CGFloat(lanes + (strip.isFolded ? 1 : 0)) * DayGridMetrics.laneHeight + 6)
        .clipped()
    }
}

struct DayGridAllDayBar: View {
    let bar: TimeGridAllDayBar

    var body: some View {
        let e = bar.event
        HStack(spacing: 4) {
            if bar.continuesBefore { Image(systemName: "arrowtriangle.left.fill").font(.system(size: 6)) }
            if let callout = EventCallout.detect(e.title) { Image(systemName: callout.symbol) }
            Text(e.title).lineLimit(1)
            Spacer(minLength: 0)
            if bar.continuesAfter { Image(systemName: "arrowtriangle.right.fill").font(.system(size: 6)) }
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 5)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .eventChip(e.colorHex)
        .opacity(e.isDeclined ? 0.5 : 1)
        .contentShape(Rectangle())
        .accessibilityLabel(Text("\(e.title), all day"))
    }
}

// MARK: - Hour scale and columns

/// The hours down the left in small mono type, with the time now on a red tag at its height.
struct DayGridHourScale: View {
    let hourHeight: CGFloat
    let now: Date
    let showsNow: Bool

    static func anchorID(_ hour: Int) -> String { "hour-\(hour)" }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 0) {
                ForEach(0..<24, id: \.self) { h in
                    Text(h == 0 ? "" : label(h))
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: DayGridMetrics.gutterWidth - 8, height: hourHeight, alignment: .topTrailing)
                        .padding(.trailing, 8)
                        .offset(y: -6)
                        .id(Self.anchorID(h))
                }
            }
            if showsNow {
                Text(now.shortTime)
                    .font(.system(size: 9, weight: .heavy, design: .monospaced))
                    .lineLimit(1)
                    .fixedSize()
                    .foregroundStyle(Color(sk1Hex: SK1.charcoalInk))
                    .padding(.horizontal, 4).padding(.vertical, 2)
                    .background(Color(sk1Hex: SK1.recRed), in: RoundedRectangle(cornerRadius: 3))
                    .padding(.trailing, 3)
                    .offset(y: y(now) - 8)
                    .accessibilityLabel("Now, \(now.shortTime)")
            }
        }
        .frame(width: DayGridMetrics.gutterWidth)
    }

    private func label(_ h: Int) -> String {
        (Calendar.app.date(bySettingHour: h, minute: 0, second: 0, of: now) ?? now).hourText
    }

    private func y(_ date: Date) -> CGFloat {
        CGFloat(TimeGridLayoutBuilder.minutes(of: date, in: now) / 60) * hourHeight
    }
}

/// One day: hour and half-hour rules, the hours outside the workday a shade darker, the meetings packed into columns,
/// the pencilled slot and the now line.
struct DayGridColumn: View {
    let day: Date
    let segments: [CalendarEventDaySegment]
    let now: Date
    let hourHeight: CGFloat
    let pencil: Date?
    let open: (CalendarEvent) -> Void
    let tapEmpty: (Date) -> Void
    let compose: (Date) -> Void

    static let workday = 8..<18

    var body: some View {
        let isToday = Calendar.app.isDate(day, inSameDayAs: now)
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .topLeading) {
                rules
                    .frame(width: w, height: hourHeight * 24)
                    .contentShape(Rectangle())
                    .onTapGesture(coordinateSpace: .local) { p in
                        tapEmpty(TimeGridLayoutBuilder.date(atY: Double(p.y), hourHeight: Double(hourHeight), day: day,
                                                            snapMinutes: 30))
                    }
                ForEach(TimeGridLayoutBuilder.place(segments)) { p in
                    let colW = w / CGFloat(p.columnCount)
                    Button { open(p.segment.event) } label: {
                        DayGridEventBlock(segment: p.segment, now: now, height: height(p.segment))
                    }
                    .buttonStyle(.plain)
                    .frame(width: max(0, colW - 3), height: height(p.segment))
                    .offset(x: colW * CGFloat(p.column) + 1.5, y: y(p.segment.segmentStart) + 0.5)
                }
                if let pencil {
                    pencilBlock(pencil, width: w)
                }
                nowLine(width: w, isToday: isToday)
            }
        }
        .background(isToday ? Color(sk1Hex: SK1.orange, opacity: 0.05) : .clear)
        .overlay(alignment: .leading) { Rectangle().fill(Color.secondary.opacity(0.25)).frame(width: 0.5) }
    }

    private var rules: some View {
        VStack(spacing: 0) {
            ForEach(0..<24, id: \.self) { h in
                VStack(spacing: 0) {
                    Rectangle().fill(Color.secondary.opacity(0.22)).frame(height: 0.5)
                    Spacer(minLength: 0)
                    Rectangle().fill(Color.secondary.opacity(0.08)).frame(height: 0.5)
                    Spacer(minLength: 0)
                }
                .frame(height: hourHeight)
                .background(Self.workday.contains(h) ? Color.clear : Color.black.opacity(0.06))
            }
        }
        .background(Color.white.opacity(0.001))
    }

    /// The slot a tap picked: an orange outline with its time; a tap on it opens the composer there.
    private func pencilBlock(_ start: Date, width: CGFloat) -> some View {
        let orange = Color(sk1Hex: SK1.orange)
        return Button { compose(start) } label: {
            HStack(spacing: 4) {
                Image(systemName: "plus").font(.system(size: 11, weight: .bold))
                Text(start.shortTime).font(.system(size: 11, weight: .bold, design: .monospaced))
                Spacer(minLength: 0)
            }
            .foregroundStyle(orange)
            .padding(.horizontal, 6)
            .frame(width: max(0, width - 4), height: max(20, hourHeight / 2 - 1), alignment: .leading)
            .background(orange.opacity(0.14), in: RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(orange, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])))
        }
        .buttonStyle(.plain)
        .offset(x: 2, y: y(start) + 0.5)
        .accessibilityLabel("New event at \(start.shortTime)")
    }

    @ViewBuilder
    private func nowLine(width: CGFloat, isToday: Bool) -> some View {
        let red = Color(sk1Hex: SK1.recRed)
        if isToday {
            HStack(spacing: 0) {
                Circle().fill(red).frame(width: 8, height: 8).offset(x: -4)
                Rectangle().fill(red).frame(height: 1.5)
            }
            .frame(width: width)
            .offset(y: y(now) - 4)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        } else {
            // The time now, faint, across the other days shown, so a glance across lines up.
            Rectangle().fill(red.opacity(0.25)).frame(width: width, height: 1)
                .offset(y: CGFloat(TimeGridLayoutBuilder.minutes(of: dayTime(now), in: day) / 60) * hourHeight)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    /// `date`'s time of day on this column's day.
    private func dayTime(_ date: Date) -> Date {
        let c = Calendar.app.dateComponents([.hour, .minute], from: date)
        return Calendar.app.date(bySettingHour: c.hour ?? 0, minute: c.minute ?? 0, second: 0, of: day) ?? day
    }

    private func y(_ date: Date) -> CGFloat {
        CGFloat(TimeGridLayoutBuilder.minutes(of: date, in: day) / 60) * hourHeight
    }

    private func height(_ s: CalendarEventDaySegment) -> CGFloat {
        max(18, y(s.segmentEnd) - y(s.segmentStart) - 1)
    }
}

/// A meeting on the grid: the calendar's tint with its colour bar down the leading edge (the Mac's event chip), the
/// title and, when there's room, the time in mono; a lit orange lamp while it's on and the service's mark when it has
/// a link. Short meetings fold to one line. Ended meetings dim; declined ones are struck through.
struct DayGridEventBlock: View {
    let segment: CalendarEventDaySegment
    let now: Date
    let height: CGFloat

    var body: some View {
        let e = segment.event
        let ended = e.end <= now
        let live = e.start <= now && !ended
        let compact = height < 34
        VStack(alignment: .leading, spacing: 1) {
            if compact {
                HStack(spacing: 4) {
                    Text(e.title).font(.caption2.weight(.semibold)).lineLimit(1).strikethrough(e.isDeclined)
                    Text(segment.segmentStart.shortTime).font(.system(size: 9, weight: .medium, design: .monospaced))
                        .opacity(0.75).lineLimit(1)
                }
            } else {
                Text(e.title).font(.caption.weight(.semibold))
                    .lineLimit(max(1, Int((height - 18) / 15))).strikethrough(e.isDeclined)
                Text(segment.timeRangeText()).font(.system(size: 9.5, weight: .medium, design: .monospaced))
                    .opacity(0.75).lineLimit(1)
            }
        }
        .padding(.leading, 4).padding(.trailing, 3).padding(.vertical, compact ? 1 : 3)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .overlay(alignment: .topTrailing) { badge(e, live: live, ended: ended, compact: compact) }
        .eventChip(e.colorHex, radius: 5)
        .overlay {
            if e.isDeclined {
                RoundedRectangle(cornerRadius: 5).strokeBorder(Color(hex: e.colorHex), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .opacity(ended || e.isDeclined ? 0.55 : 1)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(e.title), \(segment.timeRangeText())" + (live ? ", on now" : "")))
    }

    @ViewBuilder
    private func badge(_ e: CalendarEvent, live: Bool, ended: Bool, compact: Bool) -> some View {
        if !compact {
            HStack(spacing: 3) {
                if let u = e.meetURL, !ended {
                    Image(systemName: MeetingService.detect(u).symbol).font(.system(size: 9, weight: .semibold))
                }
                if live { SKLamp(color: .orange, lit: true, glow: 3, size: 5) }
            }
            .padding(4)
        }
    }
}
