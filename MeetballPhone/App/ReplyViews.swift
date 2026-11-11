import EventKit
import EventKitUI
import SwiftUI
import UIKit
import SK1Tokens
import SK1UI

/// "Going?" for a meeting you were invited to: Yes / Maybe / No, showing the reply your calendar holds now.
///
/// iOS lets only Apple's own invitation screen send a reply to the organizer (EventKit can read a reply but not change
/// it), so picking an answer opens that screen with its Accept / Maybe / Decline bar, and the hint says which to tap.
/// Once it closes, the reply is read back from the calendar.
struct ReplyGroup: View {
    let event: CalendarEvent
    @EnvironmentObject private var store: PhoneStore
    /// The reply as last read from the calendar (it can be newer than `event`).
    @State private var reply: AttendeeResponse?
    /// The answer picked here, while Apple's screen is open to send it.
    @State private var wanted: AttendeeResponse?
    @State private var unavailable = false

    var body: some View {
        let current = reply ?? event.selfResponse ?? .needsAction
        let options: [SKSegmented<String>.Option] = [.init(AttendeeResponse.accepted.rawValue, "Yes"),
                                                     .init(AttendeeResponse.tentative.rawValue, "Maybe"),
                                                     .init(AttendeeResponse.declined.rawValue, "No")]
        let selection = Binding<String>(
            get: { current.rawValue },
            set: { raw in
                guard let r = AttendeeResponse(rawValue: raw) else { return }
                if store.storedEvent(for: event) == nil { unavailable = true } else { wanted = r }
            })
        return SKGroup(caption: "Going?", note: note) {
            SKRow(title: current == .needsAction ? "Not answered" : current.label,
                  subtitle: "Your reply") {
                SKSegmented(selection: selection, options: options)
                    .frame(width: 190)
                    .accessibilityLabel("Your reply: \(current.label)")
            }
        }
        .onAppear { reply = store.currentResponse(for: event) }
        .sheet(item: $wanted, onDismiss: { reply = store.currentResponse(for: event) }) { target in
            if let stored = store.storedEvent(for: event) {
                InvitationScreen(event: stored.event, eventStore: stored.store, target: target) {
                    wanted = nil
                }
                .ignoresSafeArea()
            }
        }
        .alert("Can\u{2019}t reply from here", isPresented: $unavailable) {
            Button("Open in Calendar") { PhoneJoin.openInCalendar(event) }
            Button("OK", role: .cancel) {}
        } message: {
            Text("This meeting couldn\u{2019}t be found in your calendar just now. Reply in Calendar instead.")
        }
    }

    /// iOS only lets Apple's own invite screen send a reply, so picking one opens it.
    private var note: String {
        let repeating = event.recurrence.isRecurring || event.seriesID != nil
        return "Picking an answer opens Apple\u{2019}s invite screen, which sends it to the organizer"
            + (repeating ? " and asks whether it's for this meeting or all of them." : ".")
    }
}

extension AttendeeResponse: Identifiable {
    public var id: String { rawValue }

    /// The button on Apple's invitation bar that sends this reply.
    var appleButton: String {
        switch self {
        case .accepted: return "Accept"
        case .tentative: return "Maybe"
        case .declined: return "Decline"
        case .needsAction: return "Accept, Maybe or Decline"
        }
    }
}

/// Apple's event screen for an invitation, whose Accept / Maybe / Decline bar sends your reply. A banner on top says
/// which of them to tap for the answer picked in Meetball.
struct InvitationScreen: UIViewControllerRepresentable {
    let event: EKEvent
    let eventStore: EKEventStore
    let target: AttendeeResponse
    var onFinish: () -> Void

    func makeUIViewController(context: Context) -> UINavigationController {
        let vc = EKEventViewController()
        vc.event = event
        vc.allowsEditing = false
        vc.allowsCalendarPreview = false
        vc.delegate = context.coordinator
        vc.navigationItem.prompt = "Tap \u{201C}\(target.appleButton)\u{201D} at the bottom to reply"
        vc.navigationItem.leftBarButtonItem = UIBarButtonItem(systemItem: .close, primaryAction: UIAction { _ in
            context.coordinator.finish()
        })
        return UINavigationController(rootViewController: vc)
    }

    func updateUIViewController(_ nav: UINavigationController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    final class Coordinator: NSObject, EKEventViewDelegate {
        let onFinish: () -> Void
        private var finished = false
        init(onFinish: @escaping () -> Void) { self.onFinish = onFinish }

        /// Called when a reply is sent (`.responded`), or Done / Close is tapped.
        func eventViewController(_ controller: EKEventViewController, didCompleteWith action: EKEventViewAction) {
            finish()
        }

        func finish() {
            guard !finished else { return }
            finished = true
            onFinish()
        }
    }
}
