import Foundation

/// The app that opens directions to a meeting's place. Google Maps by default.
enum DirectionsApp: String, Codable, CaseIterable, Identifiable {
    case googleMaps, appleMaps, waze

    var id: String { rawValue }

    var title: String {
        switch self {
        case .googleMaps: return "Google Maps"
        case .appleMaps: return "Apple Maps"
        case .waze: return "Waze"
        }
    }

    var shortTitle: String {
        switch self {
        case .googleMaps: return "Google"
        case .appleMaps: return "Apple"
        case .waze: return "Waze"
        }
    }

    /// Driving directions to `destination` (an address or a place's name). The Google Maps and Waze links are universal
    /// links: they open the app when it's installed and the website when it isn't, so no app needs to be present.
    func url(to destination: String) -> URL? {
        let d = destination.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !d.isEmpty else { return nil }
        let q = Self.encode(d)
        switch self {
        case .googleMaps: return URL(string: "https://www.google.com/maps/dir/?api=1&destination=\(q)&travelmode=driving")
        case .appleMaps: return URL(string: "maps://?daddr=\(q)&dirflg=d")
        case .waze: return URL(string: "https://waze.com/ul?q=\(q)&navigate=yes")
        }
    }

    /// Percent-encodes everything but unreserved characters, so "&", "+" and "#" in an address survive.
    private static func encode(_ s: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
    }
}

/// A place picked for a meeting (from a search or an earlier meeting), written back to the event.
struct TripPlace: Equatable, Hashable {
    var name: String
    var address: String? = nil
    var latitude: Double? = nil
    var longitude: Double? = nil

    /// What goes in the event's location: "Riverside Park, 100 River Rd, Springfield", or just the name when the
    /// address adds nothing (a street address found by search is its own name).
    var locationText: String {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let a = address?.trimmingCharacters(in: .whitespacesAndNewlines), !a.isEmpty else { return n }
        if n.isEmpty { return a }
        if a.lowercased().hasPrefix(n.lowercased()) { return a }
        return "\(n), \(a)"
    }
}

/// Which meetings are trips: a place to drive to (Directions), or a game, party or appointment with no place yet
/// (Where's this?). Video calls, meeting rooms and work rituals are left alone.
enum TravelPlanner {
    enum Status: Equatable {
        /// Nothing to drive to.
        case none
        /// A real-world place: offer directions to it.
        case place(String)
        /// Looks like something you travel to, but the event has no place: ask where.
        case ask
    }

    /// How far back, and ahead, to look for the same event's place.
    static let lookbackDays = 120
    static let lookaheadDays = 60
    static let maxSuggestions = 3

    static func status(_ e: CalendarEvent, notTrips: Set<String> = [], now: Date = Date()) -> Status {
        if let place = physicalLocation(e) { return .place(place) }
        let hasLocation = !(e.location?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "").isEmpty
        // A location that isn't a place (a room, a link, "Zoom") means a meeting, not a trip.
        guard !hasLocation, e.meetURL == nil, !e.isDeclined, e.end > now,
              looksLikeTrip(e.title), !notTrips.contains(tripKey(e)) else { return .none }
        return .ask
    }

    /// The event's location when it's somewhere you could drive to.
    static func physicalLocation(_ e: CalendarEvent) -> String? {
        guard let loc = e.location?.trimmingCharacters(in: .whitespacesAndNewlines), isPhysical(loc) else { return nil }
        return loc
    }

    /// Whether a location names a real-world place rather than a link, a call or a meeting room.
    static func isPhysical(_ location: String) -> Bool {
        let l = location.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard l.count >= 3 else { return false }
        if l.contains("://") || l.hasPrefix("www.") { return false }
        if matches(virtualPattern, l) { return false }
        if matches(roomPattern, l) { return false }
        return true
    }

    /// A title that reads like something you go to: a game, a party, an appointment. Work rituals never count.
    static func looksLikeTrip(_ title: String) -> Bool {
        let t = title.lowercased()
        if matches(notTripPattern, t) { return false }
        return matches(tripPattern, t)
    }

    /// What "Not a trip" remembers: the series, or the title without the opponent ("Soccer vs Hawks" → "soccer").
    static func tripKey(_ e: CalendarEvent) -> String {
        if let s = e.seriesID, !s.isEmpty { return "s:" + s }
        return "t:" + titleStem(e.title)
    }

    /// The title cut before an opponent or venue ("U12 Soccer vs Eagles", "U12 Soccer @ Hawks" → "u12 soccer"), so the
    /// same team's games find each other.
    static func titleStem(_ title: String) -> String {
        var t = " " + title.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) + " "
        for cut in [" vs. ", " vs ", " v. ", " v ", " @ ", " at ", " against "] {
            if let r = t.range(of: cut) { t = String(t[..<r.lowerBound]) }
        }
        if let r = t.range(of: "@") { t = String(t[..<r.lowerBound]) }
        return t.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
    }

    /// Places used by earlier (or later) meetings like `e`, newest first: the same series, or the same title stem.
    static func suggestions(for e: CalendarEvent, history: [CalendarEvent]) -> [String] {
        let stem = titleStem(e.title)
        func sameSeries(_ h: CalendarEvent) -> Bool {
            guard let s = e.seriesID, !s.isEmpty else { return false }
            return h.seriesID == s
        }
        let similar = history.filter { h in
            h.uid != e.uid && (sameSeries(h) || (!stem.isEmpty && titleStem(h.title) == stem))
        }
        // The same series first, then nearest in time: last week's practice before last spring's.
        let ordered = similar.sorted {
            let a = (sameSeries($0) ? 0 : 1, abs($0.start.timeIntervalSince(e.start)))
            let b = (sameSeries($1) ? 0 : 1, abs($1.start.timeIntervalSince(e.start)))
            return a < b
        }
        var seen = Set<String>()
        var out: [String] = []
        for h in ordered {
            guard let loc = physicalLocation(h), seen.insert(loc.lowercased()).inserted else { continue }
            out.append(loc)
            if out.count == maxSuggestions { break }
        }
        return out
    }

    /// The events to search for `suggestions`: whole days around the meeting, so one meeting asks for the same range
    /// all day.
    static func historyRange(for e: CalendarEvent, calendar: Calendar = .app) -> DateInterval {
        let day = calendar.startOfDay(for: e.start)
        let from = calendar.date(byAdding: .day, value: -lookbackDays, to: day) ?? day
        let to = calendar.date(byAdding: .day, value: lookaheadDays, to: day) ?? day
        return DateInterval(start: from, end: to)
    }

    // MARK: Patterns

    /// Calls and placeholders, as whole words ("Softball Field" isn't "tba").
    private static let virtualPattern = try! NSRegularExpression(pattern:
        #"\b(zoom|microsoft\s+teams|teams\s+meeting|google\s+meet|meet\.google|webex|facetime|skype|huddle|phone\s+call|dial[\s-]in|conference\s+call|online|virtual|remote|tbd|tba|n/a|my\s+office|my\s+desk)\b"#)

    /// Meeting rooms: "Conf Room 4B", "Room 210", "Boardroom", an Exchange room with its capacity "Rainier (10)".
    private static let roomPattern = try! NSRegularExpression(pattern:
        #"\b(conf(erence)?\.?\s*rm|conf(erence)?\s+room|meeting\s+room|board\s?room|room\s*#?\s*\d+|rm\.?\s*\d+|floor\s*\d+|\d+(st|nd|rd|th)\s+floor)\b|\(\d{1,3}\)"#)

    private static let tripPattern = try! NSRegularExpression(pattern:
        #"\b(game|games|game\s?day|match|vs\.?|tournament|tourney|practice|scrimmage|tryouts?|playoffs?|meet-?up|swim\s+meet|track\s+meet|recital|concert|party|birthday|bday|wedding|reception|shower|graduation|funeral|memorial|gala|fundraiser|open\s+house|dinner|brunch|bbq|barbecue|cookout|potluck|picnic|appointment|appt|dentist|doctor|orthodontist|optometrist|physio|physical\s+therapy|vet|haircut|playdate|sleepover|field\s+trip|rehearsal|lessons?)\b|(^|\s)v\s|(^|\s)@\s*\S"#)

    private static let notTripPattern = try! NSRegularExpression(pattern:
        #"\b(stand-?up|sync|1:1|1-1|one\s+on\s+one|retro|sprint|all[\s-]hands|interview|webinar|call|demo|review|office\s+hours|planning|kickoff|onboarding|training|focus|hold|block)\b"#)

    private static func matches(_ re: NSRegularExpression, _ s: String) -> Bool {
        re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil
    }
}
