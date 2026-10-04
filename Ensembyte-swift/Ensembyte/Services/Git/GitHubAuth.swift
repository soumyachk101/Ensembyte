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
        if let fallback = UserDefaults.standard.string(forKey: fallbackKey), !fallback.isEmpty { return fallback }
        return nil
    }

    @discardableResult
    public static func setCustomToken(_ token: String) -> Bool {
        invalidateCache()
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            deleteKeychain()
            UserDefaults.standard.removeObject(forKey: fallbackKey)
            return true
        }
        let saved = APIKeychain.set(trimmed, account: account, service: service)
        if saved {
            UserDefaults.standard.removeObject(forKey: fallbackKey)
            return true
        } else {
            UserDefaults.standard.set(trimmed, forKey: fallbackKey)
            return false
        }
    }

    private enum CLISource {
        case gh
        case git
    }

    private static let cacheLock = NSLock()
    nonisolated(unsafe) private static var cachedCLIToken: String?
    nonisolated(unsafe) private static var cachedCLISource: CLISource?
    nonisolated(unsafe) private static var lastCLICheck: Date?
    private static let cacheTTL: TimeInterval = 300

    public static func invalidateCache() {
        cacheLock.lock()
        cachedCLIToken = nil
        cachedCLISource = nil
        lastCLICheck = nil
        cacheLock.unlock()
    }

    public static func warmCache() {
        Task.detached(priority: .utility) {
            _ = resolveToken()
        }
    }

    /// Resolves token: Custom token > Environment variables > gh CLI > git credential fill
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
    public static func tokenSourceDescription() -> String? {
        if let custom = customToken(), !custom.isEmpty {
            return "Custom token (Keychain)"
        }
        if let env = ProcessInfo.processInfo.environment["GITHUB_TOKEN"] ?? ProcessInfo.processInfo.environment["GH_TOKEN"], !env.isEmpty {
            return "Environment variable"
        }
        guard let token = resolveToken(), !token.isEmpty else { return nil }
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
