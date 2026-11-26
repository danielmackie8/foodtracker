import Foundation
import CryptoKit
import Security

/// Supabase project that stores Sage's data (tables prefixed `sage_`).
/// The publishable key is safe in the app: row level security limits every request
/// to the signed-in user's own rows.
enum CloudConfig {
    static let url = URL(string: "https://otnoxnqdywnthdarkgcf.supabase.co")!
    static let publishableKey = "sb_publishable_S5DUmIuyEw_SInmQckjHkQ_3TwVVsyL"
}

struct CloudSession: Codable, Equatable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date
    var userId: String
    var email: String?
}

enum CloudError: LocalizedError {
    case notSignedIn
    case server(Int, String)
    case badResponse

    var errorDescription: String? {
        switch self {
        case .notSignedIn: return "Not signed in."
        case .server(let code, let message): return "Server error \(code): \(message)"
        case .badResponse: return "Unexpected response from the server."
        }
    }
}

/// Sign in with Apple → Supabase session, kept in the Keychain and refreshed as needed.
@MainActor
@Observable
final class CloudAuth {
    private(set) var session: CloudSession?
    var isSignedIn: Bool { session != nil }

    init() {
        session = Keychain.load()
    }

    // MARK: Sign in with Apple

    /// A random nonce: the raw value goes to Supabase, its SHA-256 goes to Apple.
    static func makeNonce() -> (raw: String, hashed: String) {
        let chars = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        let raw = String((0..<32).map { _ in chars[Int.random(in: 0..<chars.count)] })
        let hashed = SHA256.hash(data: Data(raw.utf8)).map { String(format: "%02x", $0) }.joined()
        return (raw, hashed)
    }

    func signInWithApple(idToken: String, rawNonce: String) async throws {
        let json = try await tokenRequest(grantType: "id_token",
                                          body: ["provider": "apple", "id_token": idToken, "nonce": rawNonce])
        try store(json)
    }

    func signOut() {
        if let token = session?.accessToken {
            var req = URLRequest(url: CloudConfig.url.appendingPathComponent("auth/v1/logout"))
            req.httpMethod = "POST"
            req.setValue(CloudConfig.publishableKey, forHTTPHeaderField: "apikey")
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            Task { _ = try? await URLSession.shared.data(for: req) }
        }
        session = nil
        Keychain.delete()
    }

    /// A current access token, refreshing it first if it expires within a minute.
    func validAccessToken() async throws -> String {
        guard let s = session else { throw CloudError.notSignedIn }
        if s.expiresAt.timeIntervalSinceNow > 60 { return s.accessToken }
        do {
            let json = try await tokenRequest(grantType: "refresh_token", body: ["refresh_token": s.refreshToken])
            try store(json)
            return session?.accessToken ?? s.accessToken
        } catch CloudError.server(let code, _) where code == 400 || code == 401 {
            signOut() // refresh token revoked or expired: sign in again
            throw CloudError.notSignedIn
        }
    }

    // MARK: Plumbing

    private func tokenRequest(grantType: String, body: [String: String]) async throws -> [String: Any] {
        var comps = URLComponents(url: CloudConfig.url.appendingPathComponent("auth/v1/token"), resolvingAgainstBaseURL: false)!
        comps.queryItems = [URLQueryItem(name: "grant_type", value: grantType)]
        var req = URLRequest(url: comps.url!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(CloudConfig.publishableKey, forHTTPHeaderField: "apikey")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: req)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            throw CloudError.server(code, String(data: data, encoding: .utf8) ?? "")
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw CloudError.badResponse }
        return json
    }

    private func store(_ json: [String: Any]) throws {
        guard let access = json["access_token"] as? String,
              let refresh = json["refresh_token"] as? String,
              let user = json["user"] as? [String: Any],
              let userId = user["id"] as? String else { throw CloudError.badResponse }
        let expiresIn = (json["expires_in"] as? NSNumber)?.doubleValue ?? 3600
        let s = CloudSession(accessToken: access, refreshToken: refresh,
                             expiresAt: Date().addingTimeInterval(expiresIn),
                             userId: userId, email: user["email"] as? String ?? session?.email)
        session = s
        Keychain.save(s)
    }
}

/// Stores the session in the Keychain (this device only).
private enum Keychain {
    private static let service = "Sage.cloud"
    private static let account = "session"

    static func save(_ session: CloudSession) {
        guard let data = try? JSONEncoder().encode(session) else { return }
        delete()
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: data,
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    static func load() -> CloudSession? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(CloudSession.self, from: data)
    }

    static func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
