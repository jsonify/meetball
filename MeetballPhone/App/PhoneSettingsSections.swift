import SwiftUI
import UIKit
import SK1Tokens
import SK1UI

/// The settings LCD, as on the Mac's Settings sidebar: "MB-1 · SETTINGS" and the build over the section's name, so
/// every section says which version of Meetball is running.
struct PhoneSettingsLCD: View {
    let section: PhoneSettingsSection
    let version: String

    var body: some View {
        let ink = Color(sk1Hex: SK1.lcdInk)
        SKLCD(radius: 8, inset: 4) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text("MB-1 \u{00B7} SETTINGS")
                    Spacer(minLength: 6)
                    Text("V\(version)")
                }
                .font(.system(size: 10, weight: .semibold, design: .monospaced)).tracking(0.6)
                .foregroundStyle(ink.opacity(0.65))
                .lineLimit(1)
                Text(section.title.uppercased())
                    .font(.system(size: 17, weight: .semibold, design: .monospaced)).tracking(0.4)
                    .foregroundStyle(ink)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .frame(height: 52)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Settings, \(section.title)"))
        .accessibilityValue(Text("Meetball \(version)"))
    }
}

/// The sections' keys in a sunken tray, four to a row: each a symbol over its name, the one showing held down with
/// an orange bar.
struct PhoneSettingsKeys: View {
    @Binding var selection: PhoneSettingsSection
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 4)

    var body: some View {
        SKWell {
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(PhoneSettingsSection.allCases) { s in
                    PhoneSettingsKey(section: s, selected: s == selection) { selection = s }
                }
            }
            .padding(7)
        }
    }
}

private struct PhoneSettingsKey: View {
    let section: PhoneSettingsSection
    let selected: Bool
    let action: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: section.symbol).font(.system(size: 13, weight: .semibold))
                Text(section.title)
                    .font(.system(size: 10.5, weight: .medium))
                    .textCase(nil)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .foregroundStyle(Color(sk1Hex: SK1.palette(for: scheme).keyInk))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // The section showing: a glowing orange bar along the bottom of its key, as on the Mac's sidebar.
            .overlay(alignment: .bottom) {
                if selected {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color(sk1Hex: SK1.orange))
                        .frame(height: 2)
                        .shadow(color: Color(sk1Hex: SK1.orange), radius: 2)
                        .padding(.horizontal, 4)
                        .padding(.bottom, 1)
                }
            }
            // The key pads its label each side; give the name the whole face.
            .padding(.horizontal, -6)
        }
        .buttonStyle(.sk1Key(isOn: selected, size: .large))
        .accessibilityLabel(Text(section.title))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Settings › About: which build is running (version, build number, commit and when it was built), to copy into a
/// bug report or to check against TestFlight, and what's changed lately.
struct PhoneAboutGroups: View {
    @State private var copied = 0
    private let version = AppVersion.current

    var body: some View {
        SKGroup(caption: "Meetball for iPhone",
                note: "The build number goes up with every commit, so a newer build always has a bigger number. TestFlight shows the same version and build under Meetball.") {
            SKRow(title: "Version") { value(version.version) }
            SKRow(title: "Build") { value(version.build) }
            SKRow(title: "Commit", subtitle: version.commit == nil ? "Not stamped: built from Xcode rather than make or TestFlight." : nil) {
                value(version.commit ?? "—")
            }
            if let built = version.builtAt {
                SKRow(title: "Built") { value(built.formatted(date: .abbreviated, time: .shortened)) }
            }
            SKRow(title: "Copy for a bug report", subtitle: version.full) {
                Button("Copy") {
                    UIPasteboard.general.string = "\(version.full) · iOS \(UIDevice.current.systemVersion)"
                    copied += 1
                }
                .buttonStyle(.sk1Key(size: .small))
                .sensoryFeedback(.success, trigger: copied)
            }
        }
        SKGroup(caption: "This iPhone") {
            SKRow(title: "iOS") { value(UIDevice.current.systemVersion) }
        }
        ChangeLogGroup(platform: .iPhone, height: 340)
    }

    private func value(_ s: String) -> some View {
        Text(s).font(.system(.body, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled)
    }
}
