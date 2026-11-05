import Foundation

/// Works out how often a recurring series repeats from the instances that were loaded.
/// Google returns expanded instances (with `recurringEventId`) but not the rule itself; EventKit events
/// already carry their recurrence and are left alone.
public enum RecurrenceClassifier {
    public static func annotate(_ events: [CalendarEvent], calendar: Calendar = .current) -> [CalendarEvent] {
        var bySeries: [String: [Int]] = [:]
        for (i, e) in events.enumerated() where e.recurrence == .none {
            guard let s = e.seriesID else { continue }
            bySeries["\(e.accountEmail)|\(e.calendarID)|\(s)", default: []].append(i)
        }
        var out = events
        for indices in bySeries.values {
            let kind = classify(indices.map { events[$0].start }, calendar: calendar)
            for i in indices { out[i].recurrence = kind }
        }
        return out
    }

    /// Daily when consecutive instances are a day apart (weekends may be skipped), weekly when they're whole
    /// weeks apart, otherwise just "recurring".
    public static func classify(_ starts: [Date], calendar: Calendar = .current) -> EventRecurrence {
        let days = Set(starts.map { calendar.startOfDay(for: $0) }).sorted()
        guard days.count >= 2 else { return .other }
        let gaps = zip(days, days.dropFirst()).compactMap { calendar.dateComponents([.day], from: $0, to: $1).day }
        if gaps.allSatisfy({ $0 <= 3 }) && gaps.contains(1) { return .daily }
        if gaps.allSatisfy({ $0 % 7 == 0 }) { return .weekly }
        return .other
    }
}
