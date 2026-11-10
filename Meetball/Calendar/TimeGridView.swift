import SwiftUI
import SK1Tokens
import SK1UI

/// Day / week time grid: hour gutter, all-day row, overlap-packed event blocks, current-time line, drag to create.
struct TimeGridView: View {
    @EnvironmentObject var store: CalendarStore
    let days: [Date]
    var onCreate: (Date, Date) -> Void

    @AppStorage(AppPreferences.Key.density) private var densityRaw = LayoutDensity.comfortable.rawValue
    private var hourHeight: CGFloat { (LayoutDensity(rawValue: densityRaw) ?? .comfortable).hourHeight }
    let gutterWidth: CGFloat = 56
    let laneHeight: CGFloat = 20
    let workdayStartHour = 8

    var body: some View {
        let derived = store.derived
        TimelineView(.periodic(from: .now, by: 60)) { ctx in
            let now = ctx.date
            VStack(spacing: 0) {
                dayHeader(now: now)
                SKGroove()
                allDayRow(derived)
                SKGroove()
                ScrollViewReader { proxy in
                    ScrollView(.vertical) {
                        HStack(alignment: .top, spacing: 0) {
                            hourGutter
                            ForEach(days, id: \.self) { day in
                                TimeGridDayColumn(day: day, segments: timedSegments(derived, day), now: now, hourHeight: hourHeight, onCreate: onCreate)
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .frame(height: hourHeight * 24)
                    }
                    .onAppear { scrollToStart(proxy, now: now) }
                    .onChange(of: days) { _, _ in scrollToStart(proxy, now: Date()) }
                }
            }
        }
    }

    // MARK: Header

    private func dayHeader(now: Date) -> some View {
        let cal = Calendar.app
        return HStack(spacing: 0) {
            Color.clear.frame(width: gutterWidth, height: 1)
            ForEach(days, id: \.self) { day in
                let isToday = cal.isDate(day, inSameDayAs: now)
                let isSelected = cal.isDate(day, inSameDayAs: store.selectedDay)
                HStack(spacing: 6) {
                    Text(day, format: .dateTime.weekday(.abbreviated)).foregroundStyle(.secondary)
                    Text("\(cal.component(.day, from: day))").bold()
                        .foregroundStyle(isToday ? Color.white : Color.primary)
                        .frame(minWidth: 24, minHeight: 24)
                        .background(isToday ? Color(sk1Hex: SK1.orange) : .clear, in: Circle())
                }
                .font(.callout)
                .frame(maxWidth: .infinity).padding(.vertical, 6)
                .background(isSelected && days.count > 1 ? Color(sk1Hex: SK1.orange, opacity: 0.08) : .clear)
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { store.select(day); store.viewMode = .day }
                .onTapGesture { store.select(day) }
                .help(days.count > 1 ? "Double-click to open the day view" : "")
                .accessibilityElement(children: .ignore)
                .accessibilityLabel((isToday ? "Today, " : "") + day.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
                .accessibilityAction { store.select(day) }
            }
        }
    }

    // MARK: All-day row

    private func allDayRow(_ derived: CalendarDerivedEvents) -> some View {
        let bars = allDayBars(derived)
        let lanes = (bars.map(\.lane).max() ?? -1) + 1
        return HStack(alignment: .top, spacing: 0) {
            SKCaption("All-day", tone: .soft)
                .frame(width: gutterWidth - 8, alignment: .trailing).padding(.trailing, 8).padding(.top, 5)
            GeometryReader { geo in
                let colW = geo.size.width / CGFloat(max(1, days.count))
                ZStack(alignment: .topLeading) {
                    ForEach(bars) { bar in
                        AllDayBarView(bar: bar)
                            .frame(width: max(0, colW * CGFloat(bar.endIndex - bar.startIndex + 1) - 4), height: laneHeight - 2)
                            .offset(x: colW * CGFloat(bar.startIndex) + 2, y: CGFloat(bar.lane) * laneHeight + 2)
                    }
                }
            }
        }
        .frame(height: max(22, CGFloat(min(lanes, 4)) * laneHeight + 4))
        .clipped()
    }

    private func allDayBars(_ derived: CalendarDerivedEvents) -> [TimeGridAllDayBar] {
        guard let first = days.first, let week = Calendar.app.dateInterval(of: .weekOfYear, for: first),
              let spans = derived.weeks.first(where: { $0.weekStart == week.start })?.spans else { return [] }
        let offset = Calendar.app.dateComponents([.day], from: week.start, to: first).day ?? 0
        return TimeGridLayoutBuilder.allDayBars(spans: spans, firstDayOffset: offset, dayCount: days.count)
    }

    // MARK: Grid

    private var hourGutter: some View {
        VStack(spacing: 0) {
            ForEach(0..<24, id: \.self) { h in
                Text(h == 0 ? "" : hourLabel(h))
                    .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                    .frame(width: gutterWidth - 8, height: hourHeight, alignment: .topTrailing)
                    .padding(.trailing, 8)
                    .offset(y: -7)
                    .id(h)
            }
        }
    }

    private func hourLabel(_ h: Int) -> String {
        let d = Calendar.app.date(bySettingHour: h, minute: 0, second: 0, of: Date()) ?? Date()
        return d.hourText
    }

    private func timedSegments(_ derived: CalendarDerivedEvents, _ day: Date) -> [CalendarEventDaySegment] {
        (derived.segmentsByDay[Calendar.app.startOfDay(for: day)] ?? []).filter { !$0.event.isBarEvent() }
    }

    /// Scroll to just before now when today is visible, otherwise to the start of working hours.
    private func scrollToStart(_ proxy: ScrollViewProxy, now: Date) {
        let hour = TimeGridLayoutBuilder.openingHour(days: days, now: now, workdayStartHour: workdayStartHour)
        DispatchQueue.main.async { proxy.scrollTo(hour, anchor: .top) }
    }
}

private struct AllDayBarView: View {
    let bar: TimeGridAllDayBar
    var body: some View {
        let e = bar.event
        Text((bar.continuesBefore ? "◂ " : "") + e.title).font(.caption2.weight(.medium)).lineLimit(1)
            .padding(.horizontal, 5)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .eventChip(e.colorHex)
            .calendarFade(e, otherwise: e.isDeclined ? 0.5 : 1)
            .eventDetailOnClick(e, arrowEdge: .bottom)
            .contextMenu { MeetingSecondaryActions(event: e) }
            .help(e.title)
    }
}

/// One day column: hour lines, events, now-line, and a drag gesture on empty space to create an event.
struct TimeGridDayColumn: View {
    @EnvironmentObject var store: CalendarStore
    let day: Date
    let segments: [CalendarEventDaySegment]
    let now: Date
    let hourHeight: CGFloat
    let onCreate: (Date, Date) -> Void
    @State private var dragRange: NewEventDateRange?

    var body: some View {
        let isToday = Calendar.app.isDate(day, inSameDayAs: now)
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .topLeading) {
                hourLines
                    .frame(width: w, height: hourHeight * 24)
                    .contentShape(Rectangle())
                    .gesture(createGesture)

                ForEach(TimeGridLayoutBuilder.place(segments)) { p in
                    let colW = w / CGFloat(p.columnCount)
                    TimeGridEventBlock(segment: p.segment, now: now)
                        .frame(width: max(0, colW - 3), height: max(18, y(p.segment.segmentEnd) - y(p.segment.segmentStart) - 1))
                        .offset(x: colW * CGFloat(p.column) + 1, y: y(p.segment.segmentStart))
                }

                if let r = dragRange {
                    RoundedRectangle(cornerRadius: 5).fill(Color(sk1Hex: SK1.orange, opacity: 0.25))
                        .overlay(alignment: .topLeading) {
                            Text("\(r.start.shortTime) – \(r.end.shortTime)")
                                .font(.caption2.bold()).padding(4)
                        }
                        .frame(width: w - 4, height: max(12, y(r.end) - y(r.start)))
                        .offset(x: 2, y: y(r.start))
                        .allowsHitTesting(false)
                }

                if isToday {
                    HStack(spacing: 0) {
                        Circle().fill(Color(sk1Hex: SK1.recRed)).frame(width: 8, height: 8).offset(x: -4)
                        Rectangle().fill(Color(sk1Hex: SK1.recRed)).frame(height: 1.5)
                    }
                    .frame(width: w)
                    .offset(y: y(now) - 4)
                    .allowsHitTesting(false)
                }
            }
        }
        .background(isToday ? Color(sk1Hex: SK1.orange, opacity: 0.04) : .clear)
        .overlay(alignment: .leading) { Rectangle().fill(Color.secondary.opacity(0.2)).frame(width: 0.5) }
    }

    private var hourLines: some View {
        VStack(spacing: 0) {
            ForEach(0..<24, id: \.self) { _ in
                VStack(spacing: 0) {
                    Rectangle().fill(Color.secondary.opacity(0.18)).frame(height: 0.5)
                    Spacer(minLength: 0)
                }
                .frame(height: hourHeight)
            }
        }
        .background(Color(nsColor: .textBackgroundColor).opacity(0.001))
    }

    private var createGesture: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { v in
                dragRange = TimeGridLayoutBuilder.dragRange(fromY: v.startLocation.y, toY: v.location.y,
                                                            hourHeight: hourHeight, day: day)
            }
            .onEnded { v in
                let r = TimeGridLayoutBuilder.dragRange(fromY: v.startLocation.y, toY: v.location.y, hourHeight: hourHeight, day: day)
                dragRange = nil
                onCreate(r.start, r.end)
            }
    }

    private func y(_ date: Date) -> CGFloat {
        CGFloat(TimeGridLayoutBuilder.minutes(of: date, in: day) / 60) * hourHeight
    }
}

struct TimeGridEventBlock: View {
    @EnvironmentObject var store: CalendarStore
    let segment: CalendarEventDaySegment
    let now: Date

    var body: some View {
        let e = segment.event
        let color = Color(hex: e.colorHex)
        let ended = e.end <= now
        VStack(alignment: .leading, spacing: 1) {
            Text(e.title).font(.caption.weight(.semibold)).lineLimit(2).strikethrough(e.isDeclined)
            Text(segment.timeRangeText()).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(.leading, 6).padding(.trailing, 3).padding(.vertical, 2)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(color.opacity(0.22), in: RoundedRectangle(cornerRadius: 5))
        .overlay(alignment: .leading) { Rectangle().fill(color).frame(width: 3) }
        .overlay(alignment: .topTrailing) {
            if let u = e.meetURL, !ended { MeetingServiceBadge(url: u).padding(3) }
        }
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .calendarFade(e, otherwise: ended || e.isDeclined ? 0.55 : 1)
        .eventDetailOnClick(e)
        .contextMenu {
            MeetingSecondaryActions(event: e)
            Divider()  // sk1-audit: ignore (a menu item separator)
            Button("Delete", role: .destructive) { Task { await store.delete(e) } }
        }
        .help(e.title)
    }
}
