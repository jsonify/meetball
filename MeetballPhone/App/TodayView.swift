import SwiftUI
import SK1Tokens
import SK1UI

/// Today: the MB-1 display, the next meeting's "Starts in" card, change cards, and the rest of today and tomorrow.
struct TodayView: View {
    @EnvironmentObject private var store: PhoneStore
    var open: (CalendarEvent) -> Void
    var quickAdd: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 15)) { tl in
            content(now: tl.date)
        }
    }

    private func content(now: Date) -> some View {
        let events = store.events(from: now, days: 2)
        let hero = MenuAgendaBuilder.hero(events, now: now, horizon: 24 * 3600)
        let overlapping = hero.map { MenuAgendaBuilder.overlapping($0, in: events, now: now) } ?? []
        let shownInHero = Set(([hero].compactMap { $0 } + overlapping).map(\.uid))
        let groups = MenuAgendaBuilder.build(events: events, now: now, days: 2, limit: 40, excluding: shownInHero)
        let line = MeetingStatusText.line(events, now: now)
        return VStack(alignment: .leading, spacing: SK1.Metrics.groupSpacing) {
            PhoneScreenHeader(title: "Today", detail: now.formatted(.dateTime.weekday(.wide).month(.wide).day())) {
                Button(action: quickAdd) { Image(systemName: "plus") }
                    .buttonStyle(.sk1Key())
                    .accessibilityLabel("Add an event")
            }
            SKDisplay(title: "MB-1", detail: now.shortTime, message: line.message,
                      number: MeetingStatusText.remainingToday(events, now: now), digits: 2, unit: "LEFT",
                      live: line.live, height: 60)
            if store.calendarAccess != .granted {
                accessNote
            }
            if !store.changeCards.isEmpty { changeCards(now: now) }
            if let hero {
                VStack(alignment: .leading, spacing: SK1.Metrics.captionToWell) {
                    SKCaption(hero.start <= now ? "On now" : "Up next", tone: .soft)
                    PhoneHeroCard(event: hero, now: now, overlapping: overlapping, open: open)
                }
            } else if store.calendarAccess == .granted {
                freeCard
            }
            ForEach(groups) { g in
                PhoneDaySection(group: g, now: now, title: title(for: g, now: now), open: open)
            }
        }
    }

    private func title(for g: AgendaDayGroup, now: Date) -> String {
        let base = PhoneAgenda.dayTitle(g.day, now: now)
        return Calendar.app.isDate(g.day, inSameDayAs: now) ? "Later today" : base
    }

    private var accessNote: some View {
        SKWell {
            VStack(alignment: .leading, spacing: 8) {
                Text("Meetball needs your calendar").font(.headline)
                Text("It reads the calendars in the Calendar app, including a work Google calendar added through iCloud.")
                    .sk1Hint()
                Button("Allow") { Task { await store.requestCalendarAccess() } }.buttonStyle(.sk1Key(.orange))
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var freeCard: some View {
        SKWell {
            VStack(alignment: .leading, spacing: 6) {
                SKLCD {
                    HStack(spacing: 8) {
                        SKLamp(color: .success, lit: true, glow: 0, size: 5)
                        Text("ALL CLEAR").font(.system(size: 13, weight: .heavy, design: .monospaced)).tracking(1.2)
                            .foregroundStyle(Color(sk1Hex: SK1.lcdInk))
                        Spacer()
                    }
                    .padding(.horizontal, 10)
                }
                .frame(height: 40)
                Text("No meetings in the next 24 hours. Go make something.").font(.callout).foregroundStyle(.secondary)
            }
            .padding(14)
        }
    }

    private func changeCards(now: Date) -> some View {
        VStack(alignment: .leading, spacing: SK1.Metrics.captionToWell) {
            HStack {
                SKCaption("Changes", tone: .soft)
                Spacer()
                if store.changeCards.count > 1 {
                    Button("Clear") { withAnimation { store.dismissAllCards() } }.buttonStyle(.sk1Key(size: .small))
                }
            }
            ForEach(store.changeCards) { card in
                ChangeCardView(card: card, now: now) { withAnimation { store.dismissCard(card) } }
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
    }
}

/// One moved, re-linked or cancelled meeting: an LCD saying what happened, the meeting and the details.
struct ChangeCardView: View {
    let card: ChangeCard
    let now: Date
    let dismiss: () -> Void

    private var lamp: SKLampColor {
        switch card.kind {
        case .cancelled: return .orange
        case .moved: return .warning
        case .link: return .teal
        }
    }

    var body: some View {
        SKWell {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    SKLCD {
                        HStack(spacing: 6) {
                            SKLamp(color: lamp, lit: true, glow: 0, size: 5, label: card.caption)
                            Text(card.caption.uppercased()).font(.system(size: 10, weight: .heavy)).tracking(1.1)
                                .foregroundStyle(Color(sk1Hex: SK1.lcdInk))
                            Spacer(minLength: 4)
                            Text(RelativeTimeFormatter.string(for: card.at, relativeTo: now).uppercased())
                                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                .foregroundStyle(Color(sk1Hex: SK1.lcdInk).opacity(0.75))
                        }
                        .padding(.horizontal, 8)
                    }
                    .frame(height: 28)
                    Button(action: dismiss) { Image(systemName: "xmark") }
                        .buttonStyle(.sk1Key(.round, size: .small))
                        .accessibilityLabel("Dismiss")
                }
                Text(card.eventTitle).font(.headline).strikethrough(card.kind == .cancelled)
                Text(card.detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
