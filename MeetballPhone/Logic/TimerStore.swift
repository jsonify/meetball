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
    static let shared = TimerStore(publishesLiveActivity: true)

    @Published private(set) var timers: [MeetballTimer] = []
    /// Timers that went off while Meetball was open and are ringing now, oldest first.
    @Published private(set) var ringing: [UUID] = []
    /// The last few timers started from Quick start or the new-timer sheet, newest first (the MT-1's Recent).
    @Published private(set) var recent: [TimerPreset] = []
    @Published var settings = TimerSettings() {
        didSet {
            guard settings != oldValue else { return }
            saveSettings()
            if settings.soundID != oldValue.soundID { Self.prepareSounds([settings.soundID]) }
        }
    }

    private static let notificationPrefix = PhoneNotifications.timerPrefix
    private static let storageKey = "timers.v1"
    private static let recentKey = "timers.recent.v1"
    private static let settingsKey = "timers.settings.v1"
    /// With Meetball closed, an alarm rings again this often until it's stopped or auto-stop is reached, at most
    /// `maxRepeats` times (iOS keeps only 64 pending notifications in all, and meeting reminders need most of them).
    static let repeatEvery: TimeInterval = 30
    static let maxRepeats = 5

    private let defaults: UserDefaults
    private let ringer = TimerRinger()
    private var watch: Task<Void, Never>?
    private var autoStop: Task<Void, Never>?
    private var active = true

    /// Whether this store's running timers show on the Lock Screen (the shared one's do; a test's don't).
    private let publishesLiveActivity: Bool

    init(defaults: UserDefaults = .standard, publishesLiveActivity: Bool = false) {
        self.defaults = defaults
        self.publishesLiveActivity = publishesLiveActivity
        if let data = defaults.data(forKey: Self.storageKey),
           let saved = try? JSONDecoder().decode([MeetballTimer].self, from: data) {
            timers = saved
        } else {
            // A couple to start from, so the screen isn't empty the first time.
            timers = [MeetballTimer(label: "Tea", duration: 4 * 60, soundID: "New/Bloom.caf"),
                      MeetballTimer(label: "Focus", duration: 25 * 60, soundID: "New/Fanfare.caf")]
        }
        if let data = defaults.data(forKey: Self.recentKey),
           let saved = try? JSONDecoder().decode([TimerPreset].self, from: data) { recent = saved }
        if let data = defaults.data(forKey: Self.settingsKey),
           let saved = try? JSONDecoder().decode(TimerSettings.self, from: data) { settings = saved }
        rewatch()
        // Off the main thread, ahead of the first start: the list of the iPhone's sounds, and the copies of the sounds
        // in use that notifications ring with (see `notificationSound(for:)`).
        Self.prepareSounds(timers.map(\.soundID) + [settings.soundID])
        publishLiveActivity()
    }

    func timer(_ id: UUID) -> MeetballTimer? { timers.first { $0.id == id } }

    /// Starts a one-off timer for a recent or preset length, with the default sound; it goes away once stopped.
    func quickStart(_ preset: TimerPreset) {
        add(MeetballTimer(label: preset.label, duration: preset.seconds, soundID: settings.soundID, oneOff: true), start: true)
    }

    /// Puts `t` at the top of Recent.
    func remember(_ t: MeetballTimer) {
        recent = TimerPresets.remember(TimerPreset(label: t.label, seconds: t.duration), in: recent)
        if let data = try? JSONEncoder().encode(recent) { defaults.set(data, forKey: Self.recentKey) }
    }

    func clearRecent() {
        recent = []
        defaults.removeObject(forKey: Self.recentKey)
    }

    // MARK: Editing

    /// Adds `timer`; `start` sets it going straight away.
    func add(_ timer: MeetballTimer, start: Bool = false) {
        timers.append(timer)
        if start {
            remember(timer)
            self.start(timer.id)
        } else {
            save()
        }
    }

    /// Saves changes to an existing timer (name, length, sound). A running one keeps running, to its new sound.
    func update(_ timer: MeetballTimer) {
        guard let i = timers.firstIndex(where: { $0.id == timer.id }) else { return }
        if timers[i].soundID != timer.soundID { Self.prepareSounds([timer.soundID]) }
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

    /// Long-press reordering: puts the timer `id` where `target` is (the others shift up or down one).
    func move(_ id: UUID, onto target: UUID) {
        let reordered = Self.moved(timers, id: id, onto: target)
        guard reordered.map(\.id) != timers.map(\.id) else { return }
        timers = reordered
        save()
    }

    /// `list` with the timer `id` moved to `target`'s place: after it when moving down the list, before it when up.
    nonisolated static func moved(_ list: [MeetballTimer], id: UUID, onto target: UUID) -> [MeetballTimer] {
        guard id != target, let from = list.firstIndex(where: { $0.id == id }),
              let to = list.firstIndex(where: { $0.id == target }) else { return list }
        var out = list
        out.move(fromOffsets: [from], toOffset: to > from ? to + 1 : to)
        return out
    }

    /// Puts back a timer just deleted (Undo), where it was, running on if it was running.
    func restore(_ timer: MeetballTimer, at index: Int) {
        guard self.timer(timer.id) == nil else { return }
        timers.insert(timer, at: min(max(index, 0), timers.count))
        commit(timer)
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

    /// Snooze: quiet, and rings again after the snooze length (Settings).
    func snooze(_ id: UUID, now: Date = Date()) {
        stopRinging(id)
        mutate(id) { t in
            t.reset()
            t.endDate = now.addingTimeInterval(TimeInterval(settings.snoozeMinutes * 60))
        }
    }

    /// Again: the same timer from the top.
    func again(_ id: UUID, now: Date = Date()) {
        stopRinging(id)
        mutate(id) { t in
            t.reset()
            t.start(at: now)
        }
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
        // Timers that went off while Meetball was away leave the Lock Screen.
        publishLiveActivity()
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

    private func saveSettings() {
        if let data = try? JSONEncoder().encode(settings) { defaults.set(data, forKey: Self.settingsKey) }
    }

    /// Saves the timers, and brings the Lock Screen's countdown into line with them.
    private func save() {
        if let data = try? JSONEncoder().encode(timers) { defaults.set(data, forKey: Self.storageKey) }
        publishLiveActivity()
    }

    private func publishLiveActivity() {
        if publishesLiveActivity { LiveActivityController.timersChanged(timers) }
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
            // The one that went off leaves the Lock Screen (the next running one, if any, takes its place).
            self.publishLiveActivity()
            self.rewatch()
        }
    }

    private func ring(_ id: UUID) {
        guard active, !ringing.contains(id), let t = timer(id) else { return }
        ringing.append(id)
        // The notification for it isn't needed now it's ringing here.
        PhoneNotifications.center.removeDeliveredNotifications(withIdentifiers: Self.notificationIDs(id))
        unschedule(id)
        ringer.play(TimerSound.find(t.soundID))
        rearmAutoStop()
    }

    /// Stops the oldest ringing timer once it has rung for `settings.ringFor` (the MT-1's auto-stop).
    private func rearmAutoStop() {
        autoStop?.cancel()
        let due = ringing.compactMap { id in timer(id).flatMap { t in t.endDate.map { (id, $0.addingTimeInterval(settings.ringFor)) } } }
        guard let first = due.min(by: { $0.1 < $1.1 }) else { return }
        autoStop = Task { [weak self] in
            let wait = first.1.timeIntervalSinceNow
            if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
            guard !Task.isCancelled, let self else { return }
            self.stop(first.0)
        }
    }

    /// When an alarm rung by Meetball stops by itself.
    func autoStopDate(for t: MeetballTimer) -> Date? { t.endDate?.addingTimeInterval(settings.ringFor) }

    private func stopRinging(_ id: UUID) {
        ringing.removeAll { $0 == id }
        PhoneNotifications.center.removeDeliveredNotifications(withIdentifiers: Self.notificationIDs(id))
        if let last = ringing.last, let next = timer(last) {
            ringer.play(TimerSound.find(next.soundID))
        } else {
            ringer.stop()
        }
        rearmAutoStop()
    }

    /// The timer's notification and its repeats.
    static func notificationIDs(_ id: UUID) -> [String] {
        (0...maxRepeats).map { notificationPrefix + id.uuidString + ($0 == 0 ? "" : "|\($0)") }
    }

    /// When the notifications ring, `left` seconds from now: as it goes off, then every `repeatEvery` until auto-stop.
    static func ringOffsets(left: TimeInterval, ringFor: TimeInterval) -> [TimeInterval] {
        let repeats = min(maxRepeats, Int(ringFor / repeatEvery))
        return (0...repeats).map { left + TimeInterval($0) * repeatEvery }
    }

    // MARK: Notifications

    private func schedule(_ t: MeetballTimer) {
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
        // Added straight away (not after an await), so a pause or reset right after can't leave them behind.
        unschedule(t.id)
        let ids = Self.notificationIDs(t.id)
        for (n, offset) in Self.ringOffsets(left: left, ringFor: settings.ringFor).enumerated() {
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: offset, repeats: false)
            PhoneNotifications.center.add(UNNotificationRequest(identifier: ids[n], content: c, trigger: trigger),
                                          withCompletionHandler: nil)
        }
        Task { _ = await PhoneNotifications.requestAuthorization() }
    }

    private func unschedule(_ id: UUID) {
        PhoneNotifications.center.removePendingNotificationRequests(withIdentifiers: Self.notificationIDs(id))
    }

    /// Reads the iPhone's sound list and copies the sounds `ids` into Library/Sounds in the background, so starting a
    /// timer doesn't wait on the disk.
    nonisolated static func prepareSounds(_ ids: [String]) {
        let unique = Array(Set(ids))
        Task.detached(priority: .utility) {
            for id in unique { _ = notificationSound(for: TimerSound.find(id)) }
        }
    }

    /// Notifications only play sounds kept in the app's Library/Sounds folder, so the iPhone's own sound is copied
    /// there first. Falls back to the default sound when it can't be.
    nonisolated static func notificationSound(for sound: TimerSound) -> UNNotificationSound {
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
        if action == PhoneNotifications.timerSnoozeAction { snooze(id) } else { stop(id) }
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
///
/// The audio session and the player live on `TimerAudio`'s own queue: switching the session on or off talks to the
/// iPhone's media server and can hold the main thread for a noticeable moment, which made the Timers screen stall the
/// first time a timer was started, stopped or previewed.
@MainActor
final class TimerRinger {
    private let audio = TimerAudio()
    private var buzz: Task<Void, Never>?

    func play(_ sound: TimerSound) {
        let looping = sound.hasFile
        audio.play(sound.fileURL, loops: -1)
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
        if sound.hasFile {
            audio.play(sound.fileURL, loops: 0)
        } else {
            audio.stop()
            AudioServicesPlaySystemSound(Self.defaultAlert)
        }
    }

    func stop() {
        buzz?.cancel()
        buzz = nil
        audio.stop()
    }

    /// The system sound iOS plays for a default notification (Tri-tone).
    private static let defaultAlert = SystemSoundID(1007)
}

/// The audio session and player for `TimerRinger`, used only on `queue`. The session is switched on only while a sound
/// file plays and off again only if it was on, so stopping a timer that never rang costs nothing.
final class TimerAudio: @unchecked Sendable {
    private let queue = DispatchQueue(label: "app.meetball.timer-audio", qos: .userInitiated)
    private var player: AVAudioPlayer?
    private var sessionActive = false

    /// Plays the file at `url` (`loops` -1 for until stopped); nothing when there's no file.
    func play(_ url: URL?, loops: Int) {
        queue.async { [self] in
            stopPlayer()
            guard let url, let p = try? AVAudioPlayer(contentsOf: url) else { deactivate(); return }
            activate()
            p.numberOfLoops = loops
            p.prepareToPlay()
            p.play()
            player = p
        }
    }

    func stop() {
        queue.async { [self] in
            stopPlayer()
            deactivate()
        }
    }

    private func stopPlayer() {
        player?.stop()
        player = nil
    }

    private func activate() {
        guard !sessionActive else { return }
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, options: [.duckOthers])
        sessionActive = (try? session.setActive(true)) != nil
    }

    private func deactivate() {
        guard sessionActive else { return }
        sessionActive = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
