import SwiftUI
import SK1Tokens
import SK1UI

/// The Settings sidebar, after Skreener's: an LCD naming the section at the top, the sections as keys in a sunken
/// tray, and About in a tray of its own pinned to the bottom.
struct SettingsSidebar: View {
    @Binding var selection: SettingsTab

    var body: some View {
        VStack(spacing: 14) {
            SettingsSidebarLCD(section: selection.title)
            SKWell {
                VStack(spacing: 6) {
                    ForEach(SettingsTab.navigation) { key($0) }
                }
                .padding(8)
            }
            Spacer(minLength: 14)
            SKWell {
                key(.about).padding(8)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 16)
        .frame(width: SK1.Metrics.sidebarWidth + 20)
        .frame(maxHeight: .infinity)
    }

    private func key(_ tab: SettingsTab) -> some View {
        SettingsNavKey(tab: tab, selected: selection == tab) { selection = tab }
    }
}

/// The sidebar's LCD: "MEETBALL · SETTINGS" in small caps over the section's name.
private struct SettingsSidebarLCD: View {
    let section: String
    private var ink: Color { Color(sk1Hex: SK1.lcdInk) }

    var body: some View {
        SKLCD {
            VStack(alignment: .leading, spacing: 3) {
                Text("MEETBALL \u{00B7} SETTINGS")
                    .font(.system(size: 8.5, weight: .semibold, design: .monospaced)).tracking(1.2)
                    .foregroundStyle(ink.opacity(0.7))
                Text(section.uppercased())
                    .font(.system(size: 13, weight: .bold, design: .monospaced)).tracking(0.8)
                    .foregroundStyle(ink)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: 50)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Settings: \(section)"))
    }
}

/// One section's key in the sidebar: a full-width cream key with a lamp, the section's symbol and its name. The
/// chosen section's key stays down with its lamp lit orange and an orange bar under the name; the key under the
/// pointer lights its lamp teal.
private struct SettingsNavKey: View {
    let tab: SettingsTab
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let p = SK1.palette(for: scheme)
        Button(action: action) {
            HStack(spacing: 8) {
                SKLamp(color: selected ? .orange : .teal, lit: selected || hovering, glow: selected ? 4 : 2, size: 5)
                Image(systemName: tab.symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 16)
                Text(tab.title)
                    .font(.system(size: 13, weight: .semibold))
                    .tracking(0)
                    .textCase(nil)
                Spacer(minLength: 0)
            }
            .foregroundStyle(Color(sk1Hex: p.keyInk))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .bottom) {
                if selected {
                    Capsule()
                        .fill(Color(sk1Hex: SK1.orange))
                        .frame(height: 2)
                        .shadow(color: Color(sk1Hex: SK1.orange, opacity: 0.8), radius: 2)
                        .padding(.leading, 2)
                        .padding(.bottom, 4)
                }
            }
        }
        .buttonStyle(.sk1Key(isOn: selected))
        .onHover { hovering = $0 }
        .help(tab.title)
        .accessibilityLabel(Text(tab.title))
    }
}
