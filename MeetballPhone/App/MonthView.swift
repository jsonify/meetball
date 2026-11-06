import SwiftUI
import SK1Tokens
import SK1UI

/// Months on plates, one after another down a continuous scroll: each day with its meetings as coloured dots, trips
/// and on-call stretches as ribbons across the days (as in the Mac's mini month). The header follows the month at the
/// top of the scroll; ◀ and ▶ scroll a month back or on. Tapping a day opens it on the Day grid.
struct MonthView: View {
    @EnvironmentObject private var store: PhoneStore
    /// Opens a day on the Day grid.
    var pick: (Date) -> Void
    /// The month at the top of the scroll (its first day).
    @State private var visible: Date?
    @State private var paged = 0

    /// How far the scroll reaches either side of this month.
    static let monthsBack = 24
    static let monthsAhead = 60

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { tl in
            content(now: tl.date)
        }
        .sensoryFeedback(.selection, trigger: paged)
    }

    private func content(now: Date) -> some View {
        let cal = Calendar.app
        let thisMonth = Self.monthStart(now)
        let months = Self.months(around: thisMonth)
        let shown = visible ?? thisMonth
        return VStack(spacing: 10) {
            PhoneScreenHeader(title: shown.formatted(.dateTime.month(.wide)), detail: shown.formatted(.dateTime.year())) {
                HStack(spacing: 6) {
                    Button { shift(-1, from: shown, in: months) } label: { Image(systemName: "chevron.left") }
                        .buttonStyle(.sk1Key()).accessibilityLabel("Previous month")
                    Button("Today") { go(to: thisMonth) }
                        .buttonStyle(.sk1Key())
                    Button { shift(1, from: shown, in: months) } label: { Image(systemName: "chevron.right") }
                        .buttonStyle(.sk1Key()).accessibilityLabel("Next month")
                }
            }
            .padding(.horizontal, 16)
            HStack(spacing: 0) {
                ForEach(Array(PhoneAgenda.weekdaySymbols(calendar: cal).enumerated()), id: \.offset) { _, s in
                    SKCaption(s, tone: .soft).frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 26)
            .accessibilityHidden(true)
            ScrollView {
                LazyVStack(spacing: SK1.Metrics.groupSpacing) {
                    ForEach(months, id: \.self) { m in
                        MonthBlock(month: m, now: now, showsYear: !cal.isDate(m, equalTo: now, toGranularity: .year),
                                   pick: pick)
                            .id(m)
                    }
                }
                .scrollTargetLayout()
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .scrollPosition(id: $visible, anchor: .top)
            .refreshable { await store.refresh(fresh: true) }
            .onAppear { if visible == nil { visible = thisMonth } }
        }
        .padding(.top, 8)
        .frame(maxWidth: 600)
        .frame(maxWidth: .infinity)
    }

    private func shift(_ n: Int, from shown: Date, in months: [Date]) {
        guard let m = Calendar.app.date(byAdding: .month, value: n, to: shown), months.contains(m) else { return }
        go(to: m)
    }

    private func go(to month: Date) {
        withAnimation(.easeInOut(duration: 0.3)) { visible = month }
        paged += 1
    }

    static func monthStart(_ d: Date, calendar: Calendar = .app) -> Date {
        calendar.dateInterval(of: .month, for: d)?.start ?? calendar.startOfDay(for: d)
    }

    /// First days of the months the scroll holds, oldest first.
    static func months(around month: Date, calendar: Calendar = .app) -> [Date] {
        (-monthsBack...monthsAhead).compactMap { calendar.date(byAdding: .month, value: $0, to: month) }
    }
}

/// One month in the scroll: its name, then its weeks in a well. Days outside the month are left blank, since the
/// months either side show them.
struct MonthBlock: View {
    @EnvironmentObject private var store: PhoneStore
    let month: Date
    let now: Date
    let showsYear: Bool
    let pick: (Date) -> Void

    var body: some View {
        let cal = Calendar.app
        let range = CalendarVisibleRangeBuilder.build(anchor: month, calendar: cal)
        let events = store.events(in: range)
        let ribbons = MiniMonthRibbonBuilder.build(events: events, range: range, calendar: cal)
        let ribbonUIDs = MiniMonthRibbonBuilder.uids(ribbons)
        let dots = MenuAgendaBuilder.dots(events: events.filter { !ribbonUIDs.contains($0.uid) }, range: range, calendar: cal)
        let title = showsYear ? month.formatted(.dateTime.month(.wide).year()) : month.formatted(.dateTime.month(.wide))
        VStack(alignment: .leading, spacing: SK1.Metrics.captionToWell) {
            SKCaption(title, tone: cal.isDate(month, equalTo: now, toGranularity: .month) ? .ink : .soft)
                .accessibilityAddTraits(.isHeader)
            SKWell {
                VStack(spacing: 4) {
                    ForEach(PhoneAgenda.monthWeeks(anchor: month, calendar: cal), id: \.first) { week in
                        MonthWeekRow(week: week, month: month, now: now,
                                     ribbons: week.first.flatMap { ribbons[$0] } ?? [], dots: dots, pick: pick)
                    }
                }
                .padding(10)
            }
        }
    }
}

/// One week of the month: the day numbers with dots, and up to two ribbon lanes under them.
struct MonthWeekRow: View {
    let week: [Date]
    let month: Date
    let now: Date
    let ribbons: [MiniMonthRibbon]
    let dots: [Date: [String]]
    let pick: (Date) -> Void

    var body: some View {
        let cal = Calendar.app
        VStack(spacing: 2) {
            HStack(spacing: 0) {
                ForEach(week, id: \.self) { day in
                    if cal.isDate(day, equalTo: month, toGranularity: .month) {
                        Button { pick(day) } label: { dayCell(day, cal: cal) }
                            .buttonStyle(.plain)
                            .frame(maxWidth: .infinity)
                            .accessibilityHint("Opens the day")
                    } else {
                        Color.clear.frame(maxWidth: .infinity, minHeight: 46).accessibilityHidden(true)
                    }
                }
            }
            let inMonth = week.indices.filter { cal.isDate(week[$0], equalTo: month, toGranularity: .month) }
            let shown = clipped(to: (inMonth.first ?? 0)...(inMonth.last ?? 6))
            if !shown.isEmpty {
                GeometryReader { geo in
                    let col = geo.size.width / 7
                    ForEach(shown, id: \.ribbon.id) { c in
                        ribbon(c.ribbon)
                            .frame(width: col * CGFloat(c.columns.count) - 4, height: 12)
                            .offset(x: col * CGFloat(c.columns.lowerBound) + 2, y: CGFloat(c.ribbon.lane) * 14)
                    }
                }
                .frame(height: CGFloat((shown.map(\.ribbon.lane).max() ?? 0) + 1) * 14)
            }
        }
    }

    /// The ribbons cut to the month's own days in this week (the months either side draw the rest).
    private func clipped(to days: ClosedRange<Int>) -> [(ribbon: MiniMonthRibbon, columns: ClosedRange<Int>)] {
        ribbons.compactMap { r in
            let lo = max(r.startColumn, days.lowerBound), hi = min(r.endColumn, days.upperBound)
            return lo <= hi ? (r, lo...hi) : nil
        }
    }

    private func dayCell(_ day: Date, cal: Calendar) -> some View {
        let isToday = cal.isDate(day, inSameDayAs: now)
        let colors = dots[cal.startOfDay(for: day)] ?? []
        return VStack(spacing: 3) {
            Text("\(cal.component(.day, from: day))")
                .font(.system(size: 15, weight: isToday ? .heavy : .medium).monospacedDigit())
                .foregroundStyle(isToday ? Color(sk1Hex: SK1.charcoalInk) : .primary)
                .frame(width: 32, height: 32)
                .background {
                    if isToday { Circle().fill(Color(sk1Hex: SK1.orange)) }
                }
            HStack(spacing: 2) {
                ForEach(Array(colors.enumerated()), id: \.offset) { _, hex in
                    Circle().fill(Color(hex: hex)).frame(width: 5, height: 5)
                }
            }
            .frame(height: 5)
        }
        .frame(maxWidth: .infinity, minHeight: 46)
        .contentShape(Rectangle())
        .accessibilityLabel(Text(day.formatted(.dateTime.weekday(.wide).month(.wide).day()) + (colors.isEmpty ? "" : ", has meetings")))
    }

    private func ribbon(_ r: MiniMonthRibbon) -> some View {
        HStack(spacing: 3) {
            if let c = r.callout { Image(systemName: c.symbol) }
            Text(r.event.title).lineLimit(1)
            Spacer(minLength: 0)
        }
        .font(.system(size: 8.5, weight: .semibold))
        .padding(.horizontal, 3)
        .frame(maxHeight: .infinity)
        .eventChip(r.event.colorHex, radius: 3)
        .accessibilityLabel(Text(r.event.title))
    }
}
