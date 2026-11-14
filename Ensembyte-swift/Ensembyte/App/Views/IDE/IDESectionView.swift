import SwiftUI
import Foundation

/// The IDE pane's content: a tab bar over a Files tree-plus-editor and a
/// Changes diff list. The open buffers live in `AppModel.ideEditor`, so they
/// survive the pane toggling; the pane only writes a file when it is saved.
struct IDESectionView: View {
    @Environment(AppModel.self) private var model

    private enum Tab: Hashable {
        case files
        case changes
        case terminal
    }

    @State private var tab: Tab = .files
    @State private var selectedFile: String?

    var body: some View {
        VStack(spacing: 0) {
            tabBar
                .padding(.horizontal, Chrome.chromeHorizontalPadding)
                .padding(.top, Chrome.chromeTopPadding)
                .padding(.bottom, 8)

            switch tab {
            case .files:
                filesTab
            case .changes:
                changesTab
            case .terminal:
                terminalTab
            }
        }
    }

    // MARK: - Tab bar

    private var tabBar: some View {
        HStack(spacing: 2) {
            segment("Files", for: .files)
            segment("Changes", for: .changes)
            segment("Terminal", for: .terminal)
            Spacer()
        }
        .frame(height: Chrome.capsuleContentHeight)
        .chromeGlassCapsule()
        .background { NoWindowDragArea() }
        .animation(Chrome.hover, value: tab)
    }

    private func segment(_ title: String, for target: Tab) -> some View {
        let isSelected = tab == target
        return Button {
            guard tab != target else { return }
            withAnimation(Chrome.hover) { tab = target }
        } label: {
            Text(verbatim: title)
                .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? Chrome.primaryText : Chrome.secondaryText)
                .lineLimit(1)
                .padding(.horizontal, 9)
                .frame(height: 22)
                .background(
                    Capsule(style: .continuous)
                        .fill(isSelected ? Chrome.accent.opacity(0.22) : Chrome.overlay(0))
                )
                .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityLabel(Text(verbatim: title))
    }

    // MARK: - Files tab

    private var filesTab: some View {
        let directory = model.workingDirectory
        let content: some View = Group {
            if directory == nil {
                emptyHint("Select a thread to browse its files.")
            } else {
                HStack(spacing: 0) {
                    FileTreeColumn(directory: directory!, store: model.ideEditor, selectedFile: $selectedFile)
                        .frame(width: 200)
                    Rectangle()
                        .fill(Chrome.overlay(0.12))
                        .frame(width: 1)
                    EditorColumn(store: model.ideEditor, selectedFile: $selectedFile)
                }
            }
        }
        .onChange(of: selectedFile) { _, path in
            // The tree's pick is the editor's: open it into a buffer, and keep
            // the store's selection in step with the tree's highlight.
            if let path { model.ideEditor.open(path) }
            model.ideEditor.select(path)
        }
        return content
    }

    @ViewBuilder
    private var changesTab: some View {
        let directory = model.workingDirectory
        if directory == nil {
            emptyHint("Select a thread to see its changes.")
        } else {
            ChangesColumn(directory: directory!, store: model.ideEditor)
        }
    }

    // MARK: - Terminal tab

    /// The Terminal tab: the thread's own shell, shared with the chat's bottom
    /// terminal through the store, so the two show the same shell.
    @ViewBuilder
    private var terminalTab: some View {
        let directory = model.workingDirectory
        if let threadID = model.selectedThreadID, let directory {
            IDETerminalView(
                threadID: threadID,
                directory: directory,
                runtime: model.runtime(for: threadID),
                onReturnToFiles: { tab = .files }
            )
        } else {
            emptyHint("Select a thread to open its terminal.")
        }
    }

    private func emptyHint(_ text: String) -> some View {
        VStack {
            Spacer()
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(Chrome.secondaryText)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - File tree

/// The tree column of the Files tab: up to three levels of directories, each
/// expandable, children listed on demand, files selectable to open in the editor,
/// and a small mark on the ones whose buffer is dirty.
private struct FileTreeColumn: View {
    let directory: String
    let store: IDEEditorStore
    @Binding var selectedFile: String?

    /// Three visible levels: the root's children at depth 0 down to depth 2.
    private static let maxDepth = 2

    @State private var nodes: [IDEFileNode] = []
    @State private var expanded: Set<String> = []
    @State private var loadedChildren: [String: [IDEFileNode]] = [:]
    @State private var fileFilter = ""

    var body: some View {
        VStack(spacing: 0) {
            filterField
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(filteredRows) { entry in
                        rowView(entry.node, depth: entry.depth)
                    }
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .font(.system(size: 12))
        // One-level listing; restarting when the working directory moves keeps
        // the root in step with the thread, and the state resets with it.
        .task(id: directory) {
            nodes = IDEFileTree.children(of: directory) ?? []
            expanded.removeAll()
            loadedChildren.removeAll()
            fileFilter = ""
        }
        // The drift tick lives here, not in the Changes column's poll, so an
        // agent write to an open buffer is detected on this tab too.
        .task(id: directory) {
            while !Task.isCancelled {
                store.checkDiskDrift()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    /// The filter field up top: while it has text, the tree narrows to the
    /// matching rows instead of the full visible tree.
    private var filterField: some View {
        TextField("Filter…", text: $fileFilter)
            .textFieldStyle(.plain)
            .font(.system(size: 12))
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Chrome.overlay(0.08)))
            .padding(.horizontal, 4)
            .padding(.top, 6)
    }

    /// A visible tree row: a node and how deep it sits, addressed by the
    /// node's id (unique within one tree).
    private struct Row: Identifiable {
        let node: IDEFileNode
        let depth: Int
        var id: String { node.id }
    }

    /// The tree flattened to the rows that show right now: each open
    /// directory's children indented under it, up to the depth cap.
    private var visibleRows: [Row] {
        var rows: [Row] = []
        for node in nodes { append(node, depth: 0, into: &rows) }
        return rows
    }

    /// The rows on screen: the full visible tree while the filter is empty,
    /// else only the matching rows — a directory counts as a match when one
    /// of its already-loaded descendants does, so the path to a hit stays visible.
    private var filteredRows: [Row] {
        guard !fileFilter.isEmpty else { return visibleRows }
        let query = fileFilter.lowercased()
        return visibleRows.filter { row in
            let node = row.node
            if !node.isDirectory {
                return node.name.lowercased().contains(query) || node.relativePath.lowercased().contains(query)
            }
            return node.name.lowercased().contains(query)
                || descendantMatches(node, query: query)
        }
    }

    /// Whether any already-loaded child of `directory` matches `query`; the
    /// filter only sees what the tree has listed so far, which is the set the
    /// user can act on without expanding.
    private func descendantMatches(_ directory: IDEFileNode, query: String) -> Bool {
        (loadedChildren[directory.id] ?? [])
            .contains { $0.isDirectory
                ? ($0.name.lowercased().contains(query) || descendantMatches($0, query: query))
                : ($0.name.lowercased().contains(query) || $0.relativePath.lowercased().contains(query))
            }
    }

    private func append(_ node: IDEFileNode, depth: Int, into rows: inout [Row]) {
        rows.append(Row(node: node, depth: depth))
        if node.isDirectory, expanded.contains(node.id), depth < Self.maxDepth {
            for child in loadedChildren[node.id] ?? [] {
                append(child, depth: depth + 1, into: &rows)
            }
        }
    }

    @ViewBuilder
    private func rowView(_ node: IDEFileNode, depth: Int) -> some View {
        if node.isDirectory {
            directoryRow(node, depth: depth)
        } else {
            fileRow(node, depth: depth)
        }
    }

    private func directoryRow(_ node: IDEFileNode, depth: Int) -> some View {
        let isOpen = expanded.contains(node.id)
        let canExpand = depth < Self.maxDepth
        return HStack(spacing: 4) {
            if canExpand {
                Image(systemName: isOpen ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9))
                    .foregroundStyle(Chrome.secondaryText)
                    .frame(width: 11)
            } else {
                Spacer().frame(width: 11)
            }
            Image(systemName: isOpen ? "folder.open" : "folder")
                .font(.system(size: 11))
                .foregroundStyle(Chrome.secondaryText)
            Text(node.name)
                .lineLimit(1)
                .foregroundStyle(Chrome.primaryText)
        }
        .padding(.leading, CGFloat(depth) * 12)
        .contentShape(Rectangle())
        .onTapGesture {
            guard canExpand else { return }
            // Selecting a directory expands it rather than loading it; the
            // children are listed only the first time it opens.
            if isOpen {
                expanded.remove(node.id)
            } else {
                expanded.insert(node.id)
                if loadedChildren[node.id] == nil {
                    loadedChildren[node.id] = IDEFileTree.children(of: node.id) ?? []
                }
            }
        }
        .accessibilityLabel(node.name)
    }

    private func fileRow(_ node: IDEFileNode, depth: Int) -> some View {
        let isSelected = selectedFile == node.id
        let isDirty = store.isDirty(node.id)
        return HStack(spacing: 4) {
            Spacer().frame(width: 11)
            Image(systemName: IDEFileIcon.symbol(for: node.id))
                .font(.system(size: 11))
                .foregroundStyle(isSelected ? Chrome.accent : Chrome.secondaryText)
            Text(node.name)
                .lineLimit(1)
                .foregroundStyle(Chrome.primaryText)
            if isDirty {
                // The buffer's unsaved mark: it sits after the name, and with the
                // row's trailing background it tucks into the row's edge.
                Circle()
                    .fill(Chrome.accent)
                    .frame(width: 4, height: 4)
            }
        }
        .padding(.leading, CGFloat(depth) * 12)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Chrome.accent.opacity(0.14))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            // The pick both opens the buffer and moves the tree's highlight;
            // the parent's `onChange` of the selection is where the open lands.
            selectedFile = node.id
        }
        .accessibilityLabel(node.name)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Editor

/// The editor column beside the tree: the open file's text in a SwiftUI
/// `TextEditor`, a save control up top, and a banner when the file changed
/// on disk under an edited buffer. The text lives in `IDEEditorStore`, not
/// here — this view only moves it.
private struct EditorColumn: View {
    let store: IDEEditorStore
    @Binding var selectedFile: String?

    /// The last failed save's note, shown under the header until it is cleared.
    @State private var saveError: String?

    /// The buffer currently on screen, when it is open.
    private var file: IDEEditorStore.OpenFile? {
        selectedFile.flatMap(store.openFile(at:))
    }

    var body: some View {
        Group {
            if let file {
                editorBody(file: file)
            } else {
                emptyHint(selectedFile == nil ? "Select a file to open it." : "Binary or too large")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func editorBody(file: IDEEditorStore.OpenFile) -> some View {
        VStack(spacing: 0) {
            header
            if let saveError {
                saveErrorStrip(saveError)
            }
            if file.hasDiskChange {
                driftBanner
            }
            editor(text: file.text, path: file.path)
            statusBar(for: file)
        }
    }

    /// The column's bottom line: the file's language on the left, its total
    /// line count on the right.
    private func statusBar(for file: IDEEditorStore.OpenFile) -> some View {
        HStack(spacing: 6) {
            Text(IDEFileIcon.language(file.path) ?? (file.path as NSString).pathExtension)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Chrome.secondaryText)
                .lineLimit(1)
            Spacer(minLength: 0)
            Text("\(store.openFile(at: file.path)?.text.split(separator: "\n").count ?? 0) lines")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Chrome.secondaryText)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Chrome.overlay(0.06))
    }

    /// The note under the header after a save that did not land; the buffer
    /// stays dirty and the control returns until the next save.
    private func saveErrorStrip(_ message: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 11))
                .foregroundStyle(Chrome.danger)
            Text(verbatim: message)
                .font(.system(size: 12))
                .foregroundStyle(Chrome.primaryText)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Chrome.overlay(0.08))
    }

    /// The text editor over the open buffer. It rebuilds when its path
    /// changes, so a keystroke into one file is read through the store rather
    /// than writing straight back into the array.
    private func editor(text: String, path: String) -> some View {
        TextEditor(text: textBinding(for: path))
            .font(.system(size: 12, design: .monospaced))
            .foregroundStyle(Chrome.primaryText)
            .scrollContentBackground(.hidden)
            .id(path)
            .padding(8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// A text binding for the buffer at `path` that also clears its drift
    /// flag: when the drift banner is up the user is looking at the old text,
    /// so a keystroke means they chose to keep their edits.
    private func textBinding(for path: String) -> Binding<String> {
        Binding {
            store.openFile(at: path)?.text ?? ""
        } set: { value in
            guard let index = store.openFiles.firstIndex(where: { $0.path == path }) else { return }
            store.openFiles[index].text = value
            store.openFiles[index].hasDiskChange = false
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text(verbatim: (file?.path as NSString?)?.lastPathComponent ?? "")
                .font(.system(size: 12))
                .foregroundStyle(Chrome.secondaryText)
                .lineLimit(1)
            if let file, file.isDirty {
                Text("Unsaved")
                    .font(.system(size: 11))
                    .foregroundStyle(Chrome.accent)
                    .padding(.horizontal, 6)
                    .frame(height: 16)
                    .background(Capsule(style: .continuous).fill(Chrome.accent.opacity(0.14)))
            }
            Spacer(minLength: 0)
            if let file, file.isDirty {
                saveButton(path: file.path)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    private func saveButton(path: String) -> some View {
        ChromeTextButton(symbol: "square.and.arrow.down", title: "Save", help: "Save \((path as NSString).lastPathComponent)") {
            // A failed write leaves the buffer dirty, and the note says why;
            // a success clears it.
            saveError = store.save(path)
        }
        .keyboardShortcut("s", modifiers: .command)
    }

    /// A disk drift under an edited buffer: the two ways out of it.
    private var driftBanner: some View {
        HStack(spacing: 8) {
            Text("This file changed on disk while you were editing it.")
                .font(.system(size: 12))
                .foregroundStyle(Chrome.primaryText)
                .lineLimit(1)
            Spacer(minLength: 0)
            Button {
                guard let path = selectedFile else { return }
                store.reload(path)
            } label: {
                Text("Reload")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Chrome.accent)
            .accessibilityLabel("Reload from disk")
            Button {
                guard let path = selectedFile else { return }
                store.keepMine(path)
            } label: {
                Text("Keep my edits")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Chrome.primaryText)
            .accessibilityLabel("Keep your edits")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background {
            Chrome.overlay(0.08)
            Divider().opacity(0.4)
        }
    }

    private func emptyHint(_ text: String) -> some View {
        VStack {
            Spacer()
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(Chrome.secondaryText)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Changes tab

/// The Changes tab: the working tree's diff, polled every two seconds while
/// on screen. The changed files list with their +/- counts; a tapped file
/// shows its hunks inline, added lines green-tinted, removed red.
private struct ChangesColumn: View {
    let directory: String
    let store: IDEEditorStore

    @State private var files: [DiffFile] = []
    @State private var selectedDiffPath: String?
    @State private var hasLoaded = false
    @State private var isPolling = false
    /// The directory the pane is pointed at now: an in-flight poll captures the
    /// one it started against and drops its result once this has moved on.
    @State private var currentDirectory = ""

    @ViewBuilder
    var body: some View {
        Group {
            if files.isEmpty {
                emptyHint(hasLoaded ? "No changes in the working tree" : "Loading changes…")
            } else {
                HStack(spacing: 0) {
                    VStack(spacing: 0) {
                        changesSummary
                        fileList
                    }
                    .frame(width: 220)
                    Rectangle()
                        .fill(Chrome.overlay(0.12))
                        .frame(width: 1)
                    diffDetail
                }
            }
        }
        // The loop runs while the pane is on screen and this tab is selected;
        // the task cancels when the view disappears, so switching tabs stops
        // it, and `isPolling` keeps one poll in flight at a time.
        .task(id: directory) {
            currentDirectory = directory
            while !Task.isCancelled {
                guard !isPolling else { break }
                isPolling = true
                await poll()
                isPolling = false
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    /// The list's header line: the grand total of changed files and their
    /// added/removed line counts across the whole working tree.
    private var changesSummary: some View {
        let totalAdd = files.reduce(0) { $0 + $1.additions }
        let totalDel = files.reduce(0) { $0 + $1.deletions }
        return HStack(spacing: 4) {
            Text("\(files.count) files")
                .foregroundStyle(Chrome.secondaryText)
            Text("+\(totalAdd)")
                .foregroundStyle(Color.green)
            Text("−\(totalDel)")
                .foregroundStyle(Color.red)
        }
        .font(.system(size: 11))
        .lineLimit(1)
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var fileList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(files) { file in
                    row(file)
                }
            }
            .padding(6)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// The diff on display, looked up from the newest poll by path so the open
    /// detail always shows the file's current hunks instead of a frozen
    /// snapshot; it reads back nil when the path leaves the working tree.
    private var selectedDiff: DiffFile? {
        guard let selectedDiffPath else { return nil }
        return files.first { $0.path == selectedDiffPath }
    }

    private var diffDetail: some View {
        Group {
            if let selectedDiff {
                if selectedDiff.hunks.isEmpty {
                    emptyHint(selectedDiff.isBinary ? "\(selectedDiff.name) is binary." : "No line-by-line diff for \(selectedDiff.name).")
                } else {
                    diffBody(for: selectedDiff)
                }
            } else {
                emptyHint("Select a changed file to see its diff.")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func row(_ file: DiffFile) -> some View {
        let isSelected = selectedDiffPath == file.path
        return HStack(spacing: 6) {
            Image(systemName: symbol(for: file))
                .font(.system(size: 11))
                .foregroundStyle(color(for: file))
                .frame(width: 13)
            VStack(alignment: .leading, spacing: 0) {
                Text(file.path)
                    .lineLimit(1)
                    .foregroundStyle(Chrome.primaryText)
                HStack(spacing: 8) {
                    Text("+\(file.additions)")
                        .foregroundStyle(Color.green)
                    Text("−\(file.deletions)")
                        .foregroundStyle(Color.red)
                }
                .font(.system(size: 10, design: .monospaced))
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Chrome.accent.opacity(0.14))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            selectedDiffPath = file.path
        }
        .accessibilityLabel("\(file.path), plus \(file.additions) lines, minus \(file.deletions) lines")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func diffBody(for file: DiffFile) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(file.hunks) { hunk in
                    Text(hunk.header)
                        .foregroundStyle(Chrome.secondaryText)
                        .padding(.vertical, 2)
                    ForEach(hunk.lines) { line in
                        diffLine(line)
                    }
                }
            }
            .padding(8)
            .font(.system(size: 12, design: .monospaced))
            .foregroundStyle(Chrome.primaryText)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func diffLine(_ line: DiffLine) -> some View {
        HStack(spacing: 6) {
            Text(line.kind == .addition ? "+" : (line.kind == .deletion ? "−" : " "))
                .foregroundStyle(
                    line.kind == .addition ? Color.green :
                    (line.kind == .deletion ? Color.red : Color.secondary)
                )
                .fontWeight(.bold)
                .frame(width: 10, alignment: .center)
            Text(line.text.isEmpty ? " " : line.text)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 1)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(
                    line.kind == .addition ? Color.green.opacity(0.12) :
                    (line.kind == .deletion ? Color.red.opacity(0.12) : Color.clear)
                )
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func symbol(for file: DiffFile) -> String {
        switch file.change {
        case .added: "plus.circle.fill"
        case .deleted: "minus.circle.fill"
        case .renamed: "arrow.right.circle.fill"
        case .modified: "pencil.circle.fill"
        }
    }

    private func color(for file: DiffFile) -> Color {
        switch file.change {
        case .added: .green
        case .deleted: .red
        case .renamed: .blue
        case .modified: .orange
        }
    }

    private func emptyHint(_ text: String) -> some View {
        VStack {
            Spacer()
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(Chrome.secondaryText)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// One poll: the patch answers the hunks, the numstat answers the counts a
    /// truncated patch would leave off, and the status-only paths (untracked
    /// files) come in so the list matches what the working tree shows.
    private func poll() async {
        // A thread switch cancels the poll loop but not this in-flight work, so capture the
        // directory this poll started with and re-check it before committing below.
        let startedIn = directory
        let git = Git(directory)
        let changes = await git.workingChanges()
        var parsed = DiffParser.parse(changes.patch)

        let numstatText = (try? await git.output([
            "diff", "HEAD", "--numstat", "-z", "--no-renames", "--no-ext-diff",
        ])) ?? ""
        // The numstat answers the counts a truncated patch would leave off; the
        // helper that already parses `--numstat -z` is reused rather than re-built.
        let counts: [String: RevertPreview.File]
        if let summary = try? RevertPreview(numstat: numstatText) {
            counts = Dictionary(summary.files.map { ($0.path, $0) }, uniquingKeysWith: { _, new in new })
        } else {
            counts = [:]
        }
        if !counts.isEmpty {
            parsed = parsed.map { file in
                var file = file
                if let count = counts[file.path] {
                    file.reportedAdditions = count.additions
                    file.reportedDeletions = count.deletions
                    file.isBinary = count.isBinary
                }
                return file
            }
        }

        let listed = Set(parsed.map(\.path))
        let untracked = changes.summary
            .split(separator: "\n")
            .compactMap { $0.hasPrefix("?? ") ? String($0.dropFirst(3)) : nil }
        parsed += untracked
            .filter { !listed.contains($0) }
            .map { DiffFile(path: $0, change: .added, isBinary: false, hunks: []) }

        // A stale poll from the previous thread's directory must not write onto the new one.
        guard startedIn == currentDirectory else { return }
        if let selectedDiffPath, !parsed.contains(where: { $0.path == selectedDiffPath }) {
            self.selectedDiffPath = nil
        }
        files = parsed
        hasLoaded = true
    }
}
