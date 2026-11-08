import XCTest
@testable import MeetballPhone

private let now = Date(timeIntervalSince1970: 1_800_000_000)

private func ev(_ title: String, location: String? = nil, inDays days: Double = 1, id: String? = nil,
                series: String? = nil, link: URL? = nil) -> CalendarEvent {
    let start = now.addingTimeInterval(days * 86400)
    var e = CalendarEvent(id: id ?? "\(title)|\(days)", calendarID: "family", accountEmail: "Apple · iCloud", title: title,
                          start: start, end: start.addingTimeInterval(3600), isAllDay: false, meetURL: link,
                          location: location, attendees: [], htmlLink: nil)
    e.seriesID = series
    return e
}

final class TravelPlannerTests: XCTestCase {
    func testAddressIsAPlace() {
        XCTAssertEqual(TravelPlanner.status(ev("Dinner", location: "Luigi's, 12 Main St"), now: now), .place("Luigi's, 12 Main St"))
        XCTAssertEqual(TravelPlanner.status(ev("Design review", location: "500 Pine St, Seattle"), now: now),
                       .place("500 Pine St, Seattle"))
    }

    func testLinksCallsAndRoomsAreNotPlaces() {
        for loc in ["https://zoom.us/j/123", "Microsoft Teams Meeting", "Conf Room 4B", "Room 210", "Rainier (10)",
                    "Boardroom", "Google Meet", "TBD"] {
            XCTAssertFalse(TravelPlanner.isPhysical(loc), loc)
        }
        for loc in ["Riverside Park", "1200 Elm St", "Lincoln High School, Field 3", "Building 4, 1 Infinite Loop", "Softball Field"] {
            XCTAssertTrue(TravelPlanner.isPhysical(loc), loc)
        }
    }

    func testAsksForTripsWithNoPlace() {
        for title in ["U12 Soccer vs Eagles", "Soccer game", "Jen's birthday party", "Dentist", "Piano recital",
                      "Hockey @ Hawks", "Tigers v Lions", "Swim meet"] {
            XCTAssertEqual(TravelPlanner.status(ev(title), now: now), .ask, title)
        }
    }

    func testLeavesMeetingsAlone() {
        for title in ["Standup", "Design review", "1:1 with Sam", "Sprint planning", "Game design sync", "Party planning call",
                      "Q4 v2 review"] {
            XCTAssertEqual(TravelPlanner.status(ev(title), now: now), .none, title)
        }
        // A video link, a room, a past or declined event: never asked.
        XCTAssertEqual(TravelPlanner.status(ev("Soccer game", link: URL(string: "https://meet.google.com/abc")), now: now), .none)
        XCTAssertEqual(TravelPlanner.status(ev("Team dinner", location: "Conf Room 2"), now: now), .none)
        XCTAssertEqual(TravelPlanner.status(ev("Soccer game", inDays: -1), now: now), .none)
        var declined = ev("Wedding")
        declined.isDeclined = true
        XCTAssertEqual(TravelPlanner.status(declined, now: now), .none)
    }

    func testNotATripIsRemembered() {
        let game = ev("U12 Soccer vs Eagles")
        let notTrips: Set<String> = [TravelPlanner.tripKey(game)]
        XCTAssertEqual(TravelPlanner.status(ev("U12 Soccer @ Hawks", inDays: 7), notTrips: notTrips, now: now), .none)
        XCTAssertEqual(TravelPlanner.status(ev("Piano recital"), notTrips: notTrips, now: now), .ask)
        // A series is remembered by its id, whatever its title.
        let practice = ev("Practice", series: "abc")
        XCTAssertEqual(TravelPlanner.tripKey(practice), "s:abc")
    }

    func testTitleStemDropsTheOpponent() {
        XCTAssertEqual(TravelPlanner.titleStem("U12 Soccer vs Eagles"), "u12 soccer")
        XCTAssertEqual(TravelPlanner.titleStem("U12 Soccer @ Hawks"), "u12 soccer")
        XCTAssertEqual(TravelPlanner.titleStem("U12 Soccer vs. Hawks"), "u12 soccer")
        XCTAssertEqual(TravelPlanner.titleStem("Soccer game at Riverside"), "soccer game")
        XCTAssertEqual(TravelPlanner.titleStem("Jen's birthday party!"), "jen's birthday party")
    }

    func testSuggestionsComeFromLikeMeetingsNearestFirst() {
        let game = ev("U12 Soccer vs Eagles", inDays: 1)
        let history = [
            ev("U12 Soccer @ Hawks", location: "Riverside Park", inDays: -6),
            ev("U12 Soccer vs Owls", location: "Hawks Field, 9 Oak Rd", inDays: -60),
            ev("U12 Soccer vs Bears", location: "riverside park", inDays: -13),
            ev("U12 Soccer vs Foxes", location: "https://zoom.us/j/1", inDays: -20),
            ev("Piano recital", location: "Town Hall", inDays: -3),
            game,
        ]
        XCTAssertEqual(TravelPlanner.suggestions(for: game, history: history), ["Riverside Park", "Hawks Field, 9 Oak Rd"])
    }

    func testSuggestionsFollowASeries() {
        let practice = ev("Practice", inDays: 1, series: "s1")
        let history = [ev("Practice (moved)", location: "Gym B, 4 Elm St", inDays: -7, series: "s1"),
                       ev("Practice", location: "Elsewhere Park", inDays: -3, id: "other", series: "s2")]
        XCTAssertEqual(TravelPlanner.suggestions(for: practice, history: history).first, "Gym B, 4 Elm St")
    }

    func testPlaceLocationText() {
        XCTAssertEqual(TripPlace(name: "Riverside Park", address: "100 River Rd, Springfield").locationText,
                       "Riverside Park, 100 River Rd, Springfield")
        XCTAssertEqual(TripPlace(name: "100 River Rd", address: "100 River Rd, Springfield").locationText, "100 River Rd, Springfield")
        XCTAssertEqual(TripPlace(name: "Luigi's").locationText, "Luigi's")
    }

    func testDirectionsLinks() {
        let place = "Luigi's & Co, 12 Main St #3"
        XCTAssertEqual(DirectionsApp.googleMaps.url(to: place)?.absoluteString,
                       "https://www.google.com/maps/dir/?api=1&destination=Luigi%27s%20%26%20Co%2C%2012%20Main%20St%20%233&travelmode=driving")
        XCTAssertEqual(DirectionsApp.appleMaps.url(to: "1 Elm St")?.absoluteString, "maps://?daddr=1%20Elm%20St&dirflg=d")
        XCTAssertEqual(DirectionsApp.waze.url(to: "1 Elm St")?.absoluteString, "https://waze.com/ul?q=1%20Elm%20St&navigate=yes")
        XCTAssertNil(DirectionsApp.googleMaps.url(to: "  "))
    }

    func testDirectionsDefaultsToGoogleMapsAndOldSettingsKeepIt() throws {
        XCTAssertEqual(PhoneSettings().directionsApp, .googleMaps)
        let old = try JSONDecoder().decode(PhoneSettings.self, from: Data(#"{"leadMinutes": 5}"#.utf8))
        XCTAssertEqual(old.directionsApp, .googleMaps)
        XCTAssertEqual(old.leadMinutes, 5)
        let unknown = try JSONDecoder().decode(PhoneSettings.self, from: Data(#"{"directionsApp": "mapquest"}"#.utf8))
        XCTAssertEqual(unknown.directionsApp, .googleMaps)
    }

    // MARK: Drive times

    func testLeaveByTakesOffTheDriveAndTimeToPark() {
        let game = ev("Soccer game", location: "Riverside Park", inDays: 1)
        let leave = TravelPlanner.leaveBy(game, travel: 24 * 60 + 20, bufferMinutes: 5)
        // 24m20s + 5m before the start, rounded down to the minute.
        XCTAssertEqual(game.start.timeIntervalSince(leave), 30 * 60)
    }

    func testTripsNeedingTimes() {
        let soon = ev("Soccer game", location: "Riverside Park", inDays: 0.1)
        let later = ev("Dinner", location: "Luigi's, 12 Main St", inDays: 0.5)
        let tooFar = ev("Wedding", location: "Town Hall", inDays: 2)
        let call = ev("Design review", location: "https://zoom.us/j/1", inDays: 0.2)
        let started = ev("Practice", location: "Gym B", inDays: -0.01)
        XCTAssertEqual(TravelPlanner.tripsNeedingTimes([later, tooFar, call, started, soon], now: now).map(\.title),
                       ["Soccer game", "Dinner"])
    }

    func testDriveTimeFreshness() {
        let soon = ev("Soccer game", location: "Riverside Park", inDays: 1.0 / 24)    // in an hour
        let later = ev("Dinner", location: "Luigi's", inDays: 0.5)
        let eta = { (place: String, minutesAgo: Double) in
            TripETA(destination: place, travelTime: 1200, computedAt: now.addingTimeInterval(-minutesAgo * 60))
        }
        XCTAssertTrue(TravelPlanner.isFresh(eta("Riverside Park", 5), for: soon, now: now))
        XCTAssertFalse(TravelPlanner.isFresh(eta("Riverside Park", 12), for: soon, now: now))
        XCTAssertTrue(TravelPlanner.isFresh(eta("Luigi's", 20), for: later, now: now))
        XCTAssertFalse(TravelPlanner.isFresh(eta("Somewhere else", 1), for: later, now: now))
        XCTAssertFalse(TravelPlanner.isFresh(nil, for: later, now: now))
    }

    func testDriveText() {
        XCTAssertEqual(TravelPlanner.driveText(23 * 60 + 5), "24 min drive")
        XCTAssertEqual(TravelPlanner.driveText(60 * 60), "1 hr drive")
        XCTAssertEqual(TravelPlanner.driveText(65 * 60), "1 hr 5 min drive")
        XCTAssertEqual(TravelPlanner.driveText(10), "1 min drive")
    }

    func testLeaveNowAlertIsPlanned() {
        let game = ev("Soccer game", location: "Riverside Park", inDays: 0.25)
        let eta = TripETA(destination: "Riverside Park", travelTime: 24 * 60, computedAt: now)
        let settings = PhoneSettings()
        let plan = ReminderPlanner.plan([game], settings: settings, etas: [game.uid: eta], now: now)
        let leave = plan.first { $0.kind == .leave }
        XCTAssertEqual(leave?.fireDate, game.start.addingTimeInterval(-29 * 60))
        XCTAssertEqual(leave?.title, "Leave now for Soccer game")
        XCTAssertEqual(leave?.body, "24 min drive to Riverside Park · starts \(game.start.shortTime)")
        XCTAssertTrue(plan.contains { $0.kind == .lead })
    }

    func testNoLeaveAlertWhenOffStaleOrPast() {
        let game = ev("Soccer game", location: "Riverside Park", inDays: 0.25)
        let eta = TripETA(destination: "Riverside Park", travelTime: 24 * 60, computedAt: now)
        var off = PhoneSettings()
        off.leaveAlerts = false
        XCTAssertNil(ReminderPlanner.leaveAlert(game, settings: off, eta: eta, now: now))
        var noTimes = PhoneSettings()
        noTimes.driveTimes = false
        XCTAssertNil(ReminderPlanner.leaveAlert(game, settings: noTimes, eta: eta, now: now))
        // The place changed since the drive time was worked out.
        var moved = game
        moved.location = "Hawks Field"
        XCTAssertNil(ReminderPlanner.leaveAlert(moved, settings: PhoneSettings(), eta: eta, now: now))
        // Already past the leave-by time.
        XCTAssertNil(ReminderPlanner.leaveAlert(game, settings: PhoneSettings(), eta: eta, now: game.start.addingTimeInterval(-10 * 60)))
    }

    func testDriveSettingsDefaults() throws {
        let old = try JSONDecoder().decode(PhoneSettings.self, from: Data(#"{"leadMinutes": 5}"#.utf8))
        XCTAssertTrue(old.driveTimes)
        XCTAssertTrue(old.leaveAlerts)
        XCTAssertEqual(old.leaveBufferMinutes, 5)
    }
}
