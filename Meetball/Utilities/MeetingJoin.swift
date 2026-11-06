import AppKit
import SwiftUI
import SK1Tokens
import SK1UI

public struct InstalledBrowser: Identifiable, Hashable {
    public let bundleID: String
    public let name: String
    public var id: String { bundleID }
}

/// Single entry point for opening meeting links, so every Join button behaves the same way.
@MainActor
public enum MeetingJoiner {
    /// When each meeting link was last opened through Meetball, so auto-join (#24) leaves joined meetings alone.
    private static var lastJoined: [String: Date] = [:]

    /// Whether `e`'s link was opened through Meetball at or after `since`.
    public static func joined(_ e: CalendarEvent, since: Date) -> Bool {
        guard let u = e.meetURL, let at = lastJoined[u.absoluteString] else { return false }
        return at >= since
    }

    public static func join(_ url: URL, preferences: JoinPreferences = JoinPreferences()) {
        lastJoined[url.absoluteString] = Date()
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

