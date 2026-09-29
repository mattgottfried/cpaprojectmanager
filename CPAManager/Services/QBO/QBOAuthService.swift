import Foundation
import AuthenticationServices
import Observation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Manages the QuickBooks Online OAuth 2.0 connection: authorization, token
/// exchange, refresh, and Keychain-backed persistence. Client ID/Secret and
/// tokens never leave the device except to talk directly to Intuit.
///
/// Intuit requires an HTTPS redirect URI (custom URL schemes aren't accepted
/// directly), so the authorization flow goes through a small static redirect
/// page Matt hosts himself (see README) which forwards back into the app via
/// the `cpamanager://` URL scheme — that's what `ASWebAuthenticationSession`
/// is watching for below.
@Observable
final class QBOAuthService: NSObject {
    private enum Keys {
        static let clientID = "qboClientID"
        static let clientSecret = "qboClientSecret"
        static let redirectURL = "qboRedirectURL"
        static let environment = "qboEnvironment"
        static let accessToken = "qboAccessToken"
        static let refreshToken = "qboRefreshToken"
        static let realmID = "qboRealmID"
        static let expiresAt = "qboExpiresAt"
    }

    private static let authorizeURL = "https://appcenter.intuit.com/connect/oauth2"
    private static let tokenURL = "https://oauth.platform.intuit.com/oauth2/v1/tokens/bearer"
    private static let scope = "com.intuit.quickbooks.accounting"
    private static let callbackScheme = "cpamanager"

    private(set) var isConnected = false
    private var activeSession: ASWebAuthenticationSession?

    var clientID: String {
        get { KeychainStore.get(Keys.clientID) ?? "" }
        set { KeychainStore.set(newValue, forKey: Keys.clientID) }
    }
    var clientSecret: String {
        get { KeychainStore.get(Keys.clientSecret) ?? "" }
        set { KeychainStore.set(newValue, forKey: Keys.clientSecret) }
    }
    var redirectURLString: String {
        get { KeychainStore.get(Keys.redirectURL) ?? "" }
        set { KeychainStore.set(newValue, forKey: Keys.redirectURL) }
    }
    var environment: QBOEnvironment {
        get { QBOEnvironment(rawValue: KeychainStore.get(Keys.environment) ?? "") ?? .sandbox }
        set { KeychainStore.set(newValue.rawValue, forKey: Keys.environment) }
    }

    override init() {
        super.init()
        isConnected = Self.hasStoredConnection
    }

    private static var hasStoredConnection: Bool {
        KeychainStore.get(Keys.accessToken) != nil && KeychainStore.get(Keys.realmID) != nil
    }

    /// Re-reads the Keychain — a connection made on another device arrives through
    /// iCloud Keychain while the app is already running.
    func refreshConnectionState() {
        isConnected = Self.hasStoredConnection
    }

    // MARK: Connect / disconnect

    @MainActor
    func connect() async throws {
        guard !clientID.isEmpty, !clientSecret.isEmpty, !redirectURLString.isEmpty else {
            throw QBOClientError.http(0, "Enter your Client ID, Client Secret, and Redirect URL first.")
        }

        let state = UUID().uuidString
        var components = URLComponents(string: Self.authorizeURL)
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: Self.scope),
            URLQueryItem(name: "redirect_uri", value: redirectURLString),
            URLQueryItem(name: "state", value: state),
        ]
        guard let authURL = components?.url else { throw QBOClientError.decoding }

        let callbackURL: URL = try await withCheckedThrowingContinuation { continuation in
            let authSession = ASWebAuthenticationSession(
                url: authURL,
                callbackURLScheme: Self.callbackScheme
            ) { url, error in
                if let url {
                    continuation.resume(returning: url)
                } else {
                    continuation.resume(throwing: error ?? QBOClientError.decoding)
                }
            }
            authSession.presentationContextProvider = self
            authSession.prefersEphemeralWebBrowserSession = false
            activeSession = authSession
            authSession.start()
        }

        let items = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?.queryItems
        guard let returnedState = items?.first(where: { $0.name == "state" })?.value, returnedState == state else {
            throw QBOClientError.http(0, "QuickBooks authorization response failed validation.")
        }
        guard let code = items?.first(where: { $0.name == "code" })?.value,
              let realmId = items?.first(where: { $0.name == "realmId" })?.value else {
            throw QBOClientError.http(0, "QuickBooks didn't return an authorization code.")
        }

        try await exchangeCode(code, realmID: realmId)
    }

    func disconnect() {
        for key in [Keys.accessToken, Keys.refreshToken, Keys.realmID, Keys.expiresAt] {
            KeychainStore.remove(key)
        }
        isConnected = false
    }

    // MARK: Token exchange / refresh

    private func exchangeCode(_ code: String, realmID: String) async throws {
        let token = try await requestToken(formBody: [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": redirectURLString,
        ])
        store(token: token, realmID: realmID)
    }

    /// Returns a valid access token and the connected realm, refreshing first if needed.
    func validAccessToken() async throws -> (token: String, realmID: String) {
        guard let realmID = KeychainStore.get(Keys.realmID),
              let accessToken = KeychainStore.get(Keys.accessToken) else {
            throw QBOClientError.notAuthorized
        }

        let expiresAt = KeychainStore.get(Keys.expiresAt)
            .flatMap(Double.init)
            .map { Date(timeIntervalSince1970: $0) } ?? .distantPast

        if expiresAt > Date.now.addingTimeInterval(60) {
            return (accessToken, realmID)
        }

        guard let refreshToken = KeychainStore.get(Keys.refreshToken) else { throw QBOClientError.notAuthorized }
        let newToken = try await requestToken(formBody: [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
        ])
        store(token: newToken, realmID: realmID)
        return (newToken.access_token, realmID)
    }

    private func requestToken(formBody: [String: String]) async throws -> QBOTokenResponse {
        guard let url = URL(string: Self.tokenURL) else { throw QBOClientError.decoding }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let credentials = Data("\(clientID):\(clientSecret)".utf8).base64EncodedString()
        request.setValue("Basic \(credentials)", forHTTPHeaderField: "Authorization")
        request.httpBody = formBody
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")" }
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Token request failed."
            throw QBOClientError.http((response as? HTTPURLResponse)?.statusCode ?? 0, message)
        }
        do {
            return try JSONDecoder().decode(QBOTokenResponse.self, from: data)
        } catch {
            throw QBOClientError.decoding
        }
    }

    private func store(token: QBOTokenResponse, realmID: String) {
        KeychainStore.set(token.access_token, forKey: Keys.accessToken)
        KeychainStore.set(token.refresh_token, forKey: Keys.refreshToken)
        KeychainStore.set(realmID, forKey: Keys.realmID)
        let expiresAt = Date.now.addingTimeInterval(TimeInterval(token.expires_in))
        KeychainStore.set(String(expiresAt.timeIntervalSince1970), forKey: Keys.expiresAt)
        isConnected = true
    }
}

extension QBOAuthService: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        #if canImport(UIKit)
        return UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow } ?? ASPresentationAnchor()
        #else
        return NSApplication.shared.keyWindow ?? ASPresentationAnchor()
        #endif
    }
}
