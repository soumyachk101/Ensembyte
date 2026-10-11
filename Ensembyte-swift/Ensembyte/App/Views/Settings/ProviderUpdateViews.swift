import SwiftUI

/// A provider row's version line: the installed version, and the newer one in the accent
/// when its install channel has one ("v3000.10.21 · v3000.11.3 available").
struct ProviderUpdateSubtitle: View {
    @Environment(AppModel.self) private var model
    let provider: ProviderKind

    var body: some View {
        let (text, color) = line
        let monitors = model.providers.monitorsCLIUpdates(provider)
        Group {
            if let text {
                Text(verbatim: text)
                    .font(.system(size: 11))
                    .foregroundStyle(color)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .contentTransition(.opacity)
                    .animation(.easeOut(duration: 0.15), value: text)
            }
        }
        // The provider's own switch and its monitoring switch both land here.
        .onChange(of: monitors) { _, _ in model.providers.cliMonitoringChanged(provider) }
    }

    private var line: (String?, Color) {
        let status = model.providers.status(provider)
        guard status.executable != nil else {
            return status.isChecking ? (nil, Chrome.secondaryText) : ("Install the \(provider.displayName) CLI to enable", Chrome.warning)
        }
        let installed = status.version.map { "v\($0)" } ?? "Version unknown"
        guard model.providers.monitorsCLIUpdates(provider) else {
            return ("\(installed) · Update monitoring off", Chrome.secondaryText)
        }
        guard let update = model.providers.cliUpdates[provider] else { return (installed, Chrome.secondaryText) }
        switch update.phase {
        case .checking:
            return ("\(installed) · Checking for updates…", Chrome.secondaryText)
        case .current:
            return (update.latest == nil ? installed : "\(installed) · Up to date", Chrome.secondaryText)
        case .available:
            let available = "\(installed) · v\(update.latest ?? "?") available"
            // No channel the app can run: the user updates it the way they installed it.
            return (update.channel == nil ? "\(available) · update it with its installer" : available, Chrome.accent)
        case .waiting:
            return ("\(installed) · Updates once its chats finish", Chrome.secondaryText)
        case .updating:
            return ("\(installed) · Updating to v\(update.latest ?? "latest")…", Chrome.secondaryText)
        case .updated:
            return ("\(installed) · Updated", Chrome.success)
        case .failed:
            let message = update.error ?? "Unknown error"
            return ((update.updateFailed ? "Update failed · " : "Update check failed · ") + message, Chrome.danger)
        }
    }
}

/// The row's one update action, before its switch: Update when a newer version is out,
/// a spinner while it runs, Retry after a failure, Install while the CLI is missing.
struct ProviderUpdateAction: View {
    @Environment(AppModel.self) private var model
    let provider: ProviderKind

    var body: some View {
        let status = model.providers.status(provider)
        let update = model.providers.cliUpdates[provider]
        if status.executable == nil {
            if !status.isChecking {
                Link(destination: provider.installURL) {
                    Text(verbatim: "Install")
                        .font(.system(size: 11))
                        .foregroundStyle(Chrome.secondaryText)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Get \(provider.displayName)")
            }
        } else if let update, model.providers.monitorsCLIUpdates(provider) {
            switch update.phase {
            case .available where update.channel != nil:
                ProviderUpdateButton(title: "Update", isPrimary: true, help: update.channel.map { "Runs \($0.command)" }) {
                    Task { await model.providers.updateCLI(provider) }
                }
            case .waiting, .updating:
                MiniSpinner()
                    .padding(.horizontal, 9)
                    .help(update.channel.map { "Running \($0.command)" } ?? "Updating")
            case .failed:
                ProviderUpdateButton(title: "Retry", isPrimary: false, help: update.updateFailed ? update.channel.map { "Runs \($0.command) again" } : "Check for updates again") {
                    Task {
                        if update.updateFailed {
                            await model.providers.updateCLI(provider)
                        } else {
                            await model.providers.checkCLIUpdate(provider, force: true)
                        }
                    }
                }
            default:
                EmptyView()
            }
        }
    }
}

/// A small text button: accent-washed for the primary action, plain otherwise.
private struct ProviderUpdateButton: View {
    let title: String
    let isPrimary: Bool
    var help: String?
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Text(verbatim: title)
                .font(.system(size: 11, weight: isPrimary ? .medium : .regular))
                .foregroundStyle(isPrimary ? Chrome.accent : Chrome.secondaryText)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isPrimary ? Chrome.accent.opacity(isHovering ? 0.2 : 0.13) : Chrome.overlay(isHovering ? 0.06 : 0))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(Chrome.hover, value: isHovering)
        .help(help ?? title)
    }
}

/// The per-provider switch for update checks, with the command an update would run.
struct ProviderUpdateMonitoringRow: View {
    @Environment(AppModel.self) private var model
    let provider: ProviderKind

    var body: some View {
        let channel = model.providers.cliUpdates[provider]?.channel
        ChromeRow(
            title: "Check for updates",
            detail: channel.map { "Updates with \($0.command)" } ?? "Compares the installed version with the newest release every six hours."
        ) {
            SettingsSwitch(isOn: Binding(
                get: { model.settings.monitorsUpdates(provider) },
                set: { model.settings.setMonitorsUpdates($0, for: provider) }
            ))
        }
    }
}
