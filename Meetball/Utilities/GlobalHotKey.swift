import AppKit
import Carbon
import SwiftUI
import SK1UI

/// A recorded keyboard shortcut, stored with Carbon key code + modifiers so it can be registered system-wide.
public struct HotKeyCombo: Codable, Equatable {
    public var keyCode: UInt32
    public var carbonModifiers: UInt32
    public var keyLabel: String

    public static let defaultCombo = HotKeyCombo(keyCode: UInt32(kVK_ANSI_J),
                                                 carbonModifiers: UInt32(controlKey | optionKey | cmdKey), keyLabel: "J")
    static let defaultsKey = "join.hotKey"

    public init(keyCode: UInt32, carbonModifiers: UInt32, keyLabel: String) {
        self.keyCode = keyCode; self.carbonModifiers = carbonModifiers; self.keyLabel = keyLabel
    }

    init(event: NSEvent) {
        let f = event.modifierFlags
        var m: UInt32 = 0
        if f.contains(.command) { m |= UInt32(cmdKey) }
        if f.contains(.option) { m |= UInt32(optionKey) }
        if f.contains(.control) { m |= UInt32(controlKey) }
        if f.contains(.shift) { m |= UInt32(shiftKey) }
        self.init(keyCode: UInt32(event.keyCode), carbonModifiers: m, keyLabel: Self.label(for: event))
    }

    public var display: String {
        var s = ""
        if carbonModifiers & UInt32(controlKey) != 0 { s += "⌃" }
        if carbonModifiers & UInt32(optionKey) != 0 { s += "⌥" }
        if carbonModifiers & UInt32(shiftKey) != 0 { s += "⇧" }
        if carbonModifiers & UInt32(cmdKey) != 0 { s += "⌘" }
        return s + keyLabel
    }

    private static func label(for e: NSEvent) -> String {
        switch Int(e.keyCode) {
        case kVK_Space: return "Space"
        case kVK_Return: return "↩"
        case kVK_Tab: return "⇥"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        default:
            if let n = functionKeyNumber(Int(e.keyCode)) { return "F\(n)" }
            // Ask for the key's character with no modifiers, so ⇧1 is labeled "1", not "!".
            return (e.characters(byApplyingModifiers: []) ?? e.charactersIgnoringModifiers ?? "?").uppercased()
        }
    }

    private static func functionKeyNumber(_ code: Int) -> Int? {
        let map: [Int: Int] = [kVK_F1: 1, kVK_F2: 2, kVK_F3: 3, kVK_F4: 4, kVK_F5: 5, kVK_F6: 6, kVK_F7: 7, kVK_F8: 8,
                               kVK_F9: 9, kVK_F10: 10, kVK_F11: 11, kVK_F12: 12, kVK_F13: 13, kVK_F14: 14, kVK_F15: 15,
                               kVK_F16: 16, kVK_F17: 17, kVK_F18: 18, kVK_F19: 19, kVK_F20: 20]
        return map[code]
    }

    /// Missing or unreadable value → `fallback`; empty string → user cleared it.
    static func load(_ d: UserDefaults = .standard, key: String = defaultsKey,
                     fallback: HotKeyCombo? = defaultCombo) -> HotKeyCombo? {
        guard let s = d.string(forKey: key) else { return fallback }
        guard !s.isEmpty else { return nil }
        return (try? JSONDecoder().decode(HotKeyCombo.self, from: Data(s.utf8))) ?? fallback
    }

    static func save(_ c: HotKeyCombo?, _ d: UserDefaults = .standard, key: String = defaultsKey) {
        let s = c.flatMap { try? JSONEncoder().encode($0) }.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        d.set(s, forKey: key)
    }
}

/// The system-wide shortcuts Meetball offers (Settings › General › Shortcuts).
enum GlobalShortcut: UInt32, CaseIterable, Identifiable {
    case join = 1, openPopover = 2, quickAdd = 3
    var id: UInt32 { rawValue }

    var title: String {
        switch self {
        case .join: return "Join nearest meeting"
        case .openPopover: return "Open the menu bar popover"
        case .quickAdd: return "Quick add an event"
        }
    }

    var defaultsKey: String {
        switch self {
        case .join: return HotKeyCombo.defaultsKey
        case .openPopover: return "shortcut.openPopover"
        case .quickAdd: return "shortcut.quickAdd"
        }
    }

    /// Join has a default (⌃⌥⌘J); the others are off until recorded.
    var defaultCombo: HotKeyCombo? { self == .join ? .defaultCombo : nil }
}

/// Registers Meetball's system-wide hotkeys via Carbon (works inside the App Sandbox, no Accessibility permission).
@MainActor
final class GlobalHotKeyCenter {
    static let shared = GlobalHotKeyCenter()
    private var actions: [UInt32: @MainActor () -> Void] = [:]
    private var hotKeyRefs: [UInt32: EventHotKeyRef] = [:]
    private var handlerRef: EventHandlerRef?

    func setAction(for shortcut: GlobalShortcut, _ action: @escaping @MainActor () -> Void) {
        actions[shortcut.rawValue] = action
    }

    @discardableResult
    func register(_ combo: HotKeyCombo?, for shortcut: GlobalShortcut) -> Bool {
        unregister(shortcut)
        guard let combo else { return true }
        installHandlerIfNeeded()
        let id = EventHotKeyID(signature: OSType(0x4D42_484B) /* 'MBHK' */, id: shortcut.rawValue)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(combo.keyCode, combo.carbonModifiers, id, GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else { return false }
        hotKeyRefs[shortcut.rawValue] = ref
        return true
    }

    func unregister(_ shortcut: GlobalShortcut) {
        if let ref = hotKeyRefs.removeValue(forKey: shortcut.rawValue) { UnregisterEventHotKey(ref) }
    }

    fileprivate func fire(_ id: UInt32) { actions[id]?() }

    private func installHandlerIfNeeded() {
        guard handlerRef == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            guard let event else { return OSStatus(eventNotHandledErr) }
            var hotKey = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                           nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKey)
            guard status == noErr else { return status }
            let id = hotKey.id
            Task { @MainActor in GlobalHotKeyCenter.shared.fire(id) }
            return noErr
        }, 1, &spec, nil, &handlerRef)
    }
}

/// The recorded shortcuts other than Join (which `JoinController` owns): opening the popover and quick add.
@MainActor
final class AppShortcuts: ObservableObject {
    @Published private(set) var combos: [GlobalShortcut: HotKeyCombo] = [:]
    @Published private(set) var failed: Set<GlobalShortcut> = []
    static let managed: [GlobalShortcut] = [.openPopover, .quickAdd]

    init() {
        for s in Self.managed {
            combos[s] = HotKeyCombo.load(key: s.defaultsKey, fallback: s.defaultCombo)
            register(s)
        }
    }

    func setAction(for shortcut: GlobalShortcut, _ action: @escaping @MainActor () -> Void) {
        GlobalHotKeyCenter.shared.setAction(for: shortcut, action)
    }

    func set(_ combo: HotKeyCombo?, for shortcut: GlobalShortcut) {
        combos[shortcut] = combo
        HotKeyCombo.save(combo, key: shortcut.defaultsKey)
        register(shortcut)
    }

    func suspend(_ shortcut: GlobalShortcut) { GlobalHotKeyCenter.shared.unregister(shortcut) }
    func resume(_ shortcut: GlobalShortcut) { register(shortcut) }

    private func register(_ s: GlobalShortcut) {
        if GlobalHotKeyCenter.shared.register(combos[s], for: s) { failed.remove(s) } else { failed.insert(s) }
    }
}

/// Owns the "join nearest meeting" shortcut and its settings.
@MainActor
final class JoinController: ObservableObject {
    @Published var hotKey: HotKeyCombo? {
        didSet { HotKeyCombo.save(hotKey); registrationFailed = !GlobalHotKeyCenter.shared.register(hotKey, for: .join) }
    }
    @Published var windowMinutes: Int = 10 {
        didSet { JoinPreferences().joinWindowMinutes = windowMinutes }
    }
    @Published private(set) var registrationFailed = false
    private weak var calendar: CalendarStore?

    init(calendar: CalendarStore) {
        self.calendar = calendar
        hotKey = HotKeyCombo.load()
        windowMinutes = JoinPreferences().joinWindowMinutes
        GlobalHotKeyCenter.shared.setAction(for: .join) { [weak self] in self?.joinNearest() }
        registrationFailed = !GlobalHotKeyCenter.shared.register(hotKey, for: .join)
    }

    /// Temporarily releases the shortcut (e.g. while recording a new one).
    func suspend() { GlobalHotKeyCenter.shared.unregister(.join) }
    func resume() { registrationFailed = !GlobalHotKeyCenter.shared.register(hotKey, for: .join) }

    func joinNearest(now: Date = Date()) {
        guard let calendar else { return }
        if let e = NearestMeetingPicker.pick(calendar.meetingEvents, now: now, window: TimeInterval(windowMinutes * 60)),
           let url = e.meetURL {
            MeetingJoiner.join(url)
            Toast.show("Joining \(e.title)", systemImage: MeetingService.detect(url).symbol)
        } else {
            Toast.show("No meeting to join right now", systemImage: "video.slash")
        }
    }
}

/// Small transient HUD near the top of the screen.
@MainActor
enum Toast {
    private static var panel: NSPanel?
    private static var hideWork: DispatchWorkItem?

    static func show(_ text: String, systemImage: String) {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let host = NSHostingView(rootView: ToastView(text: text, systemImage: systemImage))
        let size = host.fittingSize
        let frame = NSRect(x: screen.visibleFrame.midX - size.width / 2, y: screen.visibleFrame.maxY - size.height - 24,
                           width: size.width, height: size.height)
        let p = panel ?? NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.level = .floating
        p.isOpaque = false; p.backgroundColor = .clear; p.hasShadow = true
        p.ignoresMouseEvents = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        p.contentView = host
        p.setFrame(frame, display: true)
        p.orderFrontRegardless()
        panel = p
        hideWork?.cancel()
        let work = DispatchWorkItem { p.orderOut(nil) }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: work)
    }
}

private struct ToastView: View {
    let text: String; let systemImage: String
    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.callout.weight(.medium)).lineLimit(1)
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(SKPlate(radius: 18) { Color.clear })
            .padding(8)
    }
}

/// Click, then press a key combination (must include ⌘, ⌥ or ⌃). Esc cancels. The shortcut being recorded is released
/// meanwhile, so pressing it again doesn't fire it.
struct HotKeyRecorder: View {
    @Binding var combo: HotKeyCombo?
    var suspend: () -> Void = {}
    var resume: () -> Void = {}
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 6) {
            Button { recording ? stop() : start() } label: {
                Text(recording ? "Type shortcut…" : (combo?.display ?? "Record shortcut"))
                    .frame(minWidth: 110)
            }
            .buttonStyle(.sk1Key(isOn: recording, size: .small))
            .help(recording ? "Press the new shortcut, or Esc to cancel" : "Click to record a new shortcut")
            if combo != nil && !recording {
                Button { combo = nil } label: { Image(systemName: "xmark") }
                    .buttonStyle(.sk1Key(.round, size: .small))
                    .help("Clear shortcut").accessibilityLabel("Clear shortcut")
            }
        }
        .onDisappear(perform: stop)
    }

    private func start() {
        recording = true
        suspend()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { ev in
            if Int(ev.keyCode) == kVK_Escape { stop(); return nil }
            guard !ev.modifierFlags.intersection([.command, .option, .control]).isEmpty else { NSSound.beep(); return nil }
            combo = HotKeyCombo(event: ev)
            stop()
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if recording { recording = false; resume() }
    }
}
