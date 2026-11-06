import SwiftUI
import UIKit
import SK1Tokens
import SK1UI

/// Five minutes before a meeting: who's in it, what you last met about (with your Echo note from then), and the
/// invite's links and notes, so you walk in knowing the context.
struct PreFlightSheet: View {
    let event: CalendarEvent
    @EnvironmentObject private var store: PhoneStore
    @Environment(\.dismiss) private var dismiss
    @State private var brief: PreFlightBrief?
    @State private var buzz = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SK1.Metrics.groupSpacing) {
                header
                TimelineView(.periodic(from: .now, by: 1)) { tl in lcd(now: tl.date) }
                if event.meetURL != nil {
                    PhoneJoinButton(event: event, variant: .orange, size: .large, fillsWidth: true)
                }
                if let brief {
                    if brief.isEmpty {
                        Text("No one else invited, no earlier meeting like it, and nothing in the invite. A clean slate.").sk1Hint()
                    }
                    PreFlightSections(brief: brief, showPeople: true, showNotes: true)
                }
                Button("Got it") { dismiss() }.buttonStyle(.sk1Key())
            }
            .padding(16)
        }
        .sk1Chassis()
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .sensoryFeedback(.impact(weight: .medium), trigger: buzz)
        .onAppear {
            brief = store.preFlight(for: event)
            buzz += 1
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle().fill(Color(hex: event.colorHex)).frame(width: 12, height: 12).padding(.top, 9)
            VStack(alignment: .leading, spacing: 4) {
                Text(event.title).font(.title.bold()).fixedSize(horizontal: false, vertical: true)
                Text("\(event.start.shortTime) – \(event.end.shortTime)").sk1Hint()
            }
            Spacer(minLength: 8)
            Button { dismiss() } label: { Image(systemName: "xmark") }
                .buttonStyle(.sk1Key(.round, size: .small))
                .accessibilityLabel("Close")
        }
    }

    private func lcd(now: Date) -> some View {
        let left = event.start.timeIntervalSince(now)
        let c = SK1CountdownDigits.compact(max(0, left))
        return SK1CountdownLCD(caption: left > 0 ? "Pre-flight · starts in" : "Pre-flight · on now", digits: c.digits, unit: c.unit,
                               live: left <= 0, lamp: .orange, lampBlinking: left <= 120, height: 50,
                               accessibilityText: "Pre-flight. Starts " + RelativeTimeFormatter.string(for: event.start, relativeTo: now))
    }
}

/// The pre-flight brief as groups: people, last time, and what the invite links to. The event screen shows the people
/// and notes itself, so it leaves those out.
struct PreFlightSections: View {
    let brief: PreFlightBrief
    var showPeople = true
    var showNotes = true
    @EnvironmentObject private var store: PhoneStore

    var body: some View {
        if showPeople, !brief.people.isEmpty { peopleGroup }
        if let last = brief.lastTime { lastTimeGroup(last) }
        if !brief.links.isEmpty || (showNotes && brief.notes != nil) { inviteGroup }
    }

    private var peopleGroup: some View {
        let going = brief.people.filter { $0.response == .accepted }.count
        return SKGroup(caption: "Who's in it", note: "\(going) of \(brief.people.count) going") {
            ForEach(Array(brief.people.prefix(12).enumerated()), id: \.offset) { _, p in
                SKRow(title: p.displayName, subtitle: p.isOrganizer ? "Organizer" : p.response.label) {
                    Text(p.initials)
                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(Color(sk1Hex: p.response == .accepted ? SK1.teal : SK1.amber).opacity(0.25)))
                        .accessibilityHidden(true)
                }
            }
            if brief.people.count > 12 {
                Text("And \(brief.people.count - 12) more").sk1Hint()
            }
        }
    }

    private func lastTimeGroup(_ last: CalendarEvent) -> some View {
        let notes = store.echoNotes(for: last)
        return SKGroup(caption: "Last time", note: (brief.match ?? .title).label) {
            SKRow(title: last.title,
                  subtitle: "\(last.start.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())) · \(last.start.shortTime)") {
                SKChip(RelativeTimeFormatter.string(for: last.start, relativeTo: Date()), minWidth: 60)
            }
            if notes.isEmpty {
                Text("No Echo note from then. Leave one after this meeting and it shows up here next time.").sk1Hint()
            }
            ForEach(notes) { n in EchoNoteRow(note: n) }
        }
    }

    private var inviteGroup: some View {
        SKGroup(caption: "From the invite") {
            if !brief.links.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(brief.links) { link in
                        Button { UIApplication.shared.open(link.url) } label: {
                            Label(link.label, systemImage: "arrow.up.forward.square")
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.sk1Key())
                        .accessibilityHint(link.url.absoluteString)
                    }
                }
            }
            if showNotes, let notes = brief.notes {
                Text(EventNotesFormatter.linked(notes))
                    .font(.callout)
                    .tint(Color(sk1Hex: SK1.teal))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
