import EventKit
import Foundation

/// Adds Echo notes to Reminders as follow-ups, in the default list, due the next working morning. Reminders syncs
/// them through iCloud, so they show up on the Mac too.
@MainActor
enum EchoReminders {
    private static let store = EKEventStore()

    enum Failure: LocalizedError {
        case denied, noList

        var errorDescription: String? {
            switch self {
            case .denied: return "Meetball can't add to Reminders. Turn it on in Settings › Meetball › Reminders."
            case .noList: return "Reminders has no list to add to."
            }
        }
    }

    /// Saves a reminder for `note` and returns its identifier. Asks for Reminders access the first time.
    static func add(_ note: EchoNote) async throws -> String {
        if EKEventStore.authorizationStatus(for: .reminder) != .fullAccess {
            guard (try? await store.requestFullAccessToReminders()) == true else { throw Failure.denied }
        }
        guard let list = store.defaultCalendarForNewReminders() else { throw Failure.noList }
        let r = EKReminder(eventStore: store)
        r.calendar = list
        r.title = Echo.reminderTitle(note)
        r.notes = Echo.reminderNotes(note)
        let due = Echo.dueDate(after: note.meetingEnd)
        r.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: due)
        r.addAlarm(EKAlarm(absoluteDate: due))
        try store.save(r, commit: true)
        return r.calendarItemIdentifier
    }

    /// Removes the reminder made for a note that was deleted, if it's still there.
    static func remove(_ id: String) {
        guard EKEventStore.authorizationStatus(for: .reminder) == .fullAccess,
              let r = store.calendarItem(withIdentifier: id) as? EKReminder else { return }
        try? store.remove(r, commit: true)
    }
}
