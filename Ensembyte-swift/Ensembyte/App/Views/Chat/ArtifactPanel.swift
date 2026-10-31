import AppKit
import SwiftUI

/// The thread's artifacts as a floating glass panel: the files the agent edits,
/// each with its additions and deletions, the same list and detail recipe as
/// the pane's Artifacts tab took. Tapping a file opens its content — the diff
/// for a code file, a preview for an image, the rendered markdown for a
/// document — and tapping it again folds it back to the list. The list reads
/// `changeStats` live; the selection and detail are view-local, so a panel
/// that closes or switches threads starts clean. The strip along the top is
/// the handle, with the title at its left and the close button at its right.
struct ArtifactPanel: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme
    let runtime: ThreadRuntime
    let size: CGSize
    /// The pointer's travel since the handle was grabbed.
    let onDrag: (CGSize) -> Void
    let onDragEnd: () -> Void
    let dismiss: () -> Void

    @State private var selectedPath: String?
    @State private var detail: ArtifactDetail?

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: HydraPanel.cornerRadius, style: .continuous)
        let summary = runtime.changeStats
        Group {
            if let summary, !summary.files.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(summary.files, id: \.path) { file in
                            fileRow(file)
                        }
                        if let selectedPath {
                            detailView(for: selectedPath)
                        }
                    }
                    .padding(.horizontal, Chrome.chromeHorizontalPadding)
                    .padding(.bottom, 12)
                }
            } else {
                emptyState
            }
        }
        .padding(.top, HydraPanel.stripHeight)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Artifacts"))
        .overlay(alignment: .top) {
            strip
        }
        .frame(width: size.width, height: size.height)
        .background {
            // The helper panel's recipe: one glass surface, a scrim for the text over
            // whatever the panel floats above, and the theme's tint.
            let isDark = colorScheme == .dark
            shape
                .fill(.clear)
                .glassEffect(.regular, in: shape)
                .overlay {
                    shape.fill(Chrome.glassTint.opacity(isDark ? 0.22 : 0.16))
                }
        }
        .clipShape(shape)
        // The scrim sits under the glass and carries the panel's shadow, drawn once.
        .background {
            let isDark = colorScheme == .dark
            shape
                .fill((isDark ? Color.black : Color.white).opacity(0.3))
                .shadow(color: .black.opacity(isDark ? 1 : 0.65), radius: 28, y: 10)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "shippingbox")
                .font(.system(size: 22))
                .foregroundStyle(Chrome.secondaryText)
                .frame(width: 44, height: 44)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Chrome.overlay(0.05))
                )
            Text("No artifacts yet")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Chrome.primaryText)
            Text("Files the agent edits will appear here.")
                .font(.system(size: 12))
                .foregroundStyle(Chrome.secondaryText)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// One file: its glyph and its name over its parent path, the additions and
    /// deletions at the right, and the spinner while its detail is still being read.
    private func fileRow(_ file: FileChangeSummary.File) -> some View {
        let isSelected = file.path == selectedPath
        let parent = (file.path as NSString).deletingLastPathComponent
        return Button {
            // Tapping the open file again folds the detail back to the list.
            selectedPath = isSelected ? nil : file.path
        } label: {
            HStack(spacing: 8) {
                Image(systemName: Self.symbol(for: file.path))
                    .font(.system(size: 12))
                    .foregroundStyle(Chrome.secondaryText)
                    .frame(width: 14, alignment: .center)
                VStack(alignment: .leading, spacing: 1) {
                    Text((file.path as NSString).lastPathComponent)
                        .font(.system(size: 12))
                        .foregroundStyle(Chrome.primaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if !parent.isEmpty {
                        Text(verbatim: parent)
                            .font(.system(size: 10))
                            .foregroundStyle(Chrome.secondaryText)
                            .lineLimit(1)
                            .truncationMode(.head)
                    }
                }
                Spacer(minLength: 4)
                if file.additions > 0 {
                    changeCount("+\(file.additions)", color: Chrome.success)
                }
                if file.deletions > 0 {
                    changeCount("\u{2212}\(file.deletions)", color: Chrome.danger)
                }
                if isSelected, detail == nil {
                    Image(systemName: "circle.dotted.circle")
                        .font(.system(size: 12))
                        .foregroundStyle(Chrome.secondaryText)
                        .symbolEffect(.pulse)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background {
                if isSelected {
                    Capsule().fill(Chrome.accent.opacity(0.14))
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : AccessibilityTraits())
    }

    private func changeCount(_ text: String, color: Color) -> some View {
        Text(verbatim: text)
            .font(.system(size: 11, design: .monospaced).monospacedDigit())
            .foregroundStyle(color)
    }

    /// The handle across the top: the title at the left, the close button at the
    /// right, and the room between them drags the panel.
    private var strip: some View {
        HStack(alignment: .top, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "shippingbox")
                    .font(.system(size: 12))
                    .foregroundStyle(Chrome.secondaryText)
                Text("Artifacts")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Chrome.primaryText.opacity(0.92))
            }
            .padding(.horizontal, Chrome.capsuleHorizontalPadding)
            .frame(height: Chrome.capsuleContentHeight)
            .padding(.vertical, Chrome.capsuleVerticalPadding)
            .fixedSize()
            .chromeGlassCapsule()
            // The title is a label, not a control, so it drags the panel too.
            .overlay {
                PanelDragHandle(onDrag: onDrag, onDragEnd: onDragEnd)
            }
            .padding(.top, Chrome.chromeTopPadding)
            .padding(.leading, Chrome.chromeHorizontalPadding)
            PanelDragHandle(onDrag: onDrag, onDragEnd: onDragEnd)
                .frame(maxWidth: .infinity)
                .frame(height: HydraPanel.stripHeight)
                .help("Drag to move")
                .accessibilityLabel(Text("Drag to move"))
            ChromeCircleButton(symbol: "xmark", help: "Close the artifacts panel") {
                dismiss()
            }
            .padding(.top, Chrome.chromeTopPadding)
            .padding(.trailing, Chrome.chromeHorizontalPadding)
        }
    }

    // MARK: Detail

    /// What the open file shows under the list: the diff for a code file, the preview or
    /// the rendered markdown for an image or a document, and the caption one of them
    /// cannot.
    @ViewBuilder
    private func detailView(for path: String) -> some View {
        let file = runtime.changeStats?.files.first { $0.path == path }
        VStack(alignment: .leading, spacing: 6) {
            if let image = detail?.image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 320)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else if let markdown = detail?.markdown {
                MarkdownView(text: markdown).equatable()
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if let diff = detail?.diff {
                if diff.isBinary {
                    detailCaption("Binary file")
                } else {
                    diffHunks(diff)
                }
            } else if file?.isBinary == true {
                detailCaption("Binary file")
            } else if detail == nil {
                // The diff is still coming; the spinner stands in for it.
                MiniSpinner()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            } else {
                detailCaption("No diff available for this file")
            }
        }
        .task(id: DetailKey(path: path, revision: runtime.diffRevision)) {
            await loadDetail(path: path, rowIsBinary: file?.isBinary == true)
        }
    }

    @MainActor
    private func loadDetail(path: String, rowIsBinary: Bool) async {
        detail = nil
        let diffs = await runtime.parsedDiff(selection: nil)
        guard !Task.isCancelled else { return }
        let match = diffs.first { TouchedPaths.matches($0, touched: Set([path])) }
        switch Self.kind(for: path) {
        case .markdown:
            if let absolute = resolvedOnDisk(path),
               let text = try? String(contentsOf: URL(fileURLWithPath: absolute), encoding: .utf8), !text.isEmpty {
                detail = ArtifactDetail(markdown: text)
            } else if let match {
                detail = ArtifactDetail(diff: match, isBinary: match.isBinary)
            } else {
                detail = rowIsBinary ? ArtifactDetail(isBinary: true) : ArtifactDetail()
            }
        case .image:
            if let absolute = resolvedOnDisk(path), let image = NSImage(contentsOf: URL(fileURLWithPath: absolute)) {
                detail = ArtifactDetail(image: image)
            } else {
                detail = ArtifactDetail(isBinary: true)
            }
        case .code:
            if let match {
                detail = ArtifactDetail(diff: match, isBinary: match.isBinary)
            } else {
                detail = rowIsBinary ? ArtifactDetail(isBinary: true) : ArtifactDetail()
            }
        }
    }

    /// The diff's hunks: a small counts line, then each hunk's header and lines,
    /// added and removed coloured, each line on its own padded row.
    private func diffHunks(_ diff: DiffFile) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                changeCount("+\(diff.additions)", color: Chrome.success)
                changeCount("\u{2212}\(diff.deletions)", color: Chrome.danger)
            }
            ForEach(diff.hunks) { hunk in
                VStack(alignment: .leading, spacing: 0) {
                    Text(verbatim: hunk.header)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Chrome.secondaryText)
                        .padding(6)
                    ForEach(hunk.lines) { line in
                        diffLine(line)
                    }
                }
            }
        }
    }

    private func diffLine(_ line: DiffLine) -> some View {
        let (prefix, color): (String, Color) = switch line.kind {
        case .addition: ("+", Chrome.success)
        case .deletion: ("\u{2212}", Chrome.danger)
        case .context: (" ", Chrome.primaryText)
        case .note: ("", Chrome.secondaryText)
        }
        return Text(verbatim: prefix + line.text)
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(6)
    }

    private func detailCaption(_ text: String) -> some View {
        Text(verbatim: text)
            .font(.system(size: 11))
            .foregroundStyle(Chrome.secondaryText)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 12)
    }

    // MARK: Paths and kinds

    /// The checkout the paths mean in: the thread's worktree when it has one, its
    /// project's folder otherwise — the same root the thread's own diffs read against.
    private var workingDirectory: String? {
        guard let thread = runtime.thread else { return nil }
        return thread.worktreePath ?? model.project(thread.projectID)?.path
    }

    /// A file path from the list or the diff as a place on disk, when it is one:
    /// through the tool-path resolver the timeline uses (absolute, tilde and relative
    /// against the thread's working directory), and the working directory itself as
    /// the fallback for a path relative to the repository.
    @MainActor
    private func resolvedOnDisk(_ path: String) -> String? {
        guard !path.isEmpty else { return nil }
        let call = ToolCall(kind: .read, title: path, detail: nil)
        if let found = PreviewImages.resolveToolImagePath(for: call, workingDirectory: workingDirectory) {
            return found
        }
        guard let root = workingDirectory, !path.hasPrefix("/") else { return nil }
        let candidate = (root as NSString).appendingPathComponent(path)
        return FileManager.default.fileExists(atPath: candidate) ? candidate : nil
    }

    private enum DetailKind {
        case code
        case markdown
        case image
    }

    private static func kind(for path: String) -> DetailKind {
        let ext = (path as NSString).pathExtension.lowercased()
        if ext == "md" || ext == "markdown" { return .markdown }
        if PreviewImages.isImagePath(path) { return .image }
        return .code
    }

    private static func symbol(for path: String) -> String {
        switch kind(for: path) {
        case .image: "photo"
        case .markdown: "doc.plaintext"
        case .code: "chevron.left.forwardslash.chevron.right"
        }
    }

    /// What the open file's detail area holds, whichever of the three it turned out to
    /// need: the preview, the file's markdown, or the diff it parsed to, plus the
    /// binary flag that takes its place when none of them does.
    private struct ArtifactDetail {
        var image: NSImage? = nil
        var markdown: String? = nil
        var diff: DiffFile? = nil
        var isBinary = false
    }

    /// The detail's task key: the file and the revision its diff was last seen at, so a
    /// new edit of the same file re-reads it and a switch of files cancels the old read.
    private struct DetailKey: Hashable {
        let path: String
        let revision: Int
    }
}
