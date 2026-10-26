import Foundation

struct StdioFramer {
    enum Framing: Sendable {
        case lines
        case contentLength
    }

    enum FrameError: LocalizedError, Equatable {
        case tooLarge
        var errorDescription: String? { "The agent sent a message over 16 MB" }
    }

    /// The largest frame a single message may occupy, exposed for tests of the limit.
    static let sizeLimit = 16 * 1024 * 1024
    private let framing: Framing
    private var buffer = Data()
    private var scanned = 0
    private var bodyLength: Int?
    private static let separator = Data("\r\n\r\n".utf8)

    init(framing: Framing) {
        self.framing = framing
    }

    mutating func append(_ data: Data) throws -> [Data] {
        buffer.append(data)
        var messages: [Data] = []
        var start = buffer.startIndex
        var search = start + scanned
        while true {
            switch framing {
            case .lines:
                guard let newline = buffer[search...].firstIndex(of: 0x0A) else {
                    guard buffer.endIndex - start <= Self.sizeLimit else { try failTooLarge() }
                    search = buffer.endIndex
                    break
                }
                guard newline - start <= Self.sizeLimit else { try failTooLarge() }
                messages.append(Data(buffer[start..<newline]))
                start = newline + 1
                search = start
                continue
            case .contentLength:
                if bodyLength == nil {
                    guard let headerEnd = buffer[search...].range(of: Self.separator) else {
                        guard buffer.endIndex - start <= Self.sizeLimit else { try failTooLarge() }
                        search = max(start, buffer.endIndex - 3)
                        break
                    }
                    guard headerEnd.upperBound - start <= Self.sizeLimit else { try failTooLarge() }
                    let header = String(decoding: buffer[start..<headerEnd.lowerBound], as: UTF8.self)
                    start = headerEnd.upperBound
                    search = start
                    guard let length = Self.contentLength(in: header) else { continue }
                    guard length <= Self.sizeLimit else { try failTooLarge() }
                    bodyLength = length
                }
                if let length = bodyLength, buffer.endIndex - start >= length {
                    let end = start + length
                    messages.append(Data(buffer[start..<end]))
                    bodyLength = nil
                    start = end
                    search = start
                    continue
                }
            }
            break
        }
        scanned = search - start
        if start != buffer.startIndex { buffer = Data(buffer[start...]) }
        return messages
    }

    mutating func finish() -> Data? {
        let remainder = framing == .lines && !buffer.isEmpty ? buffer : nil
        buffer = Data()
        scanned = 0
        bodyLength = nil
        return remainder
    }

    private mutating func failTooLarge() throws -> Never {
        buffer = Data()
        scanned = 0
        bodyLength = nil
        throw FrameError.tooLarge
    }

    private static func contentLength(in header: String) -> Int? {
        for line in header.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: ":", maxSplits: 1)
            guard parts.count == 2,
                  parts[0].trimmingCharacters(in: .whitespaces).lowercased() == "content-length" else { continue }
            guard let length = Int(parts[1].trimmingCharacters(in: .whitespaces)), length >= 0 else { return nil }
            return length
        }
        return nil
    }
}
