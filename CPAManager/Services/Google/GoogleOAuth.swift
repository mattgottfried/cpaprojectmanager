import Foundation
import CryptoKit
import Security

/// Pure OAuth helpers for Google's installed-app flow (PKCE, no client secret).
enum GoogleOAuth {
    static let scopes = [
        "openid",
        "email",
        "https://www.googleapis.com/auth/gmail.readonly",
        "https://www.googleapis.com/auth/calendar.readonly",
        "https://www.googleapis.com/auth/calendar.events",
        // Drive is where documents live: the app browses and links files, and files new ones
        // (scans, letters, PDFs) into the client's folder. It only ever creates files.
        "https://www.googleapis.com/auth/drive",
    ]

    /// Google's iOS-type OAuth clients redirect to the *reversed* client ID:
    /// `123-abc.apps.googleusercontent.com` → `com.googleusercontent.apps.123-abc`.
    static func redirectScheme(clientID: String) -> String? {
        let suffix = ".apps.googleusercontent.com"
        let trimmed = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasSuffix(suffix), trimmed.count > suffix.count else { return nil }
        return "com.googleusercontent.apps." + String(trimmed.dropLast(suffix.count))
    }

    static func redirectURI(clientID: String) -> String? {
        redirectScheme(clientID: clientID).map { "\($0):/oauth2redirect" }
    }

    // MARK: PKCE (RFC 7636)

    static func makeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 48)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        if status != errSecSuccess {
            bytes = (0..<48).map { _ in UInt8.random(in: 0...255) }
        }
        return base64URL(Data(bytes))
    }

    static func challenge(for verifier: String) -> String {
        base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func authorizationURL(clientID: String, redirectURI: String, state: String, challenge: String) -> URL? {
        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: scopes.joined(separator: " ")),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent"),
        ]
        return components?.url
    }
}

struct GoogleTokenResponse: Decodable {
    let access_token: String
    let refresh_token: String?
    let expires_in: Int
}
