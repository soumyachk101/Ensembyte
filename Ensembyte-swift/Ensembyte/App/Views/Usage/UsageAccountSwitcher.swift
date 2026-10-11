import SwiftUI

/// The provider's accounts under its usage limits, for providers with more than one: a
/// compact row each with its session and week use, the one in use marked. A click moves
/// the provider to that account at once; a chat's live session restarts on it with its next
/// message and picks the same conversation up. When the account in use is close to a limit
/// and another has room, a one-click suggestion leads the list.
struct UsageAccountSwitcher: View {
    @Environment(AppModel.self) private var model
    let provider: ProviderKind

    var body: some View {
        let registry = model.providers
        let accounts = registry.accounts.accounts(for: provider)
        if accounts.count > 1 {
            let activeID = registry.accounts.activeAccount(for: provider)?.id
            VStack(alignment: .leading, spacing: 0) {
                Divider().padding(.vertical, 14)
                Text(verbatim: "Accounts")
                    .font(.system(.body))
                    .foregroundStyle(Chrome.secondaryText)
                    .padding(.bottom, 6)
                if let better = registry.accountWithHeadroom(for: provider) {
                    Button {
                        registry.useAccount(better)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.left.arrow.right")
                                .font(.system(size: 11, weight: .semibold))
                            Text(verbatim: "Switch to \(better.title)")
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer(minLength: 0)
                        }
                        .font(.system(.callout, weight: .medium))
                        .foregroundStyle(Chrome.warning)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Chrome.warning.opacity(0.12))
                        )
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .help("The account in use is close to its limit; this one has room")
                    .padding(.bottom, 6)
                }
                ForEach(accounts) { account in
                    UsageAccountRow(account: account, isActive: account.id == activeID)
                }
            }
            .task(id: provider) {
                await registry.refreshAccounts(provider, force: false)
            }
        }
    }
}

private struct UsageAccountRow: View {
    @Environment(AppModel.self) private var model
    let account: ProviderAccount
    let isActive: Bool

    @State private var isHovered = false

    var body: some View {
        let state = model.providers.accountState(account.id)
        // The in-use account shows the provider's own read, which every turn refreshes.
        let limits = isActive ? (model.providers.planLimits[account.provider] ?? state.limits) : state.limits
        let signedOut = state.auth == .signedOut
        let canSwitch = !isActive && !signedOut
        Button {
            guard canSwitch else { return }
            model.providers.useAccount(account)
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .strokeBorder(isActive ? Chrome.accent : .clear, lineWidth: 1.5)
                    Circle()
                        .fill(Chrome.overlay(0.09))
                        .frame(width: 17, height: 17)
                    Text(verbatim: account.title.first.map { String($0).uppercased() } ?? "?")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(isActive ? Chrome.primaryText : Chrome.secondaryText)
                }
                .frame(width: 22, height: 22)
                Text(verbatim: account.title)
                    .foregroundStyle(Chrome.primaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if isActive {
                    Text(verbatim: "In use")
                        .foregroundStyle(Chrome.accent)
                        .fixedSize()
                }
                Spacer(minLength: 8)
                if signedOut {
                    Text(verbatim: "Signed out")
                        .foregroundStyle(Chrome.secondaryText)
                } else {
                    usage(limits)
                }
            }
            .font(.system(.callout))
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Chrome.overlay(canSwitch && isHovered ? 0.06 : 0))
            )
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, -6)
        .onHover { isHovered = $0 }
        .help(canSwitch ? "Use \(account.title) for \(account.provider.displayName)" : "")
    }

    /// "S 42% · W 91%", a window near its limit in the warning colour.
    private func usage(_ limits: PlanLimits?) -> Text {
        let windows = (limits?.windows ?? []).filter { !$0.id.contains("extra") }
        let session = windows.first { $0.title.hasPrefix("5-hour") }
        let week = windows.first { $0.title.hasPrefix("Weekly") }
        let picked: [(String, PlanLimits.Window)] = session != nil || week != nil
            ? [session.map { ("S", $0) }, week.map { ("W", $0) }].compactMap { $0 }
            : windows.prefix(2).map { ("", $0) }
        guard !picked.isEmpty else { return Text(verbatim: "–").foregroundStyle(Chrome.secondaryText) }
        var line = Text(verbatim: "")
        for (index, (label, window)) in picked.enumerated() {
            if index > 0 {
                let separator = Text(verbatim: " · ").foregroundStyle(Chrome.secondaryText)
                line = Text("\(line)\(separator)")
            }
            let percent = Int(window.percent.rounded())
            let near = window.percent >= ProviderRegistry.nearLimitPercent
            let prefix = label.isEmpty ? "" : "\(label) "
            let value = Text(verbatim: "\(prefix)\(percent)%")
                .foregroundStyle(near ? Chrome.warning : Chrome.secondaryText)
            line = Text("\(line)\(value)")
        }
        return line.monospacedDigit()
    }
}
