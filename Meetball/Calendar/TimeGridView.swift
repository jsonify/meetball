import SwiftUI

/// Day / week time grid: hour gutter, all-day row, overlap-packed event blocks, current-time line, drag to create.
struct TimeGridView: View {
    @EnvironmentObject var store: CalendarStore
    let days: [Date]
    var onCreate: (Date, Date) -> Void

    static let hourHeight: CGFloat = 48
    let gutterWidth: CGFloat = 56
    let laneHeight: CGFloat = 20
    let workdayStartHour = 8

    var body: some View {
        let derived = store.derived
        TimelineView(.periodic(from: .now, by: 60)) { ctx in
            let now = ctx.date
            VStack(spacing: 0) {
                dayHeader(now: now)
                Divider()
                allDayRow(derived)
                Divider()
                ScrollViewReader { proxy in
                    ScrollView(.vertical) {
                        HStack(alignment: .top, spacing: 0) {
                            hourGutter
                            ForEach(days, id: \.self) { day in
                                TimeGridDayColumn(day: day, segments: timedSegments(derived, day), now: now, onCreate: onCreate)
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .frame(height: Self.hourHeight * 24)
                    }
                    .onAppear { scrollToStart(proxy, now: now) }
                    .onChange(of: days) { _, _ in scrollToStart(proxy, now: Date()) }
                }
            }
        }
    }

    // MARK: Header

    private func dayHeader(now: Date) -> some View {
        let cal = Calendar.current
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
                        .background(isToday ? Color.accentColor : .clear, in: Circle())
                }
                .font(.callout)
                .frame(maxWidth: .infinity).padding(.vertical, 6)
                .background(isSelected && days.count > 1 ? Color.accentColor.opacity(0.08) : .clear)
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { store.select(day); store.viewMode = .day }
                .onTapGesture { store.select(day) }
                .help(days.count > 1 ? "Double-click to open the day view" : "")
            }
        }
    }

    // MARK: All-day row

    private func allDayRow(_ derived: CalendarDerivedEvents) -> some View {
        let bars = allDayBars(derived)
        let lanes = (bars.map(\.lane).max() ?? -1) + 1
        return HStack(alignment: .top, spacing: 0) {
            Text("all-day").font(.caption2).foregroundStyle(.secondary)
                .frame(width: gutterWidth - 8, alignment: .trailing).padding(.trailing, 8).padding(.top, 3)
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
        guard let first = days.first, let week = Calendar.current.dateInterval(of: .weekOfYear, for: first),
              let spans = derived.weeks.first(where: { $0.weekStart == week.start })?.spans else { return [] }
        let offset = Calendar.current.dateComponents([.day], from: week.start, to: first).day ?? 0
        return TimeGridLayoutBuilder.allDayBars(spans: spans, firstDayOffset: offset, dayCount: days.count)
    }

    // MARK: Grid

    private var hourGutter: some View {
        VStack(spacing: 0) {
            ForEach(0..<24, id: \.self) { h in
                Text(h == 0 ? "" : hourLabel(h))
                    .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                    .frame(width: gutterWidth - 8, height: Self.hourHeight, alignment: .topTrailing)
                    .padding(.trailing, 8)
                    .offset(y: -7)
                    .id(h)
            }
        }
    }

    private func hourLabel(_ h: Int) -> String {
        let d = Calendar.current.date(bySettingHour: h, minute: 0, second: 0, of: Date()) ?? Date()
        return d.formatted(.dateTime.hour())
    }

    private func timedSegments(_ derived: CalendarDerivedEvents, _ day: Date) -> [CalendarEventDaySegment] {
        (derived.segmentsByDay[Calendar.current.startOfDay(for: day)] ?? []).filter { !$0.event.isBarEvent() }
    }

    /// Scroll to just before now when today is visible, otherwise to the start of working hours.
    private func scrollToStart(_ proxy: ScrollViewProxy, now: Date) {
        let cal = Calendar.current
        let hour = days.contains(where: { cal.isDate($0, inSameDayAs: now) })
            ? max(0, cal.component(.hour, from: now) - 1)
            : workdayStartHour
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
            .background(Color(hex: e.colorHex).opacity(0.85), in: RoundedRectangle(cornerRadius: 4))
            .foregroundStyle(.white)
            .opacity(e.isDeclined ? 0.5 : 1)
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
    let onCreate: (Date, Date) -> Void
    @State private var dragRange: NewEventDateRange?

    private var hourHeight: CGFloat { TimeGridView.hourHeight }

    var body: some View {
        let isToday = Calendar.current.isDate(day, inSameDayAs: now)
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
                    RoundedRectangle(cornerRadius: 5).fill(Color.accentColor.opacity(0.25))
                        .overlay(alignment: .topLeading) {
                            Text("\(r.start.formatted(date: .omitted, time: .shortened)) – \(r.end.formatted(date: .omitted, time: .shortened))")
                                .font(.caption2.bold()).padding(4)
                        }
                        .frame(width: w - 4, height: max(12, y(r.end) - y(r.start)))
                        .offset(x: 2, y: y(r.start))
                        .allowsHitTesting(false)
                }

                if isToday {
                    HStack(spacing: 0) {
                        Circle().fill(Color.red).frame(width: 8, height: 8).offset(x: -4)
                        Rectangle().fill(Color.red).frame(height: 1.5)
                    }
                    .frame(width: w)
                    .offset(y: y(now) - 4)
                    .allowsHitTesting(false)
                }
            }
        }
        .background(isToday ? Color.accentColor.opacity(0.03) : .clear)
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
    @State private var showDetail = false

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
        .opacity(ended || e.isDeclined ? 0.55 : 1)
        .contentShape(Rectangle())
        .onTapGesture { showDetail = true }
        .popover(isPresented: $showDetail, arrowEdge: .trailing) { EventDetailPopover(event: e) }
        .contextMenu {
            MeetingSecondaryActions(event: e)
            Divider()
            Button("Delete", role: .destructive) { Task { await store.delete(e) } }
        }
        .help(e.title)
    }
}

struct EventDetailPopover: View {
    let event: CalendarEvent
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Circle().fill(Color(hex: event.colorHex)).frame(width: 10, height: 10).padding(.top, 5)
                Text(event.title).font(.headline).fixedSize(horizontal: false, vertical: true)
            }
            Label(timeText, systemImage: "clock").font(.callout)
            if let l = event.location, !l.isEmpty { Label(l, systemImage: "mappin.and.ellipse").font(.callout).lineLimit(2) }
            if !event.attendees.isEmpty { Label("\(event.attendees.count) attendees", systemImage: "person.2").font(.callout) }
            if event.isDeclined { Label("You declined", systemImage: "xmark.circle").font(.callout).foregroundStyle(.secondary) }
            HStack {
                JoinButton(event: event)
                Spacer()
                if let link = event.htmlLink {
                    Button { NSWorkspace.shared.open(link) } label: { Image(systemName: "arrow.up.right.square") }
                        .help("Open in Google Calendar")
                }
                if let u = event.meetURL {
                    Button { MeetingJoiner.copyLink(u) } label: { Image(systemName: "doc.on.doc") }.help("Copy meeting link")
                }
            }
        }
        .padding(14).frame(width: 300)
    }

    private var timeText: String {
        if event.isAllDay { return event.start.formatted(.dateTime.weekday(.wide).month().day()) + " · All day" }
        let day = event.start.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        return "\(day), \(event.start.formatted(date: .omitted, time: .shortened)) – \(event.end.formatted(date: .omitted, time: .shortened))"
    }
}
