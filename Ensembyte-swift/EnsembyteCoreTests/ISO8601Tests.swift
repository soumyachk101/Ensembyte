import XCTest
@testable import Ensembyte

final class ISO8601Tests: XCTestCase {
    // MARK: - date(from:)

    func testPlainStamp() {
        let date = ISO8601.date(from: "2026-09-13T18:28:42Z")
        XCTAssertNotNil(date)
        XCTAssertEqual(ISO8601.string(from: date!), "2026-09-13T18:28:42Z")
    }

    func testFractionalStamp() {
        let date = ISO8601.date(from: "2026-09-13T18:28:42.057Z")
        XCTAssertNotNil(date)
        // The formatter keeps whole seconds; the fraction is accepted, not honored.
        XCTAssertEqual(ISO8601.string(from: date!), "2026-09-13T18:28:42Z")
    }

    func testOffsetAndColonForm() {
        XCTAssertNotNil(ISO8601.date(from: "2026-09-13T18:28:42+02:00"))
        // Both shapes name the same instant in UTC.
        XCTAssertEqual(ISO8601.date(from: "2026-09-13T16:28:42Z"),
                       ISO8601.date(from: "2026-09-13T18:28:42+02:00"))
    }

    func testRejection() {
        XCTAssertNil(ISO8601.date(from: "2026-09-13"))
        XCTAssertNil(ISO8601.date(from: "18:28:42Z"))
        XCTAssertNil(ISO8601.date(from: "not a date"))
        XCTAssertNil(ISO8601.date(from: ""))
    }

    // MARK: - dateOnly(from:)

    func testDateOnly() {
        // The GitHub Copilot quota shape: a bare date with no time.
        XCTAssertNotNil(ISO8601.dateOnly(from: "2026-09-13"))
        // It parses to midnight in the local zone the format style uses; what matters
        // for the quota reader is only that a stamp arrives at all.
        let day = ISO8601.dateOnly(from: "2026-09-13")!
        var components = Calendar.current.dateComponents([.year, .month, .day], from: day)
        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 9)
        XCTAssertEqual(components.day, 13)
        _ = components
    }

    func testDateOnlyRejectsTimestamps() {
        XCTAssertNil(ISO8601.dateOnly(from: "2026-09-13T18:28:42Z"))
        XCTAssertNil(ISO8601.dateOnly(from: "2026-09-13T18:28:42.057Z"))
        XCTAssertNil(ISO8601.dateOnly(from: "not a date"))
    }

    // MARK: - string(from:)

    func testStringRoundTripAndUTC() {
        // The formatter is UTC-based, independent of the local zone the test runs in.
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        XCTAssertEqual(ISO8601.string(from: date), "2023-11-14T22:13:20Z")
        let back = ISO8601.date(from: ISO8601.string(from: date))
        XCTAssertEqual(back?.timeIntervalSince1970, 1_700_000_000)
    }
}
