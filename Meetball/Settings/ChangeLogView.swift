import SwiftUI
import SK1Tokens
import SK1UI

/// Settings › About › What's new: the change log for this platform, newest first, in a window of its own that scrolls.
/// Shared with MeetballPhone, so it must not use AppKit.
struct ChangeLogGroup: View {
    let platform: ChangeLog.Platform
    var height: CGFloat = 280

    private var entries: [ChangeLog.Entry] { ChangeLog.entries(for: platform) }

    var body: some View {
        SKGroup(caption: "What's new", note: "The most recent changes and new features, newest first. Scroll for older ones.") {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(entries) { entry in
                        ChangeLogEntryView(entry: entry)
                        if entry.id != entries.last?.id { SKGroove() }
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: height)
            .accessibilityLabel(Text("Change log"))
        }
    }
}

private struct ChangeLogEntryView: View {
    let entry: ChangeLog.Entry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(entry.title())
                .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                .foregroundStyle(Color(sk1Hex: SK1.orange))
                .accessibilityAddTraits(.isHeader)
            ForEach(Array(entry.changes.enumerated()), id: \.offset) { _, change in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    SKChip(change.kind.label, minWidth: 52, height: 16)
                        .accessibilityHidden(true)
                    Text(change.text)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(Text("\(change.kind.label.capitalized): \(change.text)"))
            }
        }
    }
}
