import Foundation

/// Low-level QuickBooks Online REST API client. Handles auth headers and JSON
/// encoding/decoding; `QBOSyncService` builds the actual customer/item/invoice
/// operations on top of this.
struct QBOClient {
    let environment: QBOEnvironment
    let realmID: String
    let accessToken: String

    private var baseURL: String { "\(environment.apiBaseURL)/v3/company/\(realmID)" }

    func query<T: Decodable>(_ sql: String, as type: T.Type) async throws -> T {
        guard var components = URLComponents(string: "\(baseURL)/query") else { throw QBOClientError.decoding }
        components.queryItems = [URLQueryItem(name: "query", value: sql)]
        guard let url = components.url else { throw QBOClientError.decoding }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        applyHeaders(to: &request)
        return try await send(request, as: type)
    }

    func create<Body: Encodable, Response: Decodable>(_ path: String, body: Body, as type: Response.Type) async throws -> Response {
        guard let url = URL(string: "\(baseURL)/\(path)") else { throw QBOClientError.decoding }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        applyHeaders(to: &request)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        return try await send(request, as: type)
    }

    private func applyHeaders(to request: inout URLRequest) {
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
    }

    private func send<T: Decodable>(_ request: URLRequest, as type: T.Type) async throws -> T {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw QBOClientError.decoding }
        guard (200..<300).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw QBOClientError.http(http.statusCode, message)
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw QBOClientError.decoding
        }
    }
}
