import Foundation

/// One login of a provider CLI. Each account is a config home of its own, handed to the CLI
/// through the variable it reads its home from (`CLAUDE_CONFIG_DIR`, `CODEX_HOME`,
/// `GROK_HOME`), so two logins never share a credential. The first account of a provider is
/// the CLI's own home, the login that existed before accounts: `home` nil leaves the
/// environment as it is. Nothing secret is kept here; the tokens stay in the CLI's home or
/// the Keychain item the CLI writes for it.
struct ProviderAccount: Codable, Identifiable, Equatable, Sendable {
    var id: UUID
    var provider: ProviderKind
    /// The config home this account runs in, or nil for the CLI's own default home.
    var home: String?
    /// The name the user gave it; the email stands in when there is none.
    var name: String?
    /// Last seen identity, kept so the row reads right before the first check lands.
    var email: String?
    var plan: String?
    var addedAt: Date

    init(id: UUID = UUID(), provider: ProviderKind, home: String?, name: String? = nil, email: String? = nil, plan: String? = nil, addedAt: Date = .now) {
        self.id = id
        self.provider = provider
        self.home = home
        self.name = name
        self.email = email
        self.plan = plan
        self.addedAt = addedAt
    }

    var isDefault: Bool { home == nil }

    var title: String {
        if let name, !name.isEmpty { return name }
        if let email, !email.isEmpty { return email }
        return isDefault ? "Default account" : "New account"
    }

    private enum CodingKeys: String, CodingKey {
        case id, provider, home, name, email, plan, addedAt
    }

    // Lenient: a field a later build added or dropped never loses the whole list.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? container.decode(UUID.self, forKey: .id)) ?? UUID()
        provider = try container.decode(ProviderKind.self, forKey: .provider)
        home = try? container.decodeIfPresent(String.self, forKey: .home)
        name = try? container.decodeIfPresent(String.self, forKey: .name)
        email = try? container.decodeIfPresent(String.self, forKey: .email)
        plan = try? container.decodeIfPresent(String.self, forKey: .plan)
        addedAt = (try? container.decode(Date.self, forKey: .addedAt)) ?? .distantPast
    }
}

/// Every account of every provider and which one each provider runs on.
struct ProviderAccountBook: Codable, Equatable, Sendable {
    var accounts: [ProviderAccount] = []
    /// Provider raw value to the account new sessions start on.
    var active: [String: UUID] = [:]

    init() {}

    private enum CodingKeys: String, CodingKey {
        case accounts, active
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // One unreadable entry (a provider a later build removed) drops alone.
        let raw = (try? container.decode([LenientAccount].self, forKey: .accounts)) ?? []
        accounts = raw.compactMap(\.account)
        active = (try? container.decode([String: UUID].self, forKey: .active)) ?? [:]
    }

    private struct LenientAccount: Decodable {
        let account: ProviderAccount?
        init(from decoder: Decoder) throws {
            account = try? ProviderAccount(from: decoder)
        }
    }
}

extension ProviderKind {
    /// The variable the CLI reads its config home from, for the CLIs whose whole login
    /// lives under that home. Those are the providers that take more than one account.
    var accountHomeVariable: String? {
        switch self {
        case .claude: "CLAUDE_CONFIG_DIR"
        case .codex: "CODEX_HOME"
        case .grok: "GROK_HOME"
        default: nil
        }
    }

    var supportsAccounts: Bool { accountHomeVariable != nil }

    /// The CLI's own home in a given environment: the variable when the login shell sets
    /// it, else the dot folder in the home directory.
    func defaultAccountHome(in environment: [String: String]) -> String? {
        guard let variable = accountHomeVariable else { return nil }
        if let configured = environment[variable], !configured.isEmpty { return configured }
        let folder = switch self {
        case .claude: ".claude"
        case .codex: ".codex"
        case .grok: ".grok"
        default: ""
        }
        return (LoginEnvironment.homeDirectory as NSString).appendingPathComponent(folder)
    }

    /// Entries of the default home an account keeps to itself: the login and what is keyed
    /// to it. Everything else (sessions, settings, skills, plugins) is linked from the
    /// default home, so a thread resumes and a setting applies whichever account runs it.
    var accountPrivateEntries: Set<String> {
        switch self {
        case .claude: [".credentials.json", ".claude.json", ".claude.json.lock", "backups"]
        case .codex: ["auth.json"]
        case .grok: ["auth.json", "auth.json.lock"]
        default: []
        }
    }

    /// The CLI's sign-out command, run in an account's home before the home is deleted so
    /// a Keychain item it wrote goes with it.
    var logoutArguments: [String]? {
        switch self {
        case .claude: ["auth", "logout"]
        case .codex: ["logout"]
        case .grok: ["logout"]
        default: nil
        }
    }
}
