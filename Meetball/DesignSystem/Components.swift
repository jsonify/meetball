import SwiftUI
import SK1Tokens
import SK1UI

/// A line in a feature list: a teal lamp (ready, included) and the text.
public struct BulletRow: View {
    let text: String
    public init(_ text: String) { self.text = text }
    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            SKLamp(color: .success, lit: true, size: 6).accessibilityHidden(true)
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
    }
}

public struct StepIndicator: View {
    let count: Int; let current: Int
    public init(count: Int, current: Int) { self.count = count; self.current = current }
    public var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { i in
                Capsule().fill(i == current ? Color(sk1Hex: SK1.orange) : Color.secondary.opacity(0.3))
                    .frame(width: i == current ? 20 : 8, height: 8)
            }
        }
    }
}

/// Wrapping horizontal layout (chips, tags).
public struct FlowWrap: Layout {
    public var spacing: CGFloat
    public init(spacing: CGFloat = 6) { self.spacing = spacing }
    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(proposal.width ?? 300, subviews).size
    }
    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let r = arrange(bounds.width, subviews)
        for (i, p) in r.points.enumerated() {
            subviews[i].place(at: CGPoint(x: bounds.minX + p.x, y: bounds.minY + p.y), proposal: .unspecified)
        }
    }
    private func arrange(_ width: CGFloat, _ subviews: Subviews) -> (size: CGSize, points: [CGPoint]) {
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, maxW: CGFloat = 0
        var pts: [CGPoint] = []
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x + sz.width > width, x > 0 { x = 0; y += rowH + spacing; rowH = 0 }
            pts.append(CGPoint(x: x, y: y))
            x += sz.width + spacing; rowH = max(rowH, sz.height); maxW = max(maxW, x)
        }
        return (CGSize(width: maxW, height: y + rowH), pts)
    }
}
