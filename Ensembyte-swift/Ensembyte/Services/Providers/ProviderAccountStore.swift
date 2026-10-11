import Foundation

/// The accounts of every provider that takes more than one, and the home each one runs in.
/// The book is a small JSON file beside the library, never inside it, and holds no secret:
/// a login lives in its account's home (or the Keychain item the CLI keys to that home).
@MainActor
@Observable
final class ProviderAccountStore {
    private(set) var book = ProviderAccountBook()

    @ObservationIgnored private let url = StoragePaths.root.appendingPathComponent("provider-accounts.json")

    /// Where added accounts keep their homes: the state folder, whose path has no spaces,
    /// so the variable reads the same in a Terminal command as in a launch.
    nonisolated static let homesDirectory = URL(fileURLWithPath: LoginEnvironment.homeDirectory)
        .appendingPathComponent(AppInfo.stateDirectoryName + "/accounts", isDirectory: true)

    init() {
        if !CaptureRun.isEnabled,
           let data = try? Data(contentsOf: url),
           let stored = try? JSONDecoder().decode(ProviderAccountBook.self, from: data) {
            book = stored
        }
        // Every provider that takes accounts starts with its CLI's own home, so the login
        // that was there before accounts is the first one and nothing changes for it.
        for provider in ProviderKind.allCases where provider.supportsAccounts {
            if !book.accounts.contains(where: { $0.provider == provider && $0.isDefault }) {
                book.accounts.insert(ProviderAccount(provider: provider, home: nil, addedAt: .distantPast), at: 0)
            }
        }
        // An active id whose account is gone falls back to the default.
        for (key, id) in book.active where !book.accounts.contains(where: { $0.id == id }) {
            book.active[key] = nil
        }
    }

    func accounts(for provider: ProviderKind) -> [ProviderAccount] {
        book.accounts
            .filter { $0.provider == provider }
            .sorted { lhs, rhs in
                if lhs.isDefault != rhs.isDefault { return lhs.isDefault }
                return lhs.addedAt < rhs.addedAt
            }
    }

    func account(_ id: UUID) -> ProviderAccount? {
        book.accounts.first { $0.id == id }
    }

    /// The account new sessions of a provider start on; nil for providers without accounts.
    func activeAccount(for provider: ProviderKind) -> ProviderAccount? {
        guard provider.supportsAccounts else { return nil }
        let list = accounts(for: provider)
        if let id = book.active[provider.rawValue], let chosen = list.first(where: { $0.id == id }) { return chosen }
        return list.first
    }

    /// Points the CLI at the account's home. The default account leaves the environment
    /// as the login shell had it.
    nonisolated static func apply(_ account: ProviderAccount?, to environment: inout [String: String]) {
        guard let account, let home = account.home, let variable = account.provider.accountHomeVariable else { return }
        environment[variable] = home
    }

    /// A fresh home for a new account of `provider`, ready for its sign-in.
    func addAccount(_ provider: ProviderKind, environment: [String: String]) -> ProviderAccount? {
        guard provider.supportsAccounts else { return nil }
        let id = UUID()
        let home = Self.homesDirectory
            .appendingPathComponent(provider.rawValue, isDirectory: true)
            .appendingPathComponent(id.uuidString, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        } catch {
            return nil
        }
        let account = ProviderAccount(id: id, provider: provider, home: home.path)
        Self.prepareHome(of: account, environment: environment)
        book.accounts.append(account)
        save()
        return account
    }

    func select(_ id: UUID) {
        guard let account = account(id) else { return }
        book.active[account.provider.rawValue] = account.isDefault ? nil : id
        save()
    }

    func rename(_ id: UUID, to name: String) {
        guard let index = book.accounts.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        book.accounts[index].name = trimmed.isEmpty ? nil : trimmed
        save()
    }

    /// Records who an account turned out to be, once a check has read it.
    func noteIdentity(_ id: UUID, email: String?, plan: String?) {
        guard let index = book.accounts.firstIndex(where: { $0.id == id }) else { return }
        var account = book.accounts[index]
        if let email, !email.isEmpty { account.email = email }
        if let plan, !plan.isEmpty { account.plan = plan }
        guard account != book.accounts[index] else { return }
        book.accounts[index] = account
        save()
    }

    /// Drops an added account and deletes its home. The default account stays: it is the
    /// CLI's own home, which the app never deletes.
    func remove(_ id: UUID) {
        guard let account = account(id), let home = account.home else { return }
        book.accounts.removeAll { $0.id == id }
        if book.active[account.provider.rawValue] == id { book.active[account.provider.rawValue] = nil }
        save()
        // Only a home the app made is deleted. `removeItem` unlinks the shared entries'
        // symlinks; it never follows them into the default home.
        if home.hasPrefix(Self.homesDirectory.path + "/") {
            try? FileManager.default.removeItem(atPath: home)
        }
    }

    /// Links every added account's home to what is new in the default home since the last
    /// look: a skill or a session folder made after the account was added.
    func refreshHomes(environment: [String: String]) {
        for account in book.accounts where !account.isDefault {
            Self.prepareHome(of: account, environment: environment)
        }
    }

    private func save() {
        guard !CaptureRun.isEnabled, let data = try? JSONEncoder().encode(book) else { return }
        try? data.write(to: url, options: .atomic)
    }

    // MARK: - Homes

    /// Links the default home's shared entries into the account's home, and gives a new
    /// Claude home a copy of the default `.claude.json` without the login in it, so its MCP
    /// servers and project trust come along while the account stays its own.
    nonisolated static func prepareHome(of account: ProviderAccount, environment: [String: String]) {
        guard let home = account.home, let source = account.provider.defaultAccountHome(in: environment) else { return }
        let manager = FileManager.default
        guard manager.fileExists(atPath: home) else { return }
        let skip = account.provider.accountPrivateEntries
        let entries = (try? manager.contentsOfDirectory(atPath: source)) ?? []
        for entry in entries where !skip.contains(entry) {
            let link = (home as NSString).appendingPathComponent(entry)
            // An entry the CLI already made in the account's home (or replaced a link with)
            // stays as it is.
            guard (try? manager.destinationOfSymbolicLink(atPath: link)) == nil, !manager.fileExists(atPath: link) else { continue }
            try? manager.createSymbolicLink(atPath: link, withDestinationPath: (source as NSString).appendingPathComponent(entry))
        }
        if account.provider == .claude {
            seedClaudeConfig(home: home, environment: environment)
        }
    }

    /// Claude keeps its identity, MCP servers and project trust in `.claude.json`: the
    /// default's sits beside `~/.claude`, a relocated home's inside it.
    private nonisolated static func seedClaudeConfig(home: String, environment: [String: String]) {
        let target = (home as NSString).appendingPathComponent(".claude.json")
        guard !FileManager.default.fileExists(atPath: target) else { return }
        let source: String
        if let configured = environment["CLAUDE_CONFIG_DIR"], !configured.isEmpty {
            source = (configured as NSString).appendingPathComponent(".claude.json")
        } else {
            source = (LoginEnvironment.homeDirectory as NSString).appendingPathComponent(".claude.json")
        }
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: source)),
              var root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return }
        for key in ["oauthAccount", "userID", "primaryApiKey"] { root[key] = nil }
        guard let seeded = try? JSONSerialization.data(withJSONObject: root) else { return }
        FileManager.default.createFile(atPath: target, contents: seeded, attributes: [.posixPermissions: 0o600])
    }

    // MARK: - Identity

    /// Who a Codex home is signed in as, from the ChatGPT login's ID token in `auth.json`.
    /// A login kept in the Keychain instead reads as unknown and the row falls back to its name.
    nonisolated static func codexIdentity(home: String) -> (email: String?, plan: String?) {
        let file = URL(fileURLWithPath: home).appendingPathComponent("auth.json")
        guard let data = try? Data(contentsOf: file),
              let root = JSONValue.parse(data) else { return (nil, nil) }
        if let token = root["tokens"]?["id_token"]?.string, let claims = jwtClaims(token) {
            let auth = claims["https://api.openai.com/auth"]
            return (claims["email"]?.string, PlanLimitsReader.codexPlanName(auth?["chatgpt_plan_type"]?.string))
        }
        if let key = root["OPENAI_API_KEY"]?.string, !key.isEmpty {
            return ("API key …\(key.suffix(4))", "API key")
        }
        return (nil, nil)
    }

    private nonisolated static func jwtClaims(_ token: String) -> JSONValue? {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var payload = parts[1].replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while !payload.count.isMultiple(of: 4) { payload += "=" }
        guard let data = Data(base64Encoded: payload) else { return nil }
        return JSONValue.parse(data)
    }
}
