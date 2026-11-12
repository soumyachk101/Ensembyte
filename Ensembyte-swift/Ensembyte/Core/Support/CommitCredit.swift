import Foundation

/// Credits `ensembyte[bot]` on commits made by processes Ensembyte starts.
///
/// Agents commit with `git` themselves, so the credit is a `commit-msg` hook
/// those processes see and a hand commit in another terminal does not. The
/// hook runs the repository's own hook first, then appends
/// `GitHubAppIdentity.coAuthorTrailer`. GitHub treats that trailer as a
/// contribution by the bot, on the commit and on a pull request that contains it.
enum CommitCredit {
    static var trailer: String { GitHubAppIdentity.coAuthorTrailer }

    /// Hooks the wrappers stand in for. `reference-transaction` and
    /// `post-index-change` are left out: they run on every ref or index write.
    static let hookNames = [
        "applypatch-msg",
        "pre-applypatch",
        "post-applypatch",
        "pre-commit",
        "pre-merge-commit",
        "prepare-commit-msg",
        "commit-msg",
        "post-commit",
        "pre-rebase",
        "post-checkout",
        "post-merge",
        "pre-push",
        "post-rewrite",
        "pre-auto-gc",
        "push-to-checkout",
        "sendemail-validate",
    ]

    private static let installLock = NSLock()

    /// Point `environment` at the hook wrappers. A GitHub credential overlay
    /// already uses `GIT_CONFIG_*`; the hooks path is appended after those
    /// entries so neither one drops the other. Install failure leaves the
    /// environment as it was, and git keeps working without the credit.
    static func applying(to environment: [String: String], hooksDirectory: URL = StoragePaths.directory("git-hooks")) -> [String: String] {
        do {
            try install(into: hooksDirectory)
        } catch {
            return environment
        }
        return appendingHooksPath(hooksDirectory.path, to: environment)
    }

    /// Append `core.hooksPath`, or retarget the existing entry when the
    /// directory changed. A second call with the same path is a no-op.
    static func appendingHooksPath(_ path: String, to environment: [String: String]) -> [String: String] {
        guard let count = Int(environment["GIT_CONFIG_COUNT"] ?? "0"), count >= 0 else {
            return environment
        }
        if let index = (0..<count).last(where: { environment["GIT_CONFIG_KEY_\($0)"] == "core.hooksPath" }) {
            guard environment["GIT_CONFIG_VALUE_\(index)"] != path else { return environment }
            var updated = environment
            updated["GIT_CONFIG_VALUE_\(index)"] = path
            return updated
        }
        var updated = environment
        updated["GIT_CONFIG_KEY_\(count)"] = "core.hooksPath"
        updated["GIT_CONFIG_VALUE_\(count)"] = path
        updated["GIT_CONFIG_COUNT"] = String(count + 1)
        return updated
    }

    static func wrapperScript() -> String {
        let trailer = trailer
        return """
        #!/bin/sh
        # Ensembyte: run this repository's own hook, then credit Ensembyte in the commit.
        name=$(basename "$0")
        here=$(cd "$(dirname "$0")" && pwd -P)
        common=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)
        # The hooks path the repository or user configured (not ours, which only
        # this process's environment carries), else the repository's hooks folder.
        dir=$(git config --file "$common/config" core.hooksPath 2>/dev/null \
            || git config --global core.hooksPath 2>/dev/null \
            || git config --system core.hooksPath 2>/dev/null)
        case "$dir" in
            "") dir="$common/hooks" ;;
            "~/"*) dir="$HOME/${dir#~/}" ;;
        esac
        original="$dir/$name"
        if [ -x "$original" ] && [ "$(cd "$dir" 2>/dev/null && pwd -P)" != "$here" ]; then
            if [ "$name" = commit-msg ]; then
                "$original" "$@" || exit $?
            else
                exec "$original" "$@"
            fi
        fi
        if [ "$name" = commit-msg ] && [ -n "$1" ]; then
            git interpret-trailers --in-place --if-exists addIfDifferent --trailer "\(trailer)" "$1" 2>/dev/null || true
        fi
        exit 0
        """
    }

    static func install(into directory: URL) throws {
        installLock.lock()
        defer { installLock.unlock() }
        let script = wrapperScript()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for name in hookNames {
            let url = directory.appendingPathComponent(name)
            if let current = try? String(contentsOf: url, encoding: .utf8), current == script {
                try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
                continue
            }
            let temp = directory.appendingPathComponent(".\(name)-\(UUID().uuidString)")
            try Data(script.utf8).write(to: temp)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: temp.path)
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
            try FileManager.default.moveItem(at: temp, to: url)
        }
    }
}
