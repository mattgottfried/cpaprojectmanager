import Foundation
import AuthenticationServices
import Observation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

enum GoogleError: LocalizedError {
    case notConnected
    case missingClientID
    case http(Int, String)
    case decoding
    case cancelled

    var errorDescription: String? {
        switch self {
        case .notConnected:    return "Google isn't connected."
        case .missingClientID: return "Enter your Google OAuth client ID first (it ends in .apps.googleusercontent.com)."
        case .http(let code, let message): return "Google error (\(code)): \(message)"
        case .decoding:        return "Unexpected response from Google."
        case .cancelled:       return "Sign-in was cancelled."
        }
    }
}

/// Google sign-in (Gmail + Calendar) using the installed-app OAuth flow with PKCE.
/// No client secret is involved; the OAuth client ID is the user's own (created in
/// their Google Cloud project — see README) and tokens live only in the Keychain.
@Observable
final class GoogleAuthService: NSObject {
    private enum Keys {
        static let clientID = "googleClientID"
        static let accessToken = "googleAccessToken"
        static let refreshToken = "googleRefreshToken"
        static let expiresAt = "googleExpiresAt"
        static let email = "googleAccountEmail"
    }

    private static let tokenURL = "https://oauth2.googleapis.com/token"

    private(set) var isConnected = false
    private var activeSession: ASWebAuthenticationSession?

    var clientID: String {
        get { KeychainStore.get(Keys.clientID) ?? "" }
        set { KeychainStore.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: Keys.clientID) }
    }

    var accountEmail: String { KeychainStore.get(Keys.email) ?? "" }

    override init() {
        super.init()
        isConnected = KeychainStore.get(Keys.refreshToken) != nil
    }

    // MARK: Connect / disconnect

    @MainActor
    func connect() async throws {
        guard let redirectURI = GoogleOAuth.redirectURI(clientID: clientID),
              let scheme = GoogleOAuth.redirectScheme(clientID: clientID) else {
            throw GoogleError.missingClientID
        }
        let verifier = GoogleOAuth.makeVerifier()
        let state = UUID().uuidString
        guard let authURL = GoogleOAuth.authorizationURL(
            clientID: clientID, redirectURI: redirectURI, state: state,
            challenge: GoogleOAuth.challenge(for: verifier)
        ) else { throw GoogleError.decoding }

        let callback: URL = try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: authURL, callbackURLScheme: scheme) { url, error in
                if let url {
                    continuation.resume(returning: url)
                } else if let authError = error as? ASWebAuthenticationSessionError, authError.code == .canceledLogin {
                    continuation.resume(throwing: GoogleError.cancelled)
                } else {
                    continuation.resume(throwing: error ?? GoogleError.decoding)
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            activeSession = session
            session.start()
        }

        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems
        guard items?.first(where: { $0.name == "state" })?.value == state else {
            throw GoogleError.http(0, "The sign-in response failed validation.")
        }
        if let error = items?.first(where: { $0.name == "error" })?.value {
            throw GoogleError.http(0, error)
        }
        guard let code = items?.first(where: { $0.name == "code" })?.value else {
            throw GoogleError.http(0, "Google didn't return an authorization code.")
        }

        let token = try await requestToken([
            "grant_type": "authorization_code",
            "code": code,
            "code_verifier": verifier,
            "client_id": clientID,
            "redirect_uri": redirectURI,
        ])
        store(token)
    }

    func disconnect() {
        for key in [Keys.accessToken, Keys.refreshToken, Keys.expiresAt, Keys.email] {
            KeychainStore.remove(key)
        }
        isConnected = false
    }

    // MARK: Tokens

    /// A valid access token, refreshing it first when it's about to expire.
    func validAccessToken() async throws -> String {
        guard let refresh = KeychainStore.get(Keys.refreshToken) else { throw GoogleError.notConnected }

        let expiresAt = KeychainStore.get(Keys.expiresAt)
            .flatMap(Double.init)
            .map { Date(timeIntervalSince1970: $0) } ?? .distantPast
        if let access = KeychainStore.get(Keys.accessToken), expiresAt > Date.now.addingTimeInterval(60) {
            return access
        }

        let token = try await requestToken([
            "grant_type": "refresh_token",
            "refresh_token": refresh,
            "client_id": clientID,
        ])
        store(token)
        return token.access_token
    }

    private func requestToken(_ form: [String: String]) async throws -> GoogleTokenResponse {
        guard let url = URL(string: Self.tokenURL) else { throw GoogleError.decoding }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = form
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "")" }
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            // A revoked/expired refresh token means the user must sign in again.
            if status == 400 || status == 401, form["grant_type"] == "refresh_token" { disconnect() }
            throw GoogleError.http(status, String(data: data, encoding: .utf8) ?? "Token request failed.")
        }
        guard let token = try? JSONDecoder().decode(GoogleTokenResponse.self, from: data) else {
            throw GoogleError.decoding
        }
        return token
    }

    private func store(_ token: GoogleTokenResponse) {
        KeychainStore.set(token.access_token, forKey: Keys.accessToken)
        // Google only returns a refresh token on the first consent; keep the old one otherwise.
        if let refresh = token.refresh_token {
            KeychainStore.set(refresh, forKey: Keys.refreshToken)
        }
        KeychainStore.set(
            String(Date.now.addingTimeInterval(TimeInterval(token.expires_in)).timeIntervalSince1970),
            forKey: Keys.expiresAt
        )
        isConnected = KeychainStore.get(Keys.refreshToken) != nil
    }

    func recordAccountEmail(_ email: String) {
        KeychainStore.set(email, forKey: Keys.email)
    }
}

extension GoogleAuthService: ASWebAuthenticationPresentationContextProviding {
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
