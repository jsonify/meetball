import SwiftUI
import SK1Tokens
import SK1UI

// Shared with the iPhone app (MeetballPhone): its Today card glows and blinks the same way.

/// How close the menu bar's next meeting is, which sets how loudly its card is drawn.
enum HeroUrgency: Equatable {
    /// More than `soonWindow` away: a quiet teal edge.
    case later
    /// Within `soonWindow`: an orange edge and an amber lamp.
    case soon
    /// Within `imminentWindow`: a brighter, glowing orange edge and a blinking amber lamp.
    case imminent
    /// Under way: glowing orange edge, red blinking lamp.
    case live

    static let soonWindow: TimeInterval = 15 * 60
    static let imminentWindow: TimeInterval = 2 * 60

    static func of(_ event: CalendarEvent, now: Date) -> HeroUrgency {
        of(start: event.start, end: event.end, now: now)
    }

    static func of(start: Date, end: Date, now: Date) -> HeroUrgency {
        if start <= now { return .live }
        let lead = start.timeIntervalSince(now)
        if lead <= imminentWindow { return .imminent }
        if lead <= soonWindow { return .soon }
        return .later
    }

    var lamp: SKLampColor {
        switch self {
        case .later: return .success
        case .soon, .imminent: return .warning
        case .live: return .danger
        }
    }

    var lampBlinks: Bool { self == .imminent || self == .live }

    /// The card's edge: orange once the meeting is near, teal before.
    var edgeColor: Color {
        self == .later ? Color(sk1Hex: SK1.teal) : Color(sk1Hex: SK1.orange)
    }

    var edgeOpacity: Double {
        switch self {
        case .later: return 0.45
        case .soon: return 0.75
        case .imminent, .live: return 1
        }
    }

    var edgeWidth: CGFloat { self == .later ? 1 : 1.5 }

    /// The glow around the card (none while the meeting is still a while off).
    var glow: CGFloat {
        switch self {
        case .later: return 0
        case .soon: return 4
        case .imminent, .live: return 8
        }
    }

    /// A faint wash of the edge colour across the tray, so the card reads as lit from inside.
    var washOpacity: Double {
        switch self {
        case .later: return 0.04
        case .soon: return 0.07
        case .imminent, .live: return 0.10
        }
    }
}
