import SwiftUI
import SK1Tokens
import SK1UI

/// Timers, after the MT-1 menu bar timer (jsonify/menubar-timer) whose panel the SK-1 look began with: each timer is
/// an MT-1 of its own (Run / Pause / Ring lamps, an LCD with its label, end time, digits and progress strip, and the
/// captioned Reset · Start · +1 Min · Edit keys), as many as you like. Under them, Recent and the presets start
/// one-off timers, and Settings holds the snooze length, auto-stop and the sound new timers get.
struct TimersView: View {
    @EnvironmentObject private var timers: TimerStore
    @State private var editing: TimerEditRequest?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { tl in
            content(now: tl.date)
        }
        .sheet(item: $editing) { request in
            TimerEditSheet(original: request.timer).environmentObject(timers)
        }
    }

    private func content(now: Date) -> some View {
        let running = timers.timers.filter { $0.state(at: now) == .running }
        return PhoneScrollScreen {
            PhoneScreenHeader(title: "Timers", detail: running.isEmpty ? "None running" : "\(running.count) running") {
                Button { editing = TimerEditRequest(timer: nil) } label: { Image(systemName: "plus") }
                    .buttonStyle(.sk1Key())
                    .accessibilityLabel("New timer")
            }
        } content: {
            VStack(alignment: .leading, spacing: SK1.Metrics.groupSpacing) {
                display(now: now, running: running)
                if timers.timers.isEmpty {
                    Text("No timers yet. Press + to make one, or start one from Recent or the presets below.").sk1Hint()
                }
                ForEach(timers.timers) { t in
                    TimerCard(timer: t, now: now) { editing = TimerEditRequest(timer: t) }
                }
                quickStart
                TimerSettingsGroup()
                Text("Timers ring with the iPhone's own sounds. With Meetball open they ring until you stop them (or auto-stop), "
                     + "even on silent. With it closed, a notification rings with the sound every 30 seconds for a few minutes, "
                     + "following the ring switch.")
                    .sk1Hint()
            }
        }
    }

    /// The next timer to go off, and how many are running.
    private func display(now: Date, running: [MeetballTimer]) -> some View {
        let next = running.min { $0.remaining(at: now) < $1.remaining(at: now) }
        let done = timers.timers.first { $0.state(at: now) == .done }
        let message: String
        if let next {
            message = "\(next.displayName.uppercased()) IN \(TimerFormat.clock(next.remaining(at: now)))"
        } else if let done {
            message = "\(done.displayName.uppercased()) DONE"
        } else {
            message = "READY"
        }
        return SKDisplay(title: "MT-1", detail: now.shortTime, message: message, number: running.count, digits: 2,
                         unit: "ON", live: !running.isEmpty, height: 60)
    }

    /// Recent timers and the presets: one tap starts a one-off timer.
    private var quickStart: some View {
        VStack(alignment: .leading, spacing: SK1.Metrics.groupSpacing) {
            VStack(alignment: .leading, spacing: SK1.Metrics.captionToWell) {
                HStack {
                    SKCaption("Recent", tone: .soft)
                    Spacer()
                    if !timers.recent.isEmpty {
                        Button("Clear") { timers.clearRecent() }
                            .buttonStyle(.sk1Key(size: .mini))
                            .accessibilityLabel("Clear recent timers")
                    }
                }
                SKWell {
                    if timers.recent.isEmpty {
                        Text("Timers you start show up here").sk1Hint()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                    } else {
                        TimerChips(presets: timers.recent) { timers.quickStart($0) }.padding(10)
                    }
                }
            }
            VStack(alignment: .leading, spacing: SK1.Metrics.captionToWell) {
                SKCaption("Presets", tone: .soft)
                SKWell {
                    VStack(alignment: .leading, spacing: 8) {
                        TimerChips(presets: TimerPresets.focus, columns: 2) { timers.quickStart($0) }
                        SKGroove()
                        TimerChips(presets: TimerPresets.lengths) { timers.quickStart($0) }
                    }
                    .padding(10)
                }
            }
        }
    }
}

/// One-tap timer keys, in a grid.
struct TimerChips: View {
    let presets: [TimerPreset]
    var columns = 3
    var highlighted: TimeInterval? = nil
    let pick: (TimerPreset) -> Void

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: columns), spacing: 6) {
            ForEach(presets, id: \.self) { p in
                Button { pick(p) } label: {
                    Text(p.title).lineLimit(1).minimumScaleFactor(0.7).frame(maxWidth: .infinity)
                }
                .buttonStyle(.sk1Key(isOn: highlighted == p.seconds, size: .small))
                .accessibilityLabel("\(p.title) timer")
            }
        }
    }
}

/// The edit sheet, for a new timer (nil) or an existing one.
struct TimerEditRequest: Identifiable {
    let id = UUID()
    let timer: MeetballTimer?
}

/// One timer as an MT-1: lamps, the LCD, and the captioned keys.
struct TimerCard: View {
    @EnvironmentObject private var timers: TimerStore
    let timer: MeetballTimer
    let now: Date
    let edit: () -> Void

    var body: some View {
        let state = timer.state(at: now)
        SKWell {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Text(timer.displayName).font(.headline).lineLimit(1)
                    Spacer(minLength: 8)
                    legend("Run", .success, state == .running)
                    legend("Pause", .warning, state == .paused)
                    legend("Ring", .danger, state == .done)
                }
                Button(action: edit) { TimerLCD(timer: timer, now: now) }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(TimerLCD.spoken(timer, now: now)))
                    .accessibilityHint("Edits the timer")
                keys(state)
            }
            .padding(12)
        }
        .contextMenu {
            Button("Edit", systemImage: "slider.horizontal.3", action: edit)
            Button("Delete", systemImage: "trash", role: .destructive) { timers.delete(timer.id) }
        }
    }

    private func legend(_ name: String, _ color: SKLampColor, _ lit: Bool) -> some View {
        HStack(spacing: 4) {
            SKLamp(color: color, lit: lit, glow: lit ? 4 : 0, size: 5, blinking: lit && name == "Ring")
            Text(name.uppercased()).font(.system(size: 9, weight: .heavy)).tracking(1).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(name))
        .accessibilityHidden(!lit)
    }

    /// Reset · Start / Pause / Resume · +1 Min · Edit, as on the MT-1 (Again and Snooze while it rings).
    private func keys(_ state: MeetballTimer.State) -> some View {
        let play: (title: String, symbol: String)
        switch state {
        case .running: play = ("Pause", "pause.fill")
        case .paused: play = ("Resume", "play.fill")
        case .idle: play = ("Start", "play.fill")
        case .done: play = ("Again", "arrow.clockwise")
        }
        return HStack(alignment: .top, spacing: 14) {
            SKCaptionedKey("Reset", systemImage: "arrow.counterclockwise") { timers.reset(timer.id) }
                .disabled(state == .idle)
            SKCaptionedKey(play.title, systemImage: play.symbol, lamp: state == .running) {
                if state == .done { timers.again(timer.id) } else { timers.toggle(timer.id) }
            }
            if state == .done {
                SKCaptionedKey("Snooze", systemImage: "zzz") { timers.snooze(timer.id) }
            } else {
                SKCaptionedKey("+1 Min", systemImage: "plus") { timers.add(60, to: timer.id) }
            }
            Spacer(minLength: 0)
            SKCaptionedKey("Edit", systemImage: "pencil", variant: .charcoal, action: edit)
        }
    }
}

/// The MT-1's LCD for a timer: label and end time, the digits, then the progress strip and state.
struct TimerLCD: View {
    let timer: MeetballTimer
    let now: Date
    var digitHeight: CGFloat = 34

    private var ink: Color { Color(sk1Hex: SK1.lcdInk) }

    var body: some View {
        let state = timer.state(at: now)
        SKLCD {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(timer.displayName.uppercased()).lineLimit(1)
                    Spacer(minLength: 8)
                    Text(rightText(state)).lineLimit(1)
                }
                .font(.system(size: 10, weight: .heavy, design: .monospaced)).tracking(0.8)
                .foregroundStyle(ink)
                // While it rings, 00:00 flashes, as on the MT-1's alarm.
                SKSevenSegment(TimerFormat.clock(timer.remaining(at: now)), digitHeight: digitHeight)
                    .opacity(state == .done && Int(now.timeIntervalSince1970) % 2 == 1 ? 0.25 : 1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 8) {
                    TimerProgressStrip(progress: timer.progress(at: now), urgency: TimerUrgency.of(timer, at: now))
                    Text(stateText(state))
                        .font(.system(size: 10, weight: .heavy, design: .monospaced)).tracking(0.8)
                        .foregroundStyle(ink)
                        .fixedSize()
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .frame(height: digitHeight + 62)
    }

    private func rightText(_ state: MeetballTimer.State) -> String {
        switch state {
        case .running: return "ENDS \(timer.endDate?.shortTime ?? "")".uppercased()
        case .paused, .idle: return "OF \(TimerFormat.clock(timer.duration))"
        case .done: return "RINGING -\(TimerFormat.clock(timer.overtime(at: now)))"
        }
    }

    private func stateText(_ state: MeetballTimer.State) -> String {
        switch state {
        case .idle: return "IDLE"
        case .running: return "RUN"
        case .paused: return "PAUSE"
        case .done: return "RING"
        }
    }

    static func spoken(_ t: MeetballTimer, now: Date) -> String {
        switch t.state(at: now) {
        case .idle: return "\(t.displayName), \(TimerFormat.spoken(t.duration)), ready"
        case .running: return "\(t.displayName), \(TimerFormat.spoken(t.remaining(at: now))) left"
        case .paused: return "\(t.displayName), paused with \(TimerFormat.spoken(t.remaining(at: now))) left"
        case .done: return "\(t.displayName), ringing"
        }
    }
}

/// The MT-1's progress strip (▰▰▰▰▱▱): twenty cells on the glass, lit as time runs out. The lit cells turn amber in
/// the last fifth and red in the last ten seconds.
struct TimerProgressStrip: View {
    let progress: Double
    let urgency: TimerUrgency
    static let cells = 20

    var body: some View {
        let lit = Int((progress * Double(Self.cells)).rounded())
        HStack(spacing: 2) {
            ForEach(0..<Self.cells, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1)
                    .fill(i < lit ? color : Color(sk1Hex: SK1.lcdInk, opacity: 0.12))
            }
        }
        .frame(height: 6)
        .accessibilityHidden(true)
    }

    private var color: Color {
        switch urgency {
        case .calm: return Color(sk1Hex: SK1.lcdInk)
        case .near: return Color(sk1Hex: SK1.amber)
        case .alarm: return Color(sk1Hex: SK1.recRed)
        }
    }
}

/// The MT-1's Settings: snooze length, how long an ignored alarm rings, and the sound new timers start with.
struct TimerSettingsGroup: View {
    @EnvironmentObject private var timers: TimerStore

    var body: some View {
        SKGroup(caption: "Settings", note: "Snooze and auto-stop are for every timer; the sound is what new timers start with.") {
            SKRow(title: "Snooze") {
                SKKnob("Snooze", value: $timers.settings.snoozeMinutes, in: 1...30, defaultValue: 5) { "\($0) MIN" }
            }
            SKRow(title: "Auto-stop", subtitle: "An alarm nobody stops goes quiet after this.") {
                SKKnob("Auto-stop", selection: $timers.settings.ringFor,
                       stops: TimerSettings.ringForStops.map { (title: "\(Int($0 / 60)) MIN", value: $0) },
                       defaultValue: 300)
            }
            SKRow(title: "Sound") {
                TimerSoundPicker(soundID: $timers.settings.soundID)
            }
        }
    }
}

/// ◀ sound ▶: steps through the iPhone's sounds (or tap the name for the list), playing each one as it's picked.
struct TimerSoundPicker: View {
    @EnvironmentObject private var timers: TimerStore
    @Binding var soundID: String

    var body: some View {
        SKPicker(selection: $soundID, options: TimerSound.installed.map { .init($0.id, $0.title.uppercased()) })
            .onChange(of: soundID) { _, id in timers.preview(TimerSound.find(id)) }
            .accessibilityLabel("Sound")
    }
}

/// Making or changing a timer: its length on Hours / Minutes / Seconds knobs as on the MT-1 (or typed on a keypad,
/// microwave style), a label, Recent and presets, and its sound.
struct TimerEditSheet: View {
    @EnvironmentObject private var timers: TimerStore
    @Environment(\.dismiss) private var dismiss
    let original: MeetballTimer?

    enum Input: String { case knobs, keypad }

    @State private var label = ""
    @State private var entry = TimerKeypadEntry()
    @State private var soundID = TimerSound.defaultID
    @AppStorage("timers.input") private var input: Input = .knobs
    @State private var confirmDelete = false
    @State private var tap = 0

    private var isNew: Bool { original == nil }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SK1.Metrics.groupSpacing) {
                header
                lengthDisplay
                SKSegmented(selection: $input, options: [.init(.knobs, "Knobs"), .init(.keypad, "Keypad")])
                    .frame(maxWidth: .infinity)
                if input == .knobs { knobs } else { keypad }
                SKTextField("Label", text: $label, prompt: "Optional: Tea, Laundry, Pasta…", height: 44)
                    .submitLabel(.done)
                    .textInputAutocapitalization(.words)
                presets
                SKGroup(caption: "Sound", note: "The iPhone's own sounds. Each plays as you pick it.") {
                    SKRow(title: "Alarm") { TimerSoundPicker(soundID: $soundID) }
                }
                if !isNew { deleteKey }
            }
            .padding(16)
        }
        .scrollDismissesKeyboard(.interactively)
        .sk1Chassis()
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .sensoryFeedback(.selection, trigger: tap)
        .onAppear {
            if let original {
                label = original.label
                entry = TimerKeypadEntry(seconds: original.duration)
                soundID = original.soundID
            } else {
                soundID = timers.settings.soundID
            }
        }
        .onDisappear { timers.stopPreview() }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Button("Cancel") { dismiss() }.buttonStyle(.sk1Key())
            Spacer()
            Text(isNew ? "New timer" : "Edit timer").font(.headline)
            Spacer()
            if isNew {
                Button("Save") { save(start: false) }
                    .buttonStyle(.sk1Key())
                    .disabled(entry.seconds <= 0)
                Button("Start") { save(start: true) }
                    .buttonStyle(.sk1Key(.orange))
                    .disabled(entry.seconds <= 0)
            } else {
                Button("Save") { save(start: false) }
                    .buttonStyle(.sk1Key(.orange))
                    .disabled(entry.seconds <= 0)
            }
        }
    }

    private var lengthDisplay: some View {
        SKLCD {
            VStack(spacing: 4) {
                SKSevenSegment(entry.display, digitHeight: 40)
                HStack {
                    Text("HR").frame(maxWidth: .infinity)
                    Text("MIN").frame(maxWidth: .infinity)
                    Text("SEC").frame(maxWidth: .infinity)
                }
                .font(.system(size: 9, weight: .heavy)).tracking(1.1)
                .foregroundStyle(Color(sk1Hex: SK1.lcdInk, opacity: 0.7))
                .frame(width: 210)
            }
            .padding(.vertical, 8)
        }
        .frame(height: 84)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Length \(TimerFormat.spoken(entry.seconds))"))
    }

    /// Hours, Minutes and Seconds knobs: drag one up or down, double-tap to zero it.
    private var knobs: some View {
        SKWell {
            HStack(alignment: .top, spacing: 4) {
                SKKnob("Hours", value: part(3600, 23), in: 0...23, defaultValue: 0) { "\($0)H" }
                SKKnob("Minutes", value: part(60, 59), in: 0...59, defaultValue: 0) { "\($0)M" }
                SKKnob("Seconds", value: part(1, 59), in: 0...59, defaultValue: 0) { "\($0)S" }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .padding(.horizontal, 6)
        }
    }

    /// The hours, minutes or seconds of the length (`unit` seconds each), as a knob sets them.
    private func part(_ unit: Int, _ maximum: Int) -> Binding<Int> {
        Binding(
            get: {
                let total = Int(entry.seconds)
                return unit == 3600 ? min(total / 3600, maximum) : (total / unit) % 60
            },
            set: { new in
                let total = Int(entry.seconds)
                let h = unit == 3600 ? new : total / 3600
                let m = unit == 60 ? new : (total % 3600) / 60
                let s = unit == 1 ? new : total % 60
                entry = TimerKeypadEntry(seconds: TimeInterval(h * 3600 + m * 60 + s))
                tap += 1
            })
    }

    /// 1–9, clear, 0, delete: digits come in from the right.
    private var keypad: some View {
        SKWell {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                ForEach(1...9, id: \.self) { d in digitKey(d) }
                Button { entry.clear(); tap += 1 } label: { Text("C").frame(maxWidth: .infinity) }
                    .buttonStyle(.sk1Key(size: .large))
                    .accessibilityLabel("Clear")
                digitKey(0)
                Button { entry.backspace(); tap += 1 } label: {
                    Image(systemName: "delete.left").frame(maxWidth: .infinity)
                }
                .buttonStyle(.sk1Key(size: .large))
                .accessibilityLabel("Delete digit")
            }
            .padding(10)
        }
    }

    private func digitKey(_ d: Int) -> some View {
        Button { entry.type(d); tap += 1 } label: {
            Text("\(d)").font(.system(size: 20, weight: .semibold, design: .rounded)).frame(maxWidth: .infinity)
        }
        .buttonStyle(.sk1Key(size: .large))
    }

    /// Recent and the presets load their length and label onto the knobs.
    private var presets: some View {
        VStack(alignment: .leading, spacing: SK1.Metrics.captionToWell) {
            SKCaption(timers.recent.isEmpty ? "Presets" : "Recent and presets", tone: .soft)
            SKWell {
                VStack(alignment: .leading, spacing: 8) {
                    if !timers.recent.isEmpty {
                        TimerChips(presets: timers.recent, columns: 2, highlighted: entry.seconds, pick: load)
                        SKGroove()
                    }
                    TimerChips(presets: TimerPresets.focus, columns: 2, highlighted: entry.seconds, pick: load)
                    TimerChips(presets: TimerPresets.lengths, highlighted: entry.seconds, pick: load)
                }
                .padding(10)
            }
        }
    }

    /// Loads a preset's length, and its name as the label unless you've typed one of your own.
    private func load(_ p: TimerPreset) {
        entry = TimerKeypadEntry(seconds: p.seconds)
        let typed = label.trimmingCharacters(in: .whitespaces)
        let known = (TimerPresets.all + timers.recent).contains { $0.label == typed }
        if typed.isEmpty || known {
            label = p.label == TimerFormat.spoken(p.seconds) ? "" : p.label
        }
        tap += 1
    }

    private var deleteKey: some View {
        Group {
            if confirmDelete {
                HStack(spacing: 8) {
                    Button("Delete it") {
                        if let original { timers.delete(original.id) }
                        dismiss()
                    }
                    .buttonStyle(.sk1Key(.charcoal))
                    Button("Keep it") { confirmDelete = false }.buttonStyle(.sk1Key())
                }
            } else {
                Button { confirmDelete = true } label: { Label("Delete Timer", systemImage: "trash") }
                    .buttonStyle(.sk1Key())
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func save(start: Bool) {
        let seconds = entry.seconds
        guard seconds > 0 else { return }
        if var t = original {
            let lengthChanged = t.duration != seconds
            t.label = label
            t.soundID = soundID
            t.duration = seconds
            // A new length on a timer that isn't running starts it afresh at that length.
            if lengthChanged && t.state(at: Date()) != .running { t.reset() }
            t.oneOff = false
            timers.update(t)
        } else {
            timers.add(MeetballTimer(label: label, duration: seconds, soundID: soundID), start: start)
        }
        dismiss()
    }
}

/// A timer going off with Meetball open, as the MT-1's alarm window: over everything, the LCD flashing 00:00 with
/// the backlight pulsing and counting how long it has rung, Again / Snooze / Stop, and when it stops by itself. The
/// sound loops (with a buzz) until then.
struct TimerRingingView: View {
    @EnvironmentObject private var timers: TimerStore
    let timer: MeetballTimer
    /// Others ringing behind this one.
    let more: Int
    @State private var pulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { tl in
            let now = tl.date
            VStack(spacing: 18) {
                Spacer()
                HStack(spacing: 6) {
                    Text("MT-1").font(.system(size: 13, weight: .black)).tracking(1)
                    Text("Time's up").font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
                    Spacer()
                    SKLamp(color: .danger, lit: true, label: "Ringing", blinking: true)
                    Text("RING").font(.system(size: 9, weight: .heavy)).tracking(1).foregroundStyle(.secondary)
                }
                TimerLCD(timer: timer, now: now, digitHeight: 64)
                    .brightness(pulse ? 0.08 : -0.04)
                Text(timer.displayName).font(.largeTitle.bold()).multilineTextAlignment(.center).lineLimit(2)
                Text("\(TimerFormat.spoken(timer.duration)) · \(TimerSound.find(timer.soundID).title)").sk1Hint()
                if more > 0 { Text("\(more) more ringing").font(.callout.weight(.semibold)) }
                Spacer()
                HStack(alignment: .top, spacing: 32) {
                    SKCaptionedKey("Again", systemImage: "arrow.clockwise") { timers.again(timer.id) }
                    SKCaptionedKey("Snooze \(timers.settings.snoozeMinutes) min", systemImage: "zzz") { timers.snooze(timer.id) }
                }
                Button { timers.stop(timer.id) } label: {
                    Label("Stop", systemImage: "stop.fill").font(.title2.weight(.bold)).frame(maxWidth: .infinity)
                }
                .buttonStyle(.sk1Key(.orange, size: .large))
                if let auto = timers.autoStopDate(for: timer) {
                    Text("Auto-stop in \(TimerFormat.clock(auto.timeIntervalSince(now)))").sk1Hint()
                }
            }
            .padding(24)
            .frame(maxWidth: 480)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        // The chassis under the status bar too, so nothing behind shows.
        .background { Color.clear.sk1Chassis().ignoresSafeArea() }
        .accessibilityAddTraits(.isModal)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) { pulse = true }
        }
    }
}
