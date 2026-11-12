import XCTest
@testable import Ensembyte

final class MCPOAuthTests: XCTestCase {
    // MARK: - Token refresh decision

    private func stored(expiresAt: Double?, refreshToken: String?) -> JSONValue {
        var json: [String: Any] = ["access_token": "tok"]
        if let expiresAt { json["expires_at"] = expiresAt }
        if let refreshToken { json["refresh_token"] = refreshToken }
        let data = try! JSONSerialization.data(withJSONObject: json)
        return JSONValue.parse(data)!
    }

    func testExpiryNotYetReachedNoRefresh() {
        let decision = MCPOAuth.tokenDecision(stored: stored(
            expiresAt: Date().timeIntervalSince1970 + 3_600,
            refreshToken: "rt"
        ))
        XCTAssertEqual(decision, .noRefresh)
    }

    func testExpiryExpiredRefresh() {
        let decision = MCPOAuth.tokenDecision(stored: stored(
            expiresAt: Date().timeIntervalSince1970 - 1,
            refreshToken: "rt"
        ))
        XCTAssertEqual(decision, .refresh)
    }

    func testNoExpiryWithRefreshTokenRefresh() {
        let decision = MCPOAuth.tokenDecision(stored: stored(
            expiresAt: nil,
            refreshToken: "rt"
        ))
        XCTAssertEqual(decision, .refresh)
    }

    func testNoExpiryWithoutRefreshTokenUseStale() {
        let decision = MCPOAuth.tokenDecision(stored: stored(
            expiresAt: nil,
            refreshToken: nil
        ))
        XCTAssertEqual(decision, .useStale)
    }
}
