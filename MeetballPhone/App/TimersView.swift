import SwiftUI
import SK1Tokens
import SK1UI

/// Timers: as many as you like, each a card with its name, an LCD counting down, and Start / Pause, Reset and +1 MIN
/// keys. Tap a card to change its name, length or sound; the + key adds one. Quick start runs a one-off timer that
/// goes away once it's stopped.
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
                quickStart
                if timers.timers.isEmpty {
                    Text("No timers yet. Press + to make one, or quick start one above.").sk1Hint()
                }
                ForEach(timers.timers) { t in
                    TimerCard(timer: t, now: now) { editing = TimerEditRequest(timer: t) }
                }
                Text("Timers ring with the iPhone's own sounds. With Meetball open they ring until you stop them, even on silent; "
                     + "with it closed you get a notification with the sound, which follows the ring switch.")
                    .sk1Hint()
            }
        }
    }

    /// The TM-1: the next timer to go off and how many are running.
    private func display(now: Date, running: [MeetballTimer]) -> some View {
        let next = running.min { $0.remaining(at: now) < $1.remaining(at: now) }
        let done = timers.timers.filter { $0.state(at: now) == .done }
        let message: String
        if let next {
            message = "\(next.displayName.uppercased()) IN \(TimerFormat.clock(next.remaining(at: now)))"
        } else if let d = done.first {
            message = "\(d.displayName.uppercased()) DONE"
        } else {
            message = "READY"
        }
        return SKDisplay(title: "TM-1", detail: now.shortTime, message: message, number: running.count, digits: 2,
                         unit: "ON", live: !running.isEmpty, height: 60)
    }

    /// One-tap timers of the usual lengths.
    private var quickStart: some View {
        VStack(alignment: .leading, spacing: SK1.Metrics.captionToWell) {
            SKCaption("Quick start", tone: .soft)
            SKWell {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
                    ForEach(TimerPresets.all, id: \.self) { p in
                        Button {
                            timers.add(MeetballTimer(label: p.label, duration: p.seconds, oneOff: true), start: true)
                        } label: {
                            Text(p.label).frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.sk1Key(size: .small))
                        .accessibilityLabel("Start a \(p.label) timer")
                    }
                }
                .padding(10)
            }
        }
    }
}

/// The edit sheet, for a new timer (nil) or an existing one.
struct TimerEditRequest: Identifiable {
    let id = UUID()
    let timer: MeetballTimer?
}

/// One timer: lamp, name and sound, the LCD counting down, and its keys.
struct TimerCard: View {
    @EnvironmentObject private var timers: TimerStore
    let timer: MeetballTimer
    let now: Date
    let edit: () -> Void

    var body: some View {
        let state = timer.state(at: now)
        SKWell {
            VStack(alignment: .leading, spacing: 10) {
                Button(action: edit) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            SKLamp(color: lamp(state), lit: state != .idle, label: stateName(state),
                                   blinking: state == .done)
                            Text(timer.displayName).font(.headline).lineLimit(1)
                            Spacer(minLength: 8)
                            Label(TimerSound.find(timer.soundID).title, systemImage: "speaker.wave.2")
                                .labelStyle(.titleAndIcon)
                                .sk1Hint()
                                .lineLimit(1)
                        }
                        lcd(state)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("\(timer.displayName), \(stateName(state)), \(TimerFormat.spoken(timer.remaining(at: now))) left"))
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

    private func lcd(_ state: MeetballTimer.State) -> some View {
        SKLCD {
            HStack(alignment: .center, spacing: 10) {
                SKSevenSegment(state == .done ? TimerFormat.clock(0) : TimerFormat.clock(timer.remaining(at: now)), digitHeight: 30)
                Spacer(minLength: 6)
                VStack(alignment: .trailing, spacing: 3) {
                    Text(stateName(state).uppercased())
                        .font(.system(size: 10, weight: .heavy, design: .monospaced)).tracking(1)
                    Text(state == .done ? "-\(TimerFormat.clock(timer.overtime(at: now)))" : TimerFormat.clock(timer.duration))
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .opacity(0.7)
                }
                .foregroundStyle(Color(sk1Hex: SK1.lcdInk))
            }
            .padding(.horizontal, 12)
        }
        .frame(height: 56)
    }

    private func keys(_ state: MeetballTimer.State) -> some View {
        HStack(spacing: 6) {
            Button { timers.toggle(timer.id) } label: {
                Label(state == .running ? "Pause" : (state == .paused ? "Resume" : "Start"),
                      systemImage: state == .running ? "pause.fill" : "play.fill")
            }
            .buttonStyle(.sk1Key(isOn: state == .running))
            Button { timers.reset(timer.id) } label: { Image(systemName: "arrow.counterclockwise") }
                .buttonStyle(.sk1Key())
                .disabled(state == .idle)
                .accessibilityLabel("Reset")
            Button { timers.add(60, to: timer.id) } label: { Text("+1 min") }
                .buttonStyle(.sk1Key())
                .accessibilityLabel("Add a minute")
            Spacer(minLength: 0)
        }
    }

    private func lamp(_ state: MeetballTimer.State) -> SKLampColor {
        switch state {
        case .idle, .running: return .success
        case .paused: return .warning
        case .done: return .danger
        }
    }

    private func stateName(_ state: MeetballTimer.State) -> String {
        switch state {
        case .idle: return "Ready"
        case .running: return "Running"
        case .paused: return "Paused"
        case .done: return "Done"
        }
    }
}

/// Making or changing a timer: its name, its length typed on a keypad (microwave style, or a preset), and its sound,
/// picked from the iPhone's own (each plays as you pick it).
struct TimerEditSheet: View {
    @EnvironmentObject private var timers: TimerStore
    @Environment(\.dismiss) private var dismiss
    let original: MeetballTimer?

    @State private var label = ""
    @State private var entry = TimerKeypadEntry()
    @State private var soundID = TimerSound.defaultID
    @State private var confirmDelete = false
    @State private var tap = 0

    private var isNew: Bool { original == nil }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SK1.Metrics.groupSpacing) {
                header
                SKTextField("Name", text: $label, prompt: "Tea, Laundry, Pasta…", height: 44)
                    .submitLabel(.done)
                    .textInputAutocapitalization(.words)
                lengthDisplay
                keypad
                presets
                sounds
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
            guard let original else { return }
            label = original.label
            entry = TimerKeypadEntry(seconds: original.duration)
            soundID = original.soundID
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

    private var presets: some View {
        VStack(alignment: .leading, spacing: SK1.Metrics.captionToWell) {
            SKCaption("Presets", tone: .soft)
            SKWell {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
                    ForEach(TimerPresets.all, id: \.self) { p in
                        Button {
                            entry = TimerKeypadEntry(seconds: p.seconds)
                            tap += 1
                        } label: { Text(p.label).frame(maxWidth: .infinity) }
                        .buttonStyle(.sk1Key(isOn: entry.seconds == p.seconds, size: .small))
                    }
                }
                .padding(10)
            }
        }
    }

    /// The iPhone's sounds, by shelf; picking one plays it.
    private var sounds: some View {
        let catalog = TimerSound.installed
        let shelves = ["iPhone"] + TimerSound.shelves.map { $0.title }
        return VStack(alignment: .leading, spacing: SK1.Metrics.groupSpacing) {
            ForEach(shelves, id: \.self) { shelf in
                let sounds = catalog.filter { $0.group == shelf }
                if !sounds.isEmpty {
                    SKGroup(caption: shelf == "iPhone" ? "Sound" : shelf) {
                        ForEach(sounds) { s in soundRow(s) }
                    }
                }
            }
        }
    }

    private func soundRow(_ s: TimerSound) -> some View {
        let picked = s.id == soundID
        return Button {
            soundID = s.id
            timers.preview(s)
        } label: {
            SKRow(title: s.title) {
                SKLamp(color: .orange, lit: picked, label: picked ? "Picked" : nil)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(picked ? .isSelected : [])
        .accessibilityHint("Plays the sound and picks it")
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

/// A timer going off with Meetball open: over everything, its name, how long since it went off, and a big STOP key.
/// The sound loops (with a buzz) until it's stopped or given more time.
struct TimerRingingView: View {
    @EnvironmentObject private var timers: TimerStore
    let timer: MeetballTimer
    /// Others ringing behind this one.
    let more: Int
    @State private var pulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { tl in
            VStack(spacing: 20) {
                Spacer()
                SKLCD {
                    HStack(spacing: 10) {
                        SKLamp(color: .danger, lit: true, size: 8, label: "Ringing", blinking: true)
                        Text("TIME'S UP").font(.system(size: 18, weight: .heavy, design: .monospaced)).tracking(2)
                            .foregroundStyle(Color(sk1Hex: SK1.lcdInk))
                        Spacer(minLength: 8)
                        SKSevenSegment("-" + TimerFormat.clock(timer.overtime(at: tl.date)), digitHeight: 22)
                    }
                    .padding(.horizontal, 14)
                }
                .frame(height: 56)
                Image(systemName: "timer")
                    .font(.system(size: 64, weight: .semibold))
                    .foregroundStyle(Color(sk1Hex: SK1.orange))
                    .scaleEffect(pulse ? 1.12 : 0.94)
                    .accessibilityHidden(true)
                Text(timer.displayName).font(.largeTitle.bold()).multilineTextAlignment(.center).lineLimit(2)
                Text("\(TimerFormat.spoken(timer.duration)) · \(TimerSound.find(timer.soundID).title)").sk1Hint()
                if more > 0 { Text("\(more) more ringing").font(.callout.weight(.semibold)) }
                Spacer()
                Button { timers.stop(timer.id) } label: {
                    Text("Stop").font(.title2.weight(.bold)).frame(maxWidth: .infinity)
                }
                .buttonStyle(.sk1Key(.orange, size: .large))
                HStack(spacing: 8) {
                    snooze(60, "+1 min")
                    snooze(5 * 60, "+5 min")
                    snooze(timer.duration, "Again")
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
            withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) { pulse = true }
        }
    }

    private func snooze(_ seconds: TimeInterval, _ title: String) -> some View {
        Button { timers.add(seconds, to: timer.id) } label: { Text(title).frame(maxWidth: .infinity) }
            .buttonStyle(.sk1Key())
            .accessibilityLabel(title == "Again" ? "Run it again" : "Add \(TimerFormat.spoken(seconds))")
    }
}
