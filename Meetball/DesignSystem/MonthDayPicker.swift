import SwiftUI
import SK1Tokens
import SK1UI

/// The weeks of a month as a square grid, for the day picker: always six rows of seven, starting on the calendar's
/// first weekday, with the days of the months either side filling the edges. Pure, so it can be tested.
enum MonthGrid {
    /// The first day of the month that `date` falls in.
    static func monthStart(_ date: Date, calendar: Calendar) -> Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? calendar.startOfDay(for: date)
    }

    /// 42 days (six weeks), starting on the first weekday on or before the 1st of `month`'s month.
    static func days(for month: Date, calendar: Calendar) -> [Date] {
        let first = monthStart(month, calendar: calendar)
        let lead = (calendar.component(.weekday, from: first) - calendar.firstWeekday + 7) % 7
        guard let gridStart = calendar.date(byAdding: .day, value: -lead, to: first) else { return [] }
        return (0..<42).compactMap { calendar.date(byAdding: .day, value: $0, to: gridStart) }
    }

    /// The weekday initials in grid order (S M T W T F S for a Sunday start).
    static func weekdaySymbols(calendar: Calendar) -> [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        return (0..<7).map { symbols[(calendar.firstWeekday - 1 + $0) % 7] }
    }

    /// `date` moved to `newDay`'s date, keeping its time of day.
    static func moving(_ date: Date, toDay newDay: Date, calendar: Calendar) -> Date {
        let time = calendar.dateComponents([.hour, .minute, .second], from: date)
        let day = calendar.startOfDay(for: newDay)
        return calendar.date(byAdding: time, to: day) ?? day
    }
}

/// Picks a day in the SK-1 look: ◀ chip ▶ (the arrows step a day), and the chip opens a square month calendar: ◀ and ▶
/// page the month, today is ringed, the chosen day is the orange square, and Today jumps back. Tapping a day picks it
/// and closes the calendar. The binding's time of day is kept; only the date changes.
struct MonthDayPicker: View {
    @Binding var selection: Date
    var name = "Day"
    /// How the chip reads a day; by default Today / Tomorrow / Yesterday, else "Wed, Nov 11".
    var label: ((Date) -> String)?
    @State private var choosing = false

    private var cal: Calendar { .app }

    var body: some View {
        HStack(spacing: 4) {
            arrow(-1, symbol: "arrowtriangle.left.fill", label: "Previous day")
            Button { choosing = true } label: { chip }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("\(name), \(chipLabel(selection))"))
                .accessibilityHint(Text("Opens a month calendar"))
                .popover(isPresented: $choosing, arrowEdge: .top) {
                    MonthDayGrid(selection: Binding(get: { selection }, set: { pick($0) }), calendar: cal)
                        .presentationCompactAdaptation(.popover)
                }
            arrow(1, symbol: "arrowtriangle.right.fill", label: "Next day")
        }
        .fixedSize()
    }

    private func pick(_ day: Date) {
        selection = MonthGrid.moving(selection, toDay: day, calendar: cal)
        choosing = false
    }

    private func chipLabel(_ date: Date) -> String {
        if let label { return label(date) }
        return Self.relativeLabel(date, now: Date(), calendar: cal)
    }

    /// Today / Tomorrow / Yesterday, else "Wed, Nov 11" (with the year when it isn't this year).
    static func relativeLabel(_ date: Date, now: Date, calendar: Calendar) -> String {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now),
                                           to: calendar.startOfDay(for: date)).day ?? 0
        switch days {
        case 0: return "Today"
        case 1: return "Tomorrow"
        case -1: return "Yesterday"
        default:
            if calendar.isDate(date, equalTo: now, toGranularity: .year) {
                return date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
            }
            return date.formatted(.dateTime.month(.abbreviated).day().year())
        }
    }

    private var chip: some View {
        ZStack {
            // Sized for the widest label it is likely to show, so the row doesn't jump as days change.
            Text("Wed, Sep 30").hidden()
            Text(chipLabel(selection))
        }
        .font(.system(size: 10, weight: .bold, design: .monospaced))
        .tracking(0.5)
        .foregroundStyle(Color(sk1Hex: SK1.lcdInk))
        .lineLimit(1)
        .padding(.horizontal, 7)
        .frame(minWidth: 44, minHeight: 20, maxHeight: 20)
        .background(SKGlass(.chip, radius: 3))
        .contentShape(Rectangle())
    }

    private func arrow(_ by: Int, symbol: String, label: String) -> some View {
        Button {
            guard let moved = cal.date(byAdding: .day, value: by, to: selection) else { return }
            selection = moved
        } label: { Image(systemName: symbol) }
            .buttonStyle(.sk1Key(.round, size: .mini))
            .accessibilityLabel(Text("\(name): \(label.lowercased())"))
    }
}

/// The square month calendar inside `MonthDayPicker`'s popover.
struct MonthDayGrid: View {
    @Binding var selection: Date
    let calendar: Calendar
    @State private var month: Date

    private static let cell: CGFloat = 36

    init(selection: Binding<Date>, calendar: Calendar) {
        _selection = selection
        self.calendar = calendar
        _month = State(initialValue: MonthGrid.monthStart(selection.wrappedValue, calendar: calendar))
    }

    var body: some View {
        let today = calendar.startOfDay(for: Date())
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Button { page(-1) } label: { Image(systemName: "arrowtriangle.left.fill") }
                    .buttonStyle(.sk1Key(.round, size: .mini))
                    .accessibilityLabel("Previous month")
                Text(month.formatted(.dateTime.month(.wide).year()).uppercased())
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .tracking(1)
                    .foregroundStyle(Color(sk1Hex: SK1.lcdInk))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, minHeight: 24)
                    .background(SKGlass(.chip, radius: 3))
                    .accessibilityAddTraits(.isHeader)
                Button { page(1) } label: { Image(systemName: "arrowtriangle.right.fill") }
                    .buttonStyle(.sk1Key(.round, size: .mini))
                    .accessibilityLabel("Next month")
            }
            HStack(spacing: 2) {
                ForEach(Array(MonthGrid.weekdaySymbols(calendar: calendar).enumerated()), id: \.offset) { _, s in
                    Text(s)
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: Self.cell)
                }
            }
            .accessibilityHidden(true)
            let days = MonthGrid.days(for: month, calendar: calendar)
            VStack(spacing: 2) {
                ForEach(0..<6, id: \.self) { row in
                    HStack(spacing: 2) {
                        ForEach(days[(row * 7)..<(row * 7 + 7)], id: \.self) { day in
                            dayCell(day, today: today)
                        }
                    }
                }
            }
            HStack {
                Button("Today") { selection = today }
                    .buttonStyle(.sk1Key(size: .small))
                    .accessibilityLabel("Pick today")
                Spacer(minLength: 0)
            }
        }
        .padding(12)
        .frame(width: Self.cell * 7 + 2 * 6 + 24)
        .sk1Chassis()
        .gesture(DragGesture(minimumDistance: 30).onEnded { v in
            guard abs(v.translation.width) > abs(v.translation.height) else { return }
            page(v.translation.width < 0 ? 1 : -1)
        })
    }

    private func page(_ by: Int) {
        if let m = calendar.date(byAdding: .month, value: by, to: month) { month = m }
    }

    private func dayCell(_ day: Date, today: Date) -> some View {
        let chosen = calendar.isDate(day, inSameDayAs: selection)
        let isToday = calendar.isDate(day, inSameDayAs: today)
        let inMonth = calendar.isDate(day, equalTo: month, toGranularity: .month)
        return Button { selection = day } label: {
            Text("\(calendar.component(.day, from: day))")
                .font(.system(size: 13, weight: chosen || isToday ? .bold : .semibold, design: .monospaced))
                .foregroundStyle(chosen ? Color.white : (inMonth ? Color.primary : Color.secondary.opacity(0.6)))
                .frame(width: Self.cell, height: Self.cell)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(chosen ? Color(sk1Hex: SK1.orange) : Color.secondary.opacity(inMonth ? 0.08 : 0.03))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(Color(sk1Hex: SK1.orange), lineWidth: isToday && !chosen ? 1.5 : 0)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(day.formatted(date: .complete, time: .omitted)))
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }
}
