import Foundation

/// The IDE tree's per-type adornments: the SF Symbol a file's extension
/// stands in for, and the short language label its status bar shows.
enum IDEFileIcon {
    /// The symbol for the file at `path`, answered from the last component's
    /// lowercased extension; anything unrecognized falls back to plain `doc`.
    static func symbol(for path: String) -> String {
        switch (path as NSString).pathExtension.lowercased() {
        case "swift": "swift"
        case "md": "doc.richtext"
        case "json": "curlybraces"
        case "yml", "yaml": "list.bullet"
        case "png", "jpg", "jpeg", "gif", "webp", "svg": "photo"
        case "mp4", "mov", "webm": "film"
        case "pdf": "doc.pdf"
        default: "doc"
        }
    }

    /// The short display language for a handful of common extensions, nil when
    /// the caller should fall back to the bare extension.
    static func language(_ path: String) -> String? {
        switch (path as NSString).pathExtension.lowercased() {
        case "swift": "Swift"
        case "py": "Python"
        case "js": "JavaScript"
        case "ts": "TypeScript"
        case "json": "JSON"
        case "md": "Markdown"
        case "c": "C"
        case "cc", "cpp", "cxx": "C++"
        case "rs": "Rust"
        case "go": "Go"
        default: nil
        }
    }
}
