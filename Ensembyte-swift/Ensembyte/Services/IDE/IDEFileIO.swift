import Foundation
import CryptoKit

/// Read, write and snapshot access for the IDE pane's editor buffers: the text
/// rules the read-only `IDEFileTree` view uses, the write path, and the content
/// markers that catch a file's state drifting on disk under an open buffer.
enum IDEFileIO {
    /// Files up to this many bytes get a content hash in their marker; beyond it,
    /// the marker carries the size instead — cheap to make, and still notices a rewrite.
    private static let snapshotCap = 8 * 1024 * 1024

    /// The file at `path` as strict UTF-8 text, uncapped. Nil for directories,
    /// binaries (a NUL byte in the first 8KB), and invalid UTF-8.
    /// (Same rules as `IDEFileTree.readText`, without its size cap.)
    static func readText(at path: String) -> String? {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
              !isDirectory.boolValue,
              let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
            return nil
        }
        if data.prefix(8 * 1024).contains(0) {
            return nil
        }
        // Strict: `String(data:encoding:)` answers nil when the bytes are not
        // valid UTF-8, unlike `String(decoding:)`, which substitutes.
        return String(data: data, encoding: .utf8)
    }

    /// A stable marker for a file's content: the SHA256 hex digest of the bytes
    /// (files up to 8MB; larger files answer with a marker that includes the
    /// size instead) plus the mtime string. Nil when the path cannot be read.
    static func snapshot(of path: String) -> String? {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
              !isDirectory.boolValue,
              let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              let size = attributes[.size] as? Int,
              0 <= size else {
            return nil
        }
        let mtime = (attributes[.modificationDate] as? Date).map { "\($0.timeIntervalSince1970)" } ?? "unknown"
        guard size <= Self.snapshotCap,
              let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
            return "\(size)|\(mtime)"
        }
        let hex = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return "\(hex)|\(mtime)"
    }

    /// Writes UTF-8 text to `path`, creating intermediate directories when the
    /// parent is missing. Throws on failure.
    static func write(text: String, to path: String) throws {
        let url = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url, options: .atomic)
    }
}
