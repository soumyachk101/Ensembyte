import Foundation
import Security

/// The GitHub App behind Ensembyte: its bot account (`ensembyte[bot]`) is what
/// GitHub resolves a co-author trailer to and what an App installation token
/// acts as. These constants are the client's source of truth; the Rust engine's
/// `commit_credit` module carries the same values.
enum GitHubAppIdentity {
    /// The GitHub App's numeric id; the JWT's `iss` claim.
    static let appId = 5597496
    /// The GitHub App's bot account.
    static let botLogin = "ensembyte[bot]"
    /// GitHub's stable numeric id for the bot: `login` noreply is `id+botLogin`.
    static let botUserID = 346184242
    static var botNoreply: String { "\(botUserID)+\(botLogin)@users.noreply.github.com" }
    /// The trailer the engine credits Ensembyte with in the commits its agents make.
    static var coAuthorTrailer: String { "Co-authored-by: \(botLogin) <\(botNoreply)>" }
}

/// Resolves the Ensembyte GitHub App's installation token. The user-side half
/// assembles a token it is handed, from the Keychain (what the user pasted)
/// or, failing that, the `GITHUB_APP_TOKEN` / `GH_APP_TOKEN` environment. It
/// mirrors `GitHubAuth` (the *user* token) so an App-auth consumer can
/// resolve one credential the same way. The bot side (the extension below)
/// instead signs App JWTs itself and mints installation tokens.
enum GitHubAppAuth {
    private static let service = "Ensembyte"
    private static let account = "GitHub App Installation Token"
    private static let envKeys = ["GITHUB_APP_TOKEN", "GH_APP_TOKEN"]

    /// The App token the user stored under their own control, or nil in a
    /// capture run and when nothing is stored.
    public static func customToken() -> String? {
        guard !CaptureRun.isEnabled else { return nil }
        if let keychain = APIKeychain.read(account, service: service), !keychain.isEmpty { return keychain }
        return nil
    }

    /// Stores the App token, or removes it for an empty one.
    @discardableResult
    public static func setCustomToken(_ token: String) -> Bool {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        return APIKeychain.set(trimmed, account: account, service: service)
    }

    /// The active App token: a stored one first, else an environment variable.
    /// Both reads are cheap and block-safe on the main thread — there is no CLI
    /// to run, unlike the user token's `gh auth token`.
    public static func cachedToken() -> String? {
        if let custom = customToken(), !custom.isEmpty {
            return custom
        }
        let environment = ProcessInfo.processInfo.environment
        for key in envKeys {
            if let value = environment[key], !value.isEmpty {
                return value
            }
        }
        return nil
    }

    /// Where the active App token came from, for Settings display.
    public static func tokenSourceDescription() -> String? {
        if let _ = customToken() {
            return "Installation token (Keychain)"
        }
        let environment = ProcessInfo.processInfo.environment
        for key in envKeys where environment[key] != nil {
            return "Environment variable"
        }
        return nil
    }
}

/// The bot side: signs the App's own JWTs with the private key and mints
/// installation access tokens, so pushes and pull requests act as
/// `ensembyte[bot]` rather than the user's account.
extension GitHubAppAuth {
    private static let keychainKeyAccount = "GitHub Bot App Key"
    private static let botTokenAccount = "GitHub Bot App Token"

    /// Stores a user-pasted App private key that takes precedence over the
    /// bundled one, or removes it for an empty one.
    @discardableResult
    public static func setKeychainKey(_ pem: String) -> Bool {
        APIKeychain.set(pem, account: keychainKeyAccount, service: service)
    }

    /// The App private key: a Keychain-stored one first, else the PEM bundled
    /// in Resources.
    private static func privateKeyData() -> Data? {
        if !CaptureRun.isEnabled,
           let keychain = APIKeychain.read(keychainKeyAccount, service: service),
           !keychain.isEmpty {
            return Data(keychain.utf8)
        }
        guard let url = Bundle.main.url(forResource: "GitHubAppPrivateKey", withExtension: "pem"),
              let data = try? Data(contentsOf: url) else { return nil }
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

    /// An installation access token, cached in the Keychain alongside its Unix
    /// expiry and re-minted once it is within five minutes of expiring.
    public static func installationAccessToken(id: Int) async throws -> String {
        if let cache = botTokenCache(), Date().timeIntervalSince1970 < cache.expiresAt - 300 {
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
        let cache = BotTokenCache(token: response.token, expiresAt: response.expires_at.timeIntervalSince1970)
        persistBotTokenCache(cache)
        return cache.token
    }

    /// The valid cached installation token, or nil when absent or inside the
    /// refresh window; minting a fresh one is `installationAccessToken(id:)`.
    public static func botToken() -> String? {
        guard !CaptureRun.isEnabled else { return nil }
        let cache = botTokenCache()
        guard let cache, Date().timeIntervalSince1970 < cache.expiresAt - 300 else { return nil }
        return cache.token
    }

    /// Clears the cached installation token. A user-stored App key survives.
    public static func removeBotToken() {
        APIKeychain.delete(botTokenAccount, service: service)
    }

    private struct BotTokenCache: Codable {
        let token: String
        let expiresAt: Double
    }

    private static func persistBotTokenCache(_ cache: BotTokenCache) {
        guard let data = try? JSONEncoder().encode(cache),
              let raw = String(data: data, encoding: .utf8) else { return }
        APIKeychain.set(raw, account: botTokenAccount, service: service)
    }

    private static func botTokenCache() -> BotTokenCache? {
        guard let raw = APIKeychain.read(botTokenAccount, service: service) else { return nil }
        return try? JSONDecoder().decode(BotTokenCache.self, from: Data(raw.utf8))
    }

    /// JWT base64url: no padding, `-` and `_` in place of `+` and `/`.
    private static func base64url(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
