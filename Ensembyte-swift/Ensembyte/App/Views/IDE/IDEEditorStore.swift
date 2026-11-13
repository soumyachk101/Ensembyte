import Foundation
import Observation

/// The IDE pane's editor buffers and selection. Owned by `AppModel` so the
/// open files survive the pane toggling. The open files, dirty flags and
/// drift marks persist across launches through
/// `IDEEditorStore+Persistence.swift`, writing on every mutation.
@MainActor
@Observable
final class IDEEditorStore {
    /// A file open in the code view: its current text, the disk state its last
    /// load or save matched, and the last observed disk state.
    struct OpenFile: Identifiable {
        /// The file's path; also the buffer's identity.
        let path: String
        /// The buffer's current text.
        var text: String
        /// The `IDEFileIO.snapshot` of the disk state the text last matched, after a load or save.
        var savedSnapshot: String?
        /// The last observed `IDEFileIO.snapshot` of the file on disk.
        var diskSnapshot: String?
        /// The text as it stood when the buffer last loaded or saved; the user
        /// has typed when `text` and this differ.
        var editedText: String
        /// A disk drift has landed while the buffer is being edited.
        var hasDiskChange: Bool = false

        var id: String { path }

        /// Dirty means the user typed, or the buffer's text has diverged from
        /// the disk state it was last saved against.
        var isDirty: Bool {
            diskSnapshot != savedSnapshot || text != editedText
        }
    }

    var openFiles: [OpenFile] = []
    var selectedPath: String?

    /// Whether the buffer at `path`, when it is open, is dirty.
    func isDirty(_ path: String) -> Bool {
        openFiles.first { $0.path == path }?.isDirty ?? false
    }

    /// The buffer at `path`, when one is open.
    func openFile(at path: String) -> OpenFile? {
        openFiles.first { $0.path == path }
    }

    /// Loads `path` into a buffer and selects it. An already open file just
    /// re-selects; a file that cannot be read (binary or not text) is not opened.
    func open(_ path: String) {
        if openFiles.contains(where: { $0.path == path }) {
            selectedPath = path
            persistState()
            return
        }
        guard let text = IDEFileIO.readText(at: path) else { return }
        let snapshot = IDEFileIO.snapshot(of: path)
        openFiles.append(OpenFile(
            path: path,
            text: text,
            savedSnapshot: snapshot,
            diskSnapshot: snapshot,
            editedText: text
        ))
        selectedPath = path
        persistState()
    }

    /// The view's selection, without touching any buffer.
    func select(_ path: String?) {
        selectedPath = path
        persistState()
    }

    /// Writes the buffer's text to disk. Returns nil on success, or a short
    /// failure string the view can show; a failed write leaves the buffer dirty.
    @discardableResult
    func save(_ path: String) -> String? {
        guard let index = openFiles.firstIndex(where: { $0.path == path }) else {
            return "The file is no longer open."
        }
        do {
            try IDEFileIO.write(text: openFiles[index].text, to: path)
        } catch {
            return "Could not save \((path as NSString).lastPathComponent): \(error.localizedDescription)"
        }
        let snapshot = IDEFileIO.snapshot(of: path)
        openFiles[index].editedText = openFiles[index].text
        openFiles[index].savedSnapshot = snapshot
        openFiles[index].diskSnapshot = snapshot
        openFiles[index].hasDiskChange = false
        persistState()
        return nil
    }

    /// Re-reads `path` from disk into its buffer: the user's edits go, and the
    /// buffer's dirty and drift flags are cleared.
    func reload(_ path: String) {
        guard let index = openFiles.firstIndex(where: { $0.path == path }) else { return }
        let snapshot = IDEFileIO.snapshot(of: path)
        if let text = IDEFileIO.readText(at: path) {
            openFiles[index].text = text
        }
        openFiles[index].editedText = openFiles[index].text
        openFiles[index].savedSnapshot = snapshot
        openFiles[index].diskSnapshot = snapshot
        openFiles[index].hasDiskChange = false
        persistState()
    }

    /// Dismisses the drift banner without touching the buffer's text: the
    /// edits stay, and the buffer shows as dirty against the newer disk state.
    func keepMine(_ path: String) {
        guard let index = openFiles.firstIndex(where: { $0.path == path }) else { return }
        openFiles[index].hasDiskChange = false
        persistState()
    }

    /// Takes a fresh `IDEFileIO.snapshot` of every open file. A drift under a
    /// buffer the user is editing is flagged for the banner; a clean buffer
    /// silently takes the new text, so an agent's write lands without
    /// bothering it.
    func checkDiskDrift() {
        for index in openFiles.indices {
            let path = openFiles[index].path
            guard let fresh = IDEFileIO.snapshot(of: path),
                  fresh != openFiles[index].diskSnapshot else { continue }
            if openFiles[index].text != openFiles[index].editedText {
                openFiles[index].diskSnapshot = fresh
                openFiles[index].hasDiskChange = true
            } else if let text = IDEFileIO.readText(at: path) {
                openFiles[index].text = text
                openFiles[index].editedText = text
                // The buffer matches the new disk state again, so its saved
                // mark follows it and it reads as not dirty.
                openFiles[index].savedSnapshot = fresh
                openFiles[index].diskSnapshot = fresh
            } else {
                openFiles[index].diskSnapshot = fresh
                openFiles[index].hasDiskChange = true
            }
        }
        persistState()
    }
}
