import SwiftUI
import SK1Tokens
import SK1UI

/// Countdown text used by the alert overlays.
public enum AlertCountdown {
    /// "4:59" or "1:02:03" before the start; "Now" in the first minute after it; then "3 min ago".
    public static func clock(until start: Date, now: Date) -> String {
        let t = start.timeIntervalSince(now)
        if t > 0 {
            let s = Int(t.rounded(.up)), h = s / 3600, m = (s % 3600) / 60, sec = s % 60
            return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
        }
        let ago = Int(-t / 60)
        return ago < 1 ? "Now" : "\(ago) min ago"
    }

    /// Label above the clock.
    public static func caption(until start: Date, now: Date) -> String {
        let t = start.timeIntervalSince(now)
        if t > 0 { return "Starts in" }
        return t > -60 ? "Starting" : "Started"
    }
}

private func timeRange(_ e: CalendarEvent) -> String {
    "\(e.start.formatted(date: .omitted, time: .shortened)) – \(e.end.formatted(date: .omitted, time: .shortened))"
}

// MARK: - Heads-up card

/// Non-intrusive card in the top-right corner, on an SK-1 plate: calendar colour accent, LCD countdown, Join / Snooze / Dismiss.
struct HeadsUpAlertCard: View {
    enum Mode { case upcoming, stillJoining }

    let event: CalendarEvent
    let mode: Mode
    let actions: AlertActions
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false
    private var accent: Color { Color(hex: event.colorHex) }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in card(now: ctx.date) }
            .frame(width: 360)
            .padding(18) // room for the shadow and the slide
            .offset(x: shown || reduceMotion ? 0 : 80)
            .opacity(shown ? 1 : 0)
            .onAppear {
                withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.38, dampingFraction: 0.82)) { shown = true }
            }
    }

    private func card(now: Date) -> some View {
        HStack(spacing: 0) {
            Rectangle().fill(accent).frame(width: 5)
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    lcd(now: now)
                    Button(action: actions.dismiss) { Image(systemName: "xmark") }
                        .buttonStyle(.sk1Key(.round, size: .small))
                        .keyboardShortcut(.cancelAction)
                        .help("Dismiss (Esc)")
                        .accessibilityLabel("Dismiss")
                }
                Text(event.title).font(.headline).lineLimit(2)
                HStack(spacing: 8) {
                    Label(timeRange(event), systemImage: "clock")
                    if let loc = event.location?.trimmingCharacters(in: .whitespacesAndNewlines), !loc.isEmpty {
                        Label(loc, systemImage: "mappin.and.ellipse").lineLimit(1)
                    }
                }
                .font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    JoinButton(event: event, key: .orange, action: actions.join).keyboardShortcut(.defaultAction)
                    switch mode {
                    case .upcoming:
                        Menu("Snooze") {
                            ForEach(MeetingGuardianManager.snoozePresets, id: \.self) { m in
                                Button("\(m) minute\(m == 1 ? "" : "s")") { actions.snooze(m) }
                            }
                        }
                        .menuStyle(.borderlessButton).fixedSize()
                        Button("Dismiss", action: actions.dismiss).buttonStyle(.sk1Key())
                    case .stillJoining:
                        Button("I'm not joining", action: actions.notJoining).buttonStyle(.sk1Key())
                    }
                }
            }
            .padding(14)
        }
        .background(SKPlate { Color.clear })
        .clipShape(RoundedRectangle(cornerRadius: SK1.Metrics.plateRadius, style: .continuous))
        .shadow(color: .black.opacity(0.25), radius: 14, y: 6)
    }

    /// Seven-segment countdown before the start; after it, short text ("NOW", "3 MIN AGO") with a blinking red lamp.
    private func lcd(now: Date) -> some View {
        let clock = AlertCountdown.clock(until: event.start, now: now)
        let upcoming = event.start > now
        let caption: String
        switch mode {
        case .stillJoining: caption = "Still joining?"
        case .upcoming: caption = AlertCountdown.caption(until: event.start, now: now)
        }
        return SK1CountdownLCD(caption: caption,
                               digits: upcoming ? clock : nil,
                               text: upcoming ? nil : clock,
                               live: !upcoming,
                               height: 36,
                               accessibilityText: header(now: now))
    }

    private func header(now: Date) -> String {
        switch mode {
        case .stillJoining:
            return "Started \(AlertCountdown.clock(until: event.start, now: now)) · Are you still joining?"
        case .upcoming:
            let clock = AlertCountdown.clock(until: event.start, now: now)
            return event.start > now ? "Starts in \(clock)" : (clock == "Now" ? "Starting now" : "Started \(clock)")
        }
    }
}

// MARK: - Hard alert

/// Full-screen alert shown on every display: big countdown, the meeting's details, Join, snooze presets.
struct HardAlertView: View {
    let event: CalendarEvent
    let actions: AlertActions
    /// The copy on the focused display shows the keyboard hint.
    var takesFocus = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false
    private var accent: Color { Color(hex: event.colorHex) }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in content(now: ctx.date) }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                ZStack {
                    Rectangle().fill(.ultraThinMaterial)  // sk1-audit: ignore (the full-screen hard alert keeps its own dark overlay)
                    LinearGradient(colors: [accent.opacity(0.55), .black.opacity(0.88)], startPoint: .top, endPoint: .bottom)
                }
                .ignoresSafeArea()
            }
            .environment(\.colorScheme, .dark)
            .opacity(shown ? 1 : 0)
            .scaleEffect(shown || reduceMotion ? 1 : 1.03)
            .onAppear { withAnimation(.easeOut(duration: reduceMotion ? 0.12 : 0.28)) { shown = true } }
    }

    private func content(now: Date) -> some View {
        VStack(spacing: 26) {
            Text(AlertCountdown.caption(until: event.start, now: now).uppercased())
                .font(.title3.weight(.semibold)).tracking(3).foregroundStyle(.white.opacity(0.7))
            Text(AlertCountdown.clock(until: event.start, now: now))
                .font(.system(size: 150, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(.white)
                .contentTransition(.numericText())
                .accessibilityLabel(Text("\(AlertCountdown.caption(until: event.start, now: now)) \(TimeUntilFormatter.string(until: event.start, now: now))"))
            Text(event.title)
                .font(.system(size: 44, weight: .semibold)).foregroundStyle(.white)
                .multilineTextAlignment(.center).lineLimit(3)
            details
            HStack(spacing: 16) {
                if event.meetURL != nil {
                    JoinButton(event: event, size: .large, action: actions.join).keyboardShortcut(.defaultAction)
                } else {
                    Button("Got it", action: actions.dismiss).buttonStyle(.borderedProminent).controlSize(.large)  // sk1-audit: ignore (the full-screen hard alert keeps its own dark overlay)
                        .keyboardShortcut(.defaultAction)
                }
            }
            HStack(spacing: 10) {
                Text("Snooze").foregroundStyle(.white.opacity(0.7))
                ForEach(MeetingGuardianManager.snoozePresets, id: \.self) { m in
                    Button("\(m) min") { actions.snooze(m) }.buttonStyle(.bordered)  // sk1-audit: ignore (the full-screen hard alert keeps its own dark overlay)
                }
                Divider().frame(height: 20).padding(.horizontal, 6)  // sk1-audit: ignore (the full-screen hard alert keeps its own dark overlay)
                Button("I'm not joining", action: actions.notJoining).buttonStyle(.bordered)  // sk1-audit: ignore (the full-screen hard alert keeps its own dark overlay)
                Button("Dismiss", action: actions.dismiss).buttonStyle(.bordered).keyboardShortcut(.cancelAction)  // sk1-audit: ignore (the full-screen hard alert keeps its own dark overlay)
            }
            .controlSize(.large)
            if takesFocus {
                Text(event.meetURL != nil ? "Return to join · Esc to dismiss" : "Esc to dismiss")
                    .font(.caption).foregroundStyle(.white.opacity(0.5))
            }
        }
        .padding(60)
        .frame(maxWidth: 1000)
    }

    private var details: some View {
        HStack(spacing: 22) {
            Label(timeRange(event), systemImage: "clock")
            if let loc = event.location?.trimmingCharacters(in: .whitespacesAndNewlines), !loc.isEmpty {
                Label(loc, systemImage: "mappin.and.ellipse").lineLimit(1)
            }
            if !event.attendees.isEmpty {
                Label("\(event.attendees.count) \(event.attendees.count == 1 ? "person" : "people")", systemImage: "person.2")
            }
            if let org = event.organizer, !org.isEmpty {
                Label(org, systemImage: "person.crop.circle")
            }
        }
        .font(.title3).foregroundStyle(.white.opacity(0.8))
    }
}
