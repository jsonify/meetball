import SwiftUI
import SK1Tokens
import SK1UI

/// The week ahead: a meeting-load meter (one LED column per day, lit by hours in meetings) and each day's meetings.
struct WeekView: View {
    @EnvironmentObject private var store: PhoneStore
    var open: (CalendarEvent) -> Void
    var quickAdd: () -> Void
    @State private var focusDay: Date?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { tl in
            content(now: tl.date)
        }
    }

    private func content(now: Date) -> some View {
        let events = store.events(from: now, days: 7)
        let loads = MeetingLoadBuilder.build(events: events, from: now, days: 7)
        let groups = MenuAgendaBuilder.build(events: events, now: now, days: 7, limit: 400)
        let total = loads.reduce(0) { $0 + $1.hours }
        return VStack(alignment: .leading, spacing: SK1.Metrics.groupSpacing) {
            PhoneScreenHeader(title: "Week", detail: summary(total: total, count: loads.reduce(0) { $0 + $1.count })) {
                Button(action: quickAdd) { Image(systemName: "plus") }
                    .buttonStyle(.sk1Key())
                    .accessibilityLabel("Add an event")
            }
            LoadMeter(loads: loads, now: now, selected: focusDay) { day in
                focusDay = Calendar.app.isDate(day, inSameDayAs: focusDay ?? .distantPast) ? nil : day
            }
            let shown = focusDay.map { d in groups.filter { Calendar.app.isDate($0.day, inSameDayAs: d) } } ?? groups
            if shown.isEmpty {
                SKWell {
                    Text(focusDay == nil ? "Nothing left this week." : "Nothing on this day.")
                        .font(.callout).foregroundStyle(.secondary)
                        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            ForEach(shown) { g in
                PhoneDaySection(group: g, now: now, open: open)
            }
        }
    }

    private func summary(total: Double, count: Int) -> String {
        let hours = total < 10 ? String(format: "%.1f", total) : "\(Int(total.rounded()))"
        return "\(count) meetings · \(hours) h in meetings over the next 7 days"
    }
}

/// Seven LED columns, one per day: lit segments for hours in meetings (teal, amber past 5 h, red past 7 h). Tap a day to
/// show only it.
struct LoadMeter: View {
    let loads: [DayMeetingLoad]
    let now: Date
    let selected: Date?
    let pick: (Date) -> Void
    static let segments = 8

    var body: some View {
        SKLCD {
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(loads) { load in
                    Button { pick(load.day) } label: { column(load) }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text("\(PhoneAgenda.dayTitle(load.day, now: now)): \(load.count) meetings, "
                                                 + String(format: "%.1f hours", load.hours)))
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
        }
        .frame(height: 132)
    }

    private func column(_ load: DayMeetingLoad) -> some View {
        let lit = PhoneAgenda.loadSegments(load.hours, segments: Self.segments)
        let isSelected = selected.map { Calendar.app.isDate($0, inSameDayAs: load.day) } ?? false
        let isToday = Calendar.app.isDate(load.day, inSameDayAs: now)
        let ink = Color(sk1Hex: SK1.lcdInk)
        return VStack(spacing: 3) {
            Text(load.count > 0 ? "\(load.count)" : "–")
                .font(.system(size: 10, weight: .heavy, design: .monospaced)).foregroundStyle(ink.opacity(0.8))
            VStack(spacing: 2) {
                ForEach((0..<Self.segments).reversed(), id: \.self) { i in
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(i < lit ? color(segment: i) : ink.opacity(0.08))
                        .frame(height: 7)
                }
            }
            Text(load.day.formatted(.dateTime.weekday(.narrow)))
                .font(.system(size: 10, weight: isToday ? .black : .bold)).foregroundStyle(ink)
                .padding(.horizontal, 4)
                .background(isSelected ? ink.opacity(0.18) : .clear, in: RoundedRectangle(cornerRadius: 3))
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }

    private func color(segment i: Int) -> Color {
        if i >= 7 { return Color(sk1Hex: SK1.recRed) }
        if i >= 5 { return Color(sk1Hex: SK1.orange) }
        return Color(sk1Hex: SK1.teal)
    }
}
