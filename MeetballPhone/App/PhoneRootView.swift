import SwiftUI
import SK1Tokens
import SK1UI

/// The app's screens, switched from the floating dock in the bottom corner (its quick menu lists them), with the event
/// and quick-add sheets and the cancellation confetti over everything. One screen gives way to the next by what they
/// are to each other (`ScreenMove`): the calendar screens zoom, Today comes down as a lid, Settings is a flip away.
struct PhoneRootView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case today, day, week, month, settings
        var id: String { rawValue }
        var title: String {
            switch self {
            case .today: return "Today"
            case .day: return "Day"
            case .week: return "Week"
            case .month: return "Month"
            case .settings: return "Settings"
            }
        }
        var symbol: String {
            switch self {
            case .today: return "sun.max"
            case .day: return "calendar.day.timeline.left"
            case .week: return "chart.bar"
            case .month: return "calendar"
            case .settings: return "slider.horizontal.3"
            }
        }
    }

    @EnvironmentObject private var store: PhoneStore
    @SceneStorage("tab") private var storedTab: Tab = .day
    @SceneStorage("settingsSection") private var settingsSection: PhoneSettingsSection = .general
    @State private var detail: CalendarEvent?
    /// The composer, open; `start` when a slot on the day grid picked the time.
    @State private var compose: ComposeRequest?
    @State private var readout = false
    /// The pre-flight card showing, and the meetings it already came up for.
    @State private var preFlight: CalendarEvent?
    @State private var shownPreFlights: Set<String> = []
    /// The Echo recorder, open for this meeting, and the meetings whose Echo banner was waved off.
    @State private var echo: CalendarEvent?
    @State private var dismissedEchoes: Set<String> = []
    @State private var moment: CalendarEvent?
    @State private var dismissedMoments: Set<String> = []
    /// A day picked on the Month tab, for the Day grid to open on.
    @State private var dayJump: Date?
    /// The dock's quick menu, open.
    @State private var menuOpen = false
    /// The move between screens under way.
    @State private var course = ScreenCourse()

    /// The tab showing: Today falls back to Day while it's switched off in Settings.
    private var tab: Tab {
        get { storedTab == .today && !store.settings.showTodayTab ? .day : storedTab }
        nonmutating set {
            course.plan(from: tab, to: newValue)
            storedTab = newValue
        }
    }

    private var tabs: [Tab] { Tab.allCases.filter { $0 != .today || store.settings.showTodayTab } }

    var body: some View {
        ZStack {
            page
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                // Its own chassis, so a screen moves as one panel.
                .sk1Chassis()
                .id(tab)
                .transition(ScreenTransition(course: course, lid: tab == .today))
                // The lid stays over the calendar, going as well as coming.
                .zIndex(tab == .today ? 1 : 0)
        }
        .animation(course.animation, value: tab)
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { course.stage = $0 }
        // Content runs under the floating dock, and scrolls far enough to clear it.
        .contentMargins(.bottom, PhoneDock.clearance, for: .scrollContent)
        .overlay {
            if menuOpen {
                Color.black.opacity(0.12)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { menuOpen = false }
                    .transition(.opacity)
                    .accessibilityLabel("Close the menu")
                    .accessibilityAddTraits(.isButton)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: menuOpen)
        .overlay(alignment: .bottom) {
            VStack(spacing: 8) {
                if !menuOpen { echoBanner }
                dock
            }
            .padding(.bottom, 4)
        }
        .sk1Chassis()
        .sheet(item: $detail) { e in
            EventDetailSheet(event: e).environmentObject(store)
        }
        .sheet(item: $compose) { request in
            QuickAddSheet(start: request.start).environmentObject(store)
        }
        .overlay {
            if let party = store.celebration {
                PhoneCelebrationView(party: party) { store.celebration = nil }
                    .id(party.id)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: store.celebration)
        .sheet(isPresented: $readout) {
            DayReadoutSheet().environmentObject(store)
        }
        .onReceive(NotificationCenter.default.publisher(for: .meetballShake)) { _ in
            if detail == nil && compose == nil && moment == nil { readout = true }
        }
        .fullScreenCover(item: $moment) { e in
            CountdownMomentView(event: e) {
                dismissedMoments.insert(e.uid)
                moment = nil
            }
        }
        .task(id: "\(store.revision)|\(store.settings.countdownMoment)") { await waitForMoment() }
        .sheet(item: $preFlight) { e in
            PreFlightSheet(event: e).environmentObject(store)
        }
        .task(id: "\(store.revision)|\(store.settings.preFlight)") { await waitForPreFlight() }
        .sheet(item: $echo) { e in
            EchoSheet(event: e).environmentObject(store)
        }
        .onChange(of: store.echoRequest, initial: true) { _, request in
            guard let request else { return }
            store.echoRequest = nil
            openEcho(store.event(for: request))
        }
        .onOpenURL { url in
            switch MeetballLink.parse(url) {
            case .join(let meeting): PhoneJoin.open(meeting)
            case .today: tab = store.settings.showTodayTab ? .today : .day
            case nil: break
            }
        }
    }

    /// Sleeps until a minute before the next meeting with a link, then shows the countdown moment (restarted by every
    /// refresh, so a moved meeting moves it).
    private func waitForMoment() async {
        guard store.settings.countdownMoment, let e = PhoneAgenda.nextJoinable(store.upcoming.filter(store.settings.alerts(for:)), now: Date()),
              !dismissedMoments.contains(e.uid) else { return }
        let wait = e.start.timeIntervalSinceNow - 60
        if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
        guard !Task.isCancelled, e.start > Date(), moment == nil else { return }
        detail = nil
        compose = nil
        readout = false
        preFlight = nil
        moment = e
    }

    /// Sleeps until five minutes before each meeting, then shows its pre-flight card, unless something else is open
    /// (restarted by every refresh, so a moved meeting moves it). Opening Meetball inside the five minutes shows it
    /// straight away.
    private func waitForPreFlight() async {
        guard store.settings.preFlight else { return }
        while !Task.isCancelled {
            let upcoming = store.upcoming.filter { !shownPreFlights.contains($0.uid) && store.settings.alerts(for: $0) }
            guard let e = PreFlight.next(upcoming, now: Date()) else { return }
            let wait = e.start.timeIntervalSinceNow - PreFlight.lead
            if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
            guard !Task.isCancelled else { return }
            shownPreFlights.insert(e.uid)
            guard e.start > Date(), detail == nil, compose == nil, moment == nil, echo == nil, preFlight == nil else { continue }
            readout = false
            preFlight = e
        }
    }

    /// The Echo recorder for `e`, over whatever else is open.
    private func openEcho(_ e: CalendarEvent) {
        let busy = detail != nil || compose != nil || readout || preFlight != nil || moment != nil
        detail = nil
        compose = nil
        readout = false
        preFlight = nil
        moment = nil
        dismissedEchoes.insert(e.uid)
        guard busy else { echo = e; return }
        // A sheet can't open while another is still going away.
        Task {
            try? await Task.sleep(for: .milliseconds(650))
            echo = e
        }
    }

    /// For half an hour after a meeting ends: its Echo key, above the dock.
    @ViewBuilder
    private var echoBanner: some View {
        if store.settings.echoMode {
            TimelineView(.periodic(from: .now, by: 30)) { tl in
                let now = tl.date
                let today = store.meetingFeed(store.events(from: now, days: 1)
                                              + store.events(from: now.addingTimeInterval(-Echo.offerWindow), days: 1)).shown
                if let e = Echo.justEnded(today, notes: store.echoNotes, dismissed: dismissedEchoes, now: now) {
                    EchoBanner(event: e, record: { openEcho(e) }, dismiss: { withAnimation { _ = dismissedEchoes.insert(e.uid) } })
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
    }

    /// The screen showing, scrolling as it does.
    @ViewBuilder
    private var page: some View {
        if tab == .day {
            // The time grid scrolls itself, under its pinned dates and all-day strip.
            DayGridView(open: { detail = $0 }, add: { compose = ComposeRequest(start: $0) }, jump: $dayJump)
                .frame(maxWidth: 700)
                .frame(maxWidth: .infinity)
        } else if tab == .month {
            // Months scroll on and on under the pinned header and weekday row.
            MonthView { day, cell in
                dayJump = day
                course.tapped = cell
                tab = .day
            }
        } else {
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
        }
    }

    @ViewBuilder
    private var screen: some View {
        let open: (CalendarEvent) -> Void = { detail = $0 }
        let add: () -> Void = { compose = ComposeRequest(start: nil) }
        switch tab {
        case .today: TodayView(open: open, quickAdd: add, filters: showFilters)
        case .day: EmptyView()   // drawn outside the scroll view, in page
        case .week: WeekView(open: open, quickAdd: add)
        case .month: EmptyView()   // drawn outside the scroll view, in page
        case .settings: PhoneSettingsView(section: $settingsSection)
        }
    }

    /// Settings › Events, from Today's filter key.
    private func showFilters() {
        settingsSection = .events
        tab = .settings
    }

    private var dock: some View {
        HStack {
            Spacer(minLength: 0)
            PhoneDock(tab: Binding(get: { tab }, set: { tab = $0 }), tabs: tabs, menuOpen: $menuOpen) {
                compose = ComposeRequest(start: nil)
            }
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: 700)
        .sensoryFeedback(.selection, trigger: tab)
        .onChange(of: tab) { _, _ in menuOpen = false }
    }
}

/// A request to open the composer, at `start` when one was picked on the day grid.
struct ComposeRequest: Identifiable {
    let id = UUID()
    var start: Date?
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
