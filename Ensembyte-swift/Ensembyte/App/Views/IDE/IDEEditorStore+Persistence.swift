import Foundation

/// The IDE pane's persisted editor state: the open buffers and the selection,
/// one file on disk under `StoragePaths.directory("ide")`.
struct IDEPaneState: Codable {
    var files: [FileState]
    var selectedPath: String?

    /// One `OpenFile`'s fields, mirrored 1:1 for the buffer.
    struct FileState: Codable {
        var path: String
        var text: String
        var savedSnapshot: String?
        var diskSnapshot: String?
        var editedText: String
        var hasDiskChange: Bool
    }
}

extension IDEEditorStore {
    /// The pane state's file, under the app's Application Support folder.
    private var stateURL: URL {
        StoragePaths.directory("ide").appendingPathComponent("editorState.json")
    }

    /// Restores the open files and selection from disk. A missing or corrupt
    /// file leaves the state empty; this never throws.
    func loadState() {
        guard let data = try? Data(contentsOf: stateURL),
              let state = try? JSONDecoder().decode(IDEPaneState.self, from: data) else { return }
        openFiles = state.files.map { file in
            OpenFile(
                path: file.path,
                text: file.text,
                savedSnapshot: file.savedSnapshot,
                diskSnapshot: file.diskSnapshot,
                editedText: file.editedText
            )
        }
        // `hasDiskChange` keeps its on-disk value: a drift that landed while
        // the app was closed resurfaces as the banner, not silently.
        for index in openFiles.indices {
            openFiles[index].hasDiskChange = state.files[index].hasDiskChange
        }
        selectedPath = state.selectedPath
    }

    /// Writes the open files and selection to disk, atomically; a failed
    /// encode or write is dropped.
    func persistState() {
        let state = IDEPaneState(
            files: openFiles.map { file in
                IDEPaneState.FileState(
                    path: file.path,
                    text: file.text,
                    savedSnapshot: file.savedSnapshot,
                    diskSnapshot: file.diskSnapshot,
                    editedText: file.editedText,
                    hasDiskChange: file.hasDiskChange
                )
            },
            selectedPath: selectedPath
        )
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: stateURL, options: .atomic)
    }
}
