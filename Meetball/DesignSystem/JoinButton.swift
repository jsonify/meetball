import SwiftUI

/// The one Join button used everywhere (menu bar, day list, time grid, alerts).
/// Shows the service's colour + name, and opens the link according to the user's per-service preference.
struct JoinButton: View {
    enum Size { case small, regular, large }

    let event: CalendarEvent
    var size: Size = .regular
    var fillsWidth = false
    /// Overrides the default open behaviour (alerts use this to also record "joined" and dismiss).
    var action: (() -> Void)?

    var body: some View {
        if let url = event.meetURL {
            let service = MeetingService.detect(url)
            Button {
                if let action { action() } else { MeetingJoiner.join(url) }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: service.symbol)
                    Text(size == .small ? "Join" : (service == .other ? "Join" : "Join \(service.shortName)"))
                }
                .font(font)
                .padding(.horizontal, size == .large ? 12 : 0)
                .padding(.vertical, size == .large ? 4 : 0)
                .frame(maxWidth: fillsWidth ? .infinity : nil)
            }
            .buttonStyle(.borderedProminent)
            .tint(service.tint)
            .controlSize(controlSize)
            .help("Join on \(service.displayName)")
            .contextMenu { MeetingSecondaryActions(event: event, includeJoin: false) }
        }
    }

    private var font: Font {
        switch size {
        case .small: return .caption.weight(.semibold)
        case .regular: return .body.weight(.semibold)
        case .large: return .title3.weight(.bold)
        }
    }

    private var controlSize: ControlSize {
        switch size {
        case .small: return .small
        case .regular: return .regular
        case .large: return .large
        }
    }
}

/// Secondary actions for an event: join, copy link, open in Google Calendar. Meant for context menus.
struct MeetingSecondaryActions: View {
    let event: CalendarEvent
    var includeJoin = true

    var body: some View {
        if let url = event.meetURL {
            if includeJoin {
                Button("Join on \(MeetingService.detect(url).displayName)") { MeetingJoiner.join(url) }
            }
            Button("Copy Meeting Link") { MeetingJoiner.copyLink(url) }
        }
        if let link = event.htmlLink {
            Button("Open in Google Calendar") { NSWorkspace.shared.open(link) }
        }
    }
}

/// Small coloured icon identifying the meeting service (for dense rows).
struct MeetingServiceBadge: View {
    let url: URL
    var body: some View {
        let s = MeetingService.detect(url)
        Image(systemName: s.symbol).font(.caption2).foregroundStyle(s.tint).help(s.displayName)
    }
}
