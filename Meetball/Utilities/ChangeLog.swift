import Foundation

/// What's changed in Meetball, newest first. Shown in Settings › About on the Mac and the iPhone, each listing only the
/// changes for its own platform. Add an entry (or a line to today's) whenever a change is worth telling people about.
/// Shared with MeetballPhone, so it must not use AppKit.
enum ChangeLog {
    enum Platform: Equatable {
        case mac, iPhone, both

        func includes(_ other: Platform) -> Bool { self == .both || other == .both || self == other }
    }

    enum Kind: Equatable {
        case new, improved, fixed

        var label: String {
            switch self {
            case .new: return "NEW"
            case .improved: return "BETTER"
            case .fixed: return "FIX"
            }
        }
    }

    struct Change: Equatable {
        let kind: Kind
        let platform: Platform
        let text: String
    }

    struct Entry: Equatable, Identifiable {
        /// "2026-11-10"
        let day: String
        let changes: [Change]

        var id: String { day }

        var date: Date? {
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = TimeZone(identifier: "UTC")!
            let parts = day.split(separator: "-").compactMap { Int($0) }
            guard parts.count == 3 else { return nil }
            return cal.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12))
        }

        /// "Nov 10, 2026"
        func title(locale: Locale = .current) -> String {
            guard let date else { return day }
            var style = Date.FormatStyle(date: .abbreviated, time: .omitted, locale: locale)
            style.timeZone = TimeZone(identifier: "UTC")!
            return date.formatted(style)
        }
    }

    /// The entries with a change for `platform`, keeping only those changes.
    static func entries(for platform: Platform, from all: [Entry] = ChangeLog.all) -> [Entry] {
        all.compactMap { entry in
            let changes = entry.changes.filter { $0.platform.includes(platform) }
            return changes.isEmpty ? nil : Entry(day: entry.day, changes: changes)
        }
    }

    private static func new(_ p: Platform, _ t: String) -> Change { Change(kind: .new, platform: p, text: t) }
    private static func better(_ p: Platform, _ t: String) -> Change { Change(kind: .improved, platform: p, text: t) }
    private static func fixed(_ p: Platform, _ t: String) -> Change { Change(kind: .fixed, platform: p, text: t) }

    static let all: [Entry] = [
        Entry(day: "2026-11-14", changes: [
            new(.iPhone, "Timers: as many as you like, each with its own name, length and one of the iPhone's own sounds (Tri-tone, Bamboo, Fanfare…). Type a length on the keypad or quick start a preset. Open the screen menu and pick Timers."),
        ]),
        Entry(day: "2026-11-11", changes: [
            better(.both, "Picking a day for a meeting opens a square month calendar: page through months and tap any day, instead of scrolling a short list of dates."),
            new(.iPhone, "The event screen blooms out of the event you tap instead of sliding up as a sheet, and turns over to edit."),
            fixed(.iPhone, "Deleting a repeating meeting asks: only this one, or this and all future ones."),
            new(.iPhone, "Going? Yes, Maybe or No on the event screen and in Edit for meetings you're invited to. Your pick opens Apple's invite screen, which sends the reply."),
            better(.iPhone, "Edit's More options is now Invitees, alerts & repeat, and isn't shown for invitations, where Apple's editor had nothing more."),
        ]),
        Entry(day: "2026-11-10", changes: [
            new(.both, "A change log here in Settings › About, so you can see what's new."),
            better(.iPhone, "Editing an event uses Meetball's own SK-1 editor; More options opens Apple's for invitees, alerts and repeat."),
            new(.both, "Filtered events can fade in the calendar views instead of disappearing. Set how much with the fade knob."),
            new(.mac, "Change your RSVP (Yes, Maybe, No) right from the event popover."),
            new(.iPhone, "Pick a meeting's end time when you add it."),
            new(.iPhone, "The small widget is the LCD itself, and the Lock Screen widget and Live Activity card are redesigned as the MB-1."),
            new(.iPhone, "Screens have their own moves when you switch: zoom, lid and flip."),
        ]),
        Entry(day: "2026-11-09", changes: [
            new(.iPhone, "Settings is split into sections, with an About page showing the exact build."),
            new(.iPhone, "The Mac's event filters, with a filter key on Today."),
            new(.iPhone, "A floating dock with standard-size keys and a quick menu replaces the bottom key row."),
            new(.iPhone, "Builds arrive through TestFlight."),
            better(.mac, "The Day grid's Up next card has room for the whole meeting."),
            better(.mac, "The event popover sizes itself to its content."),
            fixed(.mac, "The floating alert cards take clicks again."),
        ]),
        Entry(day: "2026-11-08", changes: [
            new(.iPhone, "Trips: Directions and Where's this? for meetings with a place."),
            new(.iPhone, "Leave-by times and Leave now alerts for trips."),
        ]),
        Entry(day: "2026-11-07", changes: [
            new(.iPhone, "A Delete key on the event screen."),
            fixed(.iPhone, "The app no longer freezes when you delete an event."),
        ]),
        Entry(day: "2026-11-06", changes: [
            new(.both, "Silence a calendar's alerts, with an override for single events."),
            new(.mac, "Mark work calendars, and show only them."),
            new(.mac, "Auto-join recurring meetings by default, if you choose."),
            new(.mac, "Meetings that overlap the featured one are shown alongside it."),
            new(.iPhone, "Meetball for iPhone: Day, 3-Day, Week and Month views with the Mac app's fun."),
            new(.iPhone, "Alerts Siri can announce in CarPlay."),
            new(.iPhone, "Home Screen and Lock Screen widgets, and a meeting countdown Live Activity."),
            new(.iPhone, "Join from Siri, the Action Button or a Control Center button; StandBy, shake and a countdown moment."),
            new(.iPhone, "A meeting composer for quick add, which sends work meetings to Google Calendar."),
            new(.iPhone, "The pre-flight card before a meeting, and Echo voice notes after one."),
            new(.iPhone, "Edit events: Apple's editor on writable calendars, Google's edit page for work events."),
            better(.iPhone, "The Month tab is one continuous scroll of months."),
            better(.iPhone, "The small widget shows more."),
        ]),
        Entry(day: "2026-11-05", changes: [
            new(.mac, "Cards for moved, re-linked and cancelled meetings that stay until you dismiss them."),
            new(.mac, "System, Light and Dark themes, and a sidebar in Settings."),
            new(.mac, "Settings › About shows the exact build you're running."),
            new(.mac, "Change alerts, auto-join, multi-day ribbons, an LCD in the menu bar and a new app icon."),
            new(.mac, "A setup assistant, quick add, appearance options and world clocks."),
            new(.mac, "Alert intensity for each calendar, and importance rules."),
            new(.mac, "The SK-1 look across the main window and Settings."),
            better(.both, "Quick add reads spelled-out and approximate lengths (\"an hour\", \"about 30 min\")."),
            better(.mac, "Overnight meetings stay on the time grid."),
            better(.mac, "The next meeting stands out."),
            fixed(.mac, "Apple Calendar changes are caught, and Refresh really refetches."),
        ]),
    ]
}
