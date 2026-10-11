import Foundation

/// Keeping an eye on the provider CLIs: which version is installed, which one its install
/// channel would bring, and running that channel's update when asked.
extension ProviderRegistry {
    /// How often every monitored CLI is checked, and how old a check opening the Providers
    /// page still trusts. A check is a registry request per CLI (a `brew info` for casks).
    private static let cliCheckInterval: TimeInterval = 6 * 3600
    static let cliCheckFreshnessOnOpen: TimeInterval = 15 * 60
    private static let cliLatestKey = "providerCLILatestVersions"
    private static let cliCheckWidth = 3

    /// Whether a provider is checked at all: a CLI provider, switched on, monitored.
    func monitorsCLIUpdates(_ provider: ProviderKind) -> Bool {
        !provider.isAPIKeyBased && !CaptureRun.isEnabled && settings.isEnabled(provider) && settings.monitorsUpdates(provider)
    }

    /// After the provider or its monitoring was switched: checked again, or its row
    /// cleared, a waiting update with it. An update already running finishes.
    func cliMonitoringChanged(_ provider: ProviderKind) {
        if monitorsCLIUpdates(provider) {
            Task { await checkCLIUpdate(provider, freshness: Self.cliCheckFreshnessOnOpen) }
        } else if cliUpdates[provider]?.phase != .updating {
            cliUpdates[provider] = nil
        }
    }

    /// Checks now (results under a day old come from the cache), then every six hours.
    func startCLIUpdateChecks() {
        guard cliUpdateLoop == nil, !CaptureRun.isEnabled else { return }
        cliUpdateLoop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.checkCLIUpdates(freshness: Self.cliCheckInterval)
                try? await Task.sleep(for: .seconds(Self.cliCheckInterval))
            }
        }
    }

    /// Checks every monitored CLI, a few at a time. A latest version read within `freshness`
    /// is served from the cache; `freshness: 0` asks every feed again.
    func checkCLIUpdates(freshness: TimeInterval = 0) async {
        if let running = cliUpdateCheck {
            await running.value
            guard freshness == 0 else { return }
        }
        let task = Task { [weak self] in
            guard let self else { return }
            for provider in ProviderKind.allCases where !self.monitorsCLIUpdates(provider) && cliUpdates[provider]?.phase.isBusy != true {
                cliUpdates[provider] = nil
            }
            let providers = ProviderKind.allCases.filter(self.monitorsCLIUpdates)
            var next = 0
            await withTaskGroup(of: Void.self) { group in
                while next < providers.count, next < Self.cliCheckWidth {
                    let provider = providers[next]
                    next += 1
                    group.addTask { await self.checkCLIUpdate(provider, freshness: freshness) }
                }
                for await _ in group {
                    guard next < providers.count else { continue }
                    let provider = providers[next]
                    next += 1
                    group.addTask { await self.checkCLIUpdate(provider, freshness: freshness) }
                }
            }
        }
        cliUpdateCheck = task
        await task.value
        cliUpdateCheck = nil
    }

    /// Checks one CLI. Its installed version is the one the provider check last read.
    func checkCLIUpdate(_ provider: ProviderKind, force: Bool = false, freshness: TimeInterval = 0) async {
        guard monitorsCLIUpdates(provider) else {
            if cliUpdates[provider]?.phase.isBusy != true { cliUpdates[provider] = nil }
            return
        }
        guard cliUpdates[provider]?.phase.isBusy != true else { return }
        let status = status(provider)
        guard let executable = status.executable else {
            cliUpdates[provider] = nil
            return
        }
        let installed = status.version
        let environment = environment(for: provider)
        let channel = CLIUpdates.channel(for: provider, executable: executable, environment: environment)
        var update = cliUpdates[provider] ?? CLIUpdateStatus(phase: .checking)
        update.installed = installed
        update.channel = channel
        if !force, freshness > 0, let cached = Self.cachedLatest(provider), Date.now.timeIntervalSince(cached.date) < freshness {
            update.latest = cached.version
            update.checkedAt = cached.date
            update.error = nil
            update.updateFailed = false
            update.phase = Self.phase(installed: installed, latest: cached.version)
            cliUpdates[provider] = update
            return
        }
        // "Checking" only where there is nothing to show yet; a re-check keeps the last answer up.
        if cliUpdates[provider] == nil { cliUpdates[provider] = update }
        let latest: String?
        do {
            if let channel {
                latest = try await CLIUpdates.latestVersion(provider, installed: installed, channel: channel, executable: executable, environment: environment)
            } else {
                latest = nil
            }
        } catch {
            guard cliUpdates[provider]?.phase.isBusy != true else { return }
            update.phase = .failed
            update.updateFailed = false
            update.error = Self.oneLine(error.localizedDescription)
            update.checkedAt = .now
            cliUpdates[provider] = update
            return
        }
        guard monitorsCLIUpdates(provider), cliUpdates[provider]?.phase.isBusy != true else { return }
        Self.storeLatest(latest, for: provider)
        update.latest = latest
        update.checkedAt = .now
        update.error = nil
        update.updateFailed = false
        update.phase = Self.phase(installed: installed, latest: latest)
        cliUpdates[provider] = update
    }

    private static func phase(installed: String?, latest: String?) -> CLIUpdateStatus.Phase {
        guard let installed, let latest else { return .current }
        return CLIUpdates.isNewer(latest, than: installed) ? .available : .current
    }

    /// Runs the channel's update for a provider, after any turn on it ends. A session that
    /// is open keeps the process it started with; the next one starts the new version.
    func updateCLI(_ provider: ProviderKind) async {
        guard var update = cliUpdates[provider], !update.phase.isBusy, let channel = update.channel else { return }
        let before = update.installed
        update.error = nil
        update.updateFailed = false
        if isProviderBusy(provider) {
            update.phase = .waiting
            cliUpdates[provider] = update
            while isProviderBusy(provider), cliUpdates[provider]?.phase == .waiting {
                try? await Task.sleep(for: .seconds(2))
            }
            // Monitoring or the provider switched off while it waited: the update is called off.
            guard cliUpdates[provider]?.phase == .waiting else { return }
        }
        update.phase = .updating
        cliUpdates[provider] = update
        await LoginEnvironment.load()
        let (tool, arguments, extra) = channel.invocation
        let environment = environment(for: provider).merging(extra) { $1 }
        let result: ShellResult
        do {
            result = try await Shell.run(URL(fileURLWithPath: tool), arguments, in: FileManager.default.temporaryDirectory,
                                         environment: environment, timeout: 900)
        } catch {
            failUpdate(provider, Self.oneLine(error.localizedDescription))
            return
        }
        guard result.succeeded else {
            failUpdate(provider, Self.oneLine(TextCleanup.stripANSI(result.failureMessage)))
            return
        }
        // The automatic updater counts this one: no second run of it right after.
        var dates = (UserDefaults.standard.dictionary(forKey: cliUpdatesKey) as? [String: Double]) ?? [:]
        dates[provider.rawValue] = Date.now.timeIntervalSince1970
        UserDefaults.standard.set(dates, forKey: cliUpdatesKey)
        await refresh(provider)
        let after = status(provider).version
        update = cliUpdates[provider] ?? update
        update.installed = after
        if let latest = update.latest, let after, CLIUpdates.isNewer(latest, than: after) {
            // Homebrew can lag an upstream release: `brew upgrade` succeeds with nothing to install.
            failUpdate(provider, after == before
                ? "\(channel.command) finished, but v\(after) is still installed"
                : "Updated to v\(after); v\(latest) is not out on this channel yet")
            return
        }
        update.phase = .updated
        cliUpdates[provider] = update
        await loadCatalog(provider, force: true)
    }

    private func failUpdate(_ provider: ProviderKind, _ message: String) {
        guard var update = cliUpdates[provider] else { return }
        update.phase = .failed
        update.updateFailed = true
        update.error = message
        cliUpdates[provider] = update
    }

    /// The last line worth reading of a long message, without ANSI or the npm log footer.
    private static func oneLine(_ message: String) -> String {
        let lines = message.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.contains("A complete log of this run") && !$0.hasPrefix("npm error Log files") }
        let line = lines.first(where: { $0.localizedCaseInsensitiveContains("error") }) ?? lines.last ?? "Unknown error"
        return line.count > 160 ? String(line.prefix(157)) + "…" : line
    }

    // MARK: - Cache

    private static func cachedLatest(_ provider: ProviderKind) -> (version: String?, date: Date)? {
        guard let entry = (UserDefaults.standard.dictionary(forKey: cliLatestKey) as? [String: [String: Any]])?[provider.rawValue],
              let seconds = entry["checkedAt"] as? Double else { return nil }
        return (entry["version"] as? String, Date(timeIntervalSince1970: seconds))
    }

    private static func storeLatest(_ version: String?, for provider: ProviderKind) {
        var all = (UserDefaults.standard.dictionary(forKey: cliLatestKey) as? [String: [String: Any]]) ?? [:]
        var entry: [String: Any] = ["checkedAt": Date.now.timeIntervalSince1970]
        if let version { entry["version"] = version }
        all[provider.rawValue] = entry
        UserDefaults.standard.set(all, forKey: cliLatestKey)
    }
}

extension CLIUpdateStatus.Phase {
    /// An update asked for or under way: checks leave the row alone meanwhile.
    var isBusy: Bool { self == .waiting || self == .updating }
}
