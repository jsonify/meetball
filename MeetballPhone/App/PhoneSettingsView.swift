import SwiftUI
import UIKit
import UserNotifications
import SK1Tokens
import SK1UI

/// Settings: whether alerts can reach CarPlay, alert timing, the alert schedule, recent changes, which calendars to
/// watch, the theme and the fun.
struct PhoneSettingsView: View {
    @EnvironmentObject private var store: PhoneStore
    @Environment(\.openURL) private var openURL
    @AppStorage(AppPreferences.Key.theme) private var themeRaw = AppTheme.system.rawValue

    var body: some View {
        VStack(alignment: .leading, spacing: SK1.Metrics.groupSpacing) {
            PhoneScreenHeader(title: "Settings", detail: "Meetball \(version)") { EmptyView() }
            if store.calendarAccess != .granted { accessCard }
            statusGroup
            alertsGroup
            prepGroup
            funGroup
            appearanceGroup
            upcomingGroup
            if !store.recentChanges.isEmpty { changesGroup }
            calendarsGroup
            keys
        }
    }

    private var version: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? ""
    }

    // MARK: Pre-flight and Echo

    private var prepGroup: some View {
        SKGroup(caption: "Before and after",
                note: "Echo listens only while you record, and transcribes on the iPhone itself. Notes stay in Meetball (the work calendar can't be written to) and, if you like, in Reminders.") {
            SKRow(title: "Pre-flight card", subtitle: "Five minutes before a meeting: who's in it, the last meeting with them and your note from it, and the invite's links.") {
                Toggle("Pre-flight card", isOn: $store.settings.preFlight).labelsHidden().toggleStyle(.sk1Switch)
            }
            SKRow(title: "Echo", subtitle: "When a meeting ends, one tap records a 20-second voice note for your follow-ups.") {
                Toggle("Echo", isOn: $store.settings.echoMode).labelsHidden().toggleStyle(.sk1Switch)
            }
            SKRow(title: "Add to Reminders", subtitle: "Each Echo note also becomes a reminder, due the next working morning.") {
                Toggle("Add to Reminders", isOn: $store.settings.echoToReminders).labelsHidden().toggleStyle(.sk1Switch)
                    .disabled(!store.settings.echoMode)
            }
            if !store.echoNotes.isEmpty {
                SKRow(title: "Echo notes", subtitle: "\(store.echoNotes.count) saved. Each one shows on its meeting.") { EmptyView() }
            }
        }
    }

    // MARK: Fun

    private var funGroup: some View {
        SKGroup(caption: "Fun",
                note: "Shake your phone to see the rest of your day. Ask Siri \u{201C}Join my meeting in Meetball\u{201D} or \u{201C}What's my next meeting in Meetball\u{201D}, put Join Meeting on the Action Button (Settings › Action Button › Shortcut), or add the Join Meeting control to Control Center.") {
            SKRow(title: "Celebrate cancellations", subtitle: "Confetti and a happy buzz when a meeting is called off.") {
                Toggle("Celebrate cancellations", isOn: $store.settings.celebrateCancellations).labelsHidden().toggleStyle(.sk1Switch)
            }
            SKRow(title: "Countdown moment", subtitle: "Full screen for the last minute before a meeting while Meetball is open, ticking for the last ten seconds.") {
                Toggle("Countdown moment", isOn: $store.settings.countdownMoment).labelsHidden().toggleStyle(.sk1Switch)
            }
            SKRow(title: "Try it") {
                Button("Confetti") { store.previewCelebration() }.buttonStyle(.sk1Key(size: .small))
            }
        }
    }

    // MARK: Appearance

    private var appearanceGroup: some View {
        SKGroup(caption: "Appearance") {
            SKRow(title: "Theme", subtitle: "Light is the cream SK-1 look, Dark the charcoal one. System follows the iPhone.") {
                SKSegmented(selection: $themeRaw, options: AppTheme.allCases.map { SKSegmented<String>.Option($0.rawValue, $0.title) })
            }
        }
    }

    private var accessCard: some View {
        SKGroup(caption: "Calendar access",
                note: "Meetball reads the calendars in the Calendar app, including a work Google calendar added through iCloud.") {
            SKRow(title: store.calendarAccess == .denied ? "Calendar access is off" : "Meetball needs your calendar",
                  subtitle: store.calendarAccess == .denied ? "Turn on Full Access in Settings › Apps › Meetball › Calendars." : nil) {
                if store.calendarAccess == .denied {
                    Button("Settings") { openURL(URL(string: UIApplication.openSettingsURLString)!) }
                        .buttonStyle(.sk1Key(.orange))
                } else {
                    Button("Allow") { Task { await store.requestCalendarAccess() } }
                        .buttonStyle(.sk1Key(.orange))
                }
            }
        }
    }

    // MARK: Status

    private var statusGroup: some View {
        let n = store.notificationSettings
        return SKGroup(caption: "Can alerts reach the car?",
                       note: "In CarPlay, Siri reads Time Sensitive alerts aloud when Settings › Notifications › Announce Notifications › CarPlay is on. The banner only shows on the car screen for apps Apple approves for CarPlay, so expect to hear Meetball rather than see it.") {
            SKRow(title: "Notifications", subtitle: n?.authorizationStatus == .denied ? "Off. Turn on in Settings › Notifications › Meetball." : nil) {
                lamp(n.map { $0.authorizationStatus == .authorized || $0.authorizationStatus == .provisional })
            }
            SKRow(title: "Time Sensitive", subtitle: "Lets alerts through Driving Focus.") {
                lamp(n.map { $0.timeSensitiveSetting == .enabled })
            }
            SKRow(title: "Siri announces", subtitle: "Settings › Notifications › Announce Notifications.") {
                lamp(n.map { $0.announcementSetting == .enabled })
            }
            SKRow(title: "Shown on CarPlay screen", subtitle: "Needs Apple's CarPlay approval; Siri still reads alerts without it.") {
                lamp(n.map { $0.carPlaySetting == .enabled })
            }
            SKRow(title: "Background checks",
                  subtitle: store.lastBackgroundRefresh.map { "Last ran \($0.formatted(.relative(presentation: .named)))." }
                    ?? "Needs Background App Refresh on for Meetball.") {
                lamp(UIApplication.shared.backgroundRefreshStatus == .available)
            }
        }
    }

    private func lamp(_ on: Bool?) -> some View {
        SKLamp(color: on == true ? .success : .warning, lit: on != nil, label: on == true ? "On" : "Off")
            .frame(width: 24)
    }

    // MARK: Alerts

    private var alertsGroup: some View {
        SKGroup(caption: "Alerts") {
            SKRow(title: "Remind me") {
                SKSegmented(selection: $store.settings.leadMinutes,
                            options: PhoneSettings.leadChoices.map { .init($0, "\($0)m", help: ReminderPlanner.minutes($0) + " before") })
            }
            SKRow(title: "Also when it starts") {
                Toggle("Also when it starts", isOn: $store.settings.alertAtStart).labelsHidden().toggleStyle(.sk1Switch)
            }
            SKRow(title: "Countdown on the Lock Screen",
                  subtitle: "A Live Activity in the hour before a meeting, in the Dynamic Island too. It starts when you open Meetball in that hour.") {
                Toggle("Countdown on the Lock Screen", isOn: $store.settings.liveActivity).labelsHidden().toggleStyle(.sk1Switch)
            }
            SKRow(title: "Moves, new links, cancellations",
                  subtitle: "Checked whenever Meetball runs; see Background checks above.") {
                Toggle("Moves, new links, cancellations", isOn: $store.settings.notifyChanges).labelsHidden().toggleStyle(.sk1Switch)
            }
        }
    }

    // MARK: Upcoming

    private var upcomingGroup: some View {
        let reminders = Dictionary(store.scheduled.filter { $0.kind == .lead }.map { ($0.event.uid, $0) }, uniquingKeysWith: { a, _ in a })
        return SKGroup(caption: "Alert schedule",
                       note: store.lastRefresh.map { "Checked \($0.shortTime). \(store.scheduled.count) alerts scheduled." }) {
            if store.upcoming.isEmpty {
                SKRow(title: "Nothing in the next 48 hours") { EmptyView() }
            } else {
                ForEach(store.upcoming.prefix(10)) { e in
                    SKRow(title: e.title, subtitle: subtitle(e)) {
                        SKChip(reminders[e.uid].map { $0.fireDate.shortTime } ?? "—")
                            .accessibilityLabel(reminders[e.uid].map { "Alert at \($0.fireDate.shortTime)" } ?? "No alert")
                    }
                }
            }
        }
    }

    private func subtitle(_ e: CalendarEvent) -> String {
        let day: String
        if Calendar.app.isDateInToday(e.start) { day = "Today" }
        else if Calendar.app.isDateInTomorrow(e.start) { day = "Tomorrow" }
        else { day = e.start.formatted(.dateTime.weekday(.abbreviated)) }
        let cal = store.calendars.first { $0.key == e.calendarKey }?.summary
        return ["\(day) \(e.start.shortTime)", cal].compactMap { $0 }.joined(separator: " · ")
    }

    // MARK: Changes

    private var changesGroup: some View {
        SKGroup(caption: "Recent changes") {
            ForEach(store.recentChanges.prefix(5)) { c in
                SKRow(title: c.title, subtitle: c.body) {
                    Text(c.at.shortTime).sk1Hint()
                }
            }
        }
    }

    // MARK: Calendars

    private var calendarsGroup: some View {
        SKGroup(caption: "Calendars", note: "Meetings on calendars that are off get no alerts.") {
            ForEach(store.calendars, id: \.key) { cal in
                SKRow(title: cal.summary, subtitle: cal.accountEmail.replacingOccurrences(of: AppleCalendarClient.sourcePrefix, with: "")) {
                    Toggle(cal.summary, isOn: visible(cal)).labelsHidden().toggleStyle(.sk1Switch)
                }
            }
        }
    }

    private func visible(_ cal: GCalendar) -> Binding<Bool> {
        Binding(get: { !store.settings.hiddenCalendars.contains(cal.key) },
                set: { on in
                    if on { store.settings.hiddenCalendars.remove(cal.key) } else { store.settings.hiddenCalendars.insert(cal.key) }
                })
    }

    // MARK: Keys

    private var keys: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Button("Test alert in 10 s") { Task { await store.sendTestAlert(after: 10) } }
                    .buttonStyle(.sk1Key(.orange))
                Button("Refresh") { Task { await store.refresh(fresh: true) } }
                    .buttonStyle(.sk1Key())
            }
            Text("Lock your phone after tapping Test alert, or start it before you connect to CarPlay, to hear how alerts come through.")
                .sk1Hint()
        }
    }
}
