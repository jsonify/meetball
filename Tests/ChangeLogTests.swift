import XCTest
@testable import Meetball

final class ChangeLogTests: XCTestCase {
    func testEntriesAreNewestFirstWithValidUniqueDays() {
        let dates = ChangeLog.all.map { $0.date }
        XCTAssertFalse(dates.contains(nil), "Every day should read as yyyy-MM-dd")
        let days = dates.compactMap { $0 }
        XCTAssertEqual(days, days.sorted(by: >), "Newest first")
        XCTAssertEqual(Set(ChangeLog.all.map(\.day)).count, ChangeLog.all.count, "One entry per day")
        XCTAssertFalse(ChangeLog.all.contains { $0.changes.isEmpty })
    }

    func testFilteringKeepsSharedChangesAndDropsEmptyDays() {
        let log = [
            ChangeLog.Entry(day: "2026-11-10", changes: [
                .init(kind: .new, platform: .mac, text: "Mac"),
                .init(kind: .new, platform: .both, text: "Both"),
            ]),
            ChangeLog.Entry(day: "2026-11-09", changes: [.init(kind: .fixed, platform: .iPhone, text: "Phone")]),
        ]
        let mac = ChangeLog.entries(for: .mac, from: log)
        XCTAssertEqual(mac.map(\.day), ["2026-11-10"])
        XCTAssertEqual(mac[0].changes.map(\.text), ["Mac", "Both"])
        let phone = ChangeLog.entries(for: .iPhone, from: log)
        XCTAssertEqual(phone.map { $0.changes.map(\.text) }, [["Both"], ["Phone"]])
    }

    func testTitle() {
        let e = ChangeLog.Entry(day: "2026-11-10", changes: [])
        XCTAssertEqual(e.title(locale: Locale(identifier: "en_US")), "Nov 10, 2026")
    }
}
