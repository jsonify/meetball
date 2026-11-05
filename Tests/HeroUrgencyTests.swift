import XCTest
@testable import Meetball

final class HeroUrgencyTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func urgency(startsIn minutes: Double) -> HeroUrgency {
        let start = now.addingTimeInterval(minutes * 60)
        return HeroUrgency.of(start: start, end: start.addingTimeInterval(30 * 60), now: now)
    }

    func testLevelsByLeadTime() {
        XCTAssertEqual(urgency(startsIn: 45), .later)
        XCTAssertEqual(urgency(startsIn: 15.1), .later)
        XCTAssertEqual(urgency(startsIn: 15), .soon)
        XCTAssertEqual(urgency(startsIn: 10), .soon)
        XCTAssertEqual(urgency(startsIn: 2), .imminent)
        XCTAssertEqual(urgency(startsIn: 0.5), .imminent)
        XCTAssertEqual(urgency(startsIn: 0), .live)
        XCTAssertEqual(urgency(startsIn: -5), .live)
    }

    func testLampBlinksOnlyWhenImminentOrLive() {
        XCTAssertFalse(HeroUrgency.later.lampBlinks)
        XCTAssertFalse(HeroUrgency.soon.lampBlinks)
        XCTAssertTrue(HeroUrgency.imminent.lampBlinks)
        XCTAssertTrue(HeroUrgency.live.lampBlinks)
    }

    func testCardGetsLouderAsTheMeetingNears() {
        let levels: [HeroUrgency] = [.later, .soon, .imminent]
        XCTAssertEqual(levels.map(\.glow), levels.map(\.glow).sorted())
        XCTAssertEqual(levels.map(\.edgeOpacity), levels.map(\.edgeOpacity).sorted())
        XCTAssertEqual(HeroUrgency.later.glow, 0)
    }
}
