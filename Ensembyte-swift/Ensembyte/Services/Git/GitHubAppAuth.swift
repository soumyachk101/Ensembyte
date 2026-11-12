import Foundation
import Security

enum GitHubAppAuth {
    private static let service = "Ensembyte"
}

/// The bot side: signs the App's own JWTs with the bundled Ensembyte private
/// key (or a key the user pasted over it) and mints installation access tokens,
/// so pushes and pull requests act as `ensembyte[bot]` rather than the user's account.
extension GitHubAppAuth {
    private static let keychainKeyAccount = "GitHub Bot App Key"
    private static let botTokenAccount = "GitHub Bot App Token"

    /// Stores a key pasted in Settings, which overrides the bundled Ensembyte key.
    /// An empty string removes that override and signing falls back to the bundle.
    @discardableResult
    public static func setKeychainKey(_ pem: String) -> Bool {
        APIKeychain.set(pem, account: keychainKeyAccount, service: service)
    }

    /// A key the user pasted over the bundled Ensembyte key, or nil when they have not.
    static func storedKey() -> String? {
        guard !CaptureRun.isEnabled,
              let keychain = APIKeychain.read(keychainKeyAccount, service: service),
              !keychain.isEmpty else { return nil }
        return keychain
    }

    /// The pasted key when there is one, otherwise `GitHubAppPrivateKey.pem` in the app bundle.
    private static func privateKeyData() -> Data? {
        if let keychain = storedKey() { return Data(keychain.utf8) }
        guard let url = Bundle.main.url(forResource: "GitHubAppPrivateKey", withExtension: "pem"),
              let data = try? Data(contentsOf: url), !data.isEmpty else { return nil }
        return data
    }

    /// A fresh RS256 GitHub App JWT, signed with the Security framework alone
    /// (no external crypto): PKCS#1v15 SHA-256 over the base64url header and
    /// claims. Valid for nine minutes, with a one-minute issuance skew.
    public static func appJWT() -> String? {
        guard let der = privateKeyDER() else { return nil }
        var keyErr: Unmanaged<CFError>?
        let attributes: [CFString: Any] = [
            kSecAttrKeyType: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass: kSecAttrKeyClassPrivate,
        ]
        guard let key = SecKeyCreateWithData(der as CFData, attributes as CFDictionary, &keyErr) else {
            return nil
        }
        let now = Int(Date().timeIntervalSince1970)
        let claims: [String: Any] = ["iat": now - 60, "exp": now + 540, "iss": "\(GitHubAppIdentity.appId)"]
        guard let headerJSON = try? JSONSerialization.data(withJSONObject: ["alg": "RS256", "typ": "JWT"]),
              let claimsJSON = try? JSONSerialization.data(withJSONObject: claims) else { return nil }
        let signingInput = base64url(headerJSON) + "." + base64url(claimsJSON)
        var signatureErr: Unmanaged<CFError>?
        guard let signature = SecKeyCreateSignature(
            key, SecKeyAlgorithm.rsaSignatureMessagePKCS1v15SHA256,
            signingInput.data(using: .utf8)! as CFData, &signatureErr) else { return nil }
        return signingInput + "." + base64url(signature as Data)
    }

    /// The App key on disk is PEM; this Security API wants the PKCS#1 DER body,
    /// so the base64 inside the armour is decoded back down to its raw bytes.
    private static func privateKeyDER() -> Data? {
        guard let pem = privateKeyData(),
              let text = String(data: pem, encoding: .utf8) else { return nil }
        let body = text.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("-----") }
            .joined()
        return Data(base64Encoded: body)
    }

    /// Every installation of the Ensembyte App, paginated.
    public static func listInstallations() async throws -> [GitHubAppInstallation] {
        guard let jwt = appJWT() else { throw GitHubError.appKeyMissing }
        var installations: [GitHubAppInstallation] = []
        for page in 1...50 {
            let url = URL(string: "https://api.github.com/app/installations?per_page=100&page=\(page)")!
            let batch: [GitHubAppInstallation] = try await GitHubAPI.request(url, token: jwt)
            installations.append(contentsOf: batch)
            if batch.count < 100 { break }
        }
        return installations
    }

    /// An installation access token, cached in the Keychain per installation id
    /// alongside its Unix expiry and re-minted once it is within five minutes
    /// of expiring. Each id has its own entry, so connecting installation A
    /// then B keeps B's token instead of returning A's.
    public static func installationAccessToken(id: Int) async throws -> String {
        if let cache = botTokenCache(id: id), Date().timeIntervalSince1970 < cache.expiresAt - 300 {
            return cache.token
        }
        guard let jwt = appJWT() else { throw GitHubError.appKeyMissing }
        struct TokenResponse: Decodable {
            let token: String
            let expires_at: Date
        }
        let response: TokenResponse = try await GitHubAPI.request(
            URL(string: "https://api.github.com/app/installations/\(id)/access_tokens")!,
            token: jwt, form: [:])
        upsertBotTokenCache(
            BotTokenCache(token: response.token, expiresAt: response.expires_at.timeIntervalSince1970),
            id: id)
        return response.token
    }

    /// Clears the cached token of the given installation; the stored App key
    /// survives. No-op when the id has no entry, so nothing is written.
    public static func removeBotToken(id: Int) {
        guard botTokenStore().byInstallation[id] != nil else { return }
        upsertBotTokenCache(nil, id: id)
    }

    struct BotTokenCache: Codable, Equatable, Sendable {
        let token: String
        let expiresAt: Double
    }

    /// The one Keychain item holding the per-installation cache, as a pure
    /// value so the id-keying is testable without network or Keychain.
    struct BotTokenStore: Codable {
        var byInstallation: [Int: BotTokenCache] = [:]

        /// The entry for one installation, or nil when it is absent or inside
        /// its five-minute refresh window.
        func activeEntry(id: Int, now: TimeInterval = Date().timeIntervalSince1970) -> BotTokenCache? {
            guard let entry = byInstallation[id], now < entry.expiresAt - 300 else { return nil }
            return entry
        }

        mutating func upsert(_ entry: BotTokenCache?, id: Int) {
            if let entry { byInstallation[id] = entry } else { byInstallation[id] = nil }
        }
    }

    /// One Keychain item holds a `[Int: BotTokenCache]`: each installation id
    /// owns its entry, so the cache is keyed by id even though it is a single
    /// account. `entry` is nil to remove that id's token.
    private static func upsertBotTokenCache(_ entry: BotTokenCache?, id: Int) {
        var store = botTokenStore()
        store.upsert(entry, id: id)
        persistBotTokenStore(store)
    }

    private static func persistBotTokenStore(_ store: BotTokenStore) {
        guard let data = try? JSONEncoder().encode(store),
              let raw = String(data: data, encoding: .utf8) else { return }
        APIKeychain.set(raw, account: botTokenAccount, service: service)
    }

    private static func botTokenStore() -> BotTokenStore {
        guard let raw = APIKeychain.read(botTokenAccount, service: service),
              let data = raw.data(using: .utf8) else { return BotTokenStore() }
        return (try? JSONDecoder().decode(BotTokenStore.self, from: data)) ?? BotTokenStore()
    }

    private static func botTokenCache(id: Int) -> BotTokenCache? {
        botTokenStore().activeEntry(id: id)
    }

    /// JWT base64url: no padding, `-` and `_` in place of `+` and `/`.
    private static func base64url(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
