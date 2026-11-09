import MapKit
import SwiftUI
import UIKit
import SK1Tokens
import SK1UI

// Trips: Directions to a meeting's place, and Where's this? for a game, party or appointment with none. A picked place
// is written back to the event, so Calendar, the Mac and everyone invited see it too.

/// Directions (a place to drive to) or Where's this? (looks like a trip, no place yet), else nothing.
struct PhoneTripKey: View {
    let event: CalendarEvent
    var variant: SK1KeyVariant = .cream
    var size: SK1KeySize = .regular
    var fillsWidth = false
    /// Where's this? opens the event, which asks for the place.
    var ask: (CalendarEvent) -> Void
    @EnvironmentObject private var store: PhoneStore

    var body: some View {
        switch store.tripStatus(for: event) {
        case .place(let place):
            Button { store.openDirections(to: place) } label: {
                Label(size == .small ? "Go" : "Directions", systemImage: "car.fill")
                    .frame(maxWidth: fillsWidth ? .infinity : nil)
            }
            .buttonStyle(.sk1Key(variant, size: size))
            .accessibilityLabel("Directions to \(place) in \(store.settings.directionsApp.title)")
        case .ask:
            Button { ask(event) } label: {
                Label(size == .small ? "Where?" : "Where\u{2019}s this?", systemImage: "mappin.and.ellipse")
                    .frame(maxWidth: fillsWidth ? .infinity : nil)
            }
            .buttonStyle(.sk1Key(variant, size: size))
            .accessibilityHint("Opens the event to pick where it is")
        case .none:
            EmptyView()
        }
    }
}

/// "Leave by 5:36 · 24 min drive" (orange "Leave now" once it's time), for the Up next card. Nothing until a drive
/// time is worked out.
struct PhoneLeaveLine: View {
    let event: CalendarEvent
    let now: Date
    @EnvironmentObject private var store: PhoneStore

    var body: some View {
        if event.start > now, let eta = store.eta(for: event), let leave = store.leaveBy(for: event) {
            let late = leave <= now
            Label((late ? "Leave now" : "Leave by \(leave.shortTime)") + " · " + TravelPlanner.driveText(eta.travelTime),
                  systemImage: "car.fill")
                .font(.callout.weight(.semibold))
                .foregroundStyle(late ? Color(sk1Hex: SK1.orange) : .secondary)
                .lineLimit(1)
        }
    }
}

/// The event screen's Where: the place with Directions, or Where's this? with the places earlier meetings like it were
/// at, a search, and Not a trip. Other locations (a room, a link) are shown as they are.
struct TripWhereSection: View {
    let event: CalendarEvent
    @EnvironmentObject private var store: PhoneStore
    /// The place picked here, shown until the calendar reloads with it.
    @State private var picked: String?
    @State private var suggestions: [String] = []
    @State private var canSave = true
    @State private var searching = false
    @State private var pending: TripPlace?

    var body: some View {
        content
            .onAppear {
                canSave = store.canSavePlace(for: event)
                if store.tripStatus(for: event) == .ask { suggestions = store.placeSuggestions(for: event) }
            }
            .savePlaceFlow(for: event, pending: $pending) { picked = $0 }
            .sheet(isPresented: $searching) {
                PlacePickerSheet(event: event) { picked = $0 }.environmentObject(store)
            }
    }

    @ViewBuilder
    private var content: some View {
        switch picked.map(TravelPlanner.Status.place) ?? store.tripStatus(for: event) {
        case .place(let place): placeGroup(place)
        case .ask: askGroup
        case .none:
            if let loc = event.location?.trimmingCharacters(in: .whitespacesAndNewlines), !loc.isEmpty {
                SKGroup(caption: "Where") { SKRow(title: loc) { EmptyView() } }
            }
        }
    }

    private func placeGroup(_ place: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SKGroup(caption: "Where") {
                SKRow(title: place) {
                    if canSave {
                        Button("Change") { searching = true }.buttonStyle(.sk1Key(size: .small))
                    }
                }
                driveRow(place, now: Date())
            }
            // The screen's one orange key, unless the meeting has a Join key.
            Button { store.openDirections(to: place) } label: {
                Label("Directions in \(store.settings.directionsApp.title)", systemImage: "car.fill").frame(maxWidth: .infinity)
            }
            .buttonStyle(.sk1Key(event.meetURL == nil ? .orange : .cream, size: .large))
        }
    }

    /// "24 min drive" / "Leave by 5:36 PM, with 5 min to park", or what drive times need (location access).
    @ViewBuilder
    private func driveRow(_ place: String, now: Date) -> some View {
        if store.settings.driveTimes, !event.isAllDay, event.start > now {
            if let eta = store.eta(for: event, place: place), let leave = store.leaveBy(for: event, place: place) {
                SKRow(title: TravelPlanner.driveText(eta.travelTime), subtitle: leaveText(leave, eta: eta, now: now)) {
                    SKLamp(color: leave <= now ? .orange : .teal, lit: true, label: leave <= now ? "Leave now" : "On time")
                        .frame(width: 24)
                }
            } else {
                switch store.locationStatus {
                case .notDetermined:
                    SKRow(title: "Leave-by time", subtitle: "Meetball works out the drive from where you are, with traffic.") {
                        Button("Allow") { store.requestLocation() }.buttonStyle(.sk1Key(size: .small))
                    }
                case .denied, .restricted:
                    SKRow(title: "Leave-by time", subtitle: "Needs location: Settings › Apps › Meetball › Location › While Using the App.") {
                        Button("Settings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                        }
                        .buttonStyle(.sk1Key(size: .small))
                    }
                default:
                    // Within a day of the trip, the next refresh works it out.
                    if event.start.timeIntervalSince(now) <= TravelPlanner.etaWindow {
                        SKRow(title: "Leave-by time", subtitle: "Working out the drive…") { EmptyView() }
                    }
                }
            }
        }
    }

    private func leaveText(_ leave: Date, eta: TripETA, now: Date) -> String {
        let buffer = store.settings.leaveBufferMinutes
        let when = leave <= now ? "Leave now" : "Leave by \(leave.shortTime)"
        let park = buffer > 0 ? ", with \(buffer) min to park" : ""
        return "\(when)\(park). Checked \(eta.computedAt.shortTime)."
    }

    private var askGroup: some View {
        SKGroup(caption: "Where\u{2019}s this?",
                note: canSave
                    ? "It looks like somewhere you\u{2019}ll drive to. Pick the place and Meetball saves it to the event, then Directions opens it in \(store.settings.directionsApp.title)."
                    : "This calendar is read-only here, so a place you pick opens in \(store.settings.directionsApp.title) but isn\u{2019}t saved to the event.") {
            ForEach(suggestions, id: \.self) { s in
                SKRow(title: s, subtitle: "Where it was last time") {
                    Button("Use") { pending = TripPlace(name: s) }.buttonStyle(.sk1Key(size: .small))
                }
            }
            SKRow(title: "Find a place", subtitle: "Search by name or address.") {
                Button { searching = true } label: { Image(systemName: "magnifyingglass") }
                    .buttonStyle(.sk1Key(event.meetURL == nil ? .orange : .cream, size: .small))
                    .accessibilityLabel("Find a place")
            }
            SKRow(title: "Not a trip", subtitle: notTripSubtitle) {
                Button("Not a trip") { withAnimation { store.markNotTrip(event) } }.buttonStyle(.sk1Key(size: .small))
            }
        }
    }

    private var notTripSubtitle: String {
        if event.seriesID != nil { return "Stops asking for this repeating event." }
        let stem = TravelPlanner.titleStem(event.title)
        return stem.isEmpty ? "Stops asking for this event." : "Stops asking for events called \u{201C}\(stem)\u{201D}."
    }
}

/// Search for a place (Apple's map search, as you type), or pick one an earlier meeting like this was at. The pick is
/// saved to the event, asking first whether a repeating event's later meetings should get it too.
struct PlacePickerSheet: View {
    let event: CalendarEvent
    /// The location text, once saved (or, on a read-only calendar, opened in the directions app).
    var picked: (String) -> Void
    @EnvironmentObject private var store: PhoneStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var search = PlaceSearch()
    @State private var text = ""
    @State private var suggestions: [String] = []
    @State private var canSave = true
    @State private var pending: TripPlace?
    @State private var resolving: String?

    private var typed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SK1.Metrics.groupSpacing) {
                header
                SKTextField("Place", text: $text, prompt: "Search for a place or address", height: 44)
                    .submitLabel(.search)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .onChange(of: text) { _, q in search.query = q }
                if !canSave {
                    Text("This calendar is read-only here, so the place isn\u{2019}t saved to the event; it opens in \(store.settings.directionsApp.title) straight away.")
                        .sk1Hint()
                }
                if typed.isEmpty && !suggestions.isEmpty {
                    SKGroup(caption: "Last time") {
                        ForEach(suggestions, id: \.self) { s in
                            SKRow(title: s) {
                                Button("Use") { pending = TripPlace(name: s) }.buttonStyle(.sk1Key(size: .small))
                            }
                        }
                    }
                }
                if !search.results.isEmpty { resultsGroup }
                if !typed.isEmpty {
                    SKGroup(caption: search.results.isEmpty ? "No matches yet" : "Or") {
                        SKRow(title: "Use \u{201C}\(typed)\u{201D}", subtitle: "As typed; maps search for it.") {
                            Button("Use") { pending = TripPlace(name: typed) }.buttonStyle(.sk1Key(size: .small))
                        }
                    }
                }
            }
            .padding(16)
        }
        .sk1Chassis()
        .presentationDragIndicator(.visible)
        .onAppear {
            canSave = store.canSavePlace(for: event)
            suggestions = store.placeSuggestions(for: event)
        }
        .savePlaceFlow(for: event, pending: $pending) { place in
            picked(place)
            dismiss()
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Where\u{2019}s this?").font(.title.bold())
                Text("\(event.title) · \(event.start.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())) \(event.start.shortTime)")
                    .sk1Hint().lineLimit(2)
            }
            Spacer(minLength: 8)
            Button { dismiss() } label: { Image(systemName: "xmark") }
                .buttonStyle(.sk1Key(.round, size: .small))
                .accessibilityLabel("Close")
        }
    }

    private var resultsGroup: some View {
        SKGroup(caption: "Places") {
            ForEach(Array(search.results.enumerated()), id: \.offset) { _, c in
                let key = c.title + "|" + c.subtitle
                SKRow(title: c.title, subtitle: c.subtitle.isEmpty ? nil : c.subtitle) {
                    Button(resolving == key ? "…" : "Pick") {
                        resolving = key
                        Task {
                            let place = await search.resolve(c)
                            resolving = nil
                            pending = place
                        }
                    }
                    .buttonStyle(.sk1Key(size: .small))
                    .disabled(resolving != nil)
                }
            }
        }
    }
}

/// Apple's map search as you type (no location permission needed: results lean on the phone's rough region).
@MainActor
final class PlaceSearch: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    @Published private(set) var results: [MKLocalSearchCompletion] = []
    private let searchCompleter = MKLocalSearchCompleter()

    var query = "" {
        didSet {
            let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
            if q.count < 2 {
                searchCompleter.cancel()
                results = []
            } else {
                searchCompleter.queryFragment = q
            }
        }
    }

    override init() {
        super.init()
        searchCompleter.delegate = self
        searchCompleter.resultTypes = [.address, .pointOfInterest]
    }

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        MainActor.assumeIsolated { results = Array(completer.results.prefix(8)) }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        MainActor.assumeIsolated { results = [] }
    }

    /// The place behind a suggestion, with its coordinates when the search finds it (saved to the event's structured
    /// location, which gives Calendar its map and travel time).
    func resolve(_ completion: MKLocalSearchCompletion) async -> TripPlace {
        var place = TripPlace(name: completion.title, address: completion.subtitle.isEmpty ? nil : completion.subtitle)
        if let item = try? await MKLocalSearch(request: MKLocalSearch.Request(completion: completion)).start().mapItems.first {
            let c = item.placemark.coordinate
            if CLLocationCoordinate2DIsValid(c) {
                place.latitude = c.latitude
                place.longitude = c.longitude
            }
        }
        return place
    }
}

extension View {
    /// Saves a place set in `pending` to `event`: straight away for a one-off, after asking for a repeating event (this
    /// one or all future ones). On a read-only calendar it opens directions instead. `saved` gets the location text.
    func savePlaceFlow(for event: CalendarEvent, pending: Binding<TripPlace?>, saved: @escaping (String) -> Void) -> some View {
        modifier(SavePlaceFlow(event: event, pending: pending, saved: saved))
    }
}

private struct SavePlaceFlow: ViewModifier {
    let event: CalendarEvent
    @Binding var pending: TripPlace?
    let saved: (String) -> Void
    @EnvironmentObject private var store: PhoneStore
    @State private var asking = false
    @State private var error: String?

    private var repeating: Bool { event.seriesID != nil || event.recurrence.isRecurring }

    func body(content: Content) -> some View {
        content
            .onChange(of: pending) { _, place in
                guard let place else { return }
                if !store.canSavePlace(for: event) {
                    store.openDirections(to: place.locationText)
                    saved(place.locationText)
                    pending = nil
                } else if repeating {
                    asking = true
                } else {
                    commit(place, futureToo: false)
                }
            }
            .onChange(of: asking) { _, open in
                // Dismissed without a choice: let the same place be picked again.
                if !open { DispatchQueue.main.async { pending = nil } }
            }
            .confirmationDialog("This is a repeating event.", isPresented: $asking, titleVisibility: .visible) {
                Button("Save for This Event Only") { if let p = pending { commit(p, futureToo: false) } }
                Button("Save for All Future Events") { if let p = pending { commit(p, futureToo: true) } }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(pending?.locationText ?? "")
            }
            .alert("Couldn\u{2019}t save the place",
                   isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(error ?? "")
            }
    }

    private func commit(_ place: TripPlace, futureToo: Bool) {
        do {
            try store.savePlace(place, for: event, futureToo: futureToo)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            saved(place.locationText)
        } catch {
            self.error = store.canSavePlace(for: event)
                ? error.localizedDescription
                : "It may have been deleted, or its calendar can no longer be changed."
        }
        pending = nil
    }
}
