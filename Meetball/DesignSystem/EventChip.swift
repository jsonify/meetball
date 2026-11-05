import SwiftUI
import SK1Tokens
import SK1UI

/// Colours for an event chip: the calendar's colour as a light tint behind the text and a solid bar at the leading
/// edge, with the text in a shade of the calendar's colour picked to read at 4.5:1 or better on that tint.
public enum EventChipColors {
    /// How strongly the calendar colour tints the chip.
    public static let tint = 0.24
    public static let minimumContrast = 4.5

    /// "#4285F4" → 0x4285F4 (3-digit and missing "#" allowed; unreadable → Google blue).
    public static func rgb(_ hex: String) -> UInt32 {
        var s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        return UInt32(s, radix: 16).map { $0 & 0xFFFFFF } ?? 0x4285F4
    }

    /// The chip's background: the calendar colour over the chassis at `tint`.
    public static func background(_ color: UInt32, dark: Bool) -> SK1.RGB {
        mix(SK1.RGB(hex: SK1.palette(dark: dark).chassis), SK1.RGB(hex: color), tint)
    }

    /// The calendar colour, moved toward the palette's ink until it reads on the chip's background.
    public static func text(_ color: UInt32, dark: Bool) -> SK1.RGB {
        let bg = background(color, dark: dark)
        let ink = SK1.RGB(hex: SK1.palette(dark: dark).ink)
        let base = SK1.RGB(hex: color)
        for step in 0...10 {
            let c = mix(base, ink, Double(step) / 10)
            if SK1.contrast(c, bg) >= minimumContrast { return c }
        }
        return ink
    }

    /// `a` moved toward `b` by `t` (0 = a, 1 = b).
    static func mix(_ a: SK1.RGB, _ b: SK1.RGB, _ t: Double) -> SK1.RGB {
        SK1.RGB(r: a.r + (b.r - a.r) * t, g: a.g + (b.g - a.g) * t, b: a.b + (b.b - a.b) * t)
    }
}

extension Color {
    init(sk1RGB c: SK1.RGB, opacity: Double = 1) {
        self.init(.sRGB, red: c.r / 255, green: c.g / 255, blue: c.b / 255, opacity: opacity)
    }
}

/// A tinted event chip with a coloured leading bar (month spans, all-day bars, all-day pills).
struct EventChipBackground: ViewModifier {
    let hex: String
    var radius: CGFloat = 4
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        let color = EventChipColors.rgb(hex)
        let dark = scheme == .dark
        content
            .foregroundStyle(Color(sk1RGB: EventChipColors.text(color, dark: dark)))
            .padding(.leading, 3)
            .background(Color(sk1RGB: EventChipColors.background(color, dark: dark)), in: RoundedRectangle(cornerRadius: radius))
            .overlay(alignment: .leading) {
                UnevenRoundedRectangle(topLeadingRadius: radius, bottomLeadingRadius: radius)
                    .fill(Color(sk1Hex: color)).frame(width: 3)
            }
    }
}

extension View {
    func eventChip(_ hex: String, radius: CGFloat = 4) -> some View { modifier(EventChipBackground(hex: hex, radius: radius)) }
}
