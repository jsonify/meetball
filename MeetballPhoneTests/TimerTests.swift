import XCTest
@testable import MeetballPhone

final class TimerTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    func testRunPauseResumeAndFinish() {
        var t = MeetballTimer(label: "Tea", duration: 240)
        XCTAssertEqual(t.state(at: t0), .idle)
        XCTAssertEqual(t.remaining(at: t0), 240)

        t.start(at: t0)
        XCTAssertEqual(t.state(at: t0.addingTimeInterval(60)), .running)
        XCTAssertEqual(t.remaining(at: t0.addingTimeInterval(60)), 180)

        t.pause(at: t0.addingTimeInterval(100))
        XCTAssertEqual(t.state(at: t0.addingTimeInterval(500)), .paused)
        XCTAssertEqual(t.remaining(at: t0.addingTimeInterval(500)), 140)

        t.start(at: t0.addingTimeInterval(1000))
        XCTAssertEqual(t.remaining(at: t0.addingTimeInterval(1040)), 100)
        XCTAssertEqual(t.state(at: t0.addingTimeInterval(1140)), .done)
        XCTAssertEqual(t.remaining(at: t0.addingTimeInterval(1200)), 0)
        XCTAssertEqual(t.overtime(at: t0.addingTimeInterval(1200)), 60)

        t.reset()
        XCTAssertEqual(t.state(at: t0), .idle)
        XCTAssertEqual(t.remaining(at: t0), 240)
    }

    func testAddingTime() {
        var running = MeetballTimer(label: "", duration: 60)
        running.start(at: t0)
        running.add(60, at: t0.addingTimeInterval(30))
        XCTAssertEqual(running.remaining(at: t0.addingTimeInterval(30)), 90)

        // A finished timer runs again from now.
        running.add(60, at: t0.addingTimeInterval(500))
        XCTAssertEqual(running.state(at: t0.addingTimeInterval(500)), .running)
        XCTAssertEqual(running.remaining(at: t0.addingTimeInterval(500)), 60)

        var paused = MeetballTimer(label: "", duration: 60)
        paused.start(at: t0)
        paused.pause(at: t0.addingTimeInterval(20))
        paused.add(60, at: t0.addingTimeInterval(99))
        XCTAssertEqual(paused.remaining(at: t0.addingTimeInterval(999)), 100)

        var idle = MeetballTimer(label: "", duration: 60)
        idle.add(60, at: t0)
        XCTAssertEqual(idle.duration, 120)
    }

    func testPausingAFinishedTimerDoesNothing() {
        var t = MeetballTimer(label: "", duration: 10)
        t.start(at: t0)
        t.pause(at: t0.addingTimeInterval(20))
        XCTAssertEqual(t.state(at: t0.addingTimeInterval(20)), .done)
    }

    func testProgressAndName() {
        var t = MeetballTimer(label: "  ", duration: 100)
        XCTAssertEqual(t.displayName, "Timer")
        t.start(at: t0)
        XCTAssertEqual(t.progress(at: t0.addingTimeInterval(25)), 0.25, accuracy: 0.0001)
        XCTAssertEqual(t.progress(at: t0.addingTimeInterval(500)), 1)
    }

    func testClockFormat() {
        XCTAssertEqual(TimerFormat.clock(0), "0:00")
        XCTAssertEqual(TimerFormat.clock(0.2), "0:01")
        XCTAssertEqual(TimerFormat.clock(245), "4:05")
        XCTAssertEqual(TimerFormat.clock(720), "12:00")
        XCTAssertEqual(TimerFormat.clock(3729), "1:02:09")
        XCTAssertEqual(TimerFormat.spoken(5400), "1 hr 30 min")
        XCTAssertEqual(TimerFormat.spoken(45), "45 sec")
        XCTAssertEqual(TimerFormat.spoken(0), "0 sec")
    }

    func testKeypadTypesFromTheRight() {
        var e = TimerKeypadEntry()
        e.type(0)   // a leading zero is ignored
        for d in [1, 3, 0] { e.type(d) }
        XCTAssertEqual(e.display, "00:01:30")
        XCTAssertEqual(e.seconds, 90)
        for d in [0, 0, 0, 0] { e.type(d) }   // at most six digits
        XCTAssertEqual(e.display, "13:00:00")
        e.backspace()
        XCTAssertEqual(e.display, "01:30:00")
        e.clear()
        XCTAssertEqual(e.seconds, 0)
    }

    func testKeypadCarriesOverflowAndRoundTrips() {
        XCTAssertEqual(TimerKeypadEntry(digits: "90").seconds, 90)
        XCTAssertEqual(TimerKeypadEntry(digits: "9999").seconds, 99 * 60 + 99)
        XCTAssertEqual(TimerKeypadEntry(seconds: 1500).display, "00:25:00")
        XCTAssertEqual(TimerKeypadEntry(seconds: 3725).display, "01:02:05")
        XCTAssertEqual(TimerKeypadEntry(seconds: 1500).digits, "2500")
    }

    func testSoundCatalog() {
        let paths = ["New/Fanfare.caf", "New/Choo_Choo.caf", "Modern/sms_alert_bamboo.caf", "sms-received1.caf",
                     "key_press_click.caf", "nano/Alarm.caf", "New/readme.txt"]
        let sounds = TimerSound.catalog(from: paths)
        XCTAssertEqual(sounds.map(\.title), ["Default", "Choo Choo", "Fanfare", "Bamboo", "Tri-tone"])
        XCTAssertEqual(sounds.map(\.group), ["iPhone", "Alert tones", "Alert tones", "Text tones", "Classic"])
        XCTAssertEqual(sounds[2].fileURL?.path, "/System/Library/Audio/UISounds/New/Fanfare.caf")
        XCTAssertEqual(sounds[2].notificationFileName, "Meetball-New-Fanfare.caf")
        XCTAssertNil(TimerSound.default.fileURL)
        XCTAssertNil(TimerSound.default.notificationFileName)
    }

    func testTimersSurviveSaving() throws {
        var t = MeetballTimer(label: "Laundry", duration: 2700, soundID: "New/Bloom.caf")
        t.start(at: t0)
        let back = try JSONDecoder().decode(MeetballTimer.self, from: JSONEncoder().encode(t))
        XCTAssertEqual(back, t)
        XCTAssertEqual(back.remaining(at: t0.addingTimeInterval(700)), 2000)
    }

    func testRecentKeepsFiveNewestWithoutRepeats() {
        let tea = TimerPreset(label: "Tea", seconds: 240)
        var recent: [TimerPreset] = []
        for m in 1...6 { recent = TimerPresets.remember(TimerPreset(label: "", seconds: TimeInterval(m * 60)), in: recent) }
        XCTAssertEqual(recent.map(\.seconds), [360, 300, 240, 180, 120])
        recent = TimerPresets.remember(tea, in: recent)
        recent = TimerPresets.remember(TimerPreset(label: "", seconds: 300), in: recent)
        XCTAssertEqual(recent.first?.seconds, 300)
        XCTAssertEqual(recent.count, 5)
        XCTAssertEqual(recent.filter { $0.seconds == 300 }.count, 1)
        XCTAssertEqual(tea.title, "Tea · 4 min")
        XCTAssertEqual(TimerPreset(label: "5 min", seconds: 300).title, "5 min")
        XCTAssertEqual(TimerPresets.focus.first?.title, "🍅 Pomodoro · 25 min")
    }

    func testUrgencyFollowsTheMT1Colours() {
        var t = MeetballTimer(label: "", duration: 100)
        XCTAssertEqual(TimerUrgency.of(t, at: t0), .calm)
        t.start(at: t0)
        XCTAssertEqual(TimerUrgency.of(t, at: t0.addingTimeInterval(50)), .calm)
        XCTAssertEqual(TimerUrgency.of(t, at: t0.addingTimeInterval(81)), .near)
        XCTAssertEqual(TimerUrgency.of(t, at: t0.addingTimeInterval(91)), .alarm)
        XCTAssertEqual(TimerUrgency.of(t, at: t0.addingTimeInterval(200)), .alarm)
    }

    @MainActor
    func testBackgroundAlarmRepeatsUntilAutoStop() {
        XCTAssertEqual(TimerStore.ringOffsets(left: 60, ringFor: 90), [60, 90, 120, 150])
        // Capped, to leave room for meeting reminders in iOS's 64 pending notifications.
        XCTAssertEqual(TimerStore.ringOffsets(left: 10, ringFor: 900).count, TimerStore.maxRepeats + 1)
        let ids = TimerStore.notificationIDs(UUID())
        XCTAssertEqual(ids.count, TimerStore.maxRepeats + 1)
        XCTAssertEqual(Set(ids).count, ids.count)
        XCTAssertTrue(ids.allSatisfy { $0.hasPrefix(PhoneNotifications.timerPrefix) })
    }

    func testTimersScreenIsALid() {
        XCTAssertEqual(ScreenMove.between(.day, .timers), .lid)
        XCTAssertEqual(ScreenMove.between(.timers, .settings), .flip(forward: true))
    }
}
