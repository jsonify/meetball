import Foundation

/// Which build is running: the marketing version, the build number (git commit count for `make` builds), the commit
/// and when it was built. Shown in Settings › General › About.
struct AppVersion: Equatable {
    let version: String
    let build: String
    let commit: String?
    let builtAt: Date?

    static let current = AppVersion(info: Bundle.main.infoDictionary ?? [:])

    init(info: [String: Any]) {
        func value(_ key: String) -> String? {
            guard let s = info[key] as? String else { return nil }
            let t = s.trimmingCharacters(in: .whitespaces)
            // An unexpanded "$(SETTING)" means the build didn't set it.
            return t.isEmpty || t.hasPrefix("$(") ? nil : t
        }
        version = value("CFBundleShortVersionString") ?? "0"
        build = value("CFBundleVersion") ?? "0"
        commit = value("MeetballCommit")
        builtAt = value("MeetballBuildDate").flatMap { ISO8601DateFormatter().date(from: $0) }
    }

    /// "0.1.0 (142)"
    var short: String { "\(version) (\(build))" }

    /// "Commit a1b2c3d · built Nov 5, 2026 at 12:03 PM", or a hint when the build wasn't stamped (an Xcode build).
    func detailText(calendar: Calendar = .current, locale: Locale = .current) -> String {
        var parts: [String] = []
        if let commit { parts.append("Commit \(commit)") }
        if let builtAt {
            var style = Date.FormatStyle(date: .abbreviated, time: .shortened, locale: locale, calendar: calendar)
            style.timeZone = calendar.timeZone
            parts.append("built \(builtAt.formatted(style))")
        }
        return parts.isEmpty ? "Development build (not built with make)." : parts.joined(separator: " · ")
    }

    var detail: String { detailText() }

    /// One line to paste into a bug report.
    var full: String { "Meetball \(short)" + (commit.map { " \($0)" } ?? "") }
}
