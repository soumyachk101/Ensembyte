import AppKit
import SwiftUI

/// Mode for inspecting diffs: Unified (single column inline) or Split (side-by-side).
enum DiffReviewMode: String, CaseIterable, Identifiable {
    case unified = "Unified"
    case split = "Split"

    var id: String { rawValue }
}

/// Target line for inline agent comments/feedback.
struct DiffCommentTarget: Identifiable, Equatable {
    let id = UUID()
    let path: String
    let lineNumber: Int
    let lineText: String
}

/// High-performance token differential helper for word-level diff highlights.
enum WordDiffHelper {
    struct Token: Identifiable, Equatable {
        let id: Int
        let text: String
        let isHighlighted: Bool
    }

    static func tokenize(_ string: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var inWhitespace = false
        for char in string {
            let isSpace = char.isWhitespace
            if current.isEmpty {
                current.append(char)
                inWhitespace = isSpace
            } else if isSpace == inWhitespace {
                current.append(char)
            } else {
                tokens.append(current)
                current = String(char)
                inWhitespace = isSpace
            }
        }
        if !current.isEmpty { tokens.append(current) }
        return tokens
    }

    static func highlight(text: String, counterpart: String?) -> [Token] {
        guard let counterpart, !counterpart.isEmpty else {
            return [Token(id: 0, text: text, isHighlighted: false)]
        }
        let tokensA = tokenize(counterpart)
        let tokensB = tokenize(text)
        let setA = Set(tokensA.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
        var result: [Token] = []
        for (i, tok) in tokensB.enumerated() {
            let trimmed = tok.trimmingCharacters(in: .whitespacesAndNewlines)
            let isChanged = !trimmed.isEmpty && !setA.contains(trimmed)
            result.append(Token(id: i, text: tok, isHighlighted: isChanged))
        }
        return result
    }
}

// MARK: - DiffInspector Main View

struct DiffInspector: View {
    let runtime: ThreadRuntime

    @State private var files: [DiffFile] = []
    @State private var summary = FileChangeSummary(files: [])
    @State private var isLoading = false
    @State private var collapsed: Set<String> = []
    @State private var acceptedFiles: Set<String> = []
    @State private var reviewMode: DiffReviewMode = .unified
    @State private var activeComment: DiffCommentTarget?
    @State private var changedTurns: [TurnRecord] = []
    @State private var scrollTarget: String?
    @State private var scrollRequest = 0
    @State private var isReverting = false
    @State private var feedbackSentNotice: String?

    private var loadKey: String {
        "\(runtime.diffRevision)-\(runtime.diffSelection?.uuidString ?? "all")-\(runtime.diffFocusRevision)"
    }

    var body: some View {
        @Bindable var runtime = runtime
        VStack(spacing: 0) {
            // Header Bar
            headerBar
                .padding(.horizontal, Chrome.chromeHorizontalPadding)
                .padding(.top, Chrome.chromeTopPadding)
                .padding(.bottom, 8)

            // Optional Feedback Sent Toast
            if let notice = feedbackSentNotice {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Chrome.success)
                    Text(notice)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(Chrome.primaryText)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Chrome.success.opacity(0.12), in: .rect(cornerRadius: 8, style: .continuous))
                .padding(.horizontal, Chrome.chromeHorizontalPadding)
                .padding(.bottom, 6)
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            if files.isEmpty {
                Group {
                    if isLoading {
                        ProgressView("Reading the diff…")
                    } else {
                        ContentUnavailableView(
                            "No changes yet",
                            systemImage: "doc.text.magnifyingglass",
                            description: Text("Files the agent changes appear here after each turn.")
                        )
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 10) {
                            // Completion Celebration Banner when all files are reviewed
                            if !files.isEmpty && acceptedFiles.count == files.count {
                                completionBanner
                            }

                            ForEach(files) { file in
                                DiffFileCard(
                                    file: file,
                                    isCollapsed: collapsed.contains(file.id),
                                    isAccepted: acceptedFiles.contains(file.id),
                                    reviewMode: reviewMode,
                                    activeComment: $activeComment,
                                    onToggleCollapse: {
                                        if collapsed.contains(file.id) {
                                            collapsed.remove(file.id)
                                        } else {
                                            collapsed.insert(file.id)
                                        }
                                    },
                                    onToggleAccepted: {
                                        if acceptedFiles.contains(file.id) {
                                            acceptedFiles.remove(file.id)
                                        } else {
                                            acceptedFiles.insert(file.id)
                                        }
                                    },
                                    onRevertFile: {
                                        Task { await revertFile(file.path) }
                                    },
                                    onSubmitComment: { target, comment in
                                        sendInlineFeedback(target: target, comment: comment)
                                    }
                                )
                                .equatable()
                                .id(file.id)
                            }
                        }
                        .padding(12)
                    }
                    .onChange(of: scrollRequest) {
                        guard let target = scrollTarget else { return }
                        DispatchQueue.main.async {
                            withAnimation(.smooth(duration: 0.25)) { proxy.scrollTo(target, anchor: .top) }
                        }
                    }
                }
            }
        }
        .task(id: loadKey) {
            if !runtime.hasCachedDiff(selection: runtime.diffSelection) {
                try? await Task.sleep(for: .milliseconds(180))
                guard !Task.isCancelled else { return }
            }
            await load()
        }
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        GlassEffectContainer(spacing: 2) {
            HStack(spacing: 8) {
                // Turn selection
                ChromeTextMenu(
                    symbol: "arrow.triangle.branch",
                    title: runtime.diffSelection
                        .flatMap { id in runtime.turns.first { $0.id == id } }
                        .map { "Turn \($0.index + 1)" } ?? "All changes",
                    help: "Choose which changes to show"
                ) {
                    PopoverItem("All changes", isChecked: runtime.diffSelection == nil) {
                        runtime.clearDiffFocus()
                        runtime.diffSelection = nil
                    }
                    ForEach(changedTurns) { turn in
                        PopoverItem("Turn \(turn.index + 1)", isChecked: runtime.diffSelection == turn.id) {
                            runtime.clearDiffFocus()
                            runtime.diffSelection = turn.id
                        }
                    }
                }

                if !files.isEmpty {
                    // Unified vs Split view toggle
                    ChromeSegmentedPicker(
                        options: [
                            ChromeSegmentedOption(value: .unified, title: "Unified", symbol: "rectangle.split.1x2"),
                            ChromeSegmentedOption(value: .split, title: "Split", symbol: "rectangle.split.2x1")
                        ],
                        selection: $reviewMode
                    )

                    Spacer(minLength: 4)

                    // Review status badge
                    HStack(spacing: 5) {
                        if !acceptedFiles.isEmpty {
                            Text("\(acceptedFiles.count)/\(files.count) reviewed")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Chrome.success)
                        } else {
                            Text(summary.files.count == 1 ? "1 file" : "\(summary.files.count) files")
                                .font(.system(size: 11))
                                .foregroundStyle(Chrome.secondaryText)
                        }
                        DiffStatLabel(additions: summary.additions, deletions: summary.deletions)
                    }

                    // Accept All Button
                    Button {
                        withAnimation(.smooth(duration: 0.2)) {
                            if acceptedFiles.count == files.count {
                                acceptedFiles.removeAll()
                            } else {
                                acceptedFiles = Set(files.map(\.id))
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: acceptedFiles.count == files.count ? "checkmark.circle.fill" : "checkmark.circle")
                            Text(acceptedFiles.count == files.count ? "Reviewed" : "Accept All")
                        }
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(acceptedFiles.count == files.count ? Chrome.success : Chrome.primaryText)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4.5)
                        .background(
                            acceptedFiles.count == files.count ? Chrome.success.opacity(0.18) : Chrome.overlay(0.08),
                            in: Capsule(style: .continuous)
                        )
                    }
                    .buttonStyle(.plain)
                    .help("Mark all file changes as accepted (⌘⏎)")
                    .keyboardShortcut(.return, modifiers: [.command])
                } else {
                    Spacer(minLength: 4)
                }

                // More & Dismiss
                ChromeCapsule {
                    ChromeMenuButton(symbol: "ellipsis", help: "More actions") {
                        PopoverItem("Expand all", symbol: "arrow.down.right.and.arrow.up.left") { collapsed.removeAll() }
                        PopoverItem("Collapse all", symbol: "arrow.up.left.and.arrow.down.right") { collapsed = Set(files.map(\.id)) }
                        if !files.isEmpty {
                            PopoverItem("Revert all changes", symbol: "arrow.counterclockwise") {
                                Task { await revertAll() }
                            }
                        }
                    }
                    ChromeDivider()
                    ChromeIconButton(symbol: "xmark", help: "Hide changes" + ShortcutStore.hint(for: .toggleChanges)) {
                        runtime.isDiffVisible = false
                    }
                }
            }
        }
    }

    // MARK: - Completion Banner

    private var completionBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 22))
                .foregroundStyle(Chrome.success)

            VStack(alignment: .leading, spacing: 2) {
                Text("All changes reviewed")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Chrome.primaryText)
                Text("All \(files.count) file modifications are accepted.")
                    .font(.system(size: 11))
                    .foregroundStyle(Chrome.secondaryText)
            }

            Spacer()

            Button("Reset") {
                withAnimation { acceptedFiles.removeAll() }
            }
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Chrome.secondaryText)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Chrome.overlay(0.08), in: Capsule(style: .continuous))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Chrome.success.opacity(0.12), in: .rect(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Chrome.success.opacity(0.3), lineWidth: 1)
        )
    }

    // MARK: - Actions

    private func load() async {
        let selection = runtime.diffSelection
        changedTurns = runtime.turnsWithChanges()
        isLoading = true
        defer { isLoading = false }
        let parsed = await runtime.parsedDiff(selection: selection)
        guard !Task.isCancelled else { return }
        let focusEdits = runtime.diffFocusEdits
        let missing = await Task.detached(priority: .userInitiated) { focusedFiles(focusEdits, missingFrom: parsed) }.value
        guard !Task.isCancelled else { return }
        files = missing.isEmpty ? parsed : missing + parsed
        summary = FileChangeSummary(files: files)
        let focus = Set(runtime.diffFocusEdits.map(\.path))
        let focused = focus.isEmpty ? [] : files.filter { TouchedPaths.matches($0, touched: focus) }.map(\.id)
        if !focused.isEmpty {
            collapsed = Set(files.map(\.id)).subtracting(focused)
            scrollTarget = focused.first
            scrollRequest += 1
        } else if files.count > 6, collapsed.isEmpty {
            collapsed = Set(files.dropFirst().map(\.id))
        } else {
            collapsed = collapsed.intersection(files.map(\.id))
        }
    }

    private func revertFile(_ path: String) async {
        guard !isReverting else { return }
        isReverting = true
        defer { isReverting = false }
        try? await runtime.revertFile(path: path)
        acceptedFiles.remove(path)
    }

    private func revertAll() async {
        guard !isReverting, !files.isEmpty else { return }
        isReverting = true
        defer { isReverting = false }
        try? await runtime.revertAllFiles(paths: files.map(\.path))
        acceptedFiles.removeAll()
    }

    private func sendInlineFeedback(target: DiffCommentTarget, comment: String) {
        let fileName = (target.path as NSString).lastPathComponent
        let feedback = "Regarding `\(fileName):\(target.lineNumber)`: \(comment)"
        if runtime.draft.text.isEmpty {
            runtime.draft.text = feedback
        } else {
            runtime.draft.text += "\n" + feedback
        }
        withAnimation {
            activeComment = nil
            feedbackSentNotice = "Comment added to chat composer: \(fileName):\(target.lineNumber)"
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            withAnimation {
                if feedbackSentNotice?.contains(fileName) == true {
                    feedbackSentNotice = nil
                }
            }
        }
    }
}

// MARK: - Focused Files Helper

private func focusedFiles(_ edits: [FileEdit], missingFrom files: [DiffFile]) -> [DiffFile] {
    var missing: [DiffFile] = []
    for edit in edits {
        guard !edit.path.isEmpty, let patch = edit.diff, !patch.isEmpty else { continue }
        let touched: Set<String> = [edit.path]
        guard !files.contains(where: { TouchedPaths.matches($0, touched: touched) }),
              !missing.contains(where: { TouchedPaths.matches($0, touched: touched) }) else { continue }
        let file = DiffParser.parseHunks(patch, path: edit.path)
        if !file.hunks.isEmpty { missing.append(file) }
    }
    return missing
}

// MARK: - DiffFileCard

private struct DiffFileCard: View, Equatable {
    let file: DiffFile
    let isCollapsed: Bool
    let isAccepted: Bool
    let reviewMode: DiffReviewMode
    @Binding var activeComment: DiffCommentTarget?
    let onToggleCollapse: () -> Void
    let onToggleAccepted: () -> Void
    let onRevertFile: () -> Void
    let onSubmitComment: (DiffCommentTarget, String) -> Void

    @State private var isHovering = false

    nonisolated static func == (lhs: DiffFileCard, rhs: DiffFileCard) -> Bool {
        MainActor.assumeIsolated {
            lhs.file.id == rhs.file.id
                && lhs.file.additions == rhs.file.additions
                && lhs.file.deletions == rhs.file.deletions
                && lhs.file.hunks.count == rhs.file.hunks.count
                && lhs.file.change == rhs.file.change
                && lhs.file.isBinary == rhs.file.isBinary
                && lhs.isCollapsed == rhs.isCollapsed
                && lhs.isAccepted == rhs.isAccepted
                && lhs.reviewMode == rhs.reviewMode
                && lhs.activeComment?.path == rhs.activeComment?.path
                && lhs.activeComment?.lineNumber == rhs.activeComment?.lineNumber
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // File Card Header
            HStack(spacing: 8) {
                Button(action: onToggleCollapse) {
                    HStack(spacing: 7) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.tertiary)
                            .rotationEffect(.degrees(isCollapsed ? 0 : 90))

                        Image(systemName: symbol)
                            .foregroundStyle(color)

                        Text("\(Text(file.directory).foregroundStyle(.secondary))\(file.name)")
                            .font(.system(size: 13, weight: .medium))
                            .lineLimit(1)
                            .truncationMode(.head)
                    }
                }
                .buttonStyle(.plain)

                // Change status badge
                Text(changeBadgeText)
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(color)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(color.opacity(0.12), in: Capsule(style: .continuous))

                Spacer(minLength: 8)

                DiffStatLabel(additions: file.additions, deletions: file.deletions)

                // Copy Path
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(file.path, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 11))
                        .foregroundStyle(Chrome.secondaryText)
                }
                .buttonStyle(.plain)
                .help("Copy file path")

                // Revert File Button
                Button(action: onRevertFile) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 11))
                        .foregroundStyle(Chrome.danger.opacity(0.8))
                }
                .buttonStyle(.plain)
                .help("Revert changes in this file")

                // Accept File Button
                Button(action: onToggleAccepted) {
                    HStack(spacing: 3) {
                        Image(systemName: isAccepted ? "checkmark.circle.fill" : "checkmark.circle")
                        Text(isAccepted ? "Accepted" : "Accept")
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(isAccepted ? Chrome.success : Chrome.secondaryText)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(isAccepted ? Chrome.success.opacity(0.18) : Chrome.overlay(0.08), in: Capsule(style: .continuous))
                }
                .buttonStyle(.plain)
                .help(isAccepted ? "Marked as reviewed" : "Mark as accepted")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(.rect)
            .background(isAccepted ? Chrome.success.opacity(0.06) : Color.clear)

            if !isCollapsed {
                Divider().opacity(0.4)

                if file.isBinary || file.hunks.isEmpty {
                    Text(file.isBinary ? "Binary file" : "Diff details unavailable")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                } else {
                    if reviewMode == .unified {
                        DiffLinesView(
                            file: file,
                            showsLineNumbers: true,
                            activeComment: $activeComment,
                            onSubmitComment: onSubmitComment
                        )
                        .equatable()
                        .padding(.bottom, 6)
                    } else {
                        DiffLinesSplitView(
                            file: file,
                            activeComment: $activeComment,
                            onSubmitComment: onSubmitComment
                        )
                        .equatable()
                        .padding(.bottom, 6)
                    }
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isAccepted ? Color.green.opacity(0.07) : Color.primary.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(isAccepted ? Chrome.success.opacity(0.35) : Chrome.overlay(0.12), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onHover { isHovering = $0 }
    }

    private var changeBadgeText: String {
        switch file.change {
        case .added: "Added"
        case .deleted: "Deleted"
        case .renamed: "Renamed"
        case .modified: "Modified"
        }
    }

    private var symbol: String {
        switch file.change {
        case .added: "plus.circle.fill"
        case .deleted: "minus.circle.fill"
        case .renamed: "arrow.right.circle.fill"
        case .modified: "pencil.circle.fill"
        }
    }

    private var color: Color {
        switch file.change {
        case .added: .green
        case .deleted: .red
        case .renamed: .blue
        case .modified: .orange
        }
    }
}

// MARK: - DiffLinesView (Unified Mode)

struct DiffLinesView: View, Equatable {
    let file: DiffFile
    var showsLineNumbers = true
    var activeComment: Binding<DiffCommentTarget?>? = nil
    var onSubmitComment: ((DiffCommentTarget, String) -> Void)? = nil

    nonisolated static func == (lhs: DiffLinesView, rhs: DiffLinesView) -> Bool {
        MainActor.assumeIsolated {
            lhs.sectionsKey == rhs.sectionsKey
                && lhs.showsLineNumbers == rhs.showsLineNumbers
                && lhs.activeComment?.wrappedValue?.path == rhs.activeComment?.wrappedValue?.path
                && lhs.activeComment?.wrappedValue?.lineNumber == rhs.activeComment?.wrappedValue?.lineNumber
        }
    }

    private var sectionsKey: String {
        "\(file.id)|\(file.hunks.count)|\(file.additions)|\(file.deletions)|\(totalLines)"
    }

    @State private var showsAll = false
    @State private var sections: [Section] = []

    private nonisolated static let collapsedLineLimit = 250
    private nonisolated static let tintedChunk = 40

    private var totalLines: Int {
        file.hunks.reduce(0) { $0 + $1.lines.count }
    }

    enum Section: Identifiable, Equatable {
        case header(String, Int)
        case tinted(lines: [DiffLine], counterparts: [String?], offset: Int, count: Int)
        case plain([DiffLine])

        var id: String {
            switch self {
            case .header(let text, let index): "h\(index)-\(text)"
            case .tinted(let lines, _, _, _): "t\(lines.first?.id ?? 0)"
            case .plain(let lines): "p\(lines.first?.id ?? 0)"
            }
        }
    }

    nonisolated static func makeSections(file: DiffFile, showsLineNumbers: Bool, limit: Int) -> [Section] {
        var sections: [Section] = []
        var remaining = limit

        for (hunkIndex, hunk) in file.hunks.enumerated() {
            guard !hunk.lines.isEmpty, remaining > 0 else { continue }
            if showsLineNumbers {
                sections.append(.header(hunk.header, hunkIndex))
            }

            var i = 0
            let lines = Array(hunk.lines.prefix(remaining))
            remaining -= lines.count

            while i < lines.count {
                let line = lines[i]
                if line.kind == .addition || line.kind == .deletion {
                    var run: [DiffLine] = []
                    while i < lines.count && (lines[i].kind == .addition || lines[i].kind == .deletion) {
                        run.append(lines[i])
                        i += 1
                    }
                    let dels = run.filter { $0.kind == .deletion }
                    let adds = run.filter { $0.kind == .addition }
                    var counterparts: [String?] = []
                    var delIndex = 0
                    var addIndex = 0
                    for r in run {
                        if r.kind == .deletion {
                            counterparts.append(addIndex < adds.count ? adds[addIndex].text : nil)
                            delIndex += 1
                        } else {
                            counterparts.append(delIndex <= dels.count && delIndex > 0 ? dels[delIndex - 1].text : (dels.first?.text))
                            addIndex += 1
                        }
                    }

                    for start in stride(from: 0, to: run.count, by: Self.tintedChunk) {
                        let end = min(start + Self.tintedChunk, run.count)
                        sections.append(.tinted(
                            lines: Array(run[start..<end]),
                            counterparts: Array(counterparts[start..<end]),
                            offset: start,
                            count: run.count
                        ))
                    }
                } else {
                    var plainRun: [DiffLine] = []
                    while i < lines.count && lines[i].kind != .addition && lines[i].kind != .deletion {
                        plainRun.append(lines[i])
                        i += 1
                    }
                    sections.append(.plain(plainRun))
                }
            }
        }
        return sections
    }

    @ViewBuilder private func rowList(_ rows: [Section]) -> some View {
        ForEach(rows) { section in
            switch section {
            case .header(let text, _):
                HStack(spacing: 6) {
                    Image(systemName: "number")
                        .font(.system(size: 9))
                    Text(text)
                }
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(Chrome.secondaryText)
                .lineLimit(1)
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Chrome.overlay(0.04))

            case .tinted(let lines, let counterparts, let offset, let count):
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(lines.enumerated()), id: \.element.id) { index, line in
                        DiffLineRow(
                            file: file,
                            line: line,
                            counterpartText: index < counterparts.count ? counterparts[index] : nil,
                            showsLineNumbers: showsLineNumbers,
                            activeComment: activeComment,
                            onSubmitComment: onSubmitComment,
                            rounding: DiffLineRow.blockRounding(index: offset + index, count: count)
                        )
                    }
                }

            case .plain(let lines):
                ForEach(lines) { line in
                    DiffLineRow(
                        file: file,
                        line: line,
                        counterpartText: nil,
                        showsLineNumbers: showsLineNumbers,
                        activeComment: activeComment,
                        onSubmitComment: onSubmitComment
                    )
                }
            }
        }

        if !showsAll, totalLines > Self.collapsedLineLimit {
            Button {
                showsAll.toggle()
            } label: {
                Text("Show all \(totalLines) lines")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.quaternary.opacity(0.5), in: Capsule(style: .continuous))
                    .contentShape(.capsule)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
    }

    var body: some View {
        let budget = showsAll ? Int.max : Self.collapsedLineLimit
        let rows = sections.isEmpty ? Self.makeSections(file: file, showsLineNumbers: showsLineNumbers, limit: budget) : sections
        Group {
            if showsAll, totalLines > Self.collapsedLineLimit {
                LazyVStack(alignment: .leading, spacing: 0) { rowList(rows) }
            } else {
                VStack(alignment: .leading, spacing: 0) { rowList(rows) }
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .font(.system(size: 11.5, design: .monospaced))
        .textSelection(.enabled)
        .onChange(of: "\(sectionsKey)|\(showsAll)", initial: true) {
            sections = Self.makeSections(file: file, showsLineNumbers: showsLineNumbers, limit: showsAll ? Int.max : Self.collapsedLineLimit)
        }
    }
}

// MARK: - DiffLineRow

private struct DiffLineRow: View {
    let file: DiffFile
    let line: DiffLine
    let counterpartText: String?
    let showsLineNumbers: Bool
    var activeComment: Binding<DiffCommentTarget?>? = nil
    var onSubmitComment: ((DiffCommentTarget, String) -> Void)? = nil
    var rounding = UnevenRoundedRectangle(
        topLeadingRadius: 0, bottomLeadingRadius: 0,
        bottomTrailingRadius: 0, topTrailingRadius: 0, style: .continuous
    )

    @State private var isHovering = false

    private var isCommentActive: Bool {
        guard let comment = activeComment?.wrappedValue else { return false }
        return comment.path == file.path && comment.lineNumber == (line.newNumber ?? line.oldNumber)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 0) {
                // Line numbers
                if showsLineNumbers {
                    Text(line.oldNumber.map(String.init) ?? "")
                        .frame(width: Self.numberColumnWidth, alignment: .trailing)
                        .foregroundStyle(Color.secondary.opacity(0.55))
                    Text(line.newNumber.map(String.init) ?? "")
                        .frame(width: Self.numberColumnWidth, alignment: .trailing)
                        .foregroundStyle(Color.secondary.opacity(0.55))
                }

                // Marker (+ or -)
                Text(marker)
                    .frame(width: Self.markerColumnWidth, alignment: .center)
                    .foregroundStyle(markerColor)
                    .fontWeight(.bold)

                // Line Text with word-level highlight
                lineContent
                    .frame(maxWidth: .infinity, alignment: .leading)

                // Inline comment trigger button on hover
                if (isHovering || isCommentActive), activeComment != nil {
                    Button {
                        if isCommentActive {
                            activeComment?.wrappedValue = nil
                        } else {
                            activeComment?.wrappedValue = DiffCommentTarget(
                                path: file.path,
                                lineNumber: line.newNumber ?? line.oldNumber ?? 1,
                                lineText: line.text
                            )
                        }
                    } label: {
                        Image(systemName: isCommentActive ? "bubble.left.and.bubble.right.fill" : "bubble.left.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(isCommentActive ? Chrome.accent : Chrome.secondaryText)
                            .padding(4)
                            .background(Chrome.overlay(0.12), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Leave inline comment on line \(line.newNumber ?? line.oldNumber ?? 0)")
                    .padding(.trailing, 4)
                }
            }
            .padding(.vertical, 1)
            .padding(.leading, 6)
            .padding(.trailing, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(background, in: rounding)
            .contentShape(.rect)
            .onHover { isHovering = $0 }

            // Inline comment composer box
            if isCommentActive, let target = activeComment?.wrappedValue {
                DiffInlineCommentBox(
                    target: target,
                    fileName: file.name,
                    onSend: { text in
                        onSubmitComment?(target, text)
                    },
                    onCancel: {
                        activeComment?.wrappedValue = nil
                    }
                )
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
            }
        }
    }

    @ViewBuilder
    private var lineContent: some View {
        if line.kind == .addition || line.kind == .deletion, let counterpart = counterpartText {
            let tokens = WordDiffHelper.highlight(text: line.text, counterpart: counterpart)
            HStack(spacing: 0) {
                ForEach(tokens) { token in
                    Text(token.text.isEmpty ? " " : token.text)
                        .foregroundStyle(line.kind == .note ? .secondary : .primary)
                        .background(
                            token.isHighlighted
                                ? (line.kind == .addition ? Color.green.opacity(0.32) : Color.red.opacity(0.32))
                                : Color.clear,
                            in: .rect(cornerRadius: 3, style: .continuous)
                        )
                }
            }
        } else {
            Text(line.text.isEmpty ? " " : line.text)
                .foregroundStyle(line.kind == .note ? .secondary : .primary)
        }
    }

    private static let numberColumnWidth: CGFloat = 30
    private static let markerColumnWidth: CGFloat = 14

    static func blockRounding(index: Int, count: Int) -> UnevenRoundedRectangle {
        let radius: CGFloat = 6
        let top = index == 0
        let bottom = index == count - 1
        return UnevenRoundedRectangle(
            topLeadingRadius: top ? radius : 0,
            bottomLeadingRadius: bottom ? radius : 0,
            bottomTrailingRadius: bottom ? radius : 0,
            topTrailingRadius: top ? radius : 0,
            style: .continuous
        )
    }

    private var marker: String {
        switch line.kind {
        case .addition: "+"
        case .deletion: "−"
        case .context, .note: ""
        }
    }

    private var markerColor: Color {
        switch line.kind {
        case .addition: .green
        case .deletion: .red
        default: .secondary
        }
    }

    private var background: Color {
        switch line.kind {
        case .addition: .green.opacity(0.12)
        case .deletion: .red.opacity(0.12)
        default: .clear
        }
    }
}

// MARK: - DiffLinesSplitView (Side-by-Side Split Mode)

struct DiffLinesSplitView: View, Equatable {
    let file: DiffFile
    @Binding var activeComment: DiffCommentTarget?
    let onSubmitComment: (DiffCommentTarget, String) -> Void

    nonisolated static func == (lhs: DiffLinesSplitView, rhs: DiffLinesSplitView) -> Bool {
        MainActor.assumeIsolated {
            lhs.file.id == rhs.file.id
                && lhs.file.hunks.count == rhs.file.hunks.count
                && lhs.activeComment?.path == rhs.activeComment?.path
                && lhs.activeComment?.lineNumber == rhs.activeComment?.lineNumber
        }
    }

    struct SplitPair: Identifiable {
        let id: Int
        let left: DiffLine?
        let right: DiffLine?
    }

    private var pairs: [SplitPair] {
        var result: [SplitPair] = []
        var idCounter = 0

        for hunk in file.hunks {
            var i = 0
            let lines = hunk.lines
            while i < lines.count {
                let line = lines[i]
                if line.kind == .context {
                    result.append(SplitPair(id: idCounter, left: line, right: line))
                    idCounter += 1
                    i += 1
                } else if line.kind == .deletion || line.kind == .addition {
                    var dels: [DiffLine] = []
                    var adds: [DiffLine] = []
                    while i < lines.count && (lines[i].kind == .deletion || lines[i].kind == .addition) {
                        if lines[i].kind == .deletion { dels.append(lines[i]) }
                        else { adds.append(lines[i]) }
                        i += 1
                    }
                    let count = max(dels.count, adds.count)
                    for k in 0..<count {
                        let leftLine = k < dels.count ? dels[k] : nil
                        let rightLine = k < adds.count ? adds[k] : nil
                        result.append(SplitPair(id: idCounter, left: leftLine, right: rightLine))
                        idCounter += 1
                    }
                } else {
                    i += 1
                }
            }
        }
        return result
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(pairs) { pair in
                HStack(alignment: .top, spacing: 0) {
                    // Left Cell (Old / Deletion)
                    cellView(line: pair.left, counterpart: pair.right?.text, side: .left)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    // Vertical Divider
                    Rectangle()
                        .fill(Chrome.overlay(0.12))
                        .frame(width: 1)

                    // Right Cell (New / Addition)
                    cellView(line: pair.right, counterpart: pair.left?.text, side: .right)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .font(.system(size: 11, design: .monospaced))
        .textSelection(.enabled)
    }

    enum Side { case left, right }

    @ViewBuilder
    private func cellView(line: DiffLine?, counterpart: String?, side: Side) -> some View {
        if let line {
            HStack(alignment: .top, spacing: 0) {
                Text(String(side == .left ? (line.oldNumber ?? 0) : (line.newNumber ?? 0)))
                    .frame(width: 28, alignment: .trailing)
                    .foregroundStyle(Color.secondary.opacity(0.55))
                    .padding(.trailing, 4)

                Text(line.kind == .addition ? "+" : (line.kind == .deletion ? "−" : " "))
                    .frame(width: 12, alignment: .center)
                    .foregroundStyle(line.kind == .addition ? Color.green : (line.kind == .deletion ? Color.red : Color.secondary))
                    .fontWeight(.bold)

                if (line.kind == .addition || line.kind == .deletion), let counterpart {
                    let tokens = WordDiffHelper.highlight(text: line.text, counterpart: counterpart)
                    HStack(spacing: 0) {
                        ForEach(tokens) { tok in
                            Text(tok.text.isEmpty ? " " : tok.text)
                                .background(
                                    tok.isHighlighted
                                        ? (line.kind == .addition ? Color.green.opacity(0.32) : Color.red.opacity(0.32))
                                        : Color.clear,
                                    in: .rect(cornerRadius: 2, style: .continuous)
                                )
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text(line.text.isEmpty ? " " : line.text)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.vertical, 1)
            .padding(.horizontal, 4)
            .background(cellBackground(for: line.kind))
        } else {
            Color.secondary.opacity(0.04)
                .frame(minHeight: 18)
        }
    }

    private func cellBackground(for kind: DiffLine.Kind) -> Color {
        switch kind {
        case .addition: Color.green.opacity(0.12)
        case .deletion: Color.red.opacity(0.12)
        default: Color.clear
        }
    }
}

// MARK: - DiffInlineCommentBox

private struct DiffInlineCommentBox: View {
    let target: DiffCommentTarget
    let fileName: String
    let onSend: (String) -> Void
    let onCancel: () -> Void

    @State private var text = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "bubble.left.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Chrome.accent)
                Text("Comment on \(fileName) : line \(target.lineNumber)")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(Chrome.primaryText)
                Spacer()
                Button(action: onCancel) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10))
                        .foregroundStyle(Chrome.secondaryText)
                }
                .buttonStyle(.plain)
            }

            TextEditor(text: $text)
                .font(.system(size: 12))
                .focused($isFocused)
                .frame(minHeight: 48, maxHeight: 96)
                .padding(6)
                .background(Color(nsColor: .textBackgroundColor).opacity(0.6), in: .rect(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Chrome.overlay(0.15), lineWidth: 1)
                )

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(Chrome.secondaryText)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)

                Button {
                    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                    onSend(text)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.circle.fill")
                        Text("Send to Agent")
                    }
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Chrome.accent, in: Capsule(style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(10)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.95), in: .rect(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Chrome.accent.opacity(0.3), lineWidth: 1)
        )
        .onAppear {
            isFocused = true
        }
    }
}

// MARK: - DiffPopoverCoordinator

@MainActor
final class DiffPopoverCoordinator: NSObject, NSPopoverDelegate {
    static let width: CGFloat = 780
    static let height: CGFloat = 580

    private let popover = NSPopover()
    private var anchor: WeakView?
    private var runtime: ThreadRuntime?
    private var desiredVisible = false
    private var monitors: [Any] = []
    private var session = 0
    private var pendingSession = 0

    override init() {
        super.init()
        popover.behavior = .semitransient
        popover.animates = true
        popover.delegate = self
    }

    func setAnchor(_ view: NSView) {
        anchor = WeakView(view)
        if desiredVisible { show() }
    }

    func sync(isVisible: Bool, runtime: ThreadRuntime) {
        if let current = self.runtime, current !== runtime {
            close()
            if current.isDiffVisible { current.isDiffVisible = false }
            self.runtime = runtime
            seenOpenRequest = runtime.diffOpenRequest
            if runtime.isDiffVisible, !WebsiteCaptures.isEnabled { runtime.isDiffVisible = false }
            return
        }
        if self.runtime == nil {
            self.runtime = runtime
            seenOpenRequest = runtime.diffOpenRequest
            if isVisible, !WebsiteCaptures.isEnabled {
                runtime.isDiffVisible = false
                return
            }
        }
        self.runtime = runtime
        desiredVisible = isVisible
        if isVisible { show() } else { close() }
    }

    func close() {
        stopMonitors()
        desiredVisible = false
        session += 1
        pendingSession = session
        if popover.isShown { popover.performClose(nil) }
    }

    func setFallbackAnchor(_ view: NSView) {
        fallback = WeakView(view)
        if desiredVisible { show() }
    }

    private var fallback: WeakView?
    private weak var shownOn: NSView?
    private weak var shownRuntime: ThreadRuntime?
    private var seenOpenRequest = 0

    func reopen(runtime: ThreadRuntime) {
        guard runtime === self.runtime else { sync(isVisible: runtime.isDiffVisible, runtime: runtime); return }
        guard runtime.diffOpenRequest != seenOpenRequest else { return }
        seenOpenRequest = runtime.diffOpenRequest
        desiredVisible = true
        if popover.isShown {
            if shownOn === resolvedAnchor()?.view { return }
            stopMonitors()
            session += 1
            pendingSession = session
            popover.close()
        }
        show()
    }

    private func resolvedAnchor() -> (view: NSView, edge: NSRectEdge)? {
        if let runtime, let view = runtime.diffAnchor?.value, view.window != nil {
            return (view, runtime.diffAnchorEdge)
        }
        guard let view = [anchor?.value, fallback?.value].compactMap({ $0 }).first(where: { $0.window != nil }) else {
            return nil
        }
        return (view, .maxY)
    }

    private func show() {
        guard let runtime, let target = resolvedAnchor() else { return }
        session += 1
        guard !popover.isShown else { return }
        popover.setFixedContent(DiffInspector(runtime: runtime), size: NSSize(width: Self.width, height: Self.height))
        startMonitors()
        shownOn = target.view
        shownRuntime = runtime
        popover.show(relativeTo: target.view.bounds, of: target.view, preferredEdge: target.edge)
    }

    nonisolated func popoverDidClose(_ notification: Notification) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.stopMonitors()
            self.desiredVisible = false
            if self.session == self.pendingSession {
                if let shown = self.shownRuntime, shown.isDiffVisible { shown.isDiffVisible = false }
                self.popover.contentViewController = nil
            }
            self.shownRuntime = nil
        }
    }

    private func handleMouseDown(_ event: NSEvent) -> NSEvent? {
        if event.window === popover.contentViewController?.view.window { return event }
        close()
        return event
    }

    private func handleKeyDown(_ event: NSEvent) -> NSEvent? {
        guard event.keyCode == 53 else { return event } // Escape
        close()
        return nil
    }

    private func startMonitors() {
        guard monitors.isEmpty else { return }
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] event in
            self?.handleMouseDown(event) ?? event
        }) {
            monitors.append(monitor)
        }
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            self?.handleKeyDown(event) ?? event
        }) {
            monitors.append(monitor)
        }
    }

    private func stopMonitors() {
        for monitor in monitors { NSEvent.removeMonitor(monitor) }
        monitors.removeAll()
    }
}
