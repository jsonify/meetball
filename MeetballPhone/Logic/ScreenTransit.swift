import CoreGraphics

/// How one screen gives way to another. The calendar screens are the same days seen closer or further off, so moving
/// between them zooms; Today is a lid that comes down over the calendar; Settings is on the back of the chassis.
enum ScreenMove: Equatable {
    /// To a closer look (Month → Week → Day). `dive`: into the day that was tapped, rather than the middle.
    case zoomIn(dive: Bool)
    /// To a wider look (Day → Week → Month).
    case zoomOut
    /// Today comes down over the calendar, or lifts off it.
    case lid
    /// The chassis turns over, to Settings (`forward`) or back from it.
    case flip(forward: Bool)

    typealias Tab = PhoneRootView.Tab

    /// The move from one screen to another; nil when it's the same screen.
    static func between(_ from: Tab, _ to: Tab) -> ScreenMove? {
        guard from != to else { return nil }
        if to == .settings { return .flip(forward: true) }
        if from == .settings { return .flip(forward: false) }
        if to == .today || from == .today { return .lid }
        return span(to) < span(from) ? .zoomIn(dive: false) : .zoomOut
    }

    /// How much time a calendar screen takes in, smallest first.
    private static func span(_ tab: Tab) -> Int {
        switch tab {
        case .today: return 0
        case .day: return 1
        case .week: return 2
        case .month: return 3
        case .settings: return 4
        }
    }

    /// Seconds the move takes.
    var duration: Double {
        switch self {
        case .zoomIn(let dive): return dive ? 0.5 : 0.42
        case .zoomOut: return 0.42
        case .lid: return 0.46
        case .flip: return 0.6
        }
    }

    /// Where `cell` sits in `stage` (both in the same coordinates), as fractions of the stage's width and height, for
    /// a zoom to grow out of. The middle when the stage has no size yet.
    static func anchor(of cell: CGRect, in stage: CGRect) -> CGPoint {
        guard stage.width > 0, stage.height > 0 else { return CGPoint(x: 0.5, y: 0.5) }
        return CGPoint(x: min(max((cell.midX - stage.minX) / stage.width, 0), 1),
                       y: min(max((cell.midY - stage.minY) / stage.height, 0), 1))
    }
}

/// How a screen is drawn part-way through a move.
struct ScreenPose: Equatable {
    var scale = 1.0
    var opacity = 1.0
    var blur = 0.0
    /// Raised by this share of the screen's height (the lid).
    var lift = 0.0
    /// Degrees turned about the upright axis (the flip).
    var turn = 0.0
    /// Darkened by this much: a panel turning from the light, or the calendar under the lid.
    var shade = 0.0
    /// The shadow under the lid's lower edge.
    var edge = 0.0

    /// The pose at `progress`: -1 before the screen arrives, 0 once it's settled, 1 when it has gone. `lid`: this
    /// screen is Today. With no move (or Reduce Motion, which passes none) screens cross-fade.
    static func at(_ progress: Double, move: ScreenMove?, lid: Bool = false) -> ScreenPose {
        let leaving = progress > 0
        let t = min(abs(progress), 1)
        var pose = ScreenPose()
        switch move {
        case nil:
            pose.opacity = 1 - t
        case .zoomIn(let dive):
            // The screen left behind rushes past the lens; the closer one grows out of the point looked at.
            pose.scale = leaving ? 1 + (dive ? 1.8 : 0.3) * t : 1 - (dive ? 0.6 : 0.14) * t
            pose.opacity = leaving ? max(0, 1 - 1.6 * t) : 1 - t
            pose.blur = (leaving ? 8 : 5) * t
        case .zoomOut:
            pose.scale = leaving ? 1 - 0.14 * t : 1 + 0.3 * t
            pose.opacity = leaving ? max(0, 1 - 1.6 * t) : 1 - t
            pose.blur = (leaving ? 5 : 8) * t
        case .lid:
            if lid {
                pose.lift = t
                pose.edge = t > 0 ? 1 : 0
            } else {
                pose.scale = 1 - 0.06 * t
                pose.opacity = 1 - t
                pose.shade = 0.25 * t
            }
        case .flip(let forward):
            // Edge-on at the half-way point, where one side hands over to the other.
            let half = min(2 * t, 1)
            pose.turn = (leaving == forward ? -1 : 1) * 89.9 * half
            pose.opacity = half < 1 ? 1 : 0
            pose.scale = 1 - 0.1 * half
            pose.shade = 0.35 * half
        }
        return pose
    }
}
