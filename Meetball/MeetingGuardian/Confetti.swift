import SwiftUI
import SK1Tokens
import SK1UI

// Shared with the iPhone app (MeetballPhone), which throws the same confetti when a meeting is cancelled.

/// Confetti pieces, deterministic per index so every frame agrees.
struct ConfettiPiece {
    let x: Double, delay: Double, speed: Double, drift: Double, spin: Double, size: Double, color: Color, round: Bool

    static let palette: [Color] = [Color(sk1Hex: SK1.orange), Color(sk1Hex: SK1.teal), Color(sk1Hex: SK1.amber),
                                   Color(sk1Hex: SK1.recRed), Color(sk1Hex: SK1.glassTop), Color(hex: "#7C4DFF")]

    static func make(_ count: Int) -> [ConfettiPiece] {
        var rng = SplitMix(seed: 0x5EED)
        return (0..<count).map { i in
            ConfettiPiece(x: rng.next(), delay: rng.next() * 0.9, speed: 0.55 + rng.next() * 0.6, drift: rng.next() * 2 - 1,
                          spin: (rng.next() * 2 - 1) * 9, size: 6 + rng.next() * 7, color: palette[i % palette.count],
                          round: i % 3 == 0)
        }
    }
}

/// A small seeded generator (values in 0..<1).
struct SplitMix {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> Double {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        z ^= z >> 31
        return Double(z >> 11) / Double(1 << 53)
    }
}

/// Confetti bursting up from the bottom of the view and falling back with a sideways drift, fading out over the last
/// 0.8 s of `duration`. Draws nothing after that.
struct ConfettiBurst: View {
    let start: Date
    var duration: TimeInterval = 4.5
    var count = 160
    private var pieces: [ConfettiPiece] { ConfettiPiece.make(count) }

    var body: some View {
        let pieces = self.pieces
        TimelineView(.animation) { tl in
            Canvas { ctx, size in
                let t = tl.date.timeIntervalSince(start)
                guard t < duration else { return }
                for p in pieces {
                    let life = t - p.delay
                    guard life > 0 else { continue }
                    let h = size.height
                    let y = h - (p.speed * h * 1.9 * life - 0.5 * 1.6 * h * life * life)
                    guard y < h + 20 else { continue }
                    let x = p.x * size.width + p.drift * 160 * life
                    var piece = ctx
                    piece.translateBy(x: x, y: y)
                    piece.rotate(by: .radians(p.spin * life))
                    piece.opacity = max(0, min(1, (duration - t) / 0.8))
                    let rect = CGRect(x: -p.size / 2, y: -p.size / 4, width: p.size, height: p.size / (p.round ? 1 : 2))
                    piece.fill(p.round ? Path(ellipseIn: rect) : Path(rect), with: .color(p.color))
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
