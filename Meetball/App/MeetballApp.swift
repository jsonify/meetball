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
    private var tick: Timer?
    private var bag: [Any] = []

    init() {
        calendar = CalendarStore(session: session)
        guardian = MeetingGuardianManager(store: guardianStore, subs: subs)
        join = JoinController(calendar: calendar)
        bag.append(calendar.$events.sink { [guardian] evs in guardian.reschedule(events: evs) })
        bag.append(subs.$entitlementState.sink { [guardian, calendar] _ in guardian.reschedule(events: calendar.events) })
        tick = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in Task { @MainActor in self?.now = Date() } }
        calendar.startAutoRefresh()
    }

    var menuBarTitle: String {
        guard UserDefaults.standard.object(forKey: "showCountdownInMenuBar") as? Bool ?? true,
              let next = calendar.upcoming(limit: 1, now: now).first else { return "" }
        return next.start <= now ? "now" : TimeUntilFormatter.string(until: next.start, now: now)
    }
}

@main
struct MeetballApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        Window("Meetball", id: "main") {
            CalendarContainerView().frame(minWidth: 900, minHeight: 560)
                .environmentObject(model.session).environmentObject(model.calendar).environmentObject(model.subs)
        }
        .commands {
            CommandGroup(before: .toolbar) {
                ForEach(CalendarViewMode.allCases) { mode in
                    Button(mode.title) { model.calendar.viewMode = mode }
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
                .environmentObject(model.join)
        } label: {
            Image(systemName: "calendar")
            Text(model.menuBarTitle)
        }.menuBarExtraStyle(.window)
        Settings {
            SettingsView().environmentObject(model.session).environmentObject(model.calendar).environmentObject(model.subs)
                .environmentObject(model.guardianStore).environmentObject(model.guardian).environmentObject(model.join)
        }
    }
}
