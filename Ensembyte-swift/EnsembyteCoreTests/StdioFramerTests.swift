import XCTest
@testable import Ensembyte

final class StdioFramerTests: XCTestCase {
    private func frames(_ data: Data, framing: StdioFramer.Framing) throws -> [Data] {
        var framer = StdioFramer(framing: framing)
        return try framer.append(data)
    }

    // MARK: - Line framing

    func testLinesCompletesOnlyOnNewline() throws {
        var framer = StdioFramer(framing: .lines)
        XCTAssertEqual(try framer.append(Data("first".utf8)), [])
        XCTAssertEqual(try framer.append(Data(" second\n".utf8)), [Data("first second".utf8)])
        XCTAssertEqual(try framer.append(Data("third".utf8)), [])
        XCTAssertEqual(try framer.append(Data("\nfourth\n".utf8)), [Data("third".utf8), Data("fourth".utf8)])
        // An unterminated tail is not a frame yet.
        XCTAssertEqual(try framer.append(Data("open".utf8)), [])
        XCTAssertEqual(framer.finish(), Data("open".utf8))
    }

    func testLinesEmptyFrame() throws {
        var framer = StdioFramer(framing: .lines)
        XCTAssertEqual(try framer.append(Data("\n".utf8)), [Data()])
    }

    func testLinesCrlf() throws {
        var framer = StdioFramer(framing: .lines)
        XCTAssertEqual(try framer.append(Data("one\r\n".utf8)), [Data("one\r".utf8)])
    }

    func testLinesBinary() throws {
        var framer = StdioFramer(framing: .lines)
        let payload: [UInt8] = [0xFF, 0x00, 0xFE]
        XCTAssertEqual(try framer.append(Data(payload + [0x0A])), [Data(payload)])
    }

    // MARK: - Content-Length framing

    func testContentLengthSingleFrame() throws {
        let frames = try frames(Data("Content-Length: 5\r\n\r\nhello".utf8), framing: .contentLength)
        XCTAssertEqual(frames, [Data("hello".utf8)])
    }

    func testContentLengthHeaderCaseAndWhitespace() throws {
        let frames = try frames(Data("  content-length : 3\r\nx-other: 9\r\n\r\nabc".utf8), framing: .contentLength)
        XCTAssertEqual(frames, [Data("abc".utf8)])
    }

    func testContentLengthZeroBody() throws {
        let frames = try frames(Data("Content-Length: 0\r\n\r\nNext: 2\r\n\r\nab".utf8), framing: .contentLength)
        XCTAssertEqual(frames, [Data(), Data("ab".utf8)])
    }

    func testContentLengthNoHeaderSkipsToNextHeader() throws {
        let frames = try frames(Data("X-Note: hi\r\n\r\nContent-Length: 2\r\n\r\nok".utf8), framing: .contentLength)
        XCTAssertEqual(frames, [Data("ok".utf8)])
    }

    func testContentLengthSplitAcrossChunks() throws {
        var framer = StdioFramer(framing: .contentLength)
        XCTAssertEqual(try framer.append(Data("Content-Length: 6\r\n".utf8)), [])
        XCTAssertEqual(try framer.append(Data("\r\nhello ".utf8)), [])
        XCTAssertEqual(try framer.append(Data("world!".utf8)), [Data("hello world!".utf8)])
        XCTAssertNil(framer.finish())
    }

    // MARK: - Oversized frames

    func testContentLengthRefusesOversizedFrame() {
        let header = "Content-Length: \(StdioFramer.sizeLimit + 1)\r\n\r\n"
        var framer = StdioFramer(framing: .contentLength)
        do {
            _ = try framer.append(Data(header.utf8))
            XCTFail("an oversized frame must be rejected")
        } catch let error as StdioFramer.FrameError {
            XCTAssertEqual(error, .tooLarge)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testLinesRejectsOversizedLine() {
        var framer = StdioFramer(framing: .lines)
        do {
            _ = try framer.append(Data(repeating: 0x41, count: StdioFramer.sizeLimit + 1))
            XCTFail("an oversized line must be rejected")
        } catch let error as StdioFramer.FrameError {
            XCTAssertEqual(error, .tooLarge)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testLinesAllowsExactlyTheLimit() throws {
        var framer = StdioFramer(framing: .lines)
        let payload = Data(repeating: 0x41, count: StdioFramer.sizeLimit)
        XCTAssertEqual(try framer.append(payload + Data([0x0A])), [payload])
    }

    func testOversizedFrameResetsState() {
        var framer = StdioFramer(framing: .lines)
        XCTAssertThrowsError(try framer.append(Data(repeating: 0x41, count: StdioFramer.sizeLimit + 1)))
        // Nothing is retained after a rejected frame.
        XCTAssertEqual(framer.finish(), nil)
    }

    // MARK: - Finish

    func testFinishDrainsAndResets() {
        var framer = StdioFramer(framing: .lines)
        _ = try? framer.append(Data("abc".utf8))
        XCTAssertEqual(framer.finish(), Data("abc".utf8))
        XCTAssertEqual(framer.finish(), nil)

        var header = StdioFramer(framing: .contentLength)
        _ = try? header.append(Data("Content-Length: 2\r\n".utf8))
        // Body still pending: a content-length frame is not a line, so nothing survives finish.
        XCTAssertEqual(header.finish(), nil)
    }
}
