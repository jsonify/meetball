import SwiftUI
import SK1Tokens
import SK1UI

/// The app's screens, switched by a row of SK-1 keys along the bottom, with the event and quick-add sheets and the
/// cancellation confetti over everything.
struct PhoneRootView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case today, week, month, settings
        var id: String { rawValue }
        var title: String {
            switch self {
            case .today: return "Today"
            case .week: return "Week"
            case .month: return "Month"
            case .settings: return "Settings"
            }
        }
        var symbol: String {
            switch self {
            case .today: return "sun.max"
            case .week: return "chart.bar"
            case .month: return "calendar"
            case .settings: return "slider.horizontal.3"
            }
        }
    }

    @EnvironmentObject private var store: PhoneStore
    @SceneStorage("tab") private var tab: Tab = .today
    @State private var detail: CalendarEvent?
    @State private var quickAdd = false

    var body: some View {
        ScrollView {
            screen
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 24)
                .frame(maxWidth: 600)
                .frame(maxWidth: .infinity)
        }
        .refreshable { await store.refresh(fresh: true) }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom, spacing: 0) { tabBar }
        .sk1Chassis()
        .sheet(item: $detail) { e in
            EventDetailSheet(event: e).environmentObject(store)
        }
        .sheet(isPresented: $quickAdd) {
            QuickAddSheet().environmentObject(store)
        }
        .overlay {
            if let party = store.celebration {
                PhoneCelebrationView(party: party) { store.celebration = nil }
                    .id(party.id)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: store.celebration)
        .onOpenURL { url in
            switch MeetballLink.parse(url) {
            case .join(let meeting): PhoneJoin.open(meeting)
            case .today: tab = .today
            case nil: break
            }
        }
    }

    @ViewBuilder
    private var screen: some View {
        let open: (CalendarEvent) -> Void = { detail = $0 }
        let add: () -> Void = { quickAdd = true }
        switch tab {
        case .today: TodayView(open: open, quickAdd: add)
        case .week: WeekView(open: open, quickAdd: add)
        case .month: MonthView(open: open, quickAdd: add)
        case .settings: PhoneSettingsView()
        }
    }

    private var tabBar: some View {
        VStack(spacing: 0) {
            SKGroove()
            HStack(spacing: 0) {
                ForEach(Tab.allCases) { t in
                    SKCaptionedKey(t.title, systemImage: t.symbol, lamp: tab == t) { tab = t }
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.top, 10)
            .padding(.bottom, 2)
        }
        .sk1Chassis()
        .sensoryFeedback(.selection, trigger: tab)
    }
}

/// Confetti over the whole screen and an LCD card saying the meeting is off, as on the Mac. Tap to dismiss; it goes by
/// itself after a few seconds. With Reduce Motion, only the card.
struct PhoneCelebrationView: View {
    let party: Celebration
    let done: () -> Void
    static let duration: TimeInterval = 4.5
    @State private var start = Date()
    @State private var buzz = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Color.black.opacity(0.15).ignoresSafeArea()
            if !reduceMotion {
                ConfettiBurst(start: start, duration: Self.duration, count: 180).ignoresSafeArea()
            }
            card
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: done)
        .sensoryFeedback(.success, trigger: buzz)
        .task {
            start = Date()
            buzz += 1
            try? await Task.sleep(for: .seconds(Self.duration))
            done()
        }
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Dismisses")
    }

    private var card: some View {
        VStack(spacing: 10) {
            SKLCD {
                HStack(spacing: 8) {
                    SKLamp(color: .orange, lit: true, label: "Canceled", blinking: true)
                    Text("MEETING CANCELED").font(.system(size: 15, weight: .bold, design: .monospaced)).tracking(1)
                        .foregroundStyle(Color(sk1Hex: SK1.lcdInk))
                }
                .padding(.horizontal, 14)
            }
            .frame(height: 44)
            Text(party.title).font(.title2.bold()).multilineTextAlignment(.center).lineLimit(2)
            Text(party.extra > 0 ? "And \(party.extra) more. Enjoy the free time!" : "Enjoy the free time!")
                .font(.callout).foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(maxWidth: 340)
        .sk1Chassis()
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.3), radius: 24, y: 10)
        .padding(24)
        .accessibilityElement(children: .combine)
    }
}
