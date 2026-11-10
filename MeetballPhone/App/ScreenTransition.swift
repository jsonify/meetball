import SwiftUI

/// The move under way between screens, shared by the screen leaving and the one arriving. Planned just before the
/// screen changes; a screen on its way out reads it then, which a transition fixed when the screen was drawn couldn't.
final class ScreenCourse {
    private(set) var move: ScreenMove?
    /// The point a zoom grows out of or shrinks into.
    private(set) var anchor: UnitPoint = .center
    /// Where the screens are drawn, in global coordinates.
    var stage: CGRect = .zero
    /// A day's cell tapped on Month, for the Day grid to grow out of.
    var tapped: CGRect?

    func plan(from: PhoneRootView.Tab, to: PhoneRootView.Tab) {
        defer { tapped = nil }
        move = ScreenMove.between(from, to)
        anchor = .center
        if case .zoomIn = move, let tapped {
            let p = ScreenMove.anchor(of: tapped, in: stage)
            anchor = UnitPoint(x: p.x, y: p.y)
            move = .zoomIn(dive: true)
        }
    }

    var animation: Animation {
        guard let move else { return .easeInOut(duration: 0.25) }
        if case .flip = move { return .easeInOut(duration: move.duration) }
        return .smooth(duration: move.duration)
    }
}

/// One screen giving way to another, as the course says: a zoom between the calendar screens, the Today lid, the flip
/// to Settings. A cross-fade with Reduce Motion.
struct ScreenTransition: Transition {
    let course: ScreenCourse
    /// This screen is Today, the lid.
    var lid = false

    func body(content: Content, phase: TransitionPhase) -> some View {
        content.modifier(ScreenShift(progress: phase.value, move: course.move, lid: lid, anchor: course.anchor,
                                     height: course.stage.height))
    }
}

/// Draws a screen in its pose at `progress` through a move (see `ScreenPose.at`).
private struct ScreenShift: ViewModifier, Animatable {
    var progress: Double
    let move: ScreenMove?
    let lid: Bool
    let anchor: UnitPoint
    let height: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        let pose = ScreenPose.at(progress, move: reduceMotion ? nil : move, lid: lid)
        content
            .overlay {
                Color.black.opacity(pose.shade).ignoresSafeArea().allowsHitTesting(false)
            }
            .overlay {
                // Under the very bottom of the screen, where the lid's chassis ends.
                Color.clear
                    .ignoresSafeArea()
                    .overlay(alignment: .bottom) {
                        LinearGradient(colors: [.black.opacity(0.22), .clear], startPoint: .top, endPoint: .bottom)
                            .frame(height: 28)
                            .offset(y: 28)
                    }
                    .opacity(pose.edge)
                    .allowsHitTesting(false)
            }
            .blur(radius: pose.blur)
            .scaleEffect(pose.scale, anchor: anchor)
            .rotation3DEffect(.degrees(pose.turn), axis: (x: 0, y: 1, z: 0), perspective: 0.45)
            // Past the top of the screen, status bar included.
            .offset(y: -pose.lift * (height + 120))
            .opacity(pose.opacity)
            // Nothing takes a tap while it moves.
            .allowsHitTesting(abs(progress) < 0.01)
    }
}
