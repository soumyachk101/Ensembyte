import Foundation

/// The GitHub App behind Ensembyte: its bot account (`ensembyte[bot]`) is what
/// GitHub resolves a co-author trailer to and what an App installation token
/// acts as. These constants are the client's source of truth; the Rust engine's
/// `commit_credit` module carries the same values.
enum GitHubAppIdentity {
    static let botLogin = "ensembyte[bot]"
    /// GitHub's stable numeric id for the bot: `login` noreply is `id+botLogin`.
    static let botUserID = 346184242
    static var botNoreply: String { "\(botUserID)+\(botLogin)@users.noreply.github.com" }
    /// The trailer the engine credits Ensembyte with in the commits its agents make.
    static var coAuthorTrailer: String { "Co-authored-by: \(botLogin) <\(botNoreply)>" }
}

/// Resolves the Ensembyte GitHub App's installation token. The token is minted
/// by the Cloud vault, not signed here: the app has no App private key, so
/// this only ever assembles a token it is handed, from the Keychain (what the
/// user pasted) or, failing that, the `GITHUB_APP_TOKEN` / `GH_APP_TOKEN`
/// environment. It mirrors `GitHubAuth` (the *user* token) so an App-auth
/// consumer can resolve one credential the same way.
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
