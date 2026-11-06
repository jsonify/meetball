import SwiftUI
import SK1Tokens
import SK1UI

/// Quick add, as on the Mac: one line of plain English ("Lunch with Anna tomorrow 12:30-1:30"), read back on an LCD as
/// you type, then saved to a calendar.
struct QuickAddSheet: View {
    @EnvironmentObject private var store: PhoneStore
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var calendarID = ""
    @State private var error: String?
    @State private var saved = 0

    private var parsed: QuickAddResult { QuickAddParser.parse(text) }

    var body: some View {
        let result = parsed
        ScrollView {
            VStack(alignment: .leading, spacing: SK1.Metrics.groupSpacing) {
                HStack {
                    Text("Quick add").font(.title.bold())
                    Spacer()
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .buttonStyle(.sk1Key(.round, size: .small))
                        .accessibilityLabel("Close")
                }
                SKTextField("Event", text: $text, prompt: "Lunch with Anna tomorrow 12:30-1:30", height: 44)
                    .submitLabel(.done)
                    .onSubmit(save)
                readout(result)
                if !store.writableCalendars.isEmpty {
                    SKGroup(caption: "Calendar") {
                        SKRow(title: "Add to") {
                            SKPicker(selection: $calendarID,
                                     options: store.writableCalendars.map { SKPicker<String>.Option($0.id, $0.summary) },
                                     stepper: false)
                        }
                    }
                } else {
                    Text("None of your calendars can take new events from Meetball.").sk1Hint()
                }
                if !result.attendees.isEmpty || result.addMeet {
                    Text("Invites and video links aren't sent from the iPhone; add them in the Calendar app.").sk1Hint()
                }
                if let error { Text(error).font(.callout).foregroundStyle(Color(sk1Hex: SK1.recRed)) }
                Button(action: save) {
                    Label("Add to calendar", systemImage: "calendar.badge.plus").frame(maxWidth: .infinity)
                }
                .buttonStyle(.sk1Key(.orange, size: .large))
                .disabled(cleanTitle(result).isEmpty || calendarID.isEmpty)
                .sensoryFeedback(.success, trigger: saved)
                Text("Try: \u{201C}Dentist fri 3pm\u{201D}, \u{201C}Standup tomorrow 9:15 for 15 min\u{201D}, \u{201C}Offsite dec 3\u{201D}.")
                    .sk1Hint()
            }
            .padding(16)
        }
        .sk1Chassis()
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onAppear {
            calendarID = store.defaultCalendarForNewEvents?.id ?? ""
        }
    }

    private func readout(_ r: QuickAddResult) -> some View {
        let day = r.start.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        let time = "\(r.start.shortTime)–\(r.end.shortTime)"
        return SKDisplay(title: text.isEmpty ? "Waiting" : "Reads as",
                         detail: "\(day) · \(time)",
                         message: cleanTitle(r).isEmpty ? "Type a title, a day and a time" : cleanTitle(r),
                         height: 56)
    }

    private func cleanTitle(_ r: QuickAddResult) -> String {
        r.title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func save() {
        let r = parsed
        guard !cleanTitle(r).isEmpty, let cal = store.writableCalendars.first(where: { $0.id == calendarID }) else { return }
        Task {
            do {
                try await store.addEvent(title: cleanTitle(r), start: r.start, end: r.end, calendar: cal)
                saved += 1
                dismiss()
            } catch {
                self.error = "Couldn't save it: \(error.localizedDescription)"
            }
        }
    }
}
