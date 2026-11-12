import XCTest
@testable import Ensembyte

/// The pure part of ZaiAPI's post-reset confirm: the decision "did a meter reflect the
/// cleared window" that a re-read-and-confirm loop makes on each pass. The loop itself
/// (`confirmReset`) is network lifecycle and is not unit-tested here.
final class ZaiResetConfirmTests: XCTestCase {
    private func limits(_ windows: [(id: String, percent: Double)]) -> PlanLimits {
        PlanLimits(
            planName: nil,
            windows: windows.map { PlanLimits.Window(id: $0.id, title: $0.id, percent: $0.percent, resetsAt: nil) }
        )
    }

    // MARK: - isCleared

    func testClearedAtZero() {
        XCTAssertTrue(ZaiAPI.isCleared(0))
        XCTAssertTrue(ZaiAPI.isCleared(0.01))
    }

    func testNotClearedAboveThreshold() {
        XCTAssertFalse(ZaiAPI.isCleared(0.02))
        XCTAssertFalse(ZaiAPI.isCleared(50))
    }

    // MARK: - isWindowCleared

    func testCreditWindowCleared() {
        let l = limits([("credit-0", 0), ("credit-1", 0), ("tools-0", 80)])
        XCTAssertTrue(ZaiAPI.isWindowCleared(l))
    }

    func testAnyCreditWindowClearingConfirms() {
        // One still-spent credit window does not block the confirm: a single cleared
        // credit meter is enough, since a reset card clears the active one.
        let l = limits([("credit-0", 60), ("credit-1", 0), ("tools-0", 80)])
        XCTAssertTrue(ZaiAPI.isWindowCleared(l))
    }

    func testNothingClearedYet() {
        let l = limits([("credit-0", 60), ("credit-1", 40), ("tools-0", 80)])
        XCTAssertFalse(ZaiAPI.isWindowCleared(l))
    }

    func testToolWindowsDoNotConfirm() {
        // A reset card clears the credit windows, not the MCP tool-call windows.
        let l = limits([("tools-0", 0)])
        XCTAssertFalse(ZaiAPI.isWindowCleared(l))
    }

    func testEmptyWindows() {
        XCTAssertFalse(ZaiAPI.isWindowCleared(limits([])))
    }
}
