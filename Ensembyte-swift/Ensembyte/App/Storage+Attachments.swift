import AppKit
import SwiftUI

/// The binding bridge for `Storage.importSources`. The storage layer hands back plain
/// `[Attachment]` values and knows nothing of SwiftUI; this is the one place that appends
/// them to a composer's `Binding<[Attachment]>`, counting free slots before and after the
/// copies land and removing the orphans past the cap.
@MainActor
extension Storage {
    @discardableResult
    static func attach(_ sources: [AttachmentSource], to attachments: Binding<[Attachment]>) -> Task<Void, Never>? {
        let batch = Array(sources.prefix(max(0, attachmentLimit - attachments.wrappedValue.count)))
        guard !batch.isEmpty else { return nil }
        return Task.detached(priority: .userInitiated) {
            let imported = Storage.importSources(batch)
            let kept = await MainActor.run {
                let room = max(0, attachmentLimit - attachments.wrappedValue.count)
                attachments.wrappedValue.append(contentsOf: imported.prefix(room))
                return room
            }
            for orphan in imported.dropFirst(kept) { try? FileManager.default.removeItem(at: orphan.url) }
        }
    }
}
