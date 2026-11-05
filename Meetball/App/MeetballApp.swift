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
    @Published var now = Date()
    @Published private(set) var menuBarTitle = MenuBarTitle.idle
    /// Tinted phase of the menu bar icon; alternates every second while a meeting is about to start.
    @Published private(set) var menuBarHighlighted = false
    private var tick: Timer?
    private var pulse: Timer?
    private var bag: [Any] = []

    init() {
        calendar = CalendarStore(session: session)
        guardian = MeetingGuardianManager(store: guardianStore, subs: subs)
        join = JoinController(calendar: calendar)
        bag.append(calendar.$events.sink { [guardian] evs in guardian.reschedule(events: evs) })
        // @Published emits before the new value is stored, so hop to the next main-loop turn before reading state back.
        bag.append(subs.$entitlementState.receive(on: DispatchQueue.main)
            .sink { [guardian, calendar] _ in guardian.reschedule(events: calendar.events) })
        bag.append(guardianStore.objectWillChange.receive(on: DispatchQueue.main)
            .sink { [guardian, calendar] _ in guardian.reschedule(events: calendar.events) })
        bag.append(calendar.objectWillChange.receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateMenuBarTitle() })
        bag.append(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: DispatchQueue.main).sink { [weak self] _ in self?.updateMenuBarTitle() })
        tick = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.now = Date(); self?.updateMenuBarTitle() }
        }
        calendar.startAutoRefresh()
    }

    func updateMenuBarTitle() {
        let now = Date()
        let settings = MenuBarTitleSettings(defaults: .standard)
        let title = MenuBarTitleBuilder.build(next: MenuBarTitleBuilder.pick(calendar.visibleEvents, now: now), now: now, settings: settings)
        if title != menuBarTitle { menuBarTitle = title }
        setPulsing(title.isSoon, pulse: settings.pulseWhenSoon)
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
                .environmentObject(model.guardianStore).environmentObject(model.guardian)
        }
        .commands {
            CommandGroup(before: .toolbar) {
                Button("Upcoming") { model.calendar.section = .upcoming }.keyboardShortcut("0", modifiers: .command)
                ForEach(CalendarViewMode.allCases) { mode in
                    Button(mode.title) { model.calendar.section = .calendar; model.calendar.viewMode = mode }
                        .keyboardShortcut(KeyEquivalent(mode.shortcut), modifiers: .command)
                }
                Divider()
            }
            CommandGroup(after: .newItem) {
                Button("Join Nearest Meeting") { model.join.joinNearest() }
            }
        }
        MenuBarExtra {
            MenuBarContent().environmentObject(model).environmentObject(model.session).environmentObject(model.calendar)
                .environmentObject(model.join).environmentObject(model.guardianStore)
        } label: {
            MenuBarLabelView(title: model.menuBarTitle, highlighted: model.menuBarHighlighted)
        }.menuBarExtraStyle(.window)
        Settings {
            SettingsView().environmentObject(model.session).environmentObject(model.calendar).environmentObject(model.subs)
                .environmentObject(model.guardianStore).environmentObject(model.guardian).environmentObject(model.join)
        }
    }
}
