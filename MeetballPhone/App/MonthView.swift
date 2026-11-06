import SwiftUI
import SK1Tokens
import SK1UI

/// A month on a plate: each day with its meetings as coloured dots, trips and on-call stretches as ribbons across the
/// days (as in the Mac's mini month), and the chosen day's meetings below.
struct MonthView: View {
    @EnvironmentObject private var store: PhoneStore
    var open: (CalendarEvent) -> Void
    var quickAdd: () -> Void
    @State private var month = Date()
    @State private var selected = Calendar.app.startOfDay(for: Date())

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { tl in
            content(now: tl.date)
        }
    }

    private func content(now: Date) -> some View {
        let cal = Calendar.app
        let range = CalendarVisibleRangeBuilder.build(anchor: month, calendar: cal)
        let events = store.events(in: range)
        let ribbons = MiniMonthRibbonBuilder.build(events: events, range: range, calendar: cal)
        let ribbonUIDs = MiniMonthRibbonBuilder.uids(ribbons)
        let dots = MenuAgendaBuilder.dots(events: events.filter { !ribbonUIDs.contains($0.uid) }, range: range, calendar: cal)
        let dayGroups = MenuAgendaBuilder.build(events: events, now: now, scopedDay: selected, calendar: cal)
        return VStack(alignment: .leading, spacing: SK1.Metrics.groupSpacing) {
            PhoneScreenHeader(title: month.formatted(.dateTime.month(.wide)), detail: month.formatted(.dateTime.year())) {
                HStack(spacing: 6) {
                    Button { shift(-1) } label: { Image(systemName: "chevron.left") }
                        .buttonStyle(.sk1Key()).accessibilityLabel("Previous month")
                    Button("Today") {
                        month = now
                        selected = cal.startOfDay(for: now)
                    }
                    .buttonStyle(.sk1Key())
                    Button { shift(1) } label: { Image(systemName: "chevron.right") }
                        .buttonStyle(.sk1Key()).accessibilityLabel("Next month")
                }
            }
            SKWell {
                VStack(spacing: 4) {
                    HStack(spacing: 0) {
                        ForEach(Array(PhoneAgenda.weekdaySymbols(calendar: cal).enumerated()), id: \.offset) { _, s in
                            SKCaption(s, tone: .soft).frame(maxWidth: .infinity)
                        }
                    }
                    ForEach(PhoneAgenda.monthWeeks(anchor: month, calendar: cal), id: \.first) { week in
                        MonthWeekRow(week: week, month: month, now: now, selected: selected,
                                     ribbons: week.first.flatMap { ribbons[$0] } ?? [], dots: dots) { day in
                            selected = day
                        }
                    }
                }
                .padding(10)
            }
            .gesture(DragGesture(minimumDistance: 30).onEnded { v in
                if abs(v.translation.width) > abs(v.translation.height) { shift(v.translation.width < 0 ? 1 : -1) }
            })
            if let g = dayGroups.first {
                PhoneDaySection(group: g, now: now, open: open)
            } else {
                VStack(alignment: .leading, spacing: SK1.Metrics.captionToWell) {
                    SKCaption(PhoneAgenda.dayTitle(selected, now: now), tone: .soft)
                    SKWell {
                        HStack {
                            Text("Nothing on this day.").font(.callout).foregroundStyle(.secondary)
                            Spacer()
                            Button("Add", action: quickAdd).buttonStyle(.sk1Key(size: .small))
                        }
                        .padding(12)
                    }
                }
            }
        }
    }

    private func shift(_ n: Int) {
        let cal = Calendar.app
        guard let m = cal.date(byAdding: .month, value: n, to: month) else { return }
        month = m
        if !cal.isDate(selected, equalTo: m, toGranularity: .month), let first = cal.dateInterval(of: .month, for: m)?.start {
            selected = cal.isDate(Date(), equalTo: m, toGranularity: .month) ? cal.startOfDay(for: Date()) : first
        }
    }
}

/// One week of the month: the day numbers with dots, and up to two ribbon lanes under them.
struct MonthWeekRow: View {
    let week: [Date]
    let month: Date
    let now: Date
    let selected: Date
    let ribbons: [MiniMonthRibbon]
    let dots: [Date: [String]]
    let pick: (Date) -> Void

    var body: some View {
        let cal = Calendar.app
        VStack(spacing: 2) {
            HStack(spacing: 0) {
                ForEach(week, id: \.self) { day in
                    Button { pick(day) } label: { dayCell(day, cal: cal) }
                        .buttonStyle(.plain)
                        .frame(maxWidth: .infinity)
                }
            }
            if !ribbons.isEmpty {
                GeometryReader { geo in
                    let col = geo.size.width / 7
                    ForEach(ribbons) { r in
                        ribbon(r)
                            .frame(width: col * CGFloat(r.endColumn - r.startColumn + 1) - 4, height: 12)
                            .offset(x: col * CGFloat(r.startColumn) + 2, y: CGFloat(r.lane) * 14)
                    }
                }
                .frame(height: CGFloat((ribbons.map(\.lane).max() ?? 0) + 1) * 14)
            }
        }
    }

    private func dayCell(_ day: Date, cal: Calendar) -> some View {
        let inMonth = cal.isDate(day, equalTo: month, toGranularity: .month)
        let isToday = cal.isDate(day, inSameDayAs: now)
        let isSelected = cal.isDate(day, inSameDayAs: selected)
        let colors = dots[cal.startOfDay(for: day)] ?? []
        return VStack(spacing: 3) {
            Text("\(cal.component(.day, from: day))")
                .font(.system(size: 15, weight: isToday ? .heavy : .medium).monospacedDigit())
                .foregroundStyle(isToday ? Color(sk1Hex: SK1.charcoalInk) : .primary)
                .frame(width: 32, height: 32)
                .background {
                    if isToday {
                        Circle().fill(Color(sk1Hex: SK1.orange))
                    } else if isSelected {
                        Circle().strokeBorder(Color(sk1Hex: SK1.orange), lineWidth: 1.5)
                    }
                }
            HStack(spacing: 2) {
                ForEach(Array(colors.enumerated()), id: \.offset) { _, hex in
                    Circle().fill(Color(hex: hex)).frame(width: 5, height: 5)
                }
            }
            .frame(height: 5)
        }
        .opacity(inMonth ? 1 : 0.35)
        .frame(maxWidth: .infinity, minHeight: 46)
        .contentShape(Rectangle())
        .accessibilityLabel(Text(day.formatted(.dateTime.weekday(.wide).month(.wide).day()) + (colors.isEmpty ? "" : ", has meetings")))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
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
