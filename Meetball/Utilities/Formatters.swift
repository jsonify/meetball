import Foundation

/// "in 5 min", "2 hr ago" style formatting.
public struct RelativeTimeFormatter {
    public static func string(for date: Date, relativeTo now: Date = Date()) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f.localizedString(for: date, relativeTo: now)
    }
}

/// Compact countdown used in the menu bar: "5m", "1h 20m", "now".
public struct TimeUntilFormatter {
    public static func string(until date: Date, now: Date = Date()) -> String {
        let secs = Int(date.timeIntervalSince(now).rounded(.up))
        if secs <= 0 { return "now" }
        let mins = (secs + 59) / 60
        if mins < 60 { return "\(mins)m" }
        let h = mins / 60, m = mins % 60
        if h >= 24 { return "\(h / 24)d" }
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }
}

public struct NewEventDateRange: Equatable {
    public var start: Date
    public var end: Date
}

/// Builds the default start/end for a new event on a chosen day: next half hour, 30 min long.
public struct NewEventDateRangeBuilder {
    public static func build(day: Date, now: Date = Date(), calendar: Calendar = .current) -> NewEventDateRange {
        var comps = calendar.dateComponents([.year, .month, .day], from: day)
        let nowComps = calendar.dateComponents([.hour, .minute], from: now)
        let isToday = calendar.isDate(day, inSameDayAs: now)
        var hour = isToday ? (nowComps.hour ?? 9) : 9
        var minute = 0
        if isToday {
            minute = (nowComps.minute ?? 0) < 30 ? 30 : 0
            if minute == 0 { hour += 1 }
        }
        if hour > 23 { hour = 23; minute = 0 }
        comps.hour = hour; comps.minute = minute
        let start = calendar.date(from: comps) ?? day
        return NewEventDateRange(start: start, end: start.addingTimeInterval(30 * 60))
    }
}

/// Turns event descriptions (Google sends HTML, Apple plain text) into readable plain text.
public enum EventNotesFormatter {
    public static let maxLength = 4000

    public static func plainText(_ raw: String) -> String {
        var s = raw.replacingOccurrences(of: "\r\n", with: "\n")
        if s.range(of: #"<[a-zA-Z/][^>]*>"#, options: .regularExpression) != nil {
            s = s.replacingOccurrences(of: "\n", with: " ")
            s = replaceLinks(s)
            s = s.replacingOccurrences(of: #"(?i)<br\s*/?>"#, with: "\n", options: .regularExpression)
            s = s.replacingOccurrences(of: #"(?i)<li[^>]*>"#, with: "\n• ", options: .regularExpression)
            s = s.replacingOccurrences(of: #"(?i)</(p|div|ul|ol|h[1-6]|tr)>"#, with: "\n", options: .regularExpression)
            s = s.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
        }
        s = decodeEntities(s)
        s = s.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.replacingOccurrences(of: #"[ \t\u{00A0}]+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces) }
            .joined(separator: "\n")
        s = s.replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.count > maxLength { s = String(s.prefix(maxLength)).trimmingCharacters(in: .whitespacesAndNewlines) + "…" }
        return s
    }

    /// Plain text with URLs (and emails / phone numbers) turned into clickable links.
    public static func linked(_ text: String) -> AttributedString {
        var out = AttributedString(text)
        let types: NSTextCheckingResult.CheckingType = [.link, .phoneNumber]
        guard let detector = try? NSDataDetector(types: types.rawValue) else { return out }
        for m in detector.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let r = Range(m.range, in: text),
                  let lower = AttributedString.Index(r.lowerBound, within: out),
                  let upper = AttributedString.Index(r.upperBound, within: out) else { continue }
            if let url = m.url {
                out[lower..<upper].link = url
            } else if let phone = m.phoneNumber, let url = URL(string: "tel:" + phone.filter { "+0123456789".contains($0) }) {
                out[lower..<upper].link = url
            }
        }
        return out
    }

    /// `<a href="u">text</a>` → `text (u)`, or just `u` when the text is the URL itself.
    private static func replaceLinks(_ s: String) -> String {
        guard let re = try? NSRegularExpression(pattern: #"<a\s[^>]*href\s*=\s*["']([^"']*)["'][^>]*>(.*?)</a>"#,
                                                options: [.caseInsensitive, .dotMatchesLineSeparators]) else { return s }
        var out = s
        for m in re.matches(in: s, range: NSRange(s.startIndex..., in: s)).reversed() {
            guard let whole = Range(m.range, in: out), let h = Range(m.range(at: 1), in: out), let t = Range(m.range(at: 2), in: out) else { continue }
            let href = decodeEntities(String(out[h]))
            let text = decodeEntities(String(out[t]).replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression))
                .trimmingCharacters(in: .whitespaces)
            let plainHref = href.replacingOccurrences(of: #"^(https?://|mailto:)"#, with: "", options: .regularExpression)
            let replacement = text.isEmpty || text == href || text == plainHref ? href : "\(text) (\(href))"
            out.replaceSubrange(whole, with: replacement)
        }
        return out
    }

    private static func decodeEntities(_ s: String) -> String {
        var out = s
        for (k, v) in [("&nbsp;", " "), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'"), ("&apos;", "'"), ("&amp;", "&")] {
            out = out.replacingOccurrences(of: k, with: v)
        }
        return out
    }
}

/// "30 min", "1 hr 15 min", "2 days".
public enum DurationFormatter {
    public static func string(from start: Date, to end: Date) -> String {
        let mins = max(0, Int((end.timeIntervalSince(start) / 60).rounded()))
        if mins < 60 { return "\(mins) min" }
        if mins >= 24 * 60 && mins % (24 * 60) == 0 { let d = mins / (24 * 60); return d == 1 ? "1 day" : "\(d) days" }
        let h = mins / 60, m = mins % 60
        return m == 0 ? "\(h) hr" : "\(h) hr \(m) min"
    }
}
