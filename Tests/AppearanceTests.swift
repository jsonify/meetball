import XCTest
import SK1Tokens
import AppKit
@testable import Meetball

/// Quick add's natural-language parser (#12).
final class QuickAddParserTests: XCTestCase {
    var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        c.firstWeekday = 1
        return c
    }()
    let us = Locale(identifier: "en_US")
    /// Wednesday 6 November 2030, 10:07.
    var now: Date { cal.date(from: DateComponents(year: 2030, month: 11, day: 6, hour: 10, minute: 7))! }

    func parse(_ s: String) -> QuickAddResult { QuickAddParser.parse(s, now: now, calendar: cal, locale: us) }
    func at(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int = 0) -> Date {
        cal.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi))!
    }

    func testIssueExample() {
        let r = parse("Lunch with Anna tomorrow 12:30-1:30 +meet")
        XCTAssertEqual(r.title, "Lunch with Anna")
        XCTAssertEqual(r.start, at(2030, 11, 7, 12, 30))
        XCTAssertEqual(r.end, at(2030, 11, 7, 13, 30))
        XCTAssertTrue(r.addMeet)
        XCTAssertTrue(r.hasDate); XCTAssertTrue(r.hasTime)
    }

    func testWeekdayTimeAndDuration() {
        let r = parse("Dentist fri 3pm for 45 min")
        XCTAssertEqual(r.title, "Dentist")
        XCTAssertEqual(r.start, at(2030, 11, 8, 15))
        XCTAssertEqual(r.end, at(2030, 11, 8, 15, 45))
    }

    func testRangeSharesMeridiem() {
        let r = parse("Planning next monday 3-4pm")
        XCTAssertEqual(r.title, "Planning")
        XCTAssertEqual(r.start, at(2030, 11, 11, 15))
        XCTAssertEqual(r.end, at(2030, 11, 11, 16))
        let morning = parse("Review 11-1pm")
        XCTAssertEqual(morning.start, at(2030, 11, 6, 11))
        XCTAssertEqual(morning.end, at(2030, 11, 6, 13))
    }

    func testEmailsBecomeAttendees() {
        let r = parse("Review with bob@x.com, amy@y.co on dec 3 at 10:30am")
        XCTAssertEqual(r.title, "Review")
        XCTAssertEqual(r.attendees, ["bob@x.com", "amy@y.co"])
        XCTAssertEqual(r.start, at(2030, 12, 3, 10, 30))
    }

    func testBareHourIsAfternoonUpToSeven() {
        XCTAssertEqual(parse("Standup at 9").start, at(2030, 11, 7, 9), "9:00 has passed today, so tomorrow")
        XCTAssertEqual(parse("Call at 3").start, at(2030, 11, 6, 15))
    }

    func testNoTimeUsesTheNextHalfHour() {
        let r = parse("Write report")
        XCTAssertEqual(r.title, "Write report")
        XCTAssertEqual(r.start, at(2030, 11, 6, 10, 30))
        XCTAssertEqual(r.end, at(2030, 11, 6, 11))
        XCTAssertFalse(r.hasDate); XCTAssertFalse(r.hasTime)
        XCTAssertEqual(parse("Offsite in 2 weeks").start, at(2030, 11, 20, 9))
    }

    func testDatesAndTonight() {
        XCTAssertEqual(parse("Team offsite 12/3").start, at(2030, 12, 3, 9))
        XCTAssertEqual(parse("Board the 5th of may 9am-11am").start, at(2031, 5, 5, 9), "May has passed this year")
        XCTAssertEqual(parse("Call mom tonight").start, at(2030, 11, 6, 19))
        XCTAssertEqual(parse("Coffee noon").start, at(2030, 11, 6, 12))
    }

    func testNumericDateFollowsLocale() {
        let r = QuickAddParser.parse("Trip 3/12", now: now, calendar: cal, locale: Locale(identifier: "en_GB"))
        XCTAssertEqual(r.start, at(2030, 12, 3, 9))
    }
}

final class AppPreferencesTests: XCTestCase {
    func testFirstWeekday() {
        var base = Calendar(identifier: .gregorian); base.firstWeekday = 1
        XCTAssertEqual(AppPreferences.calendar(firstWeekday: 2, base: base).firstWeekday, 2)
        XCTAssertEqual(AppPreferences.calendar(firstWeekday: 0, base: base).firstWeekday, 1, "0 follows the system")
    }

    func testClockStyle() {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!
        let d = c.date(from: DateComponents(year: 2030, month: 1, day: 1, hour: 14, minute: 30))!
        let utc = TimeZone(identifier: "UTC")!
        let base = Locale(identifier: "en_US")
        XCTAssertTrue(d.shortTime(locale: AppPreferences.locale(clock: .twentyFourHour, base: base), timeZone: utc).contains("14:30"))
        XCTAssertTrue(d.shortTime(locale: AppPreferences.locale(clock: .twelveHour, base: Locale(identifier: "en_GB")), timeZone: utc).contains("2:30"))
    }
}

final class SettingsSearchTests: XCTestCase {
    func testFindsByKeywordAndTab() {
        XCTAssertTrue(SettingsSearch.matches("dock").contains { $0.title == "Menu bar only" })
        XCTAssertTrue(SettingsSearch.matches("24-hour").contains { $0.tab == .appearance })
        XCTAssertTrue(SettingsSearch.matches("week num").contains { $0.title == "Show week numbers" })
        XCTAssertTrue(SettingsSearch.matches("").isEmpty)
        XCTAssertTrue(SettingsSearch.matches("zzzz").isEmpty)
        XCTAssertTrue(SettingsSearch.matches("dark mode").contains { $0.title == "Theme" && $0.tab == .appearance })
        XCTAssertTrue(SettingsSearch.matches("version").contains { $0.tab == .about })
    }

    func testSidebarPinsAboutLast() {
        XCTAssertFalse(SettingsTab.navigation.contains(.about))
        XCTAssertEqual(SettingsTab.navigation.first, .general)
        XCTAssertEqual(SettingsTab.navigation.count + 1, SettingsTab.allCases.count)
    }
}

final class AppThemeTests: XCTestCase {
    func testThemeDefaultsToSystemAndMapsToAppearances() {
        let d = UserDefaults(suiteName: "AppThemeTests-\(UUID().uuidString)")!
        XCTAssertEqual(AppPreferences.theme(d), .system)
        d.set("dark", forKey: AppPreferences.Key.theme)
        XCTAssertEqual(AppPreferences.theme(d), .dark)
        d.set("bogus", forKey: AppPreferences.Key.theme)
        XCTAssertEqual(AppPreferences.theme(d), .system)
        XCTAssertNil(AppTheme.system.appearanceName)
        XCTAssertEqual(AppTheme.light.appearanceName, .aqua)
        XCTAssertEqual(AppTheme.dark.appearanceName, .darkAqua)
    }
}

final class WorldClockTests: XCTestCase {
    func testSearchAndNames() {
        XCTAssertEqual(WorldClock.cityName("America/New_York"), "New York")
        XCTAssertEqual(WorldClock.search("new york", in: ["Europe/London", "America/New_York"]), ["America/New_York"])
        XCTAssertEqual(WorldClock.search("lon", in: ["Europe/London", "America/New_York"]).first, "Europe/London")
    }

    func testOffsetsAndDayShift() {
        XCTAssertEqual(WorldClock.offsetText(0), "same time")
        XCTAssertEqual(WorldClock.offsetText(5 * 3600), "+5 h")
        XCTAssertEqual(WorldClock.offsetText(-(3 * 3600 + 1800)), "\u{2212}3:30 h")
        let la = TimeZone(identifier: "America/Los_Angeles")!
        var c = Calendar(identifier: .gregorian); c.timeZone = la
        let evening = c.date(from: DateComponents(year: 2030, month: 6, day: 1, hour: 20))!
        XCTAssertEqual(WorldClock(timeZoneID: "Asia/Tokyo", label: "").dayShift(at: evening, from: la), "Tomorrow")
        XCTAssertNil(WorldClock(timeZoneID: "America/Denver", label: "").dayShift(at: evening, from: la))
    }

    func testRoundTripAndLimit() {
        let ids = ["Europe/London", "Asia/Tokyo", "America/New_York", "Australia/Sydney", "Europe/Paris"]
        let clocks = ids.map { WorldClock(timeZoneID: $0, label: "") }
        let back = WorldClock.decode(WorldClock.encode(clocks))
        XCTAssertEqual(back.count, WorldClock.limit)
        XCTAssertEqual(back.first?.displayLabel, "London")
        XCTAssertEqual(WorldClock.decode("nonsense"), [])
    }
}

final class EventChipColorsTests: XCTestCase {
    func testTextReadsOnEveryTint() {
        for hex in ["#4285F4", "#F6BF26", "#33B679", "#E67C73", "#FFFFFF", "#000000", "#616161", "#F4511E", "#9E69AF"] {
            for dark in [false, true] {
                let c = EventChipColors.rgb(hex)
                let ratio = SK1.contrast(EventChipColors.text(c, dark: dark), EventChipColors.background(c, dark: dark))
                XCTAssertGreaterThanOrEqual(ratio, EventChipColors.minimumContrast, "\(hex) dark=\(dark)")
            }
        }
    }

    func testHexParsing() {
        XCTAssertEqual(EventChipColors.rgb("#4285F4"), 0x4285F4)
        XCTAssertEqual(EventChipColors.rgb("fff"), 0xFFFFFF)
        XCTAssertEqual(EventChipColors.rgb("nope"), 0x4285F4)
    }
}

final class OnboardingAndStatusTests: XCTestCase {
    func cal(_ id: String, _ name: String) -> GCalendar {
        GCalendar(id: id, accountEmail: "me@x.com", summary: name, colorHex: "#000", accessRole: "reader", isPrimary: false, allowsMeet: false)
    }

    func testBirthdaysAndHolidaysHiddenByDefault() {
        XCTAssertTrue(OnboardingState.hiddenByDefault(cal("en.usa#holiday@group.v.calendar.google.com", "Holidays in United States")))
        XCTAssertTrue(OnboardingState.hiddenByDefault(cal("addressbook#contacts@group.v.calendar.google.com", "Birthdays")))
        XCTAssertFalse(OnboardingState.hiddenByDefault(cal("me@x.com", "Work")))
    }

    func testMigrationKeepsExistingUsersOutOfSetup() {
        let d = UserDefaults(suiteName: "onboarding-test-\(UUID().uuidString)")!
        OnboardingState.migrate(hasSource: true, defaults: d)
        XCTAssertTrue(d.bool(forKey: OnboardingState.Key.completed))
        d.set(false, forKey: OnboardingState.Key.completed)
        OnboardingState.migrate(hasSource: true, defaults: d)
        XCTAssertFalse(d.bool(forKey: OnboardingState.Key.completed), "Run Setup Again sticks")
    }

    func testSyncText() {
        let now = Date(timeIntervalSince1970: 1_900_000_000)
        XCTAssertEqual(SyncStatusText.ago(now.addingTimeInterval(-20), now: now), "just now")
        XCTAssertEqual(SyncStatusText.ago(now.addingTimeInterval(-300), now: now), "5 min ago")
        XCTAssertTrue(SyncStatusText.help(lastSynced: nil, refreshing: false, failed: true, now: now).hasPrefix("The last sync failed."))
        XCTAssertEqual(SyncErrorText.friendly("The Internet connection appears to be offline."),
                       "You're offline. Meetball will sync when the connection is back.")
    }

    func testForeignTimeZone() {
        let start = Date(timeIntervalSince1970: 1_900_000_000)
        var e = CalendarEvent(id: "1", calendarID: "c", accountEmail: "me@x.com", title: "Sync", start: start,
                              end: start.addingTimeInterval(1800), isAllDay: false, meetURL: nil, location: nil, attendees: [], htmlLink: nil)
        let la = TimeZone(identifier: "America/Los_Angeles")!
        XCTAssertNil(e.foreignTimeZone(local: la))
        e.timeZoneID = "Europe/London"
        XCTAssertEqual(e.foreignTimeZone(local: la)?.identifier, "Europe/London")
        e.timeZoneID = "America/Vancouver"
        XCTAssertNil(e.foreignTimeZone(local: la), "same offset counts as local")
    }
}
