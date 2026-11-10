import SwiftUI
import SK1Tokens
import SK1UI

/// Settings › Events on the iPhone: the same meeting-first rules and per-source overrides as the Mac's Settings › Events.
struct PhoneEventFilterGroups: View {
    @EnvironmentObject private var store: PhoneStore

    var body: some View {
        SKGroup(caption: "Events · hide or fade",
                note: "These rules apply to Today, Up next, alerts, the Live Activity, widgets and Siri. Use \u{201C}Show anyway\u{201D} on Today to see what was hidden.") {
            PhoneEventFilterRulesEditor(rules: $store.settings.filters.rules)
        }
        SKGroup(caption: "Events · calendar views",
                note: "How the Day, Week and Month views show events these rules hide: Full shows them like any other, Hidden leaves them out.") {
            SKRow(title: "Filtered events") {
                CalendarFadeSlider(fade: $store.settings.filters.calendarFade).frame(width: 190)
            }
        }
        SKGroup(caption: "Events · per source", note: "A source can follow the rules above, have its own, or show everything.") {
            if store.sources.isEmpty {
                SKRow(title: "No sources yet", subtitle: "Allow calendar access to set rules for each source.") {
                    SKLamp(color: .warning, lit: true, label: "No sources")
                }
            } else {
                ForEach(store.sources, id: \.self) { source in
                    PhoneSourceFilterRow(source: source, rule: binding(for: source))
                }
            }
        }
    }

    private func binding(for source: String) -> Binding<SourceFilterRule> {
        Binding(get: { store.settings.filters.sources[source] ?? SourceFilterRule(rules: store.settings.filters.rules) },
                set: { new in store.settings.filters.sources[source] = new.mode == .defaults ? nil : new })
    }
}

/// One source: which rules it follows, and its own rules (in a tray under it) when custom.
private struct PhoneSourceFilterRow: View {
    let source: String
    @Binding var rule: SourceFilterRule

    private var name: String {
        AppleCalendarClient.isApple(source) ? String(source.dropFirst(AppleCalendarClient.sourcePrefix.count)) : source
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SKRow(title: name) {
                SKPicker(selection: $rule.mode,
                         options: SourceFilterMode.allCases.map { SKPicker<SourceFilterMode>.Option($0, $0.title) },
                         stepper: false)
            }
            if rule.mode == .custom {
                SKWell {
                    VStack(spacing: 0) { PhoneEventFilterRulesEditor(rules: $rule.rules) }
                        .padding(.horizontal, SK1.Metrics.rowInset)
                }
                .padding(.bottom, 10)
            }
        }
    }
}

/// The rule switches and the ignored keywords; shared by the default rules and custom per-source ones.
struct PhoneEventFilterRulesEditor: View {
    @Binding var rules: EventFilterRules
    @State private var keywords = ""

    var body: some View {
        SKRow(title: "Hide events I declined") {
            Toggle("Hide events I declined", isOn: $rules.hideDeclined).labelsHidden().toggleStyle(.sk1Switch)
        }
        SKRow(title: "Hide all-day events") {
            Toggle("Hide all-day events", isOn: $rules.hideAllDay).labelsHidden().toggleStyle(.sk1Switch)
        }
        SKRow(title: "Hide events without a join link") {
            Toggle("Hide events without a join link", isOn: $rules.hideWithoutLink).labelsHidden().toggleStyle(.sk1Switch)
        }
        SKRow(title: "Hide events where I'm the only attendee") {
            Toggle("Hide events where I'm the only attendee", isOn: $rules.hideSolo).labelsHidden().toggleStyle(.sk1Switch)
        }
        SKRow(title: "Show tentative events faded", subtitle: "Events you replied Maybe to.") {
            Toggle("Show tentative events faded", isOn: $rules.dimTentative).labelsHidden().toggleStyle(.sk1Switch)
        }
        SKRow(title: "Ignore titles containing", subtitle: "Separate words with commas.") {
            SKTextField("Ignore titles containing", text: $keywords, prompt: "Lunch, Focus, Commute")
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .frame(maxWidth: 180)
                // Saved when typing stops, not on every key: each settings change reschedules the alerts.
                .onSubmit { rules.keywordText = keywords }
                .task(id: keywords) {
                    try? await Task.sleep(for: .milliseconds(800))
                    guard !Task.isCancelled, rules.keywordText != keywords else { return }
                    rules.keywordText = keywords
                }
                .onAppear { keywords = rules.keywordText }
        }
    }
}
