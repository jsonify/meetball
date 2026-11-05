import Foundation

struct GoogleCalendarClient {
    let session: SessionManager
    private let base = "https://www.googleapis.com/calendar/v3"

    enum APIError: LocalizedError {
        case http(Int, String)
        var errorDescription: String? {
            if case .http(let c, let m) = self { return "Calendar API error \(c): \(m)" }
            return nil
        }
    }

    private func request(_ email: String, _ path: String, method: String = "GET",
                         query: [URLQueryItem] = [], body: Data? = nil) async throws -> Data {
        let token = try await session.accessToken(for: email)
        var c = URLComponents(string: base + path)!
        if !query.isEmpty { c.queryItems = query }
        var req = URLRequest(url: c.url!)
        req.httpMethod = method
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body { req.httpBody = body; req.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else { throw APIError.http(code, String(data: data, encoding: .utf8) ?? "") }
        return data
    }

    func calendars(email: String) async throws -> [GCalendar] {
        struct L: Decodable {
            struct I: Decodable {
                let id: String; let summary: String?; let summaryOverride: String?
                let backgroundColor: String?; let accessRole: String?; let primary: Bool?
                let conferenceProperties: CP?
                struct CP: Decodable { let allowedConferenceSolutionTypes: [String]? }
            }
            let items: [I]
        }
        let d = try await request(email, "/users/me/calendarList", query: [.init(name: "minAccessRole", value: "reader")])
        return try JSONDecoder().decode(L.self, from: d).items.map {
            GCalendar(id: $0.id, accountEmail: email, summary: $0.summaryOverride ?? $0.summary ?? $0.id,
                      colorHex: $0.backgroundColor ?? "#4285F4", accessRole: $0.accessRole ?? "reader",
                      isPrimary: $0.primary ?? false,
                      allowsMeet: $0.conferenceProperties?.allowedConferenceSolutionTypes?.contains("hangoutsMeet") ?? false)
        }
    }

    func events(for cal: GCalendar, range: DateInterval) async throws -> [CalendarEvent] {
        struct L: Decodable {
            struct T: Decodable { let dateTime: String?; let date: String?; let timeZone: String? }
            struct A: Decodable {
                let email: String?; let displayName: String?; let responseStatus: String?; let isSelf: Bool?; let organizer: Bool?
                enum CodingKeys: String, CodingKey { case email, displayName, responseStatus, organizer, isSelf = "self" }
            }
            struct O: Decodable {
                let email: String?; let displayName: String?; let isSelf: Bool?
                enum CodingKeys: String, CodingKey { case email, displayName, isSelf = "self" }
            }
            struct EP: Decodable { let entryPointType: String?; let uri: String? }
            struct CD: Decodable { let entryPoints: [EP]? }
            struct I: Decodable {
                let id: String; let summary: String?; let status: String?
                let start: T?; let end: T?; let hangoutLink: String?; let location: String?
                let attendees: [A]?; let htmlLink: String?; let conferenceData: CD?
                let description: String?; let organizer: O?; let recurringEventId: String?
            }
            let items: [I]; let nextPageToken: String?
        }
        let iso = ISO8601DateFormatter()
        let dayF = DateFormatter(); dayF.dateFormat = "yyyy-MM-dd"; dayF.timeZone = .current
        let dtF = ISO8601DateFormatter(); dtF.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var all: [CalendarEvent] = []; var pageToken: String?
        repeat {
            var q: [URLQueryItem] = [.init(name: "timeMin", value: iso.string(from: range.start)),
                                     .init(name: "timeMax", value: iso.string(from: range.end)),
                                     .init(name: "singleEvents", value: "true"), .init(name: "orderBy", value: "startTime"),
                                     .init(name: "maxResults", value: "250")]
            if let pageToken { q.append(.init(name: "pageToken", value: pageToken)) }
            let enc = cal.id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)?.replacingOccurrences(of: "@", with: "%40") ?? cal.id
            let d = try await request(cal.accountEmail, "/calendars/\(enc)/events", query: q)
            let page = try JSONDecoder().decode(L.self, from: d)
            for i in page.items where i.status != "cancelled" {
                func parse(_ t: L.T?) -> (Date, Bool)? {
                    if let s = t?.dateTime { return ((iso.date(from: s) ?? dtF.date(from: s)).map { ($0, false) }) }
                    if let s = t?.date, let dt = dayF.date(from: s) { return (dt, true) }
                    return nil
                }
                guard let (s, allDay) = parse(i.start), let (e, _) = parse(i.end) else { continue }
                let meet = (i.hangoutLink ?? i.conferenceData?.entryPoints?.first(where: { $0.entryPointType == "video" })?.uri).flatMap(URL.init)
                all.append(CalendarEvent(id: i.id, calendarID: cal.id, accountEmail: cal.accountEmail,
                                         title: i.summary ?? "(No title)", start: s, end: e, isAllDay: allDay,
                                         meetURL: meet, location: i.location,
                                         attendees: (i.attendees ?? []).compactMap(\.email),
                                         htmlLink: i.htmlLink.flatMap(URL.init), colorHex: cal.colorHex,
                                         isDeclined: (i.attendees ?? []).contains { $0.isSelf == true && $0.responseStatus == "declined" },
                                         notes: i.description,
                                         organizer: i.organizer.flatMap { $0.displayName ?? $0.email },
                                         participants: (i.attendees ?? []).map {
                                             EventAttendee(email: $0.email, name: $0.displayName,
                                                           response: AttendeeResponse(rawValue: $0.responseStatus ?? "") ?? .needsAction,
                                                           isOrganizer: $0.organizer ?? false, isSelf: $0.isSelf ?? false)
                                         },
                                         organizerIsSelf: i.organizer?.isSelf ?? false,
                                         seriesID: i.recurringEventId,
                                         timeZoneID: i.start?.timeZone))
            }
            pageToken = page.nextPageToken
        } while pageToken != nil
        return all
    }

    func create(_ draft: NewEventDraft) async throws {
        guard let cal = draft.calendar else { throw APIError.http(0, "No calendar selected") }
        let iso = ISO8601DateFormatter()
        var body: [String: Any] = [
            "summary": draft.title.isEmpty ? (draft.isFocusBlock ? "Focus time" : "(No title)") : draft.title,
            "start": ["dateTime": iso.string(from: draft.start)],
            "end": ["dateTime": iso.string(from: draft.end)]]
        if !draft.attendees.isEmpty { body["attendees"] = draft.attendees.map { ["email": $0] } }
        if draft.isFocusBlock { body["transparency"] = "opaque"; body["colorId"] = "8" }
        var q: [URLQueryItem] = []
        if draft.addMeet {
            body["conferenceData"] = ["createRequest": ["requestId": UUID().uuidString,
                                                         "conferenceSolutionKey": ["type": "hangoutsMeet"]]]
            q.append(.init(name: "conferenceDataVersion", value: "1"))
        }
        let enc = cal.id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)?.replacingOccurrences(of: "@", with: "%40") ?? cal.id
        _ = try await request(cal.accountEmail, "/calendars/\(enc)/events", method: "POST", query: q,
                              body: try JSONSerialization.data(withJSONObject: body))
    }

    func delete(_ e: CalendarEvent) async throws {
        let enc = e.calendarID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)?.replacingOccurrences(of: "@", with: "%40") ?? e.calendarID
        _ = try await request(e.accountEmail, "/calendars/\(enc)/events/\(e.id)", method: "DELETE")
    }
}
