import AppKit
import Foundation

extension Notification.Name {
    /// The panel's open-or-toggle request: a URL when one was asked for, the toggle flag
    /// when the panel should just flip, or neither when it should open on its current tab.
    static let browserPanelRequested = Notification.Name("Ensembyte.browserPanelRequested")
    /// A browser command to run against the front tab: its `BrowserCommand` raw value
    /// under `BrowserNotificationKey.command`.
    static let browserCommand = Notification.Name("Ensembyte.browserCommand")
}

enum BrowserNotificationKey {
    /// The URL to open, in `browserPanelRequested`'s userInfo, when one was asked for.
    static let url = "Ensembyte.browser.url"
    /// Set true in `browserPanelRequested`'s userInfo to ask the panel to toggle instead.
    static let toggle = "Ensembyte.browser.toggle"
}

/// Where the rest of the app reaches the browser: the app's links, its shortcuts and
/// its tool calls post through it, and the panel observes the notifications it posts.
@MainActor
final class BrowserCoordinator {
    static let shared = BrowserCoordinator()

    /// Asks the panel to open (and show) at `url`, or at its current tab when nil.
    func requestOpen(_ url: URL?) {
        var userInfo: [AnyHashable: Any] = [:]
        if let url { userInfo[BrowserNotificationKey.url] = url }
        NotificationCenter.default.post(name: .browserPanelRequested, object: nil, userInfo: userInfo)
    }

    /// Asks the panel to flip: closed opens on the current tab, open closes.
    func requestToggle() {
        NotificationCenter.default.post(
            name: .browserPanelRequested,
            object: nil,
            userInfo: [BrowserNotificationKey.toggle: true]
        )
    }

    /// Posts a command against the front tab: the panel takes it up.
    func post(_ command: BrowserCommand) {
        NotificationCenter.default.post(
            name: .browserCommand,
            object: nil,
            userInfo: ["command": command.rawValue]
        )
    }
}
