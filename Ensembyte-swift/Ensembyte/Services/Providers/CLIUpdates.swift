import Foundation

/// Who owns an installed provider CLI, read from where its binary really lives. An update
/// goes through that owner and nothing else: `brew upgrade` on a cask, `npm install -g` on
/// an npm global, the CLI's own updater on a vendor install. Upgrading the wrong one leaves
/// the binary on the PATH exactly where it was.
enum CLIInstallChannel: Equatable, Sendable {
    case homebrew(brew: String, token: String, cask: Bool)
    case npm(tool: String, package: String, prefix: String, tag: String)
    case bun(tool: String, package: String, tag: String)
    case pnpm(tool: String, package: String, tag: String)
    case selfUpdate(executable: String, arguments: [String])

    /// What the Update button runs, as the user would type it.
    var command: String {
        let (tool, arguments, _) = invocation
        return ([(tool as NSString).lastPathComponent] + arguments).joined(separator: " ")
    }

    var invocation: (tool: String, arguments: [String], environment: [String: String]) {
        switch self {
        case .homebrew(let brew, let token, let cask):
            // No hints, emoji or prompts in a process nobody reads live.
            return (brew, ["upgrade", cask ? "--cask" : "--formula", token],
                    ["NONINTERACTIVE": "1", "HOMEBREW_NO_ENV_HINTS": "1", "HOMEBREW_NO_EMOJI": "1", "HOMEBREW_NO_ANALYTICS": "1"])
        case .npm(let tool, let package, let prefix, let tag):
            // The prefix the CLI already lives under, so a second npm (nvm, Homebrew node)
            // never installs a copy beside it that the PATH does not reach.
            return (tool, ["install", "-g", "--prefix", prefix, "\(package)@\(tag)"], ["npm_config_fund": "false", "npm_config_audit": "false"])
        case .bun(let tool, let package, let tag):
            return (tool, ["add", "-g", "\(package)@\(tag)"], [:])
        case .pnpm(let tool, let package, let tag):
            return (tool, ["add", "-g", "\(package)@\(tag)"], [:])
        case .selfUpdate(let executable, let arguments):
            return (executable, arguments, [:])
        }
    }

    /// The registry package an npm-family install tracks, for its latest version.
    var package: (name: String, tag: String)? {
        switch self {
        case .npm(_, let package, _, let tag), .bun(_, let package, let tag), .pnpm(_, let package, let tag): (package, tag)
        case .homebrew, .selfUpdate: nil
        }
    }
}

/// Installed against latest for every provider CLI, without spawning anything but the
/// provider's own read-only checks (`grok update --check`, `brew info`).
enum CLIUpdates {
    /// The arguments of each CLI's own updater, for a binary no package manager owns.
    /// Devin's `update` asks before it installs, and has no release feed to compare with.
    static func selfUpdateArguments(_ provider: ProviderKind) -> [String]? {
        switch provider {
        case .claude, .codex, .cursor, .grok, .copilot, .antigravity, .commandcode: ["update"]
        case .opencode, .opencodeGo: ["upgrade"]
        case .pi: ["update", "self"]
        // omp: no updater command is known here; an npm or bun install still updates through its package manager.
        case .devin, .deepseek, .meta, .zai, .omp: nil
        }
    }

    /// The npm package behind a provider, for its release feed when the binary came from
    /// the CLI's own installer.
    static func npmPackage(_ provider: ProviderKind, installed: String?) -> String? {
        switch provider {
        case .claude: "@anthropic-ai/claude-code"
        case .codex: "@openai/codex"
        case .copilot: "@github/copilot"
        case .commandcode: "command-code"
        case .pi: "@earendil-works/pi-coding-agent"
        // OpenCode 2 is a separate package; the 1.x updater stays on the old line.
        case .opencode, .opencodeGo: (installed.flatMap { numbers($0)?.first } ?? 0) >= 2 ? "@opencode/cli" : "opencode-ai"
        default: nil
        }
    }

    /// Reads the owner from the binary's real path (symlinks followed). Nil for a CLI it
    /// cannot place and that has no updater of its own: that row shows its version only.
    static func channel(for provider: ProviderKind, executable: URL, environment: [String: String]) -> CLIInstallChannel? {
        let resolved = executable.resolvingSymlinksInPath()
        let components = resolved.pathComponents
        if let brew = homebrew(components) { return brew }
        let tag = provider == .claude ? claudeChannel() : "latest"
        if let index = components.firstIndex(of: "node_modules"), index + 1 < components.count {
            var package = components[index + 1]
            if package.hasPrefix("@"), index + 2 < components.count { package += "/" + components[index + 2] }
            let path = resolved.path
            if path.contains("/.bun/install/global/") {
                let bun = (LoginEnvironment.homeDirectory as NSString).appendingPathComponent(".bun/bin/bun")
                let tool = FileManager.default.isExecutableFile(atPath: bun) ? bun : LoginEnvironment.which("bun", in: environment)?.path
                return tool.map { .bun(tool: $0, package: package, tag: tag) }
            }
            if path.contains("/pnpm/") {
                return LoginEnvironment.which("pnpm", in: environment).map { .pnpm(tool: $0.path, package: package, tag: tag) }
            }
            if index >= 2, components[index - 1] == "lib" {
                let prefix = NSString.path(withComponents: Array(components[..<(index - 1)]))
                let local = (prefix as NSString).appendingPathComponent("bin/npm")
                let tool = FileManager.default.isExecutableFile(atPath: local) ? local : LoginEnvironment.which("npm", in: environment)?.path
                return tool.map { .npm(tool: $0, package: package, prefix: prefix, tag: tag) }
            }
        }
        // A package manager the path does not name (a system package, Nix) is left alone.
        if resolved.path.hasPrefix("/usr/bin") || resolved.path.hasPrefix("/nix/") { return nil }
        return selfUpdateArguments(provider).map { .selfUpdate(executable: executable.path, arguments: $0) }
    }

    /// `Caskroom/<token>/<version>/…` and `Cellar/<token>/<version>/{bin,libexec}/…`: the
    /// cask or formula that owns the binary. An npm global inside a keg-only node's Cellar
    /// (`Cellar/node@22/…/lib/node_modules`) belongs to npm, not to that formula.
    private static func homebrew(_ components: [String]) -> CLIInstallChannel? {
        guard let index = components.firstIndex(where: { $0 == "Caskroom" || $0 == "Cellar" }),
              index > 0, index + 3 < components.count else { return nil }
        let cask = components[index] == "Caskroom"
        let token = components[index + 1]
        guard token.allSatisfy({ $0.isLetter || $0.isNumber || "+-_.@".contains($0) }), !token.hasSuffix(".rb") else { return nil }
        if !cask, !["bin", "libexec"].contains(components[index + 3]) { return nil }
        let brew = (NSString.path(withComponents: Array(components[..<index])) as NSString).appendingPathComponent("bin/brew")
        guard FileManager.default.isExecutableFile(atPath: brew) else { return nil }
        return .homebrew(brew: brew, token: token, cask: cask)
    }

    /// Claude Code's chosen release channel (`autoUpdatesChannel` in its user settings),
    /// so a Mac on `stable` is never offered the `latest` build its updater would skip.
    private static func claudeChannel() -> String {
        let path = (LoginEnvironment.homeDirectory as NSString).appendingPathComponent(".claude/settings.json")
        guard let data = FileManager.default.contents(atPath: path),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let channel = json["autoUpdatesChannel"] as? String, channel == "stable" else { return "latest" }
        return channel
    }

    // MARK: - Latest versions

    /// The newest version the channel would install, or nil when the provider publishes
    /// nothing to compare with. Throws when a feed that exists could not be read.
    @concurrent
    static func latestVersion(
        _ provider: ProviderKind,
        installed: String?,
        channel: CLIInstallChannel,
        executable: URL,
        environment: [String: String]
    ) async throws -> String? {
        switch channel {
        case .homebrew(let brew, let token, let cask):
            return try await homebrewVersion(brew: brew, token: token, cask: cask, environment: environment)
        case .npm, .bun, .pnpm:
            guard let (package, tag) = channel.package else { return nil }
            return try await npmVersion(package, tag: tag)
        case .selfUpdate:
            switch provider {
            case .cursor: return try await cursorVersion()
            case .antigravity: return try await antigravityVersion()
            case .grok: return try await grokVersion(executable, installed: installed, environment: environment)
            default:
                guard let package = npmPackage(provider, installed: installed) else { return nil }
                return try await npmVersion(package, tag: provider == .claude ? claudeChannel() : "latest")
            }
        }
    }

    private static func fetch(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw ShellError("The release feed answered \((response as? HTTPURLResponse)?.statusCode ?? 0).")
        }
        return data
    }

    private static func npmVersion(_ package: String, tag: String) async throws -> String? {
        let name = package.replacingOccurrences(of: "/", with: "%2f")
        guard let url = URL(string: "https://registry.npmjs.org/\(name)/\(tag)") else { return nil }
        let json = try JSONSerialization.jsonObject(with: try await fetch(url)) as? [String: Any]
        return (json?["version"] as? String).flatMap { numbers($0) == nil ? nil : $0 }
    }

    /// The newer of formulae.brew.sh and the local tap: the API knows a release before
    /// `brew update` ran; a third-party tap is only known locally.
    private static func homebrewVersion(brew: String, token: String, cask: Bool, environment: [String: String]) async throws -> String? {
        var found: [String] = []
        var failure: Error?
        if let url = URL(string: "https://formulae.brew.sh/api/\(cask ? "cask" : "formula")/\(token).json") {
            do {
                if let json = try JSONSerialization.jsonObject(with: try await fetch(url)) as? [String: Any],
                   let version = homebrewVersion(in: json, cask: cask) { found.append(version) }
            } catch { failure = error }
        }
        var environment = environment
        environment["HOMEBREW_NO_AUTO_UPDATE"] = "1"
        environment["HOMEBREW_NO_ANALYTICS"] = "1"
        if let result = try? await Shell.run(URL(fileURLWithPath: brew), ["info", cask ? "--cask" : "--formula", "--json=v2", token], environment: environment, timeout: 30),
           result.succeeded,
           let json = try? JSONSerialization.jsonObject(with: result.stdout) as? [String: Any],
           let entry = (json[cask ? "casks" : "formulae"] as? [[String: Any]])?.first,
           let version = homebrewVersion(in: entry, cask: cask) {
            found.append(version)
        }
        if found.isEmpty, let failure { throw failure }
        return found.max { isNewer($1, than: $0) }
    }

    private static func homebrewVersion(in json: [String: Any], cask: Bool) -> String? {
        let raw = cask ? json["version"] as? String : (json["versions"] as? [String: Any])?["stable"] as? String
        // A cask version can carry a build after a comma ("1.2.3,456").
        guard let version = raw?.split(separator: ",").first.map(String.init), numbers(version) != nil else { return nil }
        return version
    }

    /// Cursor's installer script names the build it installs.
    private static func cursorVersion() async throws -> String? {
        guard let url = URL(string: "https://cursor.com/install") else { return nil }
        let script = String(decoding: try await fetch(url), as: UTF8.self)
        return script.firstMatch(of: #/versions/(\d{4}\.\d{2}\.\d{2}-[0-9a-f]+)/#).map { String($0.output.1) }
    }

    /// The manifest the Antigravity CLI's installer and updater read.
    private static func antigravityVersion() async throws -> String? {
        #if arch(arm64)
        let platform = "darwin_arm64"
        #else
        let platform = "darwin_amd64"
        #endif
        guard let url = URL(string: "https://antigravity-cli-auto-updater-974169037036.us-central1.run.app/manifests/\(platform).json") else { return nil }
        let json = try JSONSerialization.jsonObject(with: try await fetch(url)) as? [String: Any]
        return json?["version"] as? String
    }

    /// `grok update --check` names the installed and the available version
    /// ("… available: 1.0.46 -> 1.0.50"); nothing newer means it is current.
    private static func grokVersion(_ executable: URL, installed: String?, environment: [String: String]) async throws -> String? {
        let result = try await Shell.run(executable, ["update", "--check"], in: FileManager.default.temporaryDirectory, environment: environment, timeout: 30)
        guard result.succeeded else { throw ShellError(result.failureMessage) }
        let text = TextCleanup.stripANSI(result.output + result.errorOutput)
        let versions = text.matches(of: #/\d+\.\d+\.\d+(?:-[0-9A-Za-z.]+)?/#).map { String($0.output) }
        return versions.last ?? installed
    }

    // MARK: - Comparing

    /// The numeric part of a version ("v2.0.24-beta" → [2, 0, 24]); nil for fewer than two numbers.
    static func numbers(_ version: String) -> [Int]? {
        let trimmed = version.trimmingCharacters(in: .whitespaces).drop { $0 == "v" }
        let numeric = trimmed.split(whereSeparator: { $0 == "-" || $0 == "+" }).first ?? ""
        let values = numeric.split(separator: ".").map { Int($0) }
        guard values.count >= 2, !values.contains(nil) else { return nil }
        return values.compactMap { $0 }
    }

    /// Whether `latest` is a later release than `installed`, numbers only: Cursor's
    /// build hash, or a prerelease tag, never makes a version newer on its own.
    static func isNewer(_ latest: String, than installed: String) -> Bool {
        guard var new = numbers(latest), var old = numbers(installed) else { return false }
        let width = max(new.count, old.count)
        new += Array(repeating: 0, count: width - new.count)
        old += Array(repeating: 0, count: width - old.count)
        return old.lexicographicallyPrecedes(new)
    }
}

/// One provider CLI's installed and latest version, and where its update stands.
struct CLIUpdateStatus: Equatable, Sendable {
    enum Phase: Equatable, Sendable {
        case checking
        case current
        case available
        /// Update asked for; chats on this provider are still running a turn.
        case waiting
        case updating
        case updated
        case failed
    }

    var phase: Phase
    var installed: String?
    var latest: String?
    var channel: CLIInstallChannel?
    /// The failed check's or update's own message, one line.
    var error: String?
    /// Whether the failure was the update itself rather than the check.
    var updateFailed = false
    var checkedAt: Date?
}
