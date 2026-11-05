import SwiftUI
import SK1Tokens
import SK1UI

/// The Settings sidebar, as Skreener's (`SettingsWindow.buildSidebar`): the LCD naming the pane, the panes' keys in a
/// sunken tray, and About's key in a tray of its own at the bottom; 14 pt from the left, 12 from the groove.
struct SettingsSidebar: View {
    @Binding var selection: SettingsTab

    var body: some View {
        VStack(spacing: 12) {
            SettingsSidebarLCD(section: selection.title)
            tray(SettingsTab.navigation)
            Spacer(minLength: 0)
            tray([.about])
        }
        .padding(.leading, 14)
        .padding(.trailing, 12)
        .padding(.vertical, 14)
        .frame(width: SK1.Metrics.sidebarWidth)
        .frame(maxHeight: .infinity)
    }

    /// A sunken tray of keys, 6 pt apart, 7 pt in (8 at the bottom).
    private func tray(_ tabs: [SettingsTab]) -> some View {
        SKWell {
            VStack(spacing: 6) {
                ForEach(tabs) { tab in
                    SettingsNavKey(tab: tab, selected: selection == tab) { selection = tab }
                }
            }
            .padding(.horizontal, 7)
            .padding(.top, 7)
            .padding(.bottom, 8)
        }
    }
}

/// The sidebar's LCD (Skreener's `SettingsLCD`): "MB-1 · SETTINGS" in small mono over the pane's name, 46 pt tall.
private struct SettingsSidebarLCD: View {
    let section: String

    var body: some View {
        SKLCD(radius: 8, inset: 4) {
            VStack(alignment: .leading, spacing: 0) {
                Text("\(SK1Nickname.meetball) \u{00B7} SETTINGS")
                    .font(.system(size: 8.5, weight: .semibold, design: .monospaced)).tracking(0.6)
                    .foregroundStyle(Color(sk1Hex: SK1.lcdInk, opacity: 0.65))
                    .frame(height: 12, alignment: .top)
                Text(section.uppercased())
                    .font(.system(size: 11.5, weight: .semibold, design: .monospaced)).tracking(0.3)
                    .foregroundStyle(Color(sk1Hex: SK1.lcdInk))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.leading, 8)
            .padding(.top, 4)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(height: 46)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Settings pane"))
        .accessibilityValue(Text(section))
    }
}

/// A key in the sidebar (Skreener's `SettingsNavKey`): a cream key 30 pt tall with a lamp 9 pt in, the pane's symbol
/// (11 pt semibold) centred 29 pt in and its name (12.5 pt medium) 42 pt in. The pane shown has its key down, its lamp
/// lit orange and a glowing orange bar along the face 10 pt in from each side; under the pointer the lamp glows teal.
private struct SettingsNavKey: View {
    let tab: SettingsTab
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let p = SK1.palette(for: scheme)
        Button(action: action) {
            ZStack(alignment: .leading) {
                SKLamp(color: selected ? .orange : .teal, lit: selected || hovering, glow: 4, size: 6)
                    .padding(.leading, 9)
                Image(systemName: tab.symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 16)
                    .padding(.leading, 21)
                Text(tab.title)
                    .font(.system(size: 12.5, weight: .medium))
                    .tracking(0)
                    .textCase(nil)
                    .padding(.leading, 42)
            }
            .foregroundStyle(Color(sk1Hex: p.keyInk))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .overlay(alignment: .bottom) {
                if selected {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color(sk1Hex: SK1.orange))
                        .frame(height: 2)
                        .shadow(color: Color(sk1Hex: SK1.orange), radius: 2)
                        .padding(.horizontal, 10)
                        .padding(.bottom, 4)
                }
            }
            // The key pads its label 10 pt each side; the layout above is measured from the face's edge.
            .padding(.horizontal, -10)
        }
        .buttonStyle(.sk1Key(isOn: selected))
        .onHover { hovering = $0 }
        .accessibilityLabel(Text(tab.title))
    }
}
