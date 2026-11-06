import SwiftUI
import UIKit
import SK1Tokens
import SK1UI

/// A meeting's details: when, where, the Join key, who's coming and the notes.
struct EventDetailSheet: View {
    let event: CalendarEvent
    @EnvironmentObject private var store: PhoneStore
    @Environment(\.dismiss) private var dismiss
    @State private var copied = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SK1.Metrics.groupSpacing) {
                header
                TimelineView(.periodic(from: .now, by: 15)) { tl in countdown(now: tl.date) }
                if event.meetURL != nil {
                    PhoneJoinButton(event: event, variant: .orange, size: .large, fillsWidth: true)
                }
                whenGroup
                if let loc = event.location, !loc.isEmpty { whereGroup(loc) }
                if !event.participants.isEmpty { peopleGroup }
                if let notes = event.notes.map(EventNotesFormatter.plainText), !notes.isEmpty { notesGroup(notes) }
                HStack(spacing: 10) {
                    Button("Open in Calendar") { PhoneJoin.openInCalendar(event) }.buttonStyle(.sk1Key())
                    if let url = event.meetURL {
                        Button("Copy link") {
                            UIPasteboard.general.string = url.absoluteString
                            copied += 1
                        }
                        .buttonStyle(.sk1Key())
                        .sensoryFeedback(.success, trigger: copied)
                    }
                }
            }
            .padding(16)
        }
        .sk1Chassis()
        .presentationDragIndicator(.visible)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle().fill(Color(hex: event.colorHex)).frame(width: 12, height: 12).padding(.top, 9)
            VStack(alignment: .leading, spacing: 4) {
                Text(event.title).font(.title.bold()).fixedSize(horizontal: false, vertical: true)
                    .strikethrough(event.isDeclined)
                if let cal = store.calendars.first(where: { $0.key == event.calendarKey }) {
                    Text(cal.summary).sk1Hint()
                }
            }
            Spacer(minLength: 8)
            Button { dismiss() } label: { Image(systemName: "xmark") }
                .buttonStyle(.sk1Key(.round, size: .small))
                .accessibilityLabel("Close")
        }
    }

    @ViewBuilder
    private func countdown(now: Date) -> some View {
        if event.end > now && !event.isAllDay {
            let live = event.start <= now
            let target = live ? event.end : event.start
            let c = SK1CountdownDigits.compact(target.timeIntervalSince(now))
            let urgency = HeroUrgency.of(event, now: now)
            SK1CountdownLCD(caption: live ? "Now · ends in" : "Starts in", digits: c.digits, unit: c.unit, live: live,
                            lamp: urgency.lamp, lampBlinking: urgency.lampBlinks, height: 50,
                            accessibilityText: (live ? "In progress, ends " : "Starts ")
                                + RelativeTimeFormatter.string(for: target, relativeTo: now))
        }
    }

    private var whenGroup: some View {
        SKGroup(caption: "When") {
            SKRow(title: event.start.formatted(.dateTime.weekday(.wide).month(.wide).day()),
                  subtitle: event.isAllDay ? "All day" : "\(event.start.shortTime) – \(event.end.shortTime)") {
                SKChip(DurationFormatter.string(from: event.start, to: event.end), minWidth: 60)
            }
            if let tz = event.foreignTimeZone() {
                SKRow(title: "Set in \(tz.localizedName(for: .generic, locale: .current) ?? tz.identifier)",
                      subtitle: "\(event.start.shortTime(locale: AppPreferences.locale, timeZone: tz)) there") { EmptyView() }
            }
            if event.recurrence.isRecurring {
                SKRow(title: "Repeats", subtitle: recurrenceText) { Image(systemName: "repeat").foregroundStyle(.secondary) }
            }
        }
    }

    private var recurrenceText: String {
        switch event.recurrence {
        case .daily: return "Every day"
        case .weekly: return "Every week"
        default: return "On a schedule"
        }
    }

    private func whereGroup(_ loc: String) -> some View {
        SKGroup(caption: "Where") {
            SKRow(title: loc) {
                if let url = mapsURL(loc), !loc.lowercased().hasPrefix("http") {
                    Button { UIApplication.shared.open(url) } label: { Image(systemName: "map") }
                        .buttonStyle(.sk1Key(size: .small))
                        .accessibilityLabel("Open in Maps")
                }
            }
        }
    }

    private func mapsURL(_ loc: String) -> URL? {
        var c = URLComponents(string: "maps://")
        c?.queryItems = [URLQueryItem(name: "q", value: loc)]
        return c?.url
    }

    private var peopleGroup: some View {
        let people = event.participants.sorted { ($0.isOrganizer ? 0 : 1, $0.displayName) < ($1.isOrganizer ? 0 : 1, $1.displayName) }
        let going = people.filter { $0.response == .accepted }.count
        return SKGroup(caption: "People", note: "\(going) of \(people.count) going") {
            ForEach(Array(people.prefix(30).enumerated()), id: \.offset) { _, p in
                SKRow(title: p.displayName + (p.isSelf ? " (you)" : ""), subtitle: p.isOrganizer ? "Organizer" : p.response.label) {
                    Image(systemName: p.response.symbol)
                        .foregroundStyle(color(p.response))
                        .accessibilityLabel(p.response.label)
                }
            }
        }
    }

    private func color(_ r: AttendeeResponse) -> Color {
        switch r {
        case .accepted: return Color(sk1Hex: SK1.teal)
        case .declined: return Color(sk1Hex: SK1.recRed)
        case .tentative: return Color(sk1Hex: SK1.amber)
        case .needsAction: return .secondary
        }
    }

    private func notesGroup(_ notes: String) -> some View {
        VStack(alignment: .leading, spacing: SK1.Metrics.captionToWell) {
            SKCaption("Notes", tone: .soft)
            SKWell {
                Text(EventNotesFormatter.linked(notes))
                    .font(.callout)
                    .tint(Color(sk1Hex: SK1.teal))
                    .textSelection(.enabled)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
