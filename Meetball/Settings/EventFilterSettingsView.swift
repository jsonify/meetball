import SwiftUI
import SK1Tokens
import SK1UI

/// Settings › Events: the meeting-first rules and per-source overrides, as SK-1 groups of rows.
struct EventFilterSettingsView: View {
    @EnvironmentObject var calendar: CalendarStore

    var body: some View {
        SK1SettingsPane {
            SKGroup(caption: "Hide or fade",
                    note: "These rules apply to the menu bar title, the menu bar popover, the Upcoming view, the join shortcut and Meeting Guardian alerts. Use \u{201C}Show anyway\u{201D} under a list to see what was hidden.") {
                EventFilterRulesEditor(rules: $calendar.filters.rules)
            }
            SKGroup(caption: "Calendar views",
                    note: "How the Day, Week and Month views show events these rules hide: Full shows them like any other, Hidden leaves them out.") {
                SKRow(title: "Filtered events") {
                    CalendarFadeSlider(fade: $calendar.filters.calendarFade).frame(width: 240)
                }
            }
            SKGroup(caption: "Per source", note: "A source can follow the rules above, have its own, or show everything.") {
                if calendar.sources.isEmpty {
                    SKRow(title: "No sources yet", subtitle: "Connect a Google account or Apple Calendar to set rules for each source.") {
                        SKLamp(color: .warning, lit: true, label: "No sources")
                    }
                } else {
                    ForEach(calendar.sources, id: \.self) { source in
                        SourceFilterRow(source: source, rule: binding(for: source))
                    }
                }
            }
        }
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

/// One source: which rules it follows, and its own rules (in a tray under it) when custom.
private struct SourceFilterRow: View {
    let source: String
    @Binding var rule: SourceFilterRule

    private var name: String {
        AppleCalendarClient.isApple(source) ? "Apple Calendar · " + source.dropFirst(AppleCalendarClient.sourcePrefix.count) : source
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SKRow(title: name) {
                SKPicker(selection: $rule.mode, options: SourceFilterMode.allCases.map { SKPicker<SourceFilterMode>.Option($0, $0.title) },
                         stepper: false)
            }
            if rule.mode == .custom {
                SKWell {
                    VStack(spacing: 0) { EventFilterRulesEditor(rules: $rule.rules) }
                        .padding(.horizontal, SK1.Metrics.rowInset)
                }
                .padding(.bottom, 10)
            }
        }
    }
}

/// The rule switches and the ignored keywords, as settings rows; shared by the default rules and custom per-source ones.
struct EventFilterRulesEditor: View {
    @Binding var rules: EventFilterRules
    @State private var keywords = ""

    var body: some View {
        SKRow(title: "Hide events I declined") {
            Toggle("Hide events I declined", isOn: $rules.hideDeclined).toggleStyle(.sk1Switch)
        }
        SKRow(title: "Hide all-day events") {
            Toggle("Hide all-day events", isOn: $rules.hideAllDay).toggleStyle(.sk1Switch)
        }
        SKRow(title: "Hide events without a join link") {
            Toggle("Hide events without a join link", isOn: $rules.hideWithoutLink).toggleStyle(.sk1Switch)
        }
        SKRow(title: "Hide events where I'm the only attendee") {
            Toggle("Hide events where I'm the only attendee", isOn: $rules.hideSolo).toggleStyle(.sk1Switch)
        }
        SKRow(title: "Show tentative events faded", subtitle: "Events you replied Maybe to.") {
            Toggle("Show tentative events faded", isOn: $rules.dimTentative).toggleStyle(.sk1Switch)
        }
        SKRow(title: "Ignore titles containing", subtitle: "Separate words with commas.") {
            SKTextField("Ignore titles containing", text: $keywords, prompt: "Lunch, Focus, Commute", height: 30)
                .frame(width: 220)
                .onSubmit { rules.keywordText = keywords }
                .onChange(of: keywords) { _, v in rules.keywordText = v }
                .onAppear { keywords = rules.keywordText }
        }
    }
}
