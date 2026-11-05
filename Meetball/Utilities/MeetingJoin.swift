import AppKit
import SwiftUI

/// Video-conferencing service a meeting link belongs to.
public enum MeetingService: String, CaseIterable, Identifiable {
    case meet, zoom, teams, webex, other
    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .meet: return "Google Meet"
        case .zoom: return "Zoom"
        case .teams: return "Microsoft Teams"
        case .webex: return "Webex"
        case .other: return "Other links"
        }
    }

    public var shortName: String {
        switch self {
        case .meet: return "Meet"
        case .zoom: return "Zoom"
        case .teams: return "Teams"
        case .webex: return "Webex"
        case .other: return "Link"
        }
    }

    public var symbol: String {
        switch self {
        case .meet, .zoom, .webex: return "video.fill"
        case .teams: return "person.2.fill"
        case .other: return "link"
        }
    }

    public var tint: Color {
        switch self {
        case .meet: return Color(hex: "#00897B")
        case .zoom: return Color(hex: "#2D8CFF")
        case .teams: return Color(hex: "#5B5FC7")
        case .webex: return Color(hex: "#0A7E9E")
        case .other: return .accentColor
        }
    }

    /// Bundle identifiers of the service's native macOS app, newest first.
    public var nativeAppBundleIDs: [String] {
        switch self {
        case .zoom: return ["us.zoom.xos"]
        case .teams: return ["com.microsoft.teams2", "com.microsoft.teams"]
        case .webex: return ["Cisco-Systems.Spark", "com.webex.meetingmanager"]
        case .meet, .other: return []
        }
    }

    public var hasNativeApp: Bool { !nativeAppBundleIDs.isEmpty }

    /// Default: native app where one exists (falls back to the browser when it isn't installed).
    public var defaultOpenMode: JoinOpenMode { hasNativeApp ? .nativeApp : .defaultBrowser }

    public static func detect(_ url: URL) -> MeetingService {
        let host = (url.host ?? "").lowercased()
        let scheme = (url.scheme ?? "").lowercased()
        if host == "meet.google.com" { return .meet }
        if scheme == "zoommtg" || scheme == "zoomus" || host == "zoom.us" || host.hasSuffix(".zoom.us")
            || host == "zoomgov.com" || host.hasSuffix(".zoomgov.com") { return .zoom }
        if scheme == "msteams" || host == "teams.microsoft.com" || host.hasSuffix(".teams.microsoft.com")
            || host == "teams.live.com" { return .teams }
        if host == "webex.com" || host.hasSuffix(".webex.com") { return .webex }
        return .other
    }

    /// A deep link that opens the meeting straight in the native app, when the service has a URL scheme for it.
    public func nativeURL(for url: URL) -> URL? {
        let scheme = (url.scheme ?? "").lowercased()
        switch self {
        case .zoom:
            if scheme == "zoommtg" || scheme == "zoomus" { return url }
            // https://acme.zoom.us/j/123456789?pwd=abc → zoommtg://acme.zoom.us/join?action=join&confno=123456789&pwd=abc
            let parts = url.pathComponents
            guard let i = parts.firstIndex(of: "j"), i + 1 < parts.count, let host = url.host else { return nil }
            var c = URLComponents()
            c.scheme = "zoommtg"; c.host = host; c.path = "/join"
            var items = [URLQueryItem(name: "action", value: "join"), URLQueryItem(name: "confno", value: parts[i + 1])]
            if let pwd = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "pwd" })?.value {
                items.append(URLQueryItem(name: "pwd", value: pwd))
            }
            c.queryItems = items
            return c.url
        case .teams:
            if scheme == "msteams" { return url }
            guard scheme == "https", var c = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
            c.scheme = "msteams"
            return c.url
        case .meet, .webex, .other:
            return nil
        }
    }
}

/// Where a meeting link of a given service should open.
public enum JoinOpenMode: Hashable {
    case defaultBrowser
    case nativeApp
    case browser(bundleID: String)

    public init(raw: String) {
        switch raw {
        case "native": self = .nativeApp
        case "default": self = .defaultBrowser
        default:
            if raw.hasPrefix("browser:") { self = .browser(bundleID: String(raw.dropFirst("browser:".count))) }
            else { self = .defaultBrowser }
        }
    }

    public var raw: String {
        switch self {
        case .defaultBrowser: return "default"
        case .nativeApp: return "native"
        case .browser(let id): return "browser:\(id)"
        }
    }
}

public struct JoinPreferences {
    public let defaults: UserDefaults
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    private func key(_ s: MeetingService) -> String { "join.openMode.\(s.rawValue)" }

    public func mode(for s: MeetingService) -> JoinOpenMode {
        defaults.string(forKey: key(s)).map(JoinOpenMode.init(raw:)) ?? s.defaultOpenMode
    }

    public func setMode(_ m: JoinOpenMode, for s: MeetingService) { defaults.set(m.raw, forKey: key(s)) }

    /// How many minutes ahead the "join nearest meeting" shortcut looks for a meeting that hasn't started.
    public var joinWindowMinutes: Int {
        get { (defaults.object(forKey: "join.windowMinutes") as? Int) ?? 10 }
        nonmutating set { defaults.set(newValue, forKey: "join.windowMinutes") }
    }
}

public struct InstalledBrowser: Identifiable, Hashable {
    public let bundleID: String
    public let name: String
    public var id: String { bundleID }
}

/// Single entry point for opening meeting links, so every Join button behaves the same way.
@MainActor
public enum MeetingJoiner {
    public static func join(_ url: URL, preferences: JoinPreferences = JoinPreferences()) {
        let ws = NSWorkspace.shared
        let service = MeetingService.detect(url)
        switch preferences.mode(for: service) {
        case .nativeApp:
            if let native = service.nativeURL(for: url), ws.urlForApplication(toOpen: native) != nil {
                ws.open(native); return
            }
            if let app = service.nativeAppBundleIDs.lazy.compactMap({ ws.urlForApplication(withBundleIdentifier: $0) }).first {
                open(url, withApplicationAt: app); return
            }
        case .browser(let id):
            if let app = ws.urlForApplication(withBundleIdentifier: id) { open(url, withApplicationAt: app); return }
        case .defaultBrowser:
            break
        }
        ws.open(url)
    }

    public static func join(_ event: CalendarEvent) {
        if let u = event.meetURL { join(u) }
    }

    public static func copyLink(_ url: URL) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
    }

    public static func installedBrowsers() -> [InstalledBrowser] {
        guard let probe = URL(string: "https://example.com") else { return [] }
        let apps = NSWorkspace.shared.urlsForApplications(toOpen: probe)
        var seen = Set<String>()
        return apps.compactMap { appURL -> InstalledBrowser? in
            guard let id = Bundle(url: appURL)?.bundleIdentifier, seen.insert(id).inserted else { return nil }
            let name = FileManager.default.displayName(atPath: appURL.path).replacingOccurrences(of: ".app", with: "")
            return InstalledBrowser(bundleID: id, name: name)
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private static func open(_ url: URL, withApplicationAt app: URL) {
        NSWorkspace.shared.open([url], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
    }
}

/// Picks the meeting the "join" shortcut should open.
public enum NearestMeetingPicker {
    /// The most recently started in-progress meeting with a link; otherwise the next one starting within `window`.
    public static func pick(_ events: [CalendarEvent], now: Date = Date(), window: TimeInterval = 10 * 60) -> CalendarEvent? {
        let joinable = events.filter { !$0.isAllDay && !$0.isDeclined && $0.meetURL != nil && $0.end > now }
        if let current = joinable.filter({ $0.start <= now }).max(by: { $0.start < $1.start }) { return current }
        return joinable.filter { $0.start > now && $0.start.timeIntervalSince(now) <= window }.min(by: { $0.start < $1.start })
    }
}
