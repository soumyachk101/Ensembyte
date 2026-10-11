import Foundation
import Synchronization

/// The permission modes a thread was taken down from because its provider cannot honour
/// them (see `ProviderKind.supports`), noted as they happen and drained by the app, which
/// tells the user once. A thread cannot say it from where it is changed (a new thread, a
/// move to another provider, a file read from disk), so this is where the app finds out.
enum PermissionLowering {
    struct Lowering: Sendable {
        var provider: ProviderKind
        var from: RuntimeMode
        var to: RuntimeMode
    }

    private static let pending = Mutex<[Lowering]>([])

    static func note(provider: ProviderKind, from: RuntimeMode, to: RuntimeMode) {
        pending.withLock { $0.append(Lowering(provider: provider, from: from, to: to)) }
    }

    /// What was noted since the last drain, oldest first.
    static func drain() -> [Lowering] {
        pending.withLock { noted in
            defer { noted.removeAll() }
            return noted
        }
    }
}
