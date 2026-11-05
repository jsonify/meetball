import Foundation

/// A city shown in the popover's world-clock strip (Settings › Menu Bar › World clocks).
public struct WorldClock: Codable, Hashable, Identifiable {
    public var timeZoneID: String
    /// What the strip shows; empty falls back to the city's name.
    public var label: String
    public var id: String { timeZoneID }

    public static let limit = 4

    public init(timeZoneID: String, label: String) {
        self.timeZoneID = timeZoneID; self.label = label
    }

    public var timeZone: TimeZone { TimeZone(identifier: timeZoneID) ?? .current }
    public var displayLabel: String {
        let l = label.trimmingCharacters(in: .whitespaces)
        return l.isEmpty ? Self.cityName(timeZoneID) : l
    }

    /// "+5 h", "−3:30 h" or "same time" relative to `zone`.
    public func offsetText(from zone: TimeZone, at date: Date = Date()) -> String {
        Self.offsetText(timeZone.secondsFromGMT(for: date) - zone.secondsFromGMT(for: date))
    }

    static func offsetText(_ seconds: Int) -> String {
        guard seconds != 0 else { return "same time" }
        let sign = seconds > 0 ? "+" : "\u{2212}"
        let h = abs(seconds) / 3600, m = (abs(seconds) % 3600) / 60
        return m == 0 ? "\(sign)\(h) h" : "\(sign)\(h):\(String(format: "%02d", m)) h"
    }

    /// "Yesterday", "Tomorrow" or nil when the clock's date is the same as here.
    public func dayShift(at date: Date, from zone: TimeZone = .current) -> String? {
        var here = Calendar(identifier: .gregorian); here.timeZone = zone
        var there = here; there.timeZone = timeZone
        let a = here.dateComponents([.year, .month, .day], from: date)
        let b = there.dateComponents([.year, .month, .day], from: date)
        guard let da = here.date(from: a), let db = here.date(from: b) else { return nil }
        let diff = here.dateComponents([.day], from: da, to: db).day ?? 0
        return diff > 0 ? "Tomorrow" : diff < 0 ? "Yesterday" : nil
    }

    /// "America/New_York" → "New York".
    public static func cityName(_ id: String) -> String {
        (id.split(separator: "/").last.map(String.init) ?? id).replacingOccurrences(of: "_", with: " ")
    }

    /// Time zones whose city, region or abbreviation matches what was typed, best first.
    public static func search(_ query: String, in ids: [String] = TimeZone.knownTimeZoneIdentifiers, limit: Int = 6) -> [String] {
        let q = query.trimmingCharacters(in: .whitespaces).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        guard !q.isEmpty else { return [] }
        func fold(_ s: String) -> String { s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil) }
        let scored: [(String, Int)] = ids.compactMap { id in
            let city = fold(cityName(id))
            if city.hasPrefix(q) { return (id, 0) }
            if city.contains(q) { return (id, 1) }
            if fold(id.replacingOccurrences(of: "_", with: " ")).contains(q) { return (id, 2) }
            if let abbr = TimeZone(identifier: id)?.abbreviation(), fold(abbr) == q { return (id, 3) }
            return nil
        }
        return scored.sorted { $0.1 != $1.1 ? $0.1 < $1.1 : $0.0 < $1.0 }.prefix(limit).map(\.0)
    }

    public static func decode(_ raw: String) -> [WorldClock] {
        guard !raw.isEmpty, let list = try? JSONDecoder().decode([WorldClock].self, from: Data(raw.utf8)) else { return [] }
        return Array(list.filter { TimeZone(identifier: $0.timeZoneID) != nil }.prefix(limit))
    }

    public static func encode(_ clocks: [WorldClock]) -> String {
        (try? JSONEncoder().encode(Array(clocks.prefix(limit)))).flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }
}
