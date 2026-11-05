import AppKit

/// Puts Settings › Appearance › Theme on every window, the menu bar popover and the alerts: `NSApp.appearance`
/// is what SwiftUI's colour scheme (and so every SK-1 component) follows.
@MainActor
enum ThemeController {
    static func apply(_ theme: AppTheme = AppPreferences.theme()) {
        let appearance = theme.appearanceName.flatMap(NSAppearance.init(named:))
        guard NSApp.appearance?.name != appearance?.name else { return }
        NSApp.appearance = appearance
    }

    /// Whether macOS itself is in Dark Mode, whatever the app's theme: the menu bar follows macOS, not the app.
    static var systemIsDark: Bool {
        UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
    }
}
