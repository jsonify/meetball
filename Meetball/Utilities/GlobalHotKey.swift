import AppKit
import Carbon
import SwiftUI

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
            return (e.charactersIgnoringModifiers ?? "?").uppercased()
        }
    }

    private static func functionKeyNumber(_ code: Int) -> Int? {
        let map: [Int: Int] = [kVK_F1: 1, kVK_F2: 2, kVK_F3: 3, kVK_F4: 4, kVK_F5: 5, kVK_F6: 6, kVK_F7: 7, kVK_F8: 8,
                               kVK_F9: 9, kVK_F10: 10, kVK_F11: 11, kVK_F12: 12, kVK_F13: 13, kVK_F14: 14, kVK_F15: 15,
                               kVK_F16: 16, kVK_F17: 17, kVK_F18: 18, kVK_F19: 19, kVK_F20: 20]
        return map[code]
    }

    /// Missing key → default shortcut; empty string → user cleared it.
    static func load(_ d: UserDefaults = .standard) -> HotKeyCombo? {
        guard let s = d.string(forKey: defaultsKey) else { return defaultCombo }
        guard !s.isEmpty else { return nil }
        return try? JSONDecoder().decode(HotKeyCombo.self, from: Data(s.utf8))
    }

    static func save(_ c: HotKeyCombo?, _ d: UserDefaults = .standard) {
        let s = c.flatMap { try? JSONEncoder().encode($0) }.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        d.set(s, forKey: defaultsKey)
    }
}

/// Registers one system-wide hotkey via Carbon (works inside the App Sandbox, no Accessibility permission).
@MainActor
final class GlobalHotKeyCenter {
    static let shared = GlobalHotKeyCenter()
    var action: (@MainActor () -> Void)?
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    @discardableResult
    func register(_ combo: HotKeyCombo?) -> Bool {
        unregister()
        guard let combo else { return true }
        installHandlerIfNeeded()
        let id = EventHotKeyID(signature: OSType(0x4D42_484B) /* 'MBHK' */, id: 1)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(combo.keyCode, combo.carbonModifiers, id, GetApplicationEventTarget(), 0, &ref)
        guard status == noErr else { return false }
        hotKeyRef = ref
        return true
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
    }

    private func installHandlerIfNeeded() {
        guard handlerRef == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            Task { @MainActor in GlobalHotKeyCenter.shared.action?() }
            return noErr
        }, 1, &spec, nil, &handlerRef)
    }
}

/// Owns the "join nearest meeting" shortcut and its settings.
@MainActor
final class JoinController: ObservableObject {
    @Published var hotKey: HotKeyCombo? {
        didSet { HotKeyCombo.save(hotKey); registrationFailed = !GlobalHotKeyCenter.shared.register(hotKey) }
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
        GlobalHotKeyCenter.shared.action = { [weak self] in self?.joinNearest() }
        registrationFailed = !GlobalHotKeyCenter.shared.register(hotKey)
    }

    /// Temporarily releases the shortcut (e.g. while recording a new one).
    func suspend() { GlobalHotKeyCenter.shared.unregister() }
    func resume() { registrationFailed = !GlobalHotKeyCenter.shared.register(hotKey) }

    func joinNearest(now: Date = Date()) {
        guard let calendar else { return }
        if let e = NearestMeetingPicker.pick(calendar.visibleEvents, now: now, window: TimeInterval(windowMinutes * 60)),
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
            .background(.regularMaterial, in: Capsule())
            .padding(8)
    }
}

/// Click, then press a key combination (must include ⌘, ⌥ or ⌃). Esc cancels.
struct HotKeyRecorder: View {
    @EnvironmentObject var join: JoinController
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 6) {
            Button { recording ? stop() : start() } label: {
                Text(recording ? "Type shortcut…" : (join.hotKey?.display ?? "Record shortcut"))
                    .frame(minWidth: 110)
            }
            if join.hotKey != nil && !recording {
                Button { join.hotKey = nil } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.borderless).help("Clear shortcut")
            }
        }
        .onDisappear(perform: stop)
    }

    private func start() {
        recording = true
        join.suspend()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { ev in
            if Int(ev.keyCode) == kVK_Escape { stop(); return nil }
            guard !ev.modifierFlags.intersection([.command, .option, .control]).isEmpty else { NSSound.beep(); return nil }
            join.hotKey = HotKeyCombo(event: ev)
            stop()
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if recording { recording = false; join.resume() }
    }
}
