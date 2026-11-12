import Foundation
import LocalAuthentication
import Security

/// Manages GitHub authentication token resolution and secure Keychain storage.
public enum GitHubAuth {
    private static let service = "Ensembyte"
    private static let legacyService = "SwarmCode"
    private static let account = "GitHub Update Token"
    private static let fallbackKey = "github_token_custom"

    public static func customToken() -> String? {
        guard !CaptureRun.isEnabled else { return nil }
        if let keychain = readKeychain(), !keychain.isEmpty { return keychain }
        if let inMemory = inMemoryToken, !inMemory.isEmpty { return inMemory }
        // The plaintext UserDefaults copy is only ever a read for a Mac whose Keychain
        // refused the write earlier; it is never re-persisted.
        if let fallback = UserDefaults.standard.string(forKey: fallbackKey), !fallback.isEmpty { return fallback }
        return nil
    }

    /// The token this session secured in memory when the Keychain refused the write;
    /// it survives until the app quits or is invalidated and is never written to disk.
    nonisolated(unsafe) private static var inMemoryToken: String?

    @discardableResult
    public static func setCustomToken(_ token: String) -> Bool {
        invalidateCache()
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            deleteKeychain()
            UserDefaults.standard.removeObject(forKey: fallbackKey)
            inMemoryToken = nil
            return true
        }
        if APIKeychain.set(trimmed, account: account, service: service) {
            inMemoryToken = nil
            UserDefaults.standard.removeObject(forKey: fallbackKey)
            return true
        }
        // The Keychain refused, so the key is held in memory for this session only;
        // it is never written to the plaintext UserDefaults fallback (a secret on disk
        // in a plist), which was removed rather than kept.
        inMemoryToken = trimmed
        return false
    }

    private enum CLISource {
        case gh
        case git
    }

    private static let cacheLock = NSLock()
    nonisolated(unsafe) private static var cachedCLIToken: String?
    nonisolated(unsafe) private static var cachedCLISource: CLISource?
    nonisolated(unsafe) private static var lastCLICheck: Date?
    nonisolated(unsafe) private static var warmInFlight = false
    /// A revoked or rotated gh-CLI token is not re-resolved for this long; short enough that
    /// a stale cached token ages out on its own, so a 401 is not served for minutes.
    private static let cacheTTL: TimeInterval = 60

    public static func invalidateCache() {
        cacheLock.lock()
        cachedCLIToken = nil
        cachedCLISource = nil
        lastCLICheck = nil
        cacheLock.unlock()
    }

    /// Call when a token consumer gets a 401: clears the cached CLI token so the next read
    /// re-resolves, instead of serving a revoked or rotated token for the whole TTL. It
    /// does not touch the user's own custom token (or its in-memory hold) — that one is
    /// still valid even if a GitHub call 401'd. The 401 handling lives in the App layer
    /// (GitHubConnection); this is the hook it should call at that narrow point.
    public static func invalidateOnAuthFailure() {
        cacheLock.lock()
        cachedCLIToken = nil
        cachedCLISource = nil
        lastCLICheck = nil
        cacheLock.unlock()
    }

    /// Kicks off the cold CLI resolve once, off the main thread. Repeated calls while a
    /// pass is running (or the cache is still fresh) are no-ops.
    public static func warmCache() {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        if warmInFlight { return }
        if let last = lastCLICheck, Date().timeIntervalSince(last) < cacheTTL { return }
        warmInFlight = true
        Task.detached(priority: .utility) {
            _ = resolveToken()
            cacheLock.withLock { warmInFlight = false }
        }
    }

    /// Cache-only token read, safe on the main thread: it never waits for a cold CLI
    /// resolve. Custom and environment tokens are fast direct reads; the CLI-backed
    /// answer is whatever a previous warm pass stored, and when nothing is cached it
    /// kicks one off in the background and returns nil.
    public static func cachedToken() -> String? {
        if let custom = customToken(), !custom.isEmpty {
            return custom
        }
        if let env = ProcessInfo.processInfo.environment["GITHUB_TOKEN"] ?? ProcessInfo.processInfo.environment["GH_TOKEN"], !env.isEmpty {
            return env
        }
        cacheLock.lock()
        let token = cachedCLIToken
        cacheLock.unlock()
        if token == nil { warmCache() }
        return token
    }

    /// Resolves token: Custom token > Environment variables > gh CLI > git credential fill.
    /// The CLI steps run synchronous processes and take up to a few seconds: call this
    /// off the main thread, or use `cachedToken` where main-thread safety matters.
    public static func resolveToken() -> String? {
        if let custom = customToken(), !custom.isEmpty {
            return custom
        }
        if let env = ProcessInfo.processInfo.environment["GITHUB_TOKEN"] ?? ProcessInfo.processInfo.environment["GH_TOKEN"], !env.isEmpty {
            return env
        }

        cacheLock.lock()
        if let last = lastCLICheck, Date().timeIntervalSince(last) < cacheTTL {
            let cached = cachedCLIToken
            cacheLock.unlock()
            return cached
        }
        cacheLock.unlock()

        let source: CLISource?
        let token: String?
        if let gh = resolveFromGHCLI(), !gh.isEmpty {
            token = gh
            source = .gh
        } else if let git = resolveFromGitCredential(), !git.isEmpty {
            token = git
            source = .git
        } else {
            token = nil
            source = nil
        }

        cacheLock.lock()
        cachedCLIToken = token
        cachedCLISource = source
        lastCLICheck = Date()
        cacheLock.unlock()

        return token
    }

    /// Short label indicating where the active token came from (for Settings display).
    /// Main-thread safe: it reads only what a warm pass has already resolved, and asks
    /// for one in the background when the cache is still empty.
    public static func tokenSourceDescription() -> String? {
        if let custom = customToken(), !custom.isEmpty {
            return "Custom token (Keychain)"
        }
        if let env = ProcessInfo.processInfo.environment["GITHUB_TOKEN"] ?? ProcessInfo.processInfo.environment["GH_TOKEN"], !env.isEmpty {
            return "Environment variable"
        }
        guard let token = cachedToken(), !token.isEmpty else { return nil }
        cacheLock.lock()
        let source = cachedCLISource
        cacheLock.unlock()
        if source == .git {
            return "Git credentials"
        }
        return "GitHub CLI (gh)"
    }

    /// Runs a CLI process safely on a background thread so `waitUntilExit` does not pump
    /// the main thread's NSRunLoop (which triggers re-entrant SwiftUI layout and AttributeGraph crashes).
    private static func runCLIProcess(executable: String, arguments: [String], input: Data? = nil, timeout: TimeInterval = 3.0) -> (status: Int32, stdout: Data)? {
        let task = { () -> (status: Int32, stdout: Data)? in
            let proc = Process()
            proc.executableURL = URL(filePath: executable)
            proc.arguments = arguments
            let outPipe = Pipe()
            proc.standardOutput = outPipe
            proc.standardError = Pipe()
            let inPipe = Pipe()
            if input != nil {
                proc.standardInput = inPipe
            }
            do {
                try proc.run()
                if let input {
                    try inPipe.fileHandleForWriting.write(contentsOf: input)
                    try inPipe.fileHandleForWriting.close()
                }
                let deadline = Date().addingTimeInterval(timeout)
                while proc.isRunning && Date() < deadline {
                    Thread.sleep(forTimeInterval: 0.05)
                }
                if proc.isRunning {
                    proc.terminate()
                    return nil
                }
                let data = outPipe.fileHandleForReading.readDataToEndOfFile()
                return (proc.terminationStatus, data)
            } catch {
                return nil
            }
        }

        if Thread.isMainThread {
            return DispatchQueue.global(qos: .userInitiated).sync(execute: task)
        } else {
            return task()
        }
    }

    private static func resolveFromGHCLI() -> String? {
        let paths = ["/opt/homebrew/bin/gh", "/usr/local/bin/gh", "/usr/bin/gh"]
        guard let exe = paths.first(where: { FileManager.default.fileExists(atPath: $0) }) else { return nil }
        guard let result = runCLIProcess(executable: exe, arguments: ["auth", "token"], timeout: 3.0),
              result.status == 0 else { return nil }
        if let str = String(data: result.stdout, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !str.isEmpty {
            return str
        }
        return nil
    }

    private static func resolveFromGitCredential() -> String? {
        guard let inData = "protocol=https\nhost=github.com\n\n".data(using: .utf8) else { return nil }
        guard let result = runCLIProcess(executable: "/usr/bin/git", arguments: ["credential", "fill"], input: inData, timeout: 3.0),
              result.status == 0 else { return nil }
        if let output = String(data: result.stdout, encoding: .utf8) {
            for line in output.components(separatedBy: "\n") {
                if line.hasPrefix("password=") {
                    let pass = String(line.dropFirst("password=".count)).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !pass.isEmpty { return pass }
                }
            }
        }
        return nil
    }

    private static func readKeychain() -> String? {
        if let key = APIKeychain.read(account, service: service), !key.isEmpty {
            return key
        }
        if let legacyKey = APIKeychain.read(account, service: legacyService), !legacyKey.isEmpty {
            return legacyKey
        }
        return nil
    }

    private static func deleteKeychain() {
        APIKeychain.delete(account, service: service)
        APIKeychain.delete(account, service: legacyService)
    }
}
