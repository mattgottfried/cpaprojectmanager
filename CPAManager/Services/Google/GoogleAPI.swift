import Foundation

/// Thin authenticated REST client for the Google APIs the app uses.
struct GoogleAPI {
    let auth: GoogleAuthService

    private func request(_ method: String, _ url: URL, body: Data? = nil) async throws -> (Data, Int) {
        let token = try await auth.validAccessToken()
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw GoogleError.decoding }
        return (data, http.statusCode)
    }

    private func decoded<T: Decodable>(_ type: T.Type, _ result: (Data, Int)) throws -> T {
        guard (200..<300).contains(result.1) else {
            throw GoogleError.http(result.1, String(data: result.0, encoding: .utf8) ?? "Unknown error")
        }
        guard let value = try? JSONDecoder().decode(T.self, from: result.0) else { throw GoogleError.decoding }
        return value
    }

    private func url(_ base: String, _ query: [URLQueryItem] = []) throws -> URL {
        guard var components = URLComponents(string: base) else { throw GoogleError.decoding }
        if !query.isEmpty { components.queryItems = query }
        guard let url = components.url else { throw GoogleError.decoding }
        return url
    }

    // MARK: Gmail

    func gmailMessageIDs(query: String, max: Int = 25) async throws -> [GmailListResponse.Ref] {
        let target = try url("https://gmail.googleapis.com/gmail/v1/users/me/messages", [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "maxResults", value: String(max)),
        ])
        return try decoded(GmailListResponse.self, try await request("GET", target)).messages ?? []
    }

    func gmailMessage(id: String) async throws -> GmailMessage {
        let target = try url("https://gmail.googleapis.com/gmail/v1/users/me/messages/\(id)", [
            URLQueryItem(name: "format", value: "metadata"),
            URLQueryItem(name: "metadataHeaders", value: "From"),
            URLQueryItem(name: "metadataHeaders", value: "Subject"),
            URLQueryItem(name: "metadataHeaders", value: "Date"),
        ])
        return try decoded(GmailMessage.self, try await request("GET", target))
    }

    // MARK: Calendar

    private func calendarBase(_ calendarID: String) -> String {
        let encoded = calendarID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? calendarID
        return "https://www.googleapis.com/calendar/v3/calendars/\(encoded)"
    }

    func calendarList() async throws -> [GoogleCalendarListResponse.Entry] {
        let target = try url("https://www.googleapis.com/calendar/v3/users/me/calendarList", [
            URLQueryItem(name: "minAccessRole", value: "writer"),
        ])
        return try decoded(GoogleCalendarListResponse.self, try await request("GET", target)).items ?? []
    }

    /// Events between `from` and `to` on the primary calendar, in start order.
    func events(from: Date, to: Date, calendarID: String = "primary") async throws -> [CalendarEvent] {
        let iso = ISO8601DateFormatter()
        let target = try url("\(calendarBase(calendarID))/events", [
            URLQueryItem(name: "timeMin", value: iso.string(from: from)),
            URLQueryItem(name: "timeMax", value: iso.string(from: to)),
            URLQueryItem(name: "singleEvents", value: "true"),
            URLQueryItem(name: "orderBy", value: "startTime"),
            URLQueryItem(name: "maxResults", value: "50"),
        ])
        let response = try decoded(GoogleEventsResponse.self, try await request("GET", target))
        return CalendarParsing.events(from: response)
    }

    /// Creates the event, or — if our deterministic ID already exists — updates it.
    func upsertEvent(_ item: CalendarSyncItem, calendarID: String) async throws {
        let base = calendarBase(calendarID)
        let createBody = try JSONSerialization.data(withJSONObject: CalendarSyncPlanner.eventBody(item, includeID: true))
        let created = try await request("POST", try url("\(base)/events"), body: createBody)
        if (200..<300).contains(created.1) { return }
        if created.1 == 409 {   // already exists → patch it
            let patchBody = try JSONSerialization.data(withJSONObject: CalendarSyncPlanner.eventBody(item, includeID: false))
            let patched = try await request("PATCH", try url("\(base)/events/\(item.eventID)"), body: patchBody)
            guard (200..<300).contains(patched.1) else {
                throw GoogleError.http(patched.1, String(data: patched.0, encoding: .utf8) ?? "")
            }
            return
        }
        throw GoogleError.http(created.1, String(data: created.0, encoding: .utf8) ?? "")
    }

    /// Deletes an event we created. Already-gone (404/410) counts as success.
    func deleteEvent(id: String, calendarID: String) async throws {
        let result = try await request("DELETE", try url("\(calendarBase(calendarID))/events/\(id)"))
        guard (200..<300).contains(result.1) || result.1 == 404 || result.1 == 410 else {
            throw GoogleError.http(result.1, String(data: result.0, encoding: .utf8) ?? "")
        }
    }

    // MARK: Drive

    /// One page of files matching a Drive query, in Drive's order. Works across My Drive and
    /// shared drives.
    func driveFiles(query: String, pageSize: Int = 100, pageToken: String? = nil, orderBy: String = "folder,name") async throws -> DriveListResponse {
        var items = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "fields", value: DriveQuery.fields),
            URLQueryItem(name: "pageSize", value: String(pageSize)),
            URLQueryItem(name: "orderBy", value: orderBy),
            URLQueryItem(name: "corpora", value: "allDrives"),
            URLQueryItem(name: "supportsAllDrives", value: "true"),
            URLQueryItem(name: "includeItemsFromAllDrives", value: "true"),
        ]
        if let pageToken { items.append(URLQueryItem(name: "pageToken", value: pageToken)) }
        let target = try url("https://www.googleapis.com/drive/v3/files", items)
        let result = try await request("GET", target)
        guard (200..<300).contains(result.1) else {
            throw GoogleError.http(result.1, String(data: result.0, encoding: .utf8) ?? "")
        }
        guard let response = DriveParsing.decode(result.0) else { throw GoogleError.decoding }
        return response
    }

    /// Creates a new file in Drive (inside `parentID` when given). Only ever creates — it never
    /// overwrites, moves or deletes anything.
    func driveUpload(name: String, mimeType: String, data: Data, parentID: String?) async throws -> DriveFile {
        let boundary = "cpa-" + UUID().uuidString
        let target = try url("https://www.googleapis.com/upload/drive/v3/files", [
            URLQueryItem(name: "uploadType", value: "multipart"),
            URLQueryItem(name: "supportsAllDrives", value: "true"),
            URLQueryItem(name: "fields", value: DriveQuery.fileFields),
        ])
        let token = try await auth.validAccessToken()
        var request = URLRequest(url: target)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(DriveUpload.contentType(boundary: boundary), forHTTPHeaderField: "Content-Type")
        request.httpBody = DriveUpload.multipartBody(name: name, mimeType: mimeType, parentID: parentID, data: data, boundary: boundary)
        let (body, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw GoogleError.decoding }
        guard (200..<300).contains(http.statusCode) else {
            throw GoogleError.http(http.statusCode, String(data: body.prefix(300), encoding: .utf8) ?? "")
        }
        guard let file = DriveParsing.decodeFile(body) else { throw GoogleError.decoding }
        return file
    }

    /// One file or folder's details (used to name a folder the user pasted or picked).
    func driveFile(id: String) async throws -> DriveFile {
        guard DriveQuery.isSafeID(id) else { throw GoogleError.decoding }
        let target = try url("https://www.googleapis.com/drive/v3/files/\(id)", [
            URLQueryItem(name: "fields", value: DriveQuery.fileFields),
            URLQueryItem(name: "supportsAllDrives", value: "true"),
        ])
        let result = try await request("GET", target)
        guard (200..<300).contains(result.1) else {
            throw GoogleError.http(result.1, String(data: result.0, encoding: .utf8) ?? "")
        }
        guard let file = DriveParsing.decodeFile(result.0) else { throw GoogleError.decoding }
        return file
    }
}
