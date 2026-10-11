import Foundation

/// What the last check of one account found.
struct ProviderAccountState: Equatable, Sendable {
    var auth: ProviderStatus.Auth = .unknown
    var limits: PlanLimits?
    var isChecking = false
    /// A sign-in was opened for this account and is being watched for.
    var isWaitingForSignIn = false
}

extension ProviderAccountState {
    /// The fullest window the account reports, in percent; nil before any usage was read.
    var peakPercent: Double? {
        limits?.windows.filter { !$0.id.contains("extra") }.map(\.percent).max()
    }
}

extension ProviderRegistry {
    /// An account at or past this share of any window is close to its limit.
    static let nearLimitPercent: Double = 90

    /// Another signed-in account with room to spare while the one in use is close to its
    /// limit: the one with the most headroom.
    func accountWithHeadroom(for provider: ProviderKind) -> ProviderAccount? {
        guard let active = accounts.activeAccount(for: provider) else { return nil }
        // The provider's own read is the in-use account's freshest: a turn re-reads it.
        let current = ProviderAccountState(limits: planLimits[provider]).peakPercent ?? accountState(active.id).peakPercent
        guard let peak = current, peak >= Self.nearLimitPercent else { return nil }
        return accounts.accounts(for: provider)
            .filter { $0.id != active.id }
            .compactMap { account -> (ProviderAccount, Double)? in
                let state = accountState(account.id)
                guard case .signedIn = state.auth, let peak = state.peakPercent, peak < Self.nearLimitPercent else { return nil }
                return (account, peak)
            }
            .min { $0.1 < $1.1 }?.0
    }

    func accountState(_ id: UUID) -> ProviderAccountState {
        accountStates[id] ?? ProviderAccountState()
    }

    /// Checks every account of a provider: who it is signed in as and, for providers that
    /// report them, its usage windows. Accounts are read side by side, each in its own home.
    /// Unforced, a check within the last minute is served as it is: the usage popover asks
    /// every time it opens.
    func refreshAccounts(_ provider: ProviderKind, force: Bool = true) async {
        guard provider.supportsAccounts else { return }
        if !force, let fetched = accountsFetchedAt[provider], Date.now.timeIntervalSince(fetched) < 60 { return }
        accountsFetchedAt[provider] = .now
        await LoginEnvironment.load()
        let list = accounts.accounts(for: provider)
        await withTaskGroup(of: Void.self) { group in
            for account in list {
                group.addTask { await self.refreshAccount(account) }
            }
        }
    }

    func refreshAccount(_ account: ProviderAccount) async {
        guard let executable = executable(for: account.provider) else { return }
        var state = accountState(account.id)
        guard !state.isChecking else { return }
        state.isChecking = true
        accountStates[account.id] = state
        defer { accountStates[account.id]?.isChecking = false }

        ProviderAccountStore.prepareHome(of: account, environment: LoginEnvironment.current)
        let environment = environment(for: account.provider, account: account)
        let auth = await Self.auth(account.provider, executable, environment)
        var limits: PlanLimits?
        if auth != .signedOut, PlanLimitsReader.exposesLimits(account.provider) {
            limits = await PlanLimitsReader.read(account.provider, executable: executable, environment: environment)
        }
        var email: String?
        var plan = limits?.planName
        if case .signedIn(let name) = auth { email = name }
        if account.provider == .codex, let home = account.home ?? account.provider.defaultAccountHome(in: environment) {
            let identity = ProviderAccountStore.codexIdentity(home: home)
            email = email ?? identity.email
            plan = plan ?? identity.plan
        }
        accounts.noteIdentity(account.id, email: email, plan: plan)
        accountStates[account.id]?.auth = auth
        accountStates[account.id]?.limits = limits
        // The active account's read is the provider's read too: the composer's popover
        // shows the same numbers without asking again.
        if accounts.activeAccount(for: account.provider)?.id == account.id, let limits, !limits.windows.isEmpty {
            setPlanLimits(limits, for: account.provider)
        }
    }

    /// Makes `account` the one new sessions and heads of its provider start on. Running
    /// sessions keep the account they started with.
    func useAccount(_ account: ProviderAccount) {
        guard accounts.activeAccount(for: account.provider)?.id != account.id else { return }
        accounts.select(account.id)
        forgetPlanLimits(account.provider)
        if let limits = accountState(account.id).limits, !limits.windows.isEmpty {
            setPlanLimits(limits, for: account.provider)
        }
        Task {
            await refresh(account.provider)
            refreshPlanLimits(account.provider, force: true)
            await loadCatalog(account.provider, force: true)
        }
    }

    /// Makes a fresh home for a new account; the caller opens its sign-in
    /// (`loginCommand(for:)`) and hands it to `watchSignIn`.
    func addAccount(_ provider: ProviderKind) async -> ProviderAccount? {
        await LoginEnvironment.load()
        guard let account = accounts.addAccount(provider, environment: LoginEnvironment.current) else { return nil }
        accountStates[account.id] = ProviderAccountState(auth: .signedOut)
        return account
    }

    /// Watches an account whose sign-in was just opened until the login lands (five
    /// minutes at most; Refresh picks up a later one).
    func watchSignIn(_ account: ProviderAccount) {
        accountSignInWatches[account.id]?.cancel()
        accountStates[account.id, default: ProviderAccountState()].isWaitingForSignIn = true
        accountSignInWatches[account.id] = Task { [weak self] in
            let deadline = Date.now.addingTimeInterval(300)
            while !Task.isCancelled, Date.now < deadline {
                try? await Task.sleep(for: .seconds(3))
                guard let self, !Task.isCancelled else { return }
                guard let current = self.accounts.account(account.id),
                      let executable = self.executable(for: current.provider) else { break }
                let auth = await Self.auth(current.provider, executable, self.environment(for: current.provider, account: current))
                if case .signedIn = auth {
                    self.accountStates[account.id]?.isWaitingForSignIn = false
                    await self.refreshAccount(current)
                    if self.accounts.activeAccount(for: current.provider)?.id == current.id {
                        await self.refresh(current.provider)
                    }
                    return
                }
            }
            self?.accountStates[account.id]?.isWaitingForSignIn = false
            self?.accountSignInWatches[account.id] = nil
        }
    }

    /// Signs the account's CLI out (which takes its Keychain item along) and deletes its
    /// home. The default account is the CLI's own home and is never removed.
    func removeAccount(_ account: ProviderAccount) async {
        guard !account.isDefault else { return }
        accountSignInWatches[account.id]?.cancel()
        accountSignInWatches[account.id] = nil
        let wasActive = accounts.activeAccount(for: account.provider)?.id == account.id
        if let arguments = account.provider.logoutArguments, let executable = executable(for: account.provider) {
            _ = try? await Shell.run(executable, arguments, environment: environment(for: account.provider, account: account), timeout: 20)
        }
        accounts.remove(account.id)
        accountStates[account.id] = nil
        guard wasActive else { return }
        forgetPlanLimits(account.provider)
        await refresh(account.provider)
        refreshPlanLimits(account.provider, force: true)
    }

    /// The login command with the account's home in front of it: the prefix wins over
    /// whatever the login shell exports.
    static func loginCommand(for account: ProviderAccount) -> String {
        guard let home = account.home, let variable = account.provider.accountHomeVariable else {
            return account.provider.loginCommand
        }
        let quoted = "'" + home.replacingOccurrences(of: "'", with: "'\\''") + "'"
        return "\(variable)=\(quoted) \(account.provider.loginCommand)"
    }
}
