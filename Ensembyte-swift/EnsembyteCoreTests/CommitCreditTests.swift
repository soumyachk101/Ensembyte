import XCTest
@testable import Ensembyte

/// Commits Ensembyte starts must carry the ensembyte[bot] co-author trailer,
/// and a commit made without that environment must not.
final class CommitCreditTests: XCTestCase {
    private var hooks: URL!
    private var repo: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        hooks = FileManager.default.temporaryDirectory.appendingPathComponent("ensembyte-hooks-\(UUID().uuidString)", isDirectory: true)
        repo = FileManager.default.temporaryDirectory.appendingPathComponent("ensembyte-repo-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: hooks)
        try? FileManager.default.removeItem(at: repo)
        try super.tearDownWithError()
    }

    func testTrailerMatchesTheBotIdentity() {
        XCTAssertEqual(GitHubAppIdentity.appId, 5597496)
        XCTAssertEqual(GitHubAppIdentity.clientID, "Iv23lip8dk91VWKI1t22")
        XCTAssertEqual(GitHubAPI.clientID, GitHubAppIdentity.clientID)
        XCTAssertEqual(GitHubAppIdentity.botUserID, 352044576)
        XCTAssertNotEqual(GitHubAppIdentity.botUserID, 346184242, "346184242 is zeronsh[bot]")
        XCTAssertEqual(
            CommitCredit.trailer,
            "Co-authored-by: ensembyte[bot] <352044576+ensembyte[bot]@users.noreply.github.com>"
        )
        XCTAssertEqual(CommitCredit.trailer, GitHubAppIdentity.coAuthorTrailer)
    }

    func testAppendingHooksPathKeepsExistingGitConfig() {
        let base = GitHubCredentials.environment(token: "secret-token")
        let env = CommitCredit.appendingHooksPath("/tmp/ensembyte-hooks", to: base)
        XCTAssertEqual(env["GH_TOKEN"], "secret-token")
        XCTAssertEqual(env["GIT_CONFIG_COUNT"], "3")
        XCTAssertEqual(env["GIT_CONFIG_KEY_0"], "credential.https://github.com.helper")
        XCTAssertEqual(env["GIT_CONFIG_VALUE_0"], "")
        XCTAssertEqual(env["GIT_CONFIG_KEY_1"], "credential.https://github.com.helper")
        XCTAssertTrue(env["GIT_CONFIG_VALUE_1"]?.contains("password=$GH_TOKEN") == true)
        XCTAssertEqual(env["GIT_CONFIG_KEY_2"], "core.hooksPath")
        XCTAssertEqual(env["GIT_CONFIG_VALUE_2"], "/tmp/ensembyte-hooks")
    }

    func testAppendingHooksPathPreservesAnEarlierEntryAndIsIdempotent() {
        let base = [
            "GIT_CONFIG_COUNT": "1",
            "GIT_CONFIG_KEY_0": "user.name",
            "GIT_CONFIG_VALUE_0": "Ada",
        ]
        let once = CommitCredit.appendingHooksPath("/hooks", to: base)
        XCTAssertEqual(once["GIT_CONFIG_COUNT"], "2")
        XCTAssertEqual(once["GIT_CONFIG_KEY_0"], "user.name")
        XCTAssertEqual(once["GIT_CONFIG_VALUE_0"], "Ada")
        XCTAssertEqual(once["GIT_CONFIG_KEY_1"], "core.hooksPath")
        XCTAssertEqual(CommitCredit.appendingHooksPath("/hooks", to: once), once)

        let moved = CommitCredit.appendingHooksPath("/other", to: once)
        XCTAssertEqual(moved["GIT_CONFIG_COUNT"], "2")
        XCTAssertEqual(moved["GIT_CONFIG_VALUE_1"], "/other")
        XCTAssertEqual(moved["GIT_CONFIG_KEY_0"], "user.name")
    }

    func testBrokenGitConfigCountIsLeftAlone() {
        let broken = ["GIT_CONFIG_COUNT": "nope", "GIT_CONFIG_KEY_0": "user.name"]
        XCTAssertEqual(CommitCredit.appendingHooksPath("/hooks", to: broken), broken)
    }

    func testInstallFailureLeavesTheEnvironmentAlone() {
        let original = ["GIT_CONFIG_COUNT": "0"]
        let blocked = URL(fileURLWithPath: "/dev/null/ensembyte-hooks")
        XCTAssertEqual(CommitCredit.applying(to: original, hooksDirectory: blocked), original)
    }

    /// Disconnect stores the human overlay, which is the credential map alone.
    /// The bot overlay adds the four author variables on top of that map, and
    /// the co-author hook is applied afterwards, the way `LoginEnvironment.current` does.
    func testDisconnectDropsTheBotAuthorAndTheHookStillCreditsTheCommit() throws {
        let botCredentials = GitHubCredentials.environment(token: "bot-token")
        let bot = GitHubCredentials.botOverlay(token: "bot-token")
        XCTAssertEqual(bot, botCredentials.merging(GitHubCredentials.botAuthorIdentity()) { _, new in new })
        XCTAssertEqual(GitHubCredentials.botAuthorIdentity(), [
            "GIT_AUTHOR_NAME": GitHubAppIdentity.botLogin,
            "GIT_AUTHOR_EMAIL": GitHubAppIdentity.botNoreply,
            "GIT_COMMITTER_NAME": GitHubAppIdentity.botLogin,
            "GIT_COMMITTER_EMAIL": GitHubAppIdentity.botNoreply,
        ])
        XCTAssertEqual(Set(bot.keys).subtracting(botCredentials.keys), Set(GitHubCredentials.botAuthorIdentity().keys))

        let human = GitHubCredentials.humanOverlay(token: "human-token")
        XCTAssertEqual(human, GitHubCredentials.environment(token: "human-token"))
        XCTAssertNil(human["GIT_AUTHOR_NAME"])
        XCTAssertNil(human["GIT_AUTHOR_EMAIL"])
        XCTAssertNil(human["GIT_COMMITTER_NAME"])
        XCTAssertNil(human["GIT_COMMITTER_EMAIL"])

        let emptyHuman = GitHubCredentials.humanOverlay(token: "")
        XCTAssertEqual(emptyHuman["GH_TOKEN"], "")
        XCTAssertNil(emptyHuman["GIT_AUTHOR_NAME"])
        XCTAssertEqual(GitHubCredentials.botOverlay(token: "")["GIT_AUTHOR_EMAIL"], GitHubAppIdentity.botNoreply)

        let credited = CommitCredit.applying(to: human, hooksDirectory: hooks)
        XCTAssertEqual(credited["GH_TOKEN"], "human-token")
        XCTAssertEqual(credited["GIT_CONFIG_COUNT"], "3")
        XCTAssertEqual(credited["GIT_CONFIG_KEY_2"], "core.hooksPath")
        XCTAssertEqual(credited["GIT_CONFIG_VALUE_2"], hooks.path)
        XCTAssertNil(credited["GIT_AUTHOR_NAME"])

        let initResult = try git(["init", "-q"], environment: [:])
        XCTAssertEqual(initResult.status, 0, initResult.stderr)
        let commit = try git(
            ["commit", "-q", "--allow-empty", "-m", "From the app"],
            environment: credited,
            author: ("Soumya", "soumya@example.com")
        )
        XCTAssertEqual(commit.status, 0, commit.stderr)
        let message = try commitMessage()
        XCTAssertTrue(message.contains(CommitCredit.trailer), message)
        let author = try git(["log", "-1", "--format=%an <%ae>"], environment: [:])
        XCTAssertEqual(author.stdout.trimmingCharacters(in: .whitespacesAndNewlines), "Soumya <soumya@example.com>")
    }

    func testAgentCommitsCreditTheBotAndKeepTheRepositoryHook() throws {
        let initResult = try git(["init", "-q"], environment: [:])
        XCTAssertEqual(initResult.status, 0, initResult.stderr)

        let hook = repo.appendingPathComponent(".git/hooks/commit-msg")
        let hookSource = """
        #!/bin/sh
        cp "$1" "$(git rev-parse --git-dir)/hook-saw"
        grep -q reject "$1" && exit 1
        echo ran >> "$(git rev-parse --git-dir)/hook-ran"
        """
        try hookSource.write(to: hook, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: hook.path)

        let credited = CommitCredit.applying(to: [:], hooksDirectory: hooks)
        XCTAssertEqual(credited["GIT_CONFIG_KEY_0"], "core.hooksPath")
        XCTAssertEqual(credited["GIT_CONFIG_VALUE_0"], hooks.path)
        let commitMsg = hooks.appendingPathComponent("commit-msg")
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: commitMsg.path))
        for name in CommitCredit.hookNames {
            XCTAssertTrue(FileManager.default.isExecutableFile(atPath: hooks.appendingPathComponent(name).path), name)
        }

        let first = try git(["commit", "-q", "--allow-empty", "-m", "Add a thing"], environment: credited)
        XCTAssertEqual(first.status, 0, first.stderr)
        let message = try commitMessage()
        XCTAssertTrue(message.contains(CommitCredit.trailer), message)
        XCTAssertEqual(message.components(separatedBy: CommitCredit.trailer).count - 1, 1)

        let saw = try String(contentsOf: repo.appendingPathComponent(".git/hook-saw"), encoding: .utf8)
        XCTAssertFalse(saw.contains("ensembyte"), "the repository hook must see the message before the trailer")
        XCTAssertTrue(FileManager.default.fileExists(atPath: repo.appendingPathComponent(".git/hook-ran").path))

        let amended = try git(["commit", "-q", "--amend", "--allow-empty", "--no-edit"], environment: credited)
        XCTAssertEqual(amended.status, 0, amended.stderr)
        let amendedMessage = try commitMessage()
        XCTAssertEqual(amendedMessage.components(separatedBy: CommitCredit.trailer).count - 1, 1, amendedMessage)

        let rejected = try git(["commit", "-q", "--allow-empty", "-m", "reject me"], environment: credited)
        XCTAssertNotEqual(rejected.status, 0)

        let byHand = try git(["commit", "-q", "--allow-empty", "-m", "By hand"], environment: [:])
        XCTAssertEqual(byHand.status, 0, byHand.stderr)
        let handMessage = try commitMessage()
        XCTAssertFalse(handMessage.contains("ensembyte"), handMessage)
    }

    private struct GitOutput {
        var status: Int32
        var stdout: String
        var stderr: String
    }

    private func git(
        _ arguments: [String],
        environment: [String: String],
        author: (name: String, email: String)? = ("T", "t@example.com")
    ) throws -> GitOutput {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = repo
        var env = environment
        if let author {
            env["GIT_AUTHOR_NAME"] = author.name
            env["GIT_AUTHOR_EMAIL"] = author.email
            env["GIT_COMMITTER_NAME"] = author.name
            env["GIT_COMMITTER_EMAIL"] = author.email
        }
        env["HOME"] = repo.path
        env["GIT_CONFIG_NOSYSTEM"] = "1"
        env["PATH"] = "/usr/bin:/bin:/usr/local/bin:/opt/homebrew/bin"
        process.environment = env
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()
        let out = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let err = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return GitOutput(status: process.terminationStatus, stdout: out, stderr: err)
    }

    private func commitMessage() throws -> String {
        let result = try git(["log", "-1", "--format=%B"], environment: [:])
        XCTAssertEqual(result.status, 0, result.stderr)
        return result.stdout
    }
}
