import SwiftUI

/// Settings › Events: the meeting-first rules and per-source overrides.
struct EventFilterSettingsView: View {
    @EnvironmentObject var calendar: CalendarStore

    var body: some View {
        Form {
            Section {
                EventFilterRulesEditor(rules: $calendar.filters.rules)
            } header: {
                Text("Hide or fade")
            } footer: {
                Text("These rules apply to the menu bar title, the menu bar popover, the Upcoming view, the join shortcut and Meeting Guardian alerts. The Day, Week and Month views always show everything. Use \u{201C}Show anyway\u{201D} under a list to see what was hidden.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Per source") {
                if calendar.sources.isEmpty {
                    Text("Connect a Google account or Apple Calendar to set rules for each source.").foregroundStyle(.secondary)
                } else {
                    ForEach(calendar.sources, id: \.self) { source in
                        SourceFilterRow(source: source, rule: binding(for: source))
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func binding(for source: String) -> Binding<SourceFilterRule> {
        Binding(get: { calendar.filters.sources[source] ?? SourceFilterRule(rules: calendar.filters.rules) },
                set: { new in
                    var s = calendar.filters
                    s.sources[source] = new.mode == .defaults ? nil : new
                    calendar.filters = s
                })
    }
}

private struct SourceFilterRow: View {
    let source: String
    @Binding var rule: SourceFilterRule

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker(selection: $rule.mode) {
                ForEach(SourceFilterMode.allCases) { Text($0.title).tag($0) }
            } label: {
                Label(AppleCalendarClient.isApple(source) ? String(source.dropFirst(AppleCalendarClient.sourcePrefix.count)) : source,
                      systemImage: AppleCalendarClient.isApple(source) ? "apple.logo" : "envelope")
            }
            if rule.mode == .custom {
                EventFilterRulesEditor(rules: $rule.rules).padding(.leading, 20)
            }
        }
    }
}

/// The rule toggles, shared by the default rules and custom per-source rules.
struct EventFilterRulesEditor: View {
    @Binding var rules: EventFilterRules
    @State private var keywords = ""

    var body: some View {
        Toggle("Hide events I declined", isOn: $rules.hideDeclined)
        Toggle("Hide all-day events", isOn: $rules.hideAllDay)
        Toggle("Hide events without a join link", isOn: $rules.hideWithoutLink)
        Toggle("Hide events where I'm the only attendee", isOn: $rules.hideSolo)
        Toggle("Show tentative events faded", isOn: $rules.dimTentative)
        LabeledContent("Ignore titles containing") {
            TextField("", text: $keywords, prompt: Text("Lunch, Focus, Commute"))
                .textFieldStyle(.roundedBorder).frame(maxWidth: 240)
                .onSubmit { rules.keywordText = keywords }
                .onChange(of: keywords) { _, v in rules.keywordText = v }
        }
        .onAppear { keywords = rules.keywordText }
    }
}
