import AppIntents

/// Siri phrases, and what shows in Shortcuts and on the Action Button (Settings › Action Button › Shortcut › Meetball).
struct MeetballShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: JoinNextMeetingIntent(),
                    phrases: ["Join my meeting in \(.applicationName)",
                              "Join my next meeting in \(.applicationName)",
                              "\(.applicationName) join"],
                    shortTitle: "Join Meeting", systemImageName: "video.fill")
        AppShortcut(intent: NextMeetingIntent(),
                    phrases: ["What's my next meeting in \(.applicationName)",
                              "When is my next meeting in \(.applicationName)",
                              "\(.applicationName) what's next"],
                    shortTitle: "Next Meeting", systemImageName: "calendar.badge.clock")
    }
}
