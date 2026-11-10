import CoreLocation
import MapKit
import UIKit

/// Drive times from where the iPhone is to a meeting's place, from Apple's directions service, with the traffic it
/// expects at the time you'd leave. Needs location access While Using: Meetball takes a fresh fix while it's open, and
/// in a background refresh uses the last location iOS has.
@MainActor
final class TravelTimes: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var waiting: [CheckedContinuation<CLLocation?, Never>] = []
    /// Places looked up by their location text, kept across launches (a background refresh is often a fresh launch),
    /// so each address is searched once rather than on every refresh.
    private var coordinates: [String: CLLocationCoordinate2D] = [:]
    private static let coordinatesKey = "phone.placeCoordinates"
    /// More places than this and the saved list starts over; trips repeat, so it refills with the ones in use.
    private static let maxSavedPlaces = 100
    private var lastStatus: CLAuthorizationStatus = .notDetermined
    /// Called when location access changes (granted or taken away in Settings).
    var onAuthorizationChange: (() -> Void)?

    override init() {
        super.init()
        lastStatus = manager.authorizationStatus
        coordinates = Self.loadCoordinates()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    var authorization: CLAuthorizationStatus { manager.authorizationStatus }
    var isAuthorized: Bool { authorization == .authorizedWhenInUse || authorization == .authorizedAlways }

    /// Asks for While Using access the first time; later calls do nothing (iOS asks only once).
    func requestAccess() {
        if authorization == .notDetermined { manager.requestWhenInUseAuthorization() }
    }

    /// Where the iPhone is: a recent fix if iOS has one, a fresh one while Meetball is open, else the last one known.
    func currentLocation() async -> CLLocation? {
        guard isAuthorized else { return nil }
        if let last = manager.location, Date().timeIntervalSince(last.timestamp) < 120 { return last }
        guard UIApplication.shared.applicationState == .active else { return manager.location }
        let fix: CLLocation? = await withCheckedContinuation { c in
            waiting.append(c)
            if waiting.count == 1 { manager.requestLocation() }
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(10))
                self?.finish(nil)
            }
        }
        return fix ?? manager.location
    }

    /// The drive from `origin` to `place` (the event's own coordinates when it has them, else a map search near you),
    /// leaving at `departure`. Nil when the place can't be found or there's no route.
    func travelTime(to event: CalendarEvent, place: String, from origin: CLLocation, departure: Date) async -> TimeInterval? {
        guard let destination = await coordinate(for: event, place: place, near: origin) else { return nil }
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: origin.coordinate))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destination))
        request.transportType = .automobile
        if departure > Date() { request.departureDate = departure }
        return try? await MKDirections(request: request).calculateETA().expectedTravelTime
    }

    private func coordinate(for event: CalendarEvent, place: String, near origin: CLLocation) async -> CLLocationCoordinate2D? {
        if let lat = event.locationLatitude, let lon = event.locationLongitude {
            return CLLocationCoordinate2D(latitude: lat, longitude: lon)
        }
        if let hit = coordinates[place] { return hit }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = place
        // Lean towards places near you: "Riverside Park" is the one in your town.
        request.region = MKCoordinateRegion(center: origin.coordinate, latitudinalMeters: 200_000, longitudinalMeters: 200_000)
        guard let item = try? await MKLocalSearch(request: request).start().mapItems.first else { return nil }
        let c = item.placemark.coordinate
        guard CLLocationCoordinate2DIsValid(c) else { return nil }
        if coordinates.count >= Self.maxSavedPlaces { coordinates.removeAll() }
        coordinates[place] = c
        saveCoordinates()
        return c
    }

    private static func loadCoordinates() -> [String: CLLocationCoordinate2D] {
        let saved = UserDefaults.standard.dictionary(forKey: coordinatesKey) as? [String: [Double]] ?? [:]
        return saved.compactMapValues { pair in
            guard pair.count == 2 else { return nil }
            let c = CLLocationCoordinate2D(latitude: pair[0], longitude: pair[1])
            return CLLocationCoordinate2DIsValid(c) ? c : nil
        }
    }

    private func saveCoordinates() {
        UserDefaults.standard.set(coordinates.mapValues { [$0.latitude, $0.longitude] }, forKey: Self.coordinatesKey)
    }

    private func finish(_ location: CLLocation?) {
        let resumed = waiting
        waiting = []
        resumed.forEach { $0.resume(returning: location) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let latest = locations.last
        MainActor.assumeIsolated { finish(latest) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        MainActor.assumeIsolated { finish(nil) }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        MainActor.assumeIsolated {
            // iOS also calls this when the manager is made; only a real change matters.
            guard status != lastStatus else { return }
            lastStatus = status
            onAuthorizationChange?()
        }
    }
}
