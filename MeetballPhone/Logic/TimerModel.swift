import Foundation

/// One of Meetball's timers: a name, a length, the sound it rings with, and where it's up to. Idle timers stay in the
/// list as ready-made ones ("Tea · 4:00"), so starting one again is a single tap.
struct MeetballTimer: Codable, Identifiable, Equatable {
    var id = UUID()
    var label: String
    /// The length it's set to, in seconds.
    var duration: TimeInterval
    /// `TimerSound.id`: a path under the iPhone's own alert sounds, or `TimerSound.defaultID`.
    var soundID: String = TimerSound.defaultID
    /// While running: when it goes off.
    var endDate: Date?
    /// While paused: the time it had left.
    var pausedRemaining: TimeInterval?
    /// A quick-start timer: it goes away once it's stopped, rather than staying in the list.
    var oneOff = false

    enum State: Equatable {
        case idle, running, paused, done
    }

    func state(at now: Date) -> State {
        if let endDate { return endDate > now ? .running : .done }
        return pausedRemaining == nil ? .idle : .paused
    }

    /// Seconds left; 0 once it has gone off. An idle timer has its whole length left.
    func remaining(at now: Date) -> TimeInterval {
        if let endDate { return max(0, endDate.timeIntervalSince(now)) }
        return pausedRemaining ?? duration
    }

    /// Seconds since it went off (0 until then).
    func overtime(at now: Date) -> TimeInterval {
        guard let endDate else { return 0 }
        return max(0, now.timeIntervalSince(endDate))
    }

    /// How far through it is, 0…1, for the meter.
    func progress(at now: Date) -> Double {
        guard duration > 0 else { return 1 }
        return min(max(1 - remaining(at: now) / duration, 0), 1)
    }

    var displayName: String {
        let t = label.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? "Timer" : t
    }

    /// Starts from the top, or carries on from a pause.
    mutating func start(at now: Date) {
        endDate = now.addingTimeInterval(pausedRemaining ?? duration)
        pausedRemaining = nil
    }

    mutating func pause(at now: Date) {
        guard let endDate, endDate > now else { return }
        pausedRemaining = endDate.timeIntervalSince(now)
        self.endDate = nil
    }

    /// Back to its full length, stopped.
    mutating func reset() {
        endDate = nil
        pausedRemaining = nil
    }

    /// More time: on a running timer it pushes the end out (a finished one starts again from now), on a paused or
    /// idle one it adds to what's left.
    mutating func add(_ seconds: TimeInterval, at now: Date) {
        if let endDate {
            self.endDate = max(endDate, now).addingTimeInterval(seconds)
        } else if let pausedRemaining {
            self.pausedRemaining = pausedRemaining + seconds
        } else {
            duration += seconds
        }
    }
}

/// How timers read on the LCD.
enum TimerFormat {
    /// "4:05", "12:00", "1:02:09": seven-segment friendly (digits and colons). Rounds up, so a timer shows 0:00 only
    /// once it's gone off.
    static func clock(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds).rounded(.up))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    /// "4 min", "1 hr 30 min", "45 sec", for captions and VoiceOver.
    static func spoken(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds).rounded())
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        var parts: [String] = []
        if h > 0 { parts.append("\(h) hr") }
        if m > 0 { parts.append("\(m) min") }
        if s > 0 || parts.isEmpty { parts.append("\(s) sec") }
        return parts.joined(separator: " ")
    }
}

/// Typing a length on the keypad, microwave style: digits come in from the right of HH:MM:SS, so 1-3-0 reads 1:30 and
/// 2-5-0-0 reads 25:00. Minutes and seconds over 59 are carried ("90" is 1:30).
struct TimerKeypadEntry: Equatable {
    /// The digits typed, at most six.
    private(set) var digits: String = ""

    init(digits: String = "") {
        self.digits = String(digits.filter { $0.isASCII && $0.isNumber }.drop { $0 == "0" }.suffix(6))
    }

    /// The entry showing `seconds` (whole seconds, up to 99:59:59).
    init(seconds: TimeInterval) {
        let total = min(Int(seconds.rounded()), 99 * 3600 + 59 * 60 + 59)
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        self.init(digits: String(format: "%02d%02d%02d", h, m, s))
    }

    mutating func type(_ digit: Int) {
        guard (0...9).contains(digit), digits.count < 6, !(digits.isEmpty && digit == 0) else { return }
        digits.append(String(digit))
    }

    mutating func backspace() {
        if !digits.isEmpty { digits.removeLast() }
    }

    mutating func clear() { digits = "" }

    private var parts: (h: Int, m: Int, s: Int) {
        let padded = String(repeating: "0", count: 6 - digits.count) + digits
        let n = padded.compactMap { $0.wholeNumberValue }
        return (n[0] * 10 + n[1], n[2] * 10 + n[3], n[4] * 10 + n[5])
    }

    var seconds: TimeInterval {
        let p = parts
        return TimeInterval(p.h * 3600 + p.m * 60 + p.s)
    }

    /// "00:01:30": what the keypad's LCD shows, as typed.
    var display: String {
        let p = parts
        return String(format: "%02d:%02d:%02d", p.h, p.m, p.s)
    }
}

/// A sound a timer can ring with: one of the alert sounds that come with iOS (Tri-tone, Bamboo, Fanfare, Chord…),
/// played from the iPhone's own system sound folder, or the iPhone's default notification sound.
struct TimerSound: Identifiable, Hashable {
    /// The path under `folder`, e.g. "New/Fanfare.caf"; `defaultID` for the default notification sound.
    let id: String
    let title: String
    /// Which shelf it's on in the picker.
    let group: String

    static let defaultID = "default"
    static let `default` = TimerSound(id: defaultID, title: "Default", group: "iPhone")

    /// Where iOS keeps its built-in alert sounds. Apps may read (not change) them.
    static let folder = URL(fileURLWithPath: "/System/Library/Audio/UISounds", isDirectory: true)

    var fileURL: URL? { id == Self.defaultID ? nil : Self.folder.appendingPathComponent(id) }

    /// The older sounds' file names and what Settings › Sounds calls them.
    static let classicNames: [String: String] = [
        "sms-received1.caf": "Tri-tone",
        "sms-received2.caf": "Chime",
        "sms-received3.caf": "Glass",
        "sms-received4.caf": "Horn",
        "sms-received5.caf": "Bell",
        "sms-received6.caf": "Electronic",
        "alarm.caf": "Alarm",
        "new-mail.caf": "New Mail",
        "mail-sent.caf": "Swoosh",
        "Voicemail.caf": "Voicemail",
        "ReceivedMessage.caf": "Received",
        "SentMessage.caf": "Sent",
        "low_power.caf": "Low Power",
        "payment_success.caf": "Payment",
    ]

    /// The shelves of the folder worth ringing a timer with (the rest are key clicks, lock sounds and the like).
    static let shelves: [(folder: String, title: String)] = [("New", "Alert tones"), ("Modern", "Text tones"), ("", "Classic")]

    /// A readable name for a sound file: "Choo_Choo.caf" → "Choo Choo", "sms_alert_bamboo.caf" → "Bamboo".
    static func title(forFile path: String) -> String {
        let file = (path as NSString).lastPathComponent
        if let classic = classicNames[file] { return classic }
        var name = (file as NSString).deletingPathExtension
        for prefix in ["sms_alert_", "sms-received", "alert_"] where name.hasPrefix(prefix) {
            name.removeFirst(prefix.count)
        }
        name = name.replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: "-", with: " ")
        return name.split(separator: " ").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }

    /// The sounds to offer, from the file paths found in `folder` (relative, e.g. "New/Bloom.caf"): the default first,
    /// then each shelf's sounds by name. Only the shelves above, and in the top folder only the sounds that have a
    /// name in Settings › Sounds.
    static func catalog(from paths: [String]) -> [TimerSound] {
        var out = [TimerSound.default]
        for shelf in shelves {
            let picked = paths.filter { path in
                let dir = (path as NSString).deletingLastPathComponent
                guard dir == shelf.folder, path.lowercased().hasSuffix(".caf") else { return false }
                return !shelf.folder.isEmpty || classicNames[(path as NSString).lastPathComponent] != nil
            }
            out += picked.map { TimerSound(id: $0, title: title(forFile: $0), group: shelf.title) }
                .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        }
        return out
    }

    /// What's on this iPhone (the simulator and older systems have fewer). Read once.
    static let installed: [TimerSound] = {
        let fm = FileManager.default
        var paths: [String] = []
        for shelf in TimerSound.shelves {
            let dir = shelf.folder.isEmpty ? TimerSound.folder : TimerSound.folder.appendingPathComponent(shelf.folder)
            let files = (try? fm.contentsOfDirectory(atPath: dir.path)) ?? []
            paths += files.map { shelf.folder.isEmpty ? $0 : "\(shelf.folder)/\($0)" }
        }
        return TimerSound.catalog(from: paths)
    }()

    /// The sound for `id`, or the default when this iPhone doesn't have it.
    static func find(_ id: String) -> TimerSound {
        installed.first { $0.id == id } ?? .default
    }

    /// The file name a notification uses for this sound: notifications can only play sounds from the app's own
    /// Library/Sounds folder, so the system file is copied there under this name ("Meetball-New-Fanfare.caf").
    var notificationFileName: String? {
        guard id != Self.defaultID else { return nil }
        return "Meetball-" + id.replacingOccurrences(of: "/", with: "-")
    }
}

/// A length offered as a one-tap timer: a recent one, or a preset.
struct TimerPreset: Hashable, Codable {
    let label: String
    let seconds: TimeInterval

    /// "🍅 Pomodoro · 25 min", or just "5 min" when the label is the length.
    var title: String {
        let length = TimerFormat.spoken(seconds)
        return label.isEmpty || label == length ? length : "\(label) · \(length)"
    }
}

/// Lengths offered as one-tap timers (Quick start) and on the new-timer sheet, as on the MT-1 menu bar timer.
enum TimerPresets {
    /// The named presets ("Focus" on the MT-1).
    static let focus: [TimerPreset] = [
        .init(label: "🍅 Pomodoro", seconds: 25 * 60), .init(label: "🧠 Deep work", seconds: 50 * 60),
    ]
    /// Plain lengths.
    static let lengths: [TimerPreset] = ([60, 180, 300, 600, 900, 1800, 3600] as [TimeInterval]).map {
        TimerPreset(label: TimerFormat.spoken($0), seconds: $0)
    }
    static var all: [TimerPreset] { focus + lengths }

    /// How many recent timers are kept.
    static let recentLimit = 5

    /// `recent` with `started` put first, no duplicates, at most `recentLimit`.
    static func remember(_ started: TimerPreset, in recent: [TimerPreset]) -> [TimerPreset] {
        Array(([started] + recent.filter { $0 != started }).prefix(recentLimit))
    }
}

/// How close a running timer is to going off, for its lamp and progress strip (the MT-1's colours): teal, amber
/// in the last fifth, red in the last ten seconds and while it rings.
enum TimerUrgency: Equatable {
    case calm, near, alarm

    static func of(_ timer: MeetballTimer, at now: Date) -> TimerUrgency {
        switch timer.state(at: now) {
        case .done: return .alarm
        case .idle: return .calm
        case .running, .paused:
            let left = timer.remaining(at: now)
            if left <= 10 { return .alarm }
            return left <= timer.duration * 0.2 ? .near : .calm
        }
    }
}

/// The timers' own settings (the MT-1's Settings): snooze length, how long an ignored alarm rings, and the sound a
/// new timer starts with.
struct TimerSettings: Codable, Equatable {
    var snoozeMinutes = 5
    /// Seconds an alarm rings if nobody stops it.
    var ringFor: TimeInterval = 300
    var soundID = "New/Bloom.caf"

    static let ringForStops: [TimeInterval] = [60, 120, 300, 600, 900]
}
