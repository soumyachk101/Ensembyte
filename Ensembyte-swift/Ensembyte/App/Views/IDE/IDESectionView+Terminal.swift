import SwiftUI
import Foundation

/// The IDE pane's Terminal tab: the thread's own shell, shared with the chat's
/// bottom terminal through the store, so the two show the same shell.
struct IDETerminalView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme

    let threadID: UUID
    let directory: String
    let runtime: ThreadRuntime
    let onReturnToFiles: () -> Void

    var body: some View {
        // The shell the thread owns: reuse it when one is open so the two hosts
        // never spawn a second shell for the same thread. Read through the store
        // on every render, so after a restart the view tracks the fresh session
        // instead of a stale local reference.
        let session = model.terminals.selected(for: threadID)
            ?? model.terminals.open(threadID: threadID, directory: directory)
        return VStack(spacing: 0) {
            controlStrip(for: session)
            if session.isRunning {
                host(session)
            } else {
                exitedPlaceholder(for: session)
            }
        }
    }

    /// Slim strip above the host: the shell's name on the left, a Restart control on the right.
    private func controlStrip(for session: TerminalSession) -> some View {
        HStack(spacing: 8) {
            Text(verbatim: session.title)
                .font(.system(size: 12))
                .foregroundStyle(Chrome.primaryText)
                .lineLimit(1)
            Spacer()
            ChromeTextButton(symbol: "arrow.clockwise", title: "Restart", help: "Restart the terminal") {
                model.terminals.restart(session)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Chrome.overlay(0.06))
    }

    /// A centered "has exited" notice for a dead shell, with one click back to a live one.
    private func exitedPlaceholder(for session: TerminalSession) -> some View {
        VStack(spacing: 10) {
            Text(verbatim: session.title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Chrome.secondaryText)
            Text("This terminal has exited.")
                .font(.system(size: 12))
                .foregroundStyle(Chrome.secondaryText)
            ChromeTextButton(symbol: "arrow.clockwise", title: "Restart", help: "Restart the terminal") {
                model.terminals.restart(session)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// The live host for the thread's shell; Escape at the prompt hands the pane back to
    /// Files and never touches the chat's bottom-docked terminal.
    private func host(_ session: TerminalSession) -> some View {
        TerminalHost(session: session, runtime: runtime, isDark: colorScheme == .dark) {
            onReturnToFiles()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
