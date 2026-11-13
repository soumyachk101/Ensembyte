import Foundation

/// One entry of the IDE pane's file tree: a file or directory as it sits in a
/// working directory, addressed by its absolute path.
struct IDEFileNode: Identifiable, Sendable {
    /// The file system path; it is also the node's identity within its directory.
    let id: String
    let name: String
    /// The path relative to the tree root, "" for the root itself.
    let relativePath: String
    let isDirectory: Bool

    init(id: String, name: String, relativePath: String, isDirectory: Bool) {
        self.id = id
        self.name = name
        self.relativePath = relativePath
        self.isDirectory = isDirectory
    }
}

/// Read-only directory and text access for the IDE pane's file tree and code view.
enum IDEFileTree {
    /// Names the pane never lists: version control, build output, and dependency trees.
    private static let ignored: Set<String> = [".git", "node_modules", ".build", "build"]

    private static let entryCap = 500

    /// Whether `name` is on the skip list, so the caller can prune whole subtrees.
    static func isIgnored(_ name: String) -> Bool {
        ignored.contains(name)
    }

    /// The direct children of `directory`, directories first, then alphabetical
    /// case-insensitive, capped at `entryCap` entries. Nil when the directory
    /// cannot be listed.
    static func children(of directory: String) -> [IDEFileNode]? {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directory, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return nil
        }
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory) else {
            return nil
        }
        var result: [IDEFileNode] = []
        for name in names {
            guard !isIgnored(name), !name.hasPrefix(".") else { continue }
            let path = (directory as NSString).appendingPathComponent(name)
            var childIsDirectory: ObjCBool = false
            let isDir = FileManager.default.fileExists(atPath: path, isDirectory: &childIsDirectory)
                ? childIsDirectory.boolValue : false
            result.append(IDEFileNode(
                id: path,
                name: name,
                relativePath: name,
                isDirectory: isDir
            ))
        }
        result.sort { a, b in
            if a.isDirectory != b.isDirectory { return a.isDirectory }
            return a.name.compare(b.name, options: [.caseInsensitive]) == .orderedAscending
        }
        return Array(result.prefix(entryCap))
    }

    /// The file at `path` as strict UTF-8 text, or nil when it is not something the
    /// pane can show: a directory, a binary, or more than `limit` bytes.
    static func readText(at path: String, limit: Int = 512_000) -> String? {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
              !isDirectory.boolValue,
              let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              let size = attributes[.size] as? Int,
              0 <= size,
              size <= limit else {
            return nil
        }
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
            return nil
        }
        if data.prefix(8 * 1024).contains(0) {
            return nil
        }
        // Strict: `String(data:encoding:)` answers nil when the bytes are not
        // valid UTF-8, unlike `String(decoding:)`, which substitutes.
        return String(data: data, encoding: .utf8)
    }
}
