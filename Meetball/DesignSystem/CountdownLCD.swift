import SwiftUI
import SK1Tokens
import SK1UI

// Shared with the iPhone app (MeetballPhone).

/// One line of LCD: a lamp and a caption at the left, seven-segment digits (with their unit) or short mono text at the right.
struct SK1CountdownLCD: View {
    let caption: String
    /// Seven-segment text: digits, ":" and "-" only.
    var digits: String?
    var unit: String?
    /// Shown instead of digits ("NOW", "3 MIN AGO").
    var text: String?
    /// Red and blinking while the meeting is under way; teal while waiting.
    var live = false
    /// Overrides the lamp `live` picks (the menu bar's next-meeting card turns it amber as the start nears).
    var lamp: SKLampColor? = nil
    var lampBlinking: Bool? = nil
    var height: CGFloat = 40
    /// What VoiceOver reads for the whole display.
    let accessibilityText: String

    private var ink: Color { Color(sk1Hex: SK1.lcdInk) }

    var body: some View {
        SKLCD {
            HStack(spacing: 6) {
                SKLamp(color: lamp ?? (live ? .danger : .success), lit: true, glow: 0, size: 5, blinking: lampBlinking ?? live)
                Text(caption.uppercased())
                    .font(.system(size: 9.5, weight: .heavy)).tracking(1.1)
                    .foregroundStyle(ink).lineLimit(1)
                Spacer(minLength: 6)
                if let digits {
                    HStack(alignment: .bottom, spacing: 3) {
                        SKSevenSegment(digits, digitHeight: max(10, height - 20), spacing: 3)
                        if let unit { Text(unit).font(.system(size: 9, weight: .heavy)).foregroundStyle(ink) }
                    }
                } else if let text {
                    Text(text.uppercased())
                        .font(.sk1(SK1.TypeScale.lcdMono)).tracking(SK1.TypeScale.lcdMono.kern)
                        .foregroundStyle(ink).lineLimit(1)
                }
            }
            .padding(.horizontal, 10)
        }
        .frame(height: height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityText))
    }
}
