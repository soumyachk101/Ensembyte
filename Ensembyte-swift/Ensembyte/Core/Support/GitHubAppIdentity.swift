import Foundation

/// The GitHub App behind Ensembyte. `ensembyte[bot]` is the account GitHub
/// resolves a co-author trailer to, and the account an installation token acts as.
/// The Rust engine's `commit_credit` module carries the same values.
enum GitHubAppIdentity {
    /// The GitHub App's numeric id; the JWT's `iss` claim.
    static let appId = 5597496
    /// The GitHub App's client id. Device-flow sign-in uses this, not a separate OAuth app.
    static let clientID = "Iv23lip8dk91VWKI1t22"
    /// The GitHub App's bot account.
    static let botLogin = "ensembyte[bot]"
    /// GitHub's numeric id for `ensembyte[bot]`. The noreply address is `id+login`.
    /// `346184242` is `zeronsh[bot]`; using it makes GitHub list that bot instead.
    static let botUserID = 352044576
    static var botNoreply: String { "\(botUserID)+\(botLogin)@users.noreply.github.com" }
    /// Appended to commits made through Ensembyte. GitHub counts it as a
    /// contribution by `ensembyte[bot]`.
    static var coAuthorTrailer: String { "Co-authored-by: \(botLogin) <\(botNoreply)>" }
}
