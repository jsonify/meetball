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
