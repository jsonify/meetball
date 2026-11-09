import SwiftUI
import UIKit
import SK1Tokens
import SK1UI

/// Opens meeting links on the iPhone. An https Zoom, Teams, Webex or Meet link opens in that service's app when it's
/// installed (universal links), so there's no per-service setting as on the Mac.
enum PhoneJoin {
    static func open(_ url: URL) {
        UIApplication.shared.open(url)
    }

    /// The Calendar app at the event's day (iOS has no link to one event).
    static func openInCalendar(_ event: CalendarEvent) {
        if let url = URL(string: "calshow:\(event.start.timeIntervalSinceReferenceDate)") { UIApplication.shared.open(url) }
    }
}

/// The Join key: the service's name and symbol, a solid thunk when pressed.
struct PhoneJoinButton: View {
    let event: CalendarEvent
    var variant: SK1KeyVariant = .cream
    var size: SK1KeySize = .regular
    var fillsWidth = false
    @State private var joins = 0

    var body: some View {
        if let url = event.meetURL {
            let service = MeetingService.detect(url)
            Button {
                joins += 1
                PhoneJoin.open(url)
            } label: {
                Label(title(service), systemImage: service.symbol)
                    .frame(maxWidth: fillsWidth ? .infinity : nil)
            }
            .buttonStyle(.sk1Key(variant, size: size))
            .sensoryFeedback(.impact(weight: .heavy), trigger: joins)
            .accessibilityLabel(Text("Join on \(service.displayName)"))
        }
    }

    private func title(_ service: MeetingService) -> String {
        size == .small || service == .other ? "Join" : "Join \(service.shortName)"
    }
}

/// The next or current meeting in a sunken tray: the countdown on an LCD, title, time and a big Join key. As on the
/// Mac's menu bar card, its edge turns from teal to a glowing orange as the meeting nears, and blinks in the last two
/// minutes and while it's on (`HeroUrgency`).
struct PhoneHeroCard: View {
    let event: CalendarEvent
    let now: Date
    /// Other meetings at the same time (`MenuAgendaBuilder.overlapping`), listed under the Join key.
    var overlapping: [CalendarEvent] = []
    var open: (CalendarEvent) -> Void = { _ in }
    @EnvironmentObject private var store: PhoneStore

    var body: some View {
        let inProgress = event.start <= now
        let target = inProgress ? event.end : event.start
        let countdown = SK1CountdownDigits.compact(target.timeIntervalSince(now))
        let urgency = HeroUrgency.of(event, now: now)
        let shape = RoundedRectangle(cornerRadius: SK1.Metrics.wellRadius, style: .continuous)
        SKWell {
            VStack(alignment: .leading, spacing: 10) {
                SK1CountdownLCD(caption: inProgress ? "Now · ends in" : "Starts in",
                                digits: countdown.digits, unit: countdown.unit, live: inProgress,
                                lamp: urgency.lamp, lampBlinking: urgency.lampBlinks, height: 58,
                                accessibilityText: (inProgress ? "In progress, ends " : "Starts ")
                                    + RelativeTimeFormatter.string(for: target, relativeTo: now))
                Button { open(event) } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Circle().fill(Color(hex: event.colorHex)).frame(width: 9, height: 9)
                            Text(event.title).font(.title2.bold()).lineLimit(2).multilineTextAlignment(.leading)
                        }
                        HStack(spacing: 12) {
                            Label("\(event.start.shortTime) – \(event.end.shortTime)", systemImage: "clock")
                            if !event.attendees.isEmpty {
                                Label("\(event.attendees.count)", systemImage: "person.2")
                            }
                        }
                        .font(.callout).foregroundStyle(.secondary)
                        if let loc = event.location, !loc.isEmpty, event.meetURL == nil || !loc.contains("http") {
                            Label(loc, systemImage: "mappin.and.ellipse").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        PhoneLeaveLine(event: event, now: now)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if event.meetURL != nil {
                    PhoneJoinButton(event: event, variant: .orange, size: .large, fillsWidth: true)
                } else if store.tripStatus(for: event, now: now) != .none {
                    // Somewhere to drive to: Directions, or Where's this? when the event has no place yet.
                    PhoneTripKey(event: event, variant: .orange, size: .large, fillsWidth: true, ask: open)
                } else {
                    Text("No video link").sk1Hint()
                }
                if !overlapping.isEmpty {
                    PhoneOverlappingList(events: overlapping, now: now, open: open)
                }
            }
            .padding(14)
            .background(shape.fill(urgency.edgeColor.opacity(urgency.washOpacity)))
        }
        .overlay(
            shape.strokeBorder(urgency.edgeColor.opacity(urgency.edgeOpacity), lineWidth: urgency.edgeWidth + 0.5)
                .shadow(color: urgency.edgeColor.opacity(urgency.glow > 0 ? 0.6 : 0), radius: urgency.glow * 1.5)
                .allowsHitTesting(false)
        )
        .animation(.easeInOut(duration: 0.4), value: urgency)
        .sensoryFeedback(.warning, trigger: urgency) { _, new in new == .imminent }
    }
}

/// The meetings that overlap the featured one, under a "Also on now" / "Overlaps" caption, each with its own Join.
struct PhoneOverlappingList: View {
    let events: [CalendarEvent]
    let now: Date
    var open: (CalendarEvent) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            SKGroove().padding(.vertical, 2)
            HStack(spacing: 5) {
                Image(systemName: "rectangle.on.rectangle").font(.caption2)
                SKCaption(OverlapCaption.text(events, now: now), tone: .soft)
            }
            .foregroundStyle(.secondary)
            ForEach(events, id: \.uid) { PhoneAgendaRow(event: $0, now: now, open: open) }
        }
    }
}

/// A meeting in a day list: its colour bar, title, time and "in 20m", and a small Join key.
struct PhoneAgendaRow: View {
    let event: CalendarEvent
    let now: Date
    var open: (CalendarEvent) -> Void = { _ in }
    /// Set by Today, so a tentative meeting is faded and one shown by "Show anyway" says why it's normally hidden.
    @Environment(\.eventFilterSettings) private var filters

    var body: some View {
        let ended = event.end <= now
        let inProgress = event.start <= now && !ended
        let tentativeDimmed = filters.map { EventFilter.isDimmed(event, settings: $0) } ?? false
        let hideReason = filters.flatMap { EventFilter.hideReason(event, settings: $0) }
        HStack(spacing: 10) {
            Button { open(event) } label: {
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 2).fill(Color(hex: event.colorHex)).frame(width: 4, height: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(event.title).font(.body.weight(inProgress ? .semibold : .regular)).lineLimit(1)
                            .strikethrough(event.isDeclined)
                        HStack(spacing: 4) {
                            Text("\(event.start.shortTime) – \(event.end.shortTime)")
                            if inProgress {
                                Text("· now")
                            } else if !ended && event.start.timeIntervalSince(now) < 12 * 3600 {
                                Text("· in \(TimeUntilFormatter.string(until: event.start, now: now))")
                            }
                            if let u = event.meetURL {
                                Image(systemName: MeetingService.detect(u).symbol).foregroundStyle(MeetingService.detect(u).tint)
                            }
                            if let hideReason {
                                Text("· hidden: \(hideReason.label.lowercased())")
                            } else if tentativeDimmed {
                                Text("· maybe")
                            }
                        }
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 4)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if !ended && !event.isDeclined { PhoneJoinButton(event: event, size: .small) }
        }
        .padding(.vertical, 3)
        .opacity(ended || event.isDeclined || tentativeDimmed || hideReason != nil ? 0.5 : 1)
    }
}

/// The red "now" line between meetings.
struct PhoneNowLine: View {
    let now: Date
    var body: some View {
        HStack(spacing: 4) {
            let red = Color(sk1Hex: SK1.recRed)
            Circle().fill(red).frame(width: 7, height: 7)
            Rectangle().fill(red).frame(height: 1)
            Text(now.shortTime).font(.caption2.monospacedDigit()).foregroundStyle(red)
        }
        .padding(.vertical, 2)
        .accessibilityLabel("Now")
    }
}

/// One day of an agenda in a well: all-day chips, then the timed meetings with the now line.
struct PhoneDaySection: View {
    let group: AgendaDayGroup
    let now: Date
    var title: String? = nil
    var open: (CalendarEvent) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: SK1.Metrics.captionToWell) {
            SKCaption(title ?? PhoneAgenda.dayTitle(group.day, now: now), tone: .soft)
            SKWell {
                VStack(alignment: .leading, spacing: 4) {
                    if !group.allDay.isEmpty {
                        FlowWrap(spacing: 5) {
                            ForEach(group.allDay, id: \.uid) { e in
                                Button { open(e) } label: { PhoneAllDayChip(event: e) }.buttonStyle(.plain)
                            }
                        }
                        .padding(.bottom, group.timed.isEmpty ? 0 : 4)
                    }
                    ForEach(Array(group.timed.enumerated()), id: \.element.uid) { i, e in
                        if group.nowLineIndex == i { PhoneNowLine(now: now) }
                        PhoneAgendaRow(event: e, now: now, open: open)
                    }
                    if let n = group.nowLineIndex, n == group.timed.count, !group.timed.isEmpty { PhoneNowLine(now: now) }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

/// An all-day or multi-day event as a tinted chip, with the away/on-call symbol when its title says so.
struct PhoneAllDayChip: View {
    let event: CalendarEvent
    var body: some View {
        HStack(spacing: 4) {
            if let callout = EventCallout.detect(event.title) { Image(systemName: callout.symbol) }
            Text(event.title).lineLimit(1)
        }
        .font(.caption.weight(.medium))
        .padding(.horizontal, 7).padding(.vertical, 3)
        .eventChip(event.colorHex)
        .opacity(event.isDeclined ? 0.5 : 1)
    }
}

/// A screen's heading on the chassis: a caption and the screen's keys.
struct PhoneScreenHeader<Keys: View>: View {
    let title: String
    let detail: String
    @ViewBuilder var keys: () -> Keys

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.largeTitle.bold())
                Text(detail).sk1Hint()
            }
            Spacer(minLength: 8)
            keys()
        }
    }
}
