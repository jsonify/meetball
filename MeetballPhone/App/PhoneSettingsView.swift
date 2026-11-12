import CoreLocation
import SwiftUI
import UIKit
import UserNotifications
import SK1Tokens
import SK1UI

/// The sections of the iPhone's Settings, as the Mac's Settings window has them: a key for each in a tray under the
/// settings LCD, which names the section showing and the build that's running.
enum PhoneSettingsSection: String, CaseIterable, Identifiable {
    case general, alerts, events, calendars, prep, trips, style, about
    var id: String { rawValue }
    var title: String {
        switch self {
        case .general: return "General"
        case .alerts: return "Alerts"
        case .events: return "Events"
        case .calendars: return "Calendars"
        case .prep: return "Prep"
        case .trips: return "Trips"
        case .style: return "Style"
        case .about: return "About"
        }
    }
    /// What the section covers, under the LCD.
    var detail: String {
        switch self {
        case .general: return "Calendar access, whether alerts reach the car, and a test alert."
        case .alerts: return "When you're reminded, the alert schedule and recent changes."
        case .events: return "Which events Today, alerts, widgets and Siri hide or fade."
        case .calendars: return "Which calendars show, and which stay quiet."
        case .prep: return "The pre-flight card before a meeting and Echo notes after it."
        case .trips: return "Directions, drive times and Leave now alerts."
        case .style: return "Theme, the Today tab and the fun."
        case .about: return "Which build of Meetball is running."
        }
    }
    var symbol: String {
        switch self {
        case .general: return "gearshape.fill"
        case .alerts: return "bell.badge.fill"
        case .events: return "line.3.horizontal.decrease.circle.fill"
        case .calendars: return "calendar"
        case .prep: return "checklist"
        case .trips: return "car.fill"
        case .style: return "paintpalette.fill"
        case .about: return "info.circle.fill"
        }
    }
}

/// Settings: the settings LCD (the section showing and the version), a tray of keys for the sections, and the
/// section's groups.
struct PhoneSettingsView: View {
    @Binding var section: PhoneSettingsSection
    @EnvironmentObject private var store: PhoneStore
    @Environment(\.openURL) private var openURL
    @AppStorage(AppPreferences.Key.theme) private var themeRaw = AppTheme.system.rawValue

    var body: some View {
        PhoneScrollScreen {
            PhoneScreenHeader(title: "Settings", detail: "Meetball \(AppVersion.current.short)") { EmptyView() }
        } content: {
            VStack(alignment: .leading, spacing: SK1.Metrics.groupSpacing) {
                VStack(alignment: .leading, spacing: 8) {
                    PhoneSettingsLCD(section: section, version: AppVersion.current.short)
                    PhoneSettingsKeys(selection: $section)
                    Text(section.detail).sk1Hint()
                }
                if store.calendarAccess != .granted && section != .about { accessCard }
                content
            }
        }
        .sensoryFeedback(.selection, trigger: section)
    }

    @ViewBuilder private var content: some View {
        switch section {
        case .general:
            statusGroup
            keys
        case .alerts:
            alertsGroup
            upcomingGroup
            if !store.recentChanges.isEmpty { changesGroup }
        case .events:
            PhoneEventFilterGroups()
        case .calendars:
            workGroup
            calendarsGroup
        case .prep:
            prepGroup
        case .trips:
            tripsGroup
        case .style:
            appearanceGroup
            funGroup
        case .about:
            PhoneAboutGroups()
        }
    }

    // MARK: Pre-flight and Echo

    private var prepGroup: some View {
        SKGroup(caption: "Before and after",
                note: "Echo listens only while you record, and transcribes on the iPhone itself. Notes stay in Meetball (the work calendar can't be written to) and, if you like, in Reminders.") {
            SKRow(title: "Pre-flight card", subtitle: "Five minutes before a meeting: who's in it, the last meeting with them and your note from it, and the invite's links.") {
                Toggle("Pre-flight card", isOn: $store.settings.preFlight).labelsHidden().toggleStyle(.sk1Switch)
            }
            SKRow(title: "Echo", subtitle: "When a meeting ends, one tap records a voice note for your follow-ups, for as long as you talk.") {
                Toggle("Echo", isOn: $store.settings.echoMode).labelsHidden().toggleStyle(.sk1Switch)
            }
            SKRow(title: "Add to To-do", subtitle: "Each Echo note also goes on your to-do list, due the next working morning. Off: add the ones you want from the note.") {
                Toggle("Add to To-do", isOn: $store.settings.echoToReminders).labelsHidden().toggleStyle(.sk1Switch)
                    .disabled(!store.settings.echoMode)
            }
            if !store.echoNotes.isEmpty {
                SKRow(title: "Echo notes", subtitle: "\(store.echoNotes.count) saved. Each one shows on its meeting.") { EmptyView() }
            }
        }
    }

    // MARK: Trips

    private var tripsGroup: some View {
        SKGroup(caption: "Trips",
                note: "Games, parties and appointments get a Directions key. When one has no place, Meetball asks where it is (suggesting where it was last time) and saves your pick to the event. Drive times come from Apple Maps; your location stays on the iPhone and Apple's directions service.") {
            SKRow(title: "Directions in", subtitle: "Google Maps and Waze open their app if it's installed, or the website if not.") {
                SKSegmented(selection: $store.settings.directionsApp,
                            options: DirectionsApp.allCases.map { .init($0, $0.shortTitle, help: $0.title) })
            }
            SKRow(title: "Leave-by times", subtitle: locationSubtitle) {
                HStack(spacing: 10) {
                    if store.locationStatus == .notDetermined && store.settings.driveTimes {
                        Button("Allow") { store.requestLocation() }.buttonStyle(.sk1Key(size: .small))
                    } else if (store.locationStatus == .denied || store.locationStatus == .restricted) && store.settings.driveTimes {
                        Button("Settings") { openURL(URL(string: UIApplication.openSettingsURLString)!) }.buttonStyle(.sk1Key(size: .small))
                    }
                    Toggle("Leave-by times", isOn: $store.settings.driveTimes).labelsHidden().toggleStyle(.sk1Switch)
                }
            }
            SKRow(title: "Leave now alert", subtitle: "At the leave-by time; tap it, or Directions, to start the drive. Siri reads it in CarPlay.") {
                Toggle("Leave now alert", isOn: $store.settings.leaveAlerts).labelsHidden().toggleStyle(.sk1Switch)
                    .disabled(!store.settings.driveTimes)
            }
            SKRow(title: "Time to park", subtitle: "Added to the drive.") {
                SKSegmented(selection: $store.settings.leaveBufferMinutes,
                            options: TravelPlanner.bufferChoices.map { .init($0, "\($0)m", help: "\($0) minutes to park and walk in") })
            }
            if !store.settings.notTrips.isEmpty {
                SKRow(title: "Not a trip", subtitle: "\(store.settings.notTrips.count) skipped by Where's this?") {
                    Button("Ask again") { store.settings.notTrips = [] }.buttonStyle(.sk1Key(size: .small))
                }
            }
        }
    }

    private var locationSubtitle: String {
        switch store.locationStatus {
        case .notDetermined: return "The drive from where you are, with traffic, for trips in the next day. Needs location access."
        case .denied, .restricted: return "Location is off for Meetball. Turn on While Using the App in Settings › Apps › Meetball › Location."
        default: return "The drive from where you are, with traffic, for trips in the next day, checked every 10 minutes in the two hours before."
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
            SKRow(title: "Today tab", subtitle: "The MB-1 display and the rest of today and tomorrow as a list. Meetball opens on the Day grid either way.") {
                Toggle("Today tab", isOn: $store.settings.showTodayTab).labelsHidden().toggleStyle(.sk1Switch)
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
                  subtitle: "Checked whenever Meetball runs; see Background checks in General.") {
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
                        SKChip(reminders[e.uid].map { $0.fireDate.shortTime } ?? (store.settings.alerts(for: e) ? "—" : "Silent"))
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
        SKGroup(caption: "Calendars",
                note: "Switch a calendar off to hide it. Press its bell to keep it visible but silence its alerts (a family calendar, say); you can still turn alerts on for one of its meetings from the meeting itself. Press its briefcase to mark it as a work calendar.") {
            ForEach(store.calendars, id: \.key) { cal in
                SKRow(title: cal.summary, subtitle: cal.accountEmail.replacingOccurrences(of: AppleCalendarClient.sourcePrefix, with: "")) {
                    HStack(spacing: 10) {
                        let shown = !store.settings.hiddenCalendars.contains(cal.key)
                        let silenced = store.settings.silencedCalendars.contains(cal.key)
                        Button { toggleSilenced(cal) } label: {
                            Image(systemName: silenced ? "bell.slash.fill" : "bell")
                        }
                        .buttonStyle(.sk1Key(isOn: silenced, size: .small))
                        .disabled(!shown)
                        .opacity(shown ? 1 : 0.4)
                        .accessibilityLabel(silenced ? "Turn on alerts for \(cal.summary)" : "Silence alerts for \(cal.summary)")
                        let work = store.settings.workCalendars.contains(cal.key)
                        Button { store.settings.toggleWork(cal.key) } label: {
                            Image(systemName: work ? "briefcase.fill" : "briefcase")
                        }
                        .buttonStyle(.sk1Key(isOn: work, size: .small))
                        .disabled(!shown)
                        .opacity(shown ? 1 : 0.4)
                        .accessibilityLabel(work ? "Unmark \(cal.summary) as a work calendar" : "Mark \(cal.summary) as a work calendar")
                        Toggle(cal.summary, isOn: visible(cal)).labelsHidden().toggleStyle(.sk1Switch)
                    }
                }
            }
        }
    }

    /// "Work only", as the Day grid's All / Work switch sets it.
    private var workGroup: some View {
        let marked = store.settings.workCalendars.count
        return SKGroup(caption: "Work",
                       note: marked == 0
                        ? "Press the briefcase beside your work calendars below, then switch between All and Work from the Day screen."
                        : "Day, Week, Month and Today show only the \(marked == 1 ? "work calendar" : "\(marked) work calendars"). Alerts, widgets and the Live Activity still cover every calendar that's switched on.") {
            SKRow(title: "Work calendars only", subtitle: marked == 0 ? "No calendar marked as work yet" : nil) {
                Toggle("Work calendars only", isOn: Binding(get: { store.settings.isWorkOnly },
                                                            set: { store.settings.workOnly = $0 }))
                    .labelsHidden().toggleStyle(.sk1Switch)
                    .disabled(marked == 0)
            }
        }
    }

    private func toggleSilenced(_ cal: GCalendar) {
        if store.settings.silencedCalendars.contains(cal.key) { store.settings.silencedCalendars.remove(cal.key) }
        else { store.settings.silencedCalendars.insert(cal.key) }
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
