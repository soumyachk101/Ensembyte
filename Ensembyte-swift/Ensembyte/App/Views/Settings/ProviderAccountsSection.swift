import SwiftUI

/// A provider's logins inside its expanded row on the Providers page: one row per account
/// with its initial, email, plan and state, and its session and week usage on the right.
/// The account new sessions start on carries the accent ring and reads "In use"; a click on
/// any other signed-in row moves new sessions to it.
struct ProviderAccountsSection: View {
    @Environment(AppModel.self) private var model
    let provider: ProviderKind
    /// The row stays mounted while collapsed; its accounts are checked when it opens.
    let isExpanded: Bool

    var body: some View {
        let registry = model.providers
        let accounts = registry.accounts.accounts(for: provider)
        let activeID = registry.accounts.activeAccount(for: provider)?.id
        let isChecking = accounts.contains { registry.accountState($0.id).isChecking }
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text(verbatim: "Accounts")
                    .font(.system(.body, weight: .semibold))
                    .foregroundStyle(Chrome.secondaryText)
                Spacer(minLength: 8)
                Button {
                    Task { await registry.refreshAccounts(provider) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Chrome.secondaryText)
                        .frame(width: 22, height: 22)
                        .contentShape(.rect)
                        .opacity(isChecking ? 0.4 : 1)
                }
                .buttonStyle(.plain)
                .disabled(isChecking)
                .help(isChecking ? "Checking accounts…" : "Refresh usage")
                .accessibilityLabel(Text("Refresh accounts"))
            }
            .padding(.bottom, 4)
            ForEach(Array(accounts.enumerated()), id: \.element.id) { index, account in
                if index > 0 { Divider() }
                ProviderAccountRow(account: account, isActive: account.id == activeID)
            }
            Button {
                Task {
                    guard let account = await registry.addAccount(provider) else { return }
                    Workspace.openTerminal(running: ProviderRegistry.loginCommand(for: account))
                    registry.watchSignIn(account)
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .semibold))
                    Text(verbatim: "Add account")
                }
                .font(.system(.body))
                .foregroundStyle(Chrome.secondaryText)
                .padding(.vertical, 6)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
            .help("Sign in to another \(provider.displayName) account")
        }
        .task(id: isExpanded) {
            // Opening the row checks its accounts; the refresh button checks again.
            guard isExpanded else { return }
            await registry.refreshAccounts(provider)
        }
    }
}

private struct ProviderAccountRow: View {
    @Environment(AppModel.self) private var model
    let account: ProviderAccount
    let isActive: Bool

    @State private var showMenu = false
    @State private var isRenaming = false
    @State private var newName = ""
    @State private var confirmsRemoval = false
    @State private var isHovered = false

    private var state: ProviderAccountState { model.providers.accountState(account.id) }

    private var isSignedIn: Bool {
        if case .signedIn = state.auth { return true }
        return false
    }

    private var canSwitch: Bool { !isActive && isSignedIn }

    var body: some View {
        HStack(spacing: 14) {
            avatar
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: account.title)
                    .font(.system(.body))
                    .foregroundStyle(Chrome.primaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
                metaLine
                    .font(.system(.subheadline))
                    .lineLimit(1)
            }
            Spacer(minLength: 12)
            usage
            Button {
                showMenu.toggle()
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Chrome.secondaryText)
                    .frame(width: 26, height: 26)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .help("Account actions")
            .accessibilityLabel(Text("Actions for \(account.title)"))
            .popover(isPresented: $showMenu, arrowEdge: .bottom) { menu }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Chrome.overlay(canSwitch && isHovered ? 0.04 : 0))
        )
        .padding(.horizontal, -8)
        .contentShape(.rect)
        .onHover { isHovered = $0 }
        .onTapGesture {
            guard canSwitch else { return }
            model.providers.useAccount(account)
        }
        .help(canSwitch ? "Use this account for new chats" : "")
        .alert("Rename account", isPresented: $isRenaming) {
            TextField("Name", text: $newName)
            Button("Save") { model.providers.accounts.rename(account.id, to: newName) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(verbatim: "Shown in place of the email. Leave it empty to show the email again.")
        }
        .confirmationDialog("Remove \(account.title)?", isPresented: $confirmsRemoval) {
            Button("Remove account", role: .destructive) {
                Task { await model.providers.removeAccount(account) }
            }
        } message: {
            Text(verbatim: "Signs this account out of \(account.provider.displayName) on this Mac. Chats keep their history.")
        }
        .animation(.easeOut(duration: 0.15), value: state)
    }

    /// The initial on a soft disc; the account in use gets an accent ring with a hairline
    /// of air between ring and disc.
    private var avatar: some View {
        let initial = account.title.first.map { String($0).uppercased() } ?? "?"
        return ZStack {
            Circle()
                .strokeBorder(isActive ? Chrome.accent : .clear, lineWidth: 1.5)
            Circle()
                .fill(Chrome.overlay(0.09))
                .frame(width: 25, height: 25)
            Text(verbatim: initial)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(isActive ? Chrome.primaryText : Chrome.secondaryText)
        }
        .frame(width: 32, height: 32)
        .accessibilityHidden(true)
    }

    private var metaLine: Text {
        var parts: [Text] = []
        let plan = state.limits?.planName ?? account.plan
        if let plan, !plan.isEmpty {
            parts.append(Text(verbatim: plan).foregroundStyle(Chrome.secondaryText))
        }
        if account.name != nil, let email = account.email, !email.isEmpty {
            parts.append(Text(verbatim: email).foregroundStyle(Chrome.secondaryText))
        }
        if state.isWaitingForSignIn {
            parts.append(Text(verbatim: "Waiting for sign-in…").foregroundStyle(Chrome.secondaryText))
        } else if state.auth == .signedOut {
            parts.append(Text(verbatim: "Signed out — sign in again").foregroundStyle(Chrome.warning))
        } else if isActive {
            parts.append(Text(verbatim: "In use").foregroundStyle(Chrome.accent))
        } else if state.isChecking, state.auth == .unknown {
            parts.append(Text(verbatim: "Checking…").foregroundStyle(Chrome.secondaryText))
        }
        guard var line = parts.first else { return Text(verbatim: "") }
        for part in parts.dropFirst() {
            let separator = Text(verbatim: " · ").foregroundStyle(Chrome.secondaryText)
            line = Text("\(line)\(separator)\(part)")
        }
        return line
    }

    /// The session and week windows, label, bar and percentage in fixed columns so the
    /// bars line up down the list. A row without numbers keeps the column's width.
    private var usage: some View {
        let windows = Self.meterWindows(state.limits)
        return VStack(alignment: .leading, spacing: 4) {
            ForEach(windows, id: \.window.id) { item in
                HStack(spacing: 8) {
                    Text(verbatim: item.label)
                        .foregroundStyle(Chrome.secondaryText)
                        .frame(width: 52, alignment: .leading)
                        .lineLimit(1)
                    UsageBar(fraction: item.window.percent / 100, tint: Self.tint(for: item.window.percent), label: item.label)
                        .frame(width: 88, height: 4)
                    Text(verbatim: "\(Int(item.window.percent.rounded()))%")
                        .foregroundStyle(item.window.percent >= 75 ? Self.tint(for: item.window.percent) : Chrome.secondaryText)
                        .monospacedDigit()
                        .frame(width: 34, alignment: .trailing)
                }
                .frame(height: 16)
                .help(item.window.resetsAt.map { "\(item.label) resets \(Self.resetText($0))" } ?? item.label)
            }
        }
        .font(.system(size: 11.5))
        .frame(width: 190, alignment: .leading)
    }

    private struct Meter {
        let label: String
        let window: PlanLimits.Window
    }

    /// The five-hour and weekly windows when the provider names them, else the first two.
    private static func meterWindows(_ limits: PlanLimits?) -> [Meter] {
        let windows = (limits?.windows ?? []).filter { !$0.id.contains("extra") }
        let session = windows.first { $0.title.hasPrefix("5-hour") }
        let week = windows.first { $0.title.hasPrefix("Weekly") }
        let picked = session != nil || week != nil ? [session, week].compactMap { $0 } : Array(windows.prefix(2))
        return picked.map { Meter(label: label(for: $0.title), window: $0) }
    }

    private static func label(for title: String) -> String {
        if title.hasPrefix("5-hour") { return "Session" }
        if title.hasPrefix("Weekly") { return "Week" }
        if title.hasPrefix("Daily") { return "Day" }
        if title.hasPrefix("Monthly") { return "Month" }
        return title
    }

    private static func tint(for percent: Double) -> Color {
        if percent >= 90 { return Chrome.danger }
        if percent >= 75 { return Chrome.warning }
        return Chrome.accent
    }

    private static func resetText(_ date: Date) -> String {
        let seconds = max(0, date.timeIntervalSinceNow)
        if seconds < 86_400 {
            let hours = Int(seconds) / 3_600
            let minutes = Int(seconds) % 3_600 / 60
            return hours > 0 ? "in \(hours) hr \(minutes) min" : "in \(max(1, minutes)) min"
        }
        return date.formatted(.dateTime.weekday(.abbreviated).hour().minute())
    }

    private var menu: some View {
        PopoverMenu {
            if canSwitch {
                PopoverItem("Use this account", symbol: "checkmark.circle") {
                    model.providers.useAccount(account)
                }
            }
            PopoverItem("Sign in again", symbol: "person.crop.circle.badge.checkmark") {
                Workspace.openTerminal(running: ProviderRegistry.loginCommand(for: account))
                model.providers.watchSignIn(account)
            }
            PopoverItem("Rename…", symbol: "pencil") {
                showMenu = false
                newName = account.name ?? ""
                isRenaming = true
            }
            if !account.isDefault {
                PopoverDivider()
                PopoverItem("Remove account", symbol: "trash", isDestructive: true) {
                    showMenu = false
                    confirmsRemoval = true
                }
            }
        }
    }
}
