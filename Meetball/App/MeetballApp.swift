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
    @Published var now = Date()
    private var tick: Timer?
    private var bag: [Any] = []

    init() {
        calendar = CalendarStore(session: session)
        guardian = MeetingGuardianManager(store: guardianStore, subs: subs)
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
        MenuBarExtra {
            MenuBarContent().environmentObject(model).environmentObject(model.session).environmentObject(model.calendar)
        } label: {
            Image(systemName: "calendar")
            Text(model.menuBarTitle)
        }.menuBarExtraStyle(.window)
        Settings {
            SettingsView().environmentObject(model.session).environmentObject(model.calendar).environmentObject(model.subs)
                .environmentObject(model.guardianStore).environmentObject(model.guardian)
        }
    }
}

struct MenuBarContent: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var session: SessionManager
    @EnvironmentObject var calendar: CalendarStore
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !calendar.hasAnySource {
                Text("Connect a calendar").font(.headline)
                Button("Sign in with Google") { Task { await session.addAccount() } }
                Button("Use Apple Calendar") { Task { await calendar.enableApple() } }
            } else if calendar.upcoming().isEmpty {
                Text("No upcoming events").foregroundStyle(.secondary)
            } else {
                ForEach(calendar.upcoming()) { MenubarEventRow(event: $0); Divider() }
            }
            HStack {
                Button("Open Meetball") { openWindow(id: "main"); NSApp.activate(ignoringOtherApps: true) }
                Button("Settings…") { openSettings(); NSApp.activate(ignoringOtherApps: true) }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }
        }.padding(12).frame(width: 340)
    }
}
