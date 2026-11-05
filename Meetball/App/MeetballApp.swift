import SwiftUI
import Combine
import UserNotifications

@MainActor
final class AppModel: ObservableObject {
    let session = SessionManager()
    let subs = SubscriptionManager()
    let guardianStore = MeetingGuardianStore()
    let calendar: CalendarStore
    let guardian: MeetingGuardianManager
    let join: JoinController
    let shortcuts = AppShortcuts()
    @Published var now = Date()
    @Published private(set) var menuBarTitle = MenuBarTitle.idle
    /// Tinted phase of the menu bar icon; alternates every second while a meeting is about to start.
    @Published private(set) var menuBarHighlighted = false {
        didSet { if oldValue != menuBarHighlighted { renderLCD() } }
    }
    /// The LCD-style menu bar item, when Settings › Menu Bar uses it.
    @Published private(set) var menuBarLCD: NSImage?
    private var menuBarStyle: MenuBarStyle = .plain
    let changeNotifier: MeetingChangeNotifier
    let autoJoin: AutoJoinController
    private var tick: Timer?
    private var pulse: Timer?
    private var bag: [Any] = []

    init() {
        calendar = CalendarStore(session: session)
        // Before Meeting Guardian starts: it asks for notification permission at launch only once setup is done.
        OnboardingState.migrate(hasSource: calendar.hasAnySource)
        guardian = MeetingGuardianManager(store: guardianStore, subs: subs)
        join = JoinController(calendar: calendar)
        changeNotifier = MeetingChangeNotifier(store: guardianStore)
        autoJoin = AutoJoinController(store: guardianStore)
        calendar.onMeetingChanges = { [changeNotifier] in changeNotifier.handle($0) }
        shortcuts.setAction(for: .openPopover) { StatusItemOpener.toggle() }
        shortcuts.setAction(for: .quickAdd) { [calendar] in QuickAddPanel.show(store: calendar) }
        if UserDefaults.standard.bool(forKey: AppPreferences.Key.hideDockIcon) {
            DispatchQueue.main.async { DockIcon.apply(hidden: true) }
        }
        // @Published emits before the new value is stored, so hop to the next main-loop turn before reading state back.
        // Guardian only alerts for events that pass the meeting-first rules (Settings › Events).
        bag.append(subs.$entitlementState.receive(on: DispatchQueue.main)
            .sink { [guardian, calendar] _ in guardian.reschedule(events: calendar.meetingEvents) })
        bag.append(guardianStore.objectWillChange.receive(on: DispatchQueue.main)
            .sink { [guardian, calendar] _ in guardian.reschedule(events: calendar.meetingEvents) })
        bag.append(calendar.objectWillChange.receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.updateMenuBarTitle()
                self.guardian.reschedule(events: self.calendar.meetingEvents)
                self.autoJoin.tick(events: self.calendar.meetingEvents)
            })
        bag.append(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: DispatchQueue.main).sink { [weak self] _ in self?.updateMenuBarTitle() })
        tick = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.now = Date(); self.updateMenuBarTitle()
                self.autoJoin.tick(events: self.calendar.meetingEvents)
            }
        }
        calendar.startAutoRefresh()
    }

    func updateMenuBarTitle() {
        let now = Date()
        let settings = MenuBarTitleSettings(defaults: .standard)
        let title = MenuBarTitleBuilder.build(next: MenuBarTitleBuilder.pick(calendar.meetingEvents, now: now), now: now, settings: settings)
        let styleChanged = settings.style != menuBarStyle
        menuBarStyle = settings.style
        if title != menuBarTitle || styleChanged { menuBarTitle = title; renderLCD() }
        setPulsing(title.isSoon, pulse: settings.pulseWhenSoon)
    }

    private func renderLCD() {
        guard menuBarStyle == .lcd else { if menuBarLCD != nil { menuBarLCD = nil }; return }
        let dark = NSApp?.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let image = MenuBarLCDRenderer.image(title: menuBarTitle, highlighted: menuBarHighlighted, dark: dark)
        if image !== menuBarLCD { menuBarLCD = image }
    }

    /// Soon: tint the icon, and blink it once a second when pulsing is on.
    private func setPulsing(_ soon: Bool, pulse shouldPulse: Bool) {
        guard soon else {
            pulse?.invalidate(); pulse = nil
            if menuBarHighlighted { menuBarHighlighted = false }
            return
        }
        guard shouldPulse else {
            pulse?.invalidate(); pulse = nil
            if !menuBarHighlighted { menuBarHighlighted = true }
            return
        }
        guard pulse == nil else { return }
        menuBarHighlighted = true
        pulse = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.menuBarHighlighted.toggle() }
        }
    }
}

@main
struct MeetballApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        Window("Meetball", id: "main") {
            CalendarContainerView().frame(minWidth: 900, minHeight: 560)
                .environmentObject(model.session).environmentObject(model.calendar).environmentObject(model.subs)
                .environmentObject(model.guardianStore).environmentObject(model.guardian).environmentObject(model.shortcuts)
        }
        .commands {
            CommandGroup(before: .toolbar) {
                Button("Upcoming") { model.calendar.section = .upcoming }.keyboardShortcut("0", modifiers: .command)
                ForEach(CalendarViewMode.allCases) { mode in
                    Button(mode.title) { model.calendar.section = .calendar; model.calendar.viewMode = mode }
                        .keyboardShortcut(KeyEquivalent(mode.shortcut), modifiers: .command)
                }
                Divider()  // sk1-audit: ignore (a menu item separator)
                Button("Refresh Calendars") { model.calendar.refresh(.user) }.keyboardShortcut("r", modifiers: .command)
                Divider()  // sk1-audit: ignore (a menu item separator)
            }
            CommandGroup(replacing: .newItem) {
                Button("New Event\u{2026}") {
                    WindowOpener.openMain()
                    model.calendar.composer = .quickAdd(nil)
                }
                .keyboardShortcut("n", modifiers: .command)
                Button("Join Nearest Meeting") { model.join.joinNearest() }
            }
        }
        MenuBarExtra {
            MenuBarContent().environmentObject(model).environmentObject(model.session).environmentObject(model.calendar)
                .environmentObject(model.join).environmentObject(model.guardianStore).environmentObject(model.shortcuts)
        } label: {
            MenuBarLabelView(title: model.menuBarTitle, highlighted: model.menuBarHighlighted, lcd: model.menuBarLCD)
        }.menuBarExtraStyle(.window)
        Settings {
            SettingsView().environmentObject(model.session).environmentObject(model.calendar).environmentObject(model.subs)
                .environmentObject(model.guardianStore).environmentObject(model.guardian).environmentObject(model.join)
                .environmentObject(model.shortcuts)
        }
    }
}
