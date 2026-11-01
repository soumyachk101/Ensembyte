import AppKit

/// The one place an `NSImage(named:)` becomes a sized `NSImage` for inline use: the
/// head's dragon as a template that a `Text` run can hold (`MarkdownBlockView`), and
/// tinted with the head's colour for the AppKit link paragraph's glyph
/// (`LinkParagraphView`). Previously each caller drew it into its own cache under
/// its own key, so the same asset at the same size was rasterised twice.

enum GlyphCache {
    /// A template glyph sized for a `Text` run: `nil` tint, crisp on any display.
    @MainActor
    static func template(named name: String, size: CGFloat) -> NSImage {
        value(named: name, tint: nil, size: size)
    }

    /// The glyph filled with `tint` on top of its own pixels: the `sourceAtop` fill
    /// keeps the dragon's silhouette where the source image has no pixels.
    @MainActor
    static func tinted(named name: String, tint: NSColor, size: CGFloat) -> NSImage {
        value(named: name, tint: tint, size: size)
    }

    /// The one cache for both: the key carries the tint, so a head's template dragon
    /// and the dragons tinted into its colours keep distinct entries for the same
    /// asset and size.
    @MainActor
    private static func value(named name: String, tint: NSColor?, size: CGFloat) -> NSImage {
        let tintKey = tint.map { "\($0.redComponent)\($0.greenComponent)\($0.blueComponent)\($0.alphaComponent)" } ?? "-"
        let key = "\(name)@\(tintKey)@\(size)"
        if let cached = images[key] { return cached }
        let source = NSImage(named: name)
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            source?.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
            if let tint {
                tint.set()
                rect.fill(using: .sourceAtop)
            }
            return true
        }
        if tint == nil { image.isTemplate = true }
        images[key] = image
        return image
    }

    @MainActor
    private static var images: [String: NSImage] = [:]
}
