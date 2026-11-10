import SwiftUI
import SK1Tokens
import SK1UI

/// Colours and small parts shared by the widgets and the Live Activity.
enum WidgetStyle {
    static var lcdInk: Color { Color(sk1Hex: SK1.lcdInk) }
    static var glass: LinearGradient {
        LinearGradient(colors: [Color(sk1Hex: SK1.glassTop), Color(sk1Hex: SK1.glassMiddle), Color(sk1Hex: SK1.glassBottom)],
                       startPoint: .top, endPoint: .bottom)
    }
    static var orange: Color { Color(sk1Hex: SK1.orange) }
    static var teal: Color { Color(sk1Hex: SK1.teal) }
    static var red: Color { Color(sk1Hex: SK1.recRed) }

    /// "#4285F4" → a colour (unreadable → Google blue).
    static func color(_ hex: String) -> Color {
        var s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        return Color(sk1Hex: UInt32(s, radix: 16).map { $0 & 0xFFFFFF } ?? 0x4285F4)
    }

    /// The lamp's colour as a meeting nears, as on the app's "Starts in" card: teal, orange within 15 minutes, red
    /// while it's on.
    static func lamp(for m: WidgetMeeting, now: Date) -> Color {
        if m.start <= now { return red }
        return m.start.timeIntervalSince(now) <= 15 * 60 ? orange : teal
    }
}

/// LCD glass with a bezel, drawn with plain shapes so it renders in a widget.
struct WidgetLCD<Content: View>: View {
    var radius: CGFloat = 8
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(WidgetStyle.glass, in: RoundedRectangle(cornerRadius: radius - 3, style: .continuous))
            .padding(3)
            .background(Color(sk1Hex: 0x2b2a27), in: RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

/// The tape: the hours ahead as a strip of half-hour LEDs, lit where there's a meeting, with every third hour printed
/// under it when `scale` is on. The first LED is the half hour it is now.
struct WidgetTape: View {
    let slots: [WidgetTapeSlot]
    var height: CGFloat = 6
    var scale = true
    /// A free half hour.
    let idle: Color
    /// A taken one, from its meeting's colour.
    let lit: (String) -> Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 1.5) {
                ForEach(slots, id: \.start) { slot in
                    RoundedRectangle(cornerRadius: 1, style: .continuous)
                        .fill(slot.colorHex.map(lit) ?? idle)
                        .frame(height: height)
                }
            }
            if scale {
                // The same columns as the LEDs, so each hour sits under its own.
                HStack(spacing: 1.5) {
                    ForEach(Array(slots.enumerated()), id: \.element.start) { i, slot in
                        Color.clear.frame(height: 8).overlay(alignment: .leading) {
                            // Not on the last LEDs, where it would run off the edge.
                            if i < slots.count - 2, let label = slot.label() {
                                Text(label).font(.system(size: 7.5, weight: .heavy)).monospacedDigit().fixedSize()
                                    .opacity(0.65)
                            }
                        }
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// A key on the chassis, as wide as the widget: cream and raised, or orange when it's the one to press.
struct WidgetKey<Label: View>: View {
    var lit = false
    @ViewBuilder var label: () -> Label
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        HStack(spacing: 4) { label() }
            .lineLimit(1)
            .foregroundStyle(lit ? Color.white : Color.primary)
            .padding(.horizontal, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 20)
            .background(lit ? WidgetStyle.orange : Color.white.opacity(scheme == .dark ? 0.1 : 0.6), in: shape)
            .overlay(shape.strokeBorder(Color.black.opacity(0.14), lineWidth: 0.5))
            // The key's front edge, below its top.
            .background(Color.black.opacity(scheme == .dark ? 0.5 : 0.22), in: shape.offset(y: 2))
            .padding(.bottom, 2)
    }
}
