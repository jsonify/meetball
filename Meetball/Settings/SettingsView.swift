import SwiftUI
import ServiceManagement

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings().tabItem { Label("General", systemImage: "gearshape") }
            AccountsSettings().tabItem { Label("Accounts", systemImage: "person.crop.circle") }
            MeetingGuardianSettingsView().tabItem { Label("Alerts", systemImage: "bell.badge") }
            SubscriptionSettings().tabItem { Label("Pro", systemImage: "star") }
        }.frame(width: 620, height: 560)
    }
}

struct GeneralSettings: View {
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @AppStorage("refreshIntervalSeconds") private var refresh: Double = 120
    @AppStorage("showCountdownInMenuBar") private var showCountdown = true
    var body: some View {
        Form {
            Section("App") {
                Toggle("Launch at Login", isOn: $launchAtLogin).onChange(of: launchAtLogin) { _, on in
                    do { if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } } catch { launchAtLogin.toggle() }
                }
                Text("Choose whether Meetball should launch automatically when you sign in to your Mac.").font(.caption).foregroundStyle(.secondary)
                Toggle("Show next meeting countdown in the menu bar", isOn: $showCountdown)
            }
            Section("Sync") {
                Picker("Refresh Google Calendar", selection: $refresh) {
                    Text("Every minute").tag(60.0); Text("Every 2 minutes").tag(120.0); Text("Every 5 minutes").tag(300.0)
                }
                Text("Control how Meetball refreshes Google Calendar changes.").font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped)
    }
}

struct AccountsSettings: View {
    @EnvironmentObject var session: SessionManager
    @EnvironmentObject var subs: SubscriptionManager
    @State private var selection: AuthenticatedUser?
    private let palette = ["#4285F4", "#0B8043", "#D50000", "#F4511E", "#8E24AA", "#039BE5", "#616161"]
    var body: some View {
        HSplitView {
            VStack {
                List(session.accounts, selection: $selection) { Text($0.email).tag($0) }
                if session.accounts.isEmpty { Text("Add a Google account to manage alerts and account accents.").font(.caption).padding() }
                Button("Add Google account") { Task { await session.addAccount() } }.padding(8)
            }.frame(minWidth: 200, maxWidth: 240)
            VStack(alignment: .leading, spacing: 12) {
                if let a = selection {
                    Text(a.name).font(.headline); Text(a.email).foregroundStyle(.secondary)
                    Text("Account accent color").font(.subheadline)
                    HStack { ForEach(palette, id: \.self) { hex in
                        Circle().fill(Color(hex: hex)).frame(width: 22, height: 22)
                            .overlay(Circle().stroke(.primary, lineWidth: session.accentHex[a.email] == hex ? 2 : 0))
                            .onTapGesture { session.setAccent(hex, for: a.email) } } }
                    Button("Remove account", role: .destructive) { session.remove(a); selection = nil }
                } else { Text("Choose an account on the left to see and edit its settings.").foregroundStyle(.secondary) }
                if let e = session.lastError { Text(e).font(.caption).foregroundStyle(.red) }
                Spacer()
            }.padding().frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }
}

struct SubscriptionSettings: View {
    var body: some View { Form { SubscriptionStatusView() }.formStyle(.grouped) }
}
