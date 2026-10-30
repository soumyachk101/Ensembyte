import AppKit
import SwiftUI

/// The thread's to-dos and artifacts as a fixed bottom section: a tab row over one
/// content area, each tab reading its list live — the to-do list from the thread's
/// `.todos` entries, the files the agent produced from `changeStats` — so the
/// section keeps moving as the agent works. The chrome is the terminal section's:
/// rounded top corners, an opaque surface, a hairline on the edge, and no drag
/// handles.
struct ThreadTaskSection: View {
    @Environment(AppModel.self) private var model
    let runtime: ThreadRuntime
    let close: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            content
        }
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Chrome.overlay(0.1))
                .frame(height: 1)
        }
        // Rounded top corners like the terminal's sheet, over an opaque surface
        // that carries the content, the browser section's recipe.
        .background {
            UnevenRoundedRectangle(
                topLeadingRadius: Chrome.sheetCornerRadius,
                topTrailingRadius: Chrome.sheetCornerRadius,
                style: .continuous
            )
            .fill(Chrome.glassTint)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Thread tasks and artifacts"))
    }

    /// The tab row: a tab per list, the close mark at the right. The padding and
    /// height mirror the terminal section's header row.
    private var header: some View {
        HStack(spacing: 6) {
            tabButton(.todos, symbol: "checklist", title: "Todos")
            tabButton(.artifacts, symbol: "shippingbox", title: "Artifacts")
            Spacer(minLength: 0)
            ChromeCircleButton(symbol: "xmark", help: "Close") {
                close()
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 38)
    }

    private func tabButton(_ tab: ThreadRuntime.TaskSectionTab, symbol: String, title: String) -> some View {
        let isActive = runtime.taskSectionTab == tab
        return Button {
            runtime.taskSectionTab = tab
        } label: {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .medium))
                Text(verbatim: title)
                    .font(.system(size: 12, weight: .medium))
            }
            .padding(.horizontal, 10)
            .frame(height: 26)
            .foregroundStyle(isActive ? Chrome.primaryText : Chrome.secondaryText)
            .background {
                Capsule(style: .continuous)
                    .fill(isActive ? Chrome.accent.opacity(0.14) : Color.clear)
            }
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(title))
        .accessibilityAddTraits(isActive ? [.isButton, .isSelected] : .isButton)
    }

    @ViewBuilder
    private var content: some View {
        Group {
            switch runtime.taskSectionTab {
            case .todos:
                TodosTab(runtime: runtime)
            case .artifacts:
                ArtifactsTab(runtime: runtime)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// The Todos tab: the thread's to-do list read live — a progress line over the
/// checklist, the step under way in its own row, the done steps checked and
/// struck through.
private struct TodosTab: View {
    let runtime: ThreadRuntime

    /// The most recent non-empty `.todos` entry of this thread. The entries array and
    /// each entry's `item` are observed, so the tab redraws whenever the agent rewrites
    /// the checklist.
    private var steps: [TodoStep] {
        runtime.entries.reversed()
            .compactMap { entry -> [TodoStep] in
                if case .todos(let todoSteps) = entry.item.content { todoSteps } else { [] }
            }
            .first(where: { !$0.isEmpty }) ?? []
    }

    var body: some View {
        Group {
            if steps.isEmpty {
                emptyState
            } else {
                taskList
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "checklist")
                .font(.system(size: 22))
                .foregroundStyle(Chrome.secondaryText)
                .frame(width: 44, height: 44)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Chrome.overlay(0.05))
                )
            Text("No tasks yet")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Chrome.primaryText)
            Text("The agent's to-do list appears here as it works.")
                .font(.system(size: 12))
                .foregroundStyle(Chrome.secondaryText)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var taskList: some View {
        let done = steps.count { $0.status == .done }
        return VStack(alignment: .leading, spacing: 8) {
            Text("\(done) of \(steps.count) done")
                .font(.system(size: 12))
                .foregroundStyle(Chrome.secondaryText)
            ProgressView(value: Double(done), total: Double(max(1, steps.count)))
                .tint(Chrome.accent)
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(Array(steps.enumerated()), id: \.offset) { _, step in
                        stepRow(step)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding(.horizontal, Chrome.chromeHorizontalPadding)
        .padding(.top, 8)
        .padding(.bottom, 8)
    }

    /// One step: its glyph, its words — what it is doing while it runs — and the spinner
    /// on the step that is under way.
    private func stepRow(_ step: TodoStep) -> some View {
        HStack(spacing: 8) {
            Image(systemName: Self.symbol(for: step.status))
                .font(.system(size: 12))
                .foregroundStyle(Self.iconColor(for: step.status))
            Text(verbatim: Self.text(for: step))
                .font(.system(size: 12.5))
                .foregroundStyle(Chrome.primaryText)
                .strikethrough(step.status == .done, color: .secondary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            if step.status == .active {
                MiniSpinner()
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background {
            if step.status == .active {
                Capsule().fill(Chrome.accent.opacity(0.14))
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            Text("\(Self.text(for: step)), \(step.status == .done ? "done" : (step.status == .active ? "in progress" : "not started"))")
        )
    }

    /// The step's words: while it is under way, the provider's own words for what it is
    /// doing; otherwise its plain text.
    private static func text(for step: TodoStep) -> String {
        if step.status == .active, let active = step.activeForm, !active.isEmpty { return active }
        return step.text
    }

    private static func symbol(for status: TodoStep.Status) -> String {
        switch status {
        case .pending: "circle"
        case .active: "circle.dotted.circle"
        case .done: "checkmark.circle.fill"
        }
    }

    private static func iconColor(for status: TodoStep.Status) -> Color {
        switch status {
        case .pending: Chrome.secondaryText
        case .active: Chrome.accent
        case .done: Chrome.success
        }
    }
}

/// The Artifacts tab: the files the agent produced, each with its additions and
/// deletions. Tapping a file opens its content — the diff for a code file, a
/// preview for an image, the rendered markdown for a document — and tapping it
/// again folds it back to the list. The list reads `changeStats` live.
private struct ArtifactsTab: View {
    @Environment(AppModel.self) private var model
    let runtime: ThreadRuntime

    @State private var selectedPath: String?
    @State private var detail: ArtifactDetail?

    var body: some View {
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
                    .padding(.top, 8)
                    .padding(.bottom, 12)
                }
            } else {
                emptyState
            }
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
