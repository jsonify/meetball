import Foundation
import AVFoundation
import AudioToolbox
import UserNotifications

/// Meetball's timers: as many as you like, each with its own name, length and iPhone sound. Running timers are kept
/// as end times, so they carry on while Meetball is closed or the iPhone restarts.
///
/// When one goes off with Meetball open, its sound loops (with a buzz) over a full-screen card until it's stopped.
/// With Meetball in the background, a Time Sensitive notification rings with the same sound instead: those are
/// handed to iOS when a timer starts, so they fire on time even if Meetball isn't running.
@MainActor
final class TimerStore: ObservableObject {
    static let shared = TimerStore()

    @Published private(set) var timers: [MeetballTimer] = []
    /// Timers that went off while Meetball was open and are ringing now, oldest first.
    @Published private(set) var ringing: [UUID] = []

    private static let notificationPrefix = PhoneNotifications.timerPrefix
    private static let storageKey = "timers.v1"

    private let defaults: UserDefaults
    private let ringer = TimerRinger()
    private var watch: Task<Void, Never>?
    private var active = true

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.storageKey),
           let saved = try? JSONDecoder().decode([MeetballTimer].self, from: data) {
            timers = saved
        } else {
            // A couple to start from, so the screen isn't empty the first time.
            timers = [MeetballTimer(label: "Tea", duration: 4 * 60, soundID: "New/Bloom.caf"),
                      MeetballTimer(label: "Focus", duration: 25 * 60, soundID: "New/Fanfare.caf")]
        }
        rewatch()
    }

    func timer(_ id: UUID) -> MeetballTimer? { timers.first { $0.id == id } }

    // MARK: Editing

    /// Adds `timer`; `start` sets it going straight away.
    func add(_ timer: MeetballTimer, start: Bool = false) {
        timers.append(timer)
        if start { self.start(timer.id) } else { save() }
    }

    /// Saves changes to an existing timer (name, length, sound). A running one keeps running, to its new sound.
    func update(_ timer: MeetballTimer) {
        guard let i = timers.firstIndex(where: { $0.id == timer.id }) else { return }
        timers[i] = timer
        commit(timers[i])
    }

    func delete(_ id: UUID) {
        stopRinging(id)
        timers.removeAll { $0.id == id }
        unschedule(id)
        save()
        rewatch()
    }

    func move(from source: IndexSet, to destination: Int) {
        timers.move(fromOffsets: source, toOffset: destination)
        save()
    }

    // MARK: Running

    func start(_ id: UUID, now: Date = Date()) {
        mutate(id) { $0.start(at: now) }
    }

    func pause(_ id: UUID, now: Date = Date()) {
        mutate(id) { $0.pause(at: now) }
    }

    func reset(_ id: UUID) {
        stopRinging(id)
        mutate(id) { $0.reset() }
    }

    /// Adds time (a ringing timer stops ringing and runs again for that long).
    func add(_ seconds: TimeInterval, to id: UUID, now: Date = Date()) {
        stopRinging(id)
        mutate(id) { $0.add(seconds, at: now) }
    }

    /// Stop on the ringing card (or the notification): quiet, and back to its full length, ready to go again. A
    /// quick-start timer goes away instead.
    func stop(_ id: UUID) {
        if timer(id)?.oneOff == true { delete(id) } else { reset(id) }
    }

    /// Start or pause, whichever it needs; a finished timer starts again from the top.
    func toggle(_ id: UUID, now: Date = Date()) {
        guard let t = timer(id) else { return }
        switch t.state(at: now) {
        case .running: pause(id, now: now)
        case .paused, .idle: start(id, now: now)
        case .done:
            reset(id)
            start(id, now: now)
        }
    }

    // MARK: App life

    /// Meetball came to the front. Timers that went off while it was away already rang as a notification, so they
    /// just show as done (with how long ago); the ones still running ring here when they go off.
    func becameActive() {
        active = true
        // One still ringing from before Meetball went away picks its sound back up.
        if let last = ringing.last, let t = timer(last) { ringer.play(TimerSound.find(t.soundID)) }
        rewatch()
    }

    /// Meetball went to the background: the sound stops (iOS would cut it off anyway) and notifications take over.
    func becameInactive() {
        active = false
        ringer.stop()
    }

    // MARK: Internals

    private func mutate(_ id: UUID, _ change: (inout MeetballTimer) -> Void) {
        guard let i = timers.firstIndex(where: { $0.id == id }) else { return }
        change(&timers[i])
        commit(timers[i])
    }

    /// Saves, and brings the timer's notification and the watch for the next one to go off into line.
    private func commit(_ t: MeetballTimer) {
        save()
        if t.state(at: Date()) == .running { schedule(t) } else { unschedule(t.id) }
        if ringing.contains(t.id) { ringer.play(TimerSound.find(t.soundID)) }
        rewatch()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(timers) { defaults.set(data, forKey: Self.storageKey) }
    }

    /// Sleeps until the next running timer goes off, then rings it (and goes back to sleep for the one after).
    private func rewatch() {
        watch?.cancel()
        let ends = timers.compactMap { t in t.endDate.flatMap { $0 > Date() ? $0 : nil } }
        guard let next = ends.min() else { return }
        watch = Task { [weak self] in
            let wait = next.timeIntervalSinceNow
            if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
            guard !Task.isCancelled, let self else { return }
            let now = Date()
            for t in self.timers where t.state(at: now) == .done && t.overtime(at: now) < 5 { self.ring(t.id) }
            self.rewatch()
        }
    }

    private func ring(_ id: UUID) {
        guard active, !ringing.contains(id), let t = timer(id) else { return }
        ringing.append(id)
        // The notification for it isn't needed now it's ringing here.
        PhoneNotifications.center.removeDeliveredNotifications(withIdentifiers: [Self.notificationPrefix + id.uuidString])
        ringer.play(TimerSound.find(t.soundID))
    }

    private func stopRinging(_ id: UUID) {
        ringing.removeAll { $0 == id }
        PhoneNotifications.center.removeDeliveredNotifications(withIdentifiers: [Self.notificationPrefix + id.uuidString])
        if let last = ringing.last, let next = timer(last) {
            ringer.play(TimerSound.find(next.soundID))
        } else {
            ringer.stop()
        }
    }

    // MARK: Notifications

    private func schedule(_ t: MeetballTimer) {
        let id = Self.notificationPrefix + t.id.uuidString
        let left = t.remaining(at: Date())
        guard left > 0 else { return }
        let c = UNMutableNotificationContent()
        c.title = "\(t.displayName) is done"
        c.body = "\(TimerFormat.spoken(t.duration)) timer"
        c.sound = Self.notificationSound(for: TimerSound.find(t.soundID))
        c.interruptionLevel = .timeSensitive
        c.relevanceScore = 1
        c.categoryIdentifier = PhoneNotifications.timerCategory
        c.threadIdentifier = "meetball.timers"
        c.userInfo = [PhoneNotifications.timerIDKey: t.id.uuidString]
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: left, repeats: false)
        // Added straight away (not after an await), so a pause or reset right after can't leave it behind.
        PhoneNotifications.center.add(UNNotificationRequest(identifier: id, content: c, trigger: trigger), withCompletionHandler: nil)
        Task { _ = await PhoneNotifications.requestAuthorization() }
    }

    private func unschedule(_ id: UUID) {
        PhoneNotifications.center.removePendingNotificationRequests(withIdentifiers: [Self.notificationPrefix + id.uuidString])
    }

    /// Notifications only play sounds kept in the app's Library/Sounds folder, so the iPhone's own sound is copied
    /// there first. Falls back to the default sound when it can't be.
    static func notificationSound(for sound: TimerSound) -> UNNotificationSound {
        guard let source = sound.fileURL, let name = sound.notificationFileName,
              let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first else { return .default }
        let folder = library.appendingPathComponent("Sounds", isDirectory: true)
        let target = folder.appendingPathComponent(name)
        let fm = FileManager.default
        if !fm.fileExists(atPath: target.path) {
            do {
                try fm.createDirectory(at: folder, withIntermediateDirectories: true)
                try fm.copyItem(at: source, to: target)
            } catch {
                return .default
            }
        }
        return UNNotificationSound(named: UNNotificationSoundName(name))
    }

    /// A tap on a timer's notification, or one of its actions.
    func handle(action: String, timerID: String) {
        guard let id = UUID(uuidString: timerID), timer(id) != nil else { return }
        if action == PhoneNotifications.timerSnoozeAction { add(60, to: id) } else { stop(id) }
    }

    /// Plays `sound` once, for the picker.
    func preview(_ sound: TimerSound) {
        ringer.preview(sound)
    }

    func stopPreview() {
        if ringing.isEmpty { ringer.stop() }
    }
}

/// Plays a timer's sound: on a loop with a buzz while it rings, once for a preview. Uses the playback audio session, so
/// it's heard with the ring switch on silent, as a timer should be.
@MainActor
final class TimerRinger {
    private var player: AVAudioPlayer?
    private var buzz: Task<Void, Never>?

    func play(_ sound: TimerSound) {
        let looping = start(sound, loops: -1)
        buzz?.cancel()
        buzz = Task {
            while !Task.isCancelled {
                // The default sound has no file to loop: the system alert (with its buzz) goes again each time round.
                if looping { AudioServicesPlaySystemSound(kSystemSoundID_Vibrate) } else { AudioServicesPlayAlertSound(Self.defaultAlert) }
                try? await Task.sleep(for: .seconds(looping ? 1.6 : 2.5))
            }
        }
    }

    func preview(_ sound: TimerSound) {
        buzz?.cancel()
        if !start(sound, loops: 0) { AudioServicesPlaySystemSound(Self.defaultAlert) }
    }

    func stop() {
        buzz?.cancel()
        buzz = nil
        player?.stop()
        player = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// The system sound iOS plays for a default notification (Tri-tone).
    private static let defaultAlert = SystemSoundID(1007)

    /// Starts the sound's file playing; false when there's no file to play (the default sound, or one this iPhone
    /// lacks).
    @discardableResult
    private func start(_ sound: TimerSound, loops: Int) -> Bool {
        player?.stop()
        player = nil
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, options: [.duckOthers])
        try? session.setActive(true)
        guard let url = sound.fileURL, let p = try? AVAudioPlayer(contentsOf: url) else { return false }
        p.numberOfLoops = loops
        p.prepareToPlay()
        p.play()
        player = p
        return true
    }
}
