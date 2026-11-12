import XCTest
@testable import Ensembyte

/// The per-installation-id token cache is a pure value: `BotTokenStore` maps an
/// installation id to its entry, so the keying — the part that mattered when a
/// fixed account returned the *first* connected installation's token for the
/// *second* — is testable without network or Keychain.
final class GitHubBotTokenCacheTests: XCTestCase {

    private func entry(_ token: String, expiresAt: Double) -> GitHubAppAuth.BotTokenCache {
        .init(token: token, expiresAt: expiresAt)
    }

    private func token(_ store: GitHubAppAuth.BotTokenStore, id: Int, now: TimeInterval = 0) -> String? {
        store.activeEntry(id: id, now: now)?.token
    }

    func testPerIdIsolation() {
        var store = GitHubAppAuth.BotTokenStore()
        store.upsert(entry("tokenA", expiresAt: 1_000_000), id: 1)
        store.upsert(entry("tokenB", expiresAt: 1_000_000), id: 2)
        // Connecting A then B keeps B's token under B's id, not A's.
        XCTAssertEqual(token(store, id: 1), "tokenA")
        XCTAssertEqual(token(store, id: 2), "tokenB")
        // An unconnected installation has no entry.
        XCTAssertNil(store.activeEntry(id: 3, now: 0))
    }

    func testOverwriteSameId() {
        var store = GitHubAppAuth.BotTokenStore()
        store.upsert(entry("old", expiresAt: 1_000_000), id: 7)
        store.upsert(entry("new", expiresAt: 1_000_000), id: 7)
        XCTAssertEqual(token(store, id: 7), "new")
    }

    func testRemoveOneIdKeepsOthers() {
        var store = GitHubAppAuth.BotTokenStore()
        store.upsert(entry("tokenA", expiresAt: 1_000_000), id: 1)
        store.upsert(entry("tokenB", expiresAt: 1_000_000), id: 2)
        store.upsert(nil, id: 1)
        XCTAssertNil(store.activeEntry(id: 1, now: 0))
        XCTAssertEqual(token(store, id: 2), "tokenB")
    }

    func testRefreshWindow() {
        // Inside five minutes of expiry the entry is considered stale, so the
        // caller mints a fresh token instead of reusing it.
        var store = GitHubAppAuth.BotTokenStore()
        store.upsert(entry("token", expiresAt: 1_000_000), id: 1)
        XCTAssertNotNil(store.activeEntry(id: 1, now: 1_000_000 - 301))
        XCTAssertNil(store.activeEntry(id: 1, now: 1_000_000 - 299))
        XCTAssertNil(store.activeEntry(id: 1, now: 1_000_000))
    }
}
