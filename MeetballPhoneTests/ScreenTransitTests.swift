import XCTest
@testable import MeetballPhone

final class ScreenTransitTests: XCTestCase {
    func testCalendarScreensZoom() {
        XCTAssertEqual(ScreenMove.between(.month, .day), .zoomIn(dive: false))
        XCTAssertEqual(ScreenMove.between(.week, .day), .zoomIn(dive: false))
        XCTAssertEqual(ScreenMove.between(.day, .week), .zoomOut)
        XCTAssertEqual(ScreenMove.between(.week, .month), .zoomOut)
        XCTAssertNil(ScreenMove.between(.day, .day))
    }

    func testTodayIsALidAndSettingsAFlip() {
        XCTAssertEqual(ScreenMove.between(.day, .today), .lid)
        XCTAssertEqual(ScreenMove.between(.today, .month), .lid)
        XCTAssertEqual(ScreenMove.between(.week, .settings), .flip(forward: true))
        XCTAssertEqual(ScreenMove.between(.settings, .week), .flip(forward: false))
        XCTAssertEqual(ScreenMove.between(.today, .settings), .flip(forward: true))
        XCTAssertEqual(ScreenMove.between(.settings, .today), .flip(forward: false))
    }

    func testEveryMoveSettlesAndClears() {
        let moves: [ScreenMove?] = [nil, .zoomIn(dive: false), .zoomIn(dive: true), .zoomOut, .lid, .flip(forward: true),
                                    .flip(forward: false)]
        for move in moves {
            for lid in [false, true] {
                XCTAssertEqual(ScreenPose.at(0, move: move, lid: lid), ScreenPose(), "\(String(describing: move)) settled")
                for end in [-1.0, 1.0] {
                    let pose = ScreenPose.at(end, move: move, lid: lid)
                    XCTAssertTrue(pose.opacity == 0 || pose.lift == 1, "\(String(describing: move)) at \(end) is out of sight")
                }
            }
        }
    }

    func testZoomInGrowsOutOfTheCloserScreen() {
        XCTAssertGreaterThan(ScreenPose.at(0.5, move: .zoomIn(dive: false)).scale, 1)
        XCTAssertLessThan(ScreenPose.at(-0.5, move: .zoomIn(dive: false)).scale, 1)
        XCTAssertLessThan(ScreenPose.at(0.5, move: .zoomOut).scale, 1)
        XCTAssertGreaterThan(ScreenPose.at(-0.5, move: .zoomOut).scale, 1)
        XCTAssertLessThan(ScreenPose.at(-1, move: .zoomIn(dive: true)).scale, ScreenPose.at(-1, move: .zoomIn(dive: false)).scale)
    }

    func testFlipHandsOverEdgeOn() {
        let out = ScreenPose.at(0.25, move: .flip(forward: true)), back = ScreenPose.at(-0.25, move: .flip(forward: true))
        XCTAssertEqual(out.turn, -back.turn, accuracy: 0.001)
        XCTAssertEqual(out.opacity, 1)
        XCTAssertEqual(ScreenPose.at(0.5, move: .flip(forward: true)).opacity, 0)
        XCTAssertEqual(ScreenPose.at(-0.75, move: .flip(forward: true)).opacity, 0)
        XCTAssertEqual(ScreenPose.at(0.25, move: .flip(forward: false)).turn, -out.turn, accuracy: 0.001)
    }

    func testOnlyTheLidLifts() {
        XCTAssertEqual(ScreenPose.at(-0.5, move: .lid, lid: true).lift, 0.5)
        XCTAssertEqual(ScreenPose.at(-0.5, move: .lid, lid: true).opacity, 1)
        XCTAssertEqual(ScreenPose.at(0.5, move: .lid).lift, 0)
        XCTAssertLessThan(ScreenPose.at(0.5, move: .lid).opacity, 1)
    }

    func testAnchorOfATappedCell() {
        let stage = CGRect(x: 0, y: 50, width: 400, height: 800)
        let p = ScreenMove.anchor(of: CGRect(x: 80, y: 430, width: 40, height: 40), in: stage)
        XCTAssertEqual(p.x, 0.25, accuracy: 0.001)
        XCTAssertEqual(p.y, 0.5, accuracy: 0.001)
        XCTAssertEqual(ScreenMove.anchor(of: CGRect(x: 500, y: 0, width: 10, height: 10), in: stage), CGPoint(x: 1, y: 0))
        XCTAssertEqual(ScreenMove.anchor(of: .zero, in: .zero), CGPoint(x: 0.5, y: 0.5))
    }
}
