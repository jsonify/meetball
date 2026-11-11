import XCTest
@testable import Meetball

final class MonthDayPickerTests: XCTestCase {
    private func cal(firstWeekday: Int) -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        c.firstWeekday = firstWeekday
        return c
    }

    private func date(_ c: Calendar, _ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
        c.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    func testGridIsSixWeeksStartingOnFirstWeekday() {
        let c = cal(firstWeekday: 1)
        // November 2026 starts on a Sunday, so a Sunday-first grid opens on the 1st.
        let days = MonthGrid.days(for: date(c, 2026, 11, 18), calendar: c)
        XCTAssertEqual(days.count, 42)
        XCTAssertEqual(days.first, date(c, 2026, 11, 1))
        XCTAssertEqual(days.last, date(c, 2026, 12, 12))

        // Monday-first: the grid opens on Monday, Oct 26.
        let m = cal(firstWeekday: 2)
        let mdays = MonthGrid.days(for: date(m, 2026, 11, 18), calendar: m)
        XCTAssertEqual(mdays.first, date(m, 2026, 10, 26))
        XCTAssertEqual(m.component(.weekday, from: mdays.first!), 2)
    }

    func testGridDaysAreConsecutiveAcrossDaylightSavingEnd() {
        let c = cal(firstWeekday: 1)
        let days = MonthGrid.days(for: date(c, 2026, 11, 1), calendar: c)
        for (a, b) in zip(days, days.dropFirst()) {
            XCTAssertEqual(c.dateComponents([.day], from: a, to: b).day, 1)
            XCTAssertEqual(c.component(.hour, from: b), 0)
        }
    }

    func testWeekdaySymbolsFollowFirstWeekday() {
        XCTAssertEqual(MonthGrid.weekdaySymbols(calendar: cal(firstWeekday: 1)).count, 7)
        XCTAssertEqual(MonthGrid.weekdaySymbols(calendar: cal(firstWeekday: 2)).first,
                       cal(firstWeekday: 2).veryShortStandaloneWeekdaySymbols[1])
    }

    func testMovingKeepsTimeOfDay() {
        let c = cal(firstWeekday: 1)
        let moved = MonthGrid.moving(date(c, 2026, 11, 11, 8, 30), toDay: date(c, 2027, 1, 4, 17), calendar: c)
        XCTAssertEqual(moved, date(c, 2027, 1, 4, 8, 30))
    }

    func testRelativeLabel() {
        let c = cal(firstWeekday: 1)
        let now = date(c, 2026, 11, 11, 9)
        XCTAssertEqual(MonthDayPicker.relativeLabel(date(c, 2026, 11, 11, 18), now: now, calendar: c), "Today")
        XCTAssertEqual(MonthDayPicker.relativeLabel(date(c, 2026, 11, 12), now: now, calendar: c), "Tomorrow")
        XCTAssertEqual(MonthDayPicker.relativeLabel(date(c, 2026, 11, 10, 23), now: now, calendar: c), "Yesterday")
    }
}
