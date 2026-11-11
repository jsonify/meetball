import Foundation

/// Puts Echo notes on the to-do list (the Meetball list in Reminders) as follow-ups tied to their meeting, due the next
/// working morning. Reminders syncs them through iCloud, so they show up on the Mac too.
@MainActor
enum EchoReminders {
    /// Adds a to-do for `note` and returns its identifier. Asks for Reminders access the first time.
    static func add(_ note: EchoNote) async throws -> String {
        let meeting = TodoMeeting(uid: note.eventUID, title: note.meetingTitle, start: note.meetingStart)
        return try await TodoStore.shared.add(Echo.reminderTitle(note), meeting: meeting, notes: Echo.reminderNotes(note),
                                              due: Echo.dueDate(after: note.meetingEnd))
    }

    /// Removes the to-do made for a note that was deleted, if it's still there.
    static func remove(_ id: String) {
        TodoStore.shared.delete(id: id)
    }
}
