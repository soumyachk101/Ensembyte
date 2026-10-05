import AppKit
import Foundation
import LocalAuthentication
import Security
import UserNotifications

/// A release version as GitHub tags it: `v1.2.3` or `1.2`. Anything with a prerelease suffix
/// (`-nightly.…`, `-beta.1`) is not a version the app offers, so it does not parse.
struct AppVersion: Comparable, Hashable, CustomStringConvertible, Sendable {
    let components: [Int]

    init?(_ raw: String) {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("v") || text.hasPrefix("V") { text.removeFirst() }
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...3).contains(parts.count) else { return nil }
        var numbers: [Int] = []
        for part in parts {
            guard !part.isEmpty, part.allSatisfy(\.isNumber), let number = Int(part) else { return nil }
            numbers.append(number)
        }
        while numbers.count < 3 { numbers.append(0) }
        components = numbers
    }

    var description: String {
        components.map(String.init).joined(separator: ".")
    }

    /// The tag without its leading v: the version as the release calls itself.
    static func text(ofTag tag: String) -> String {
        var text = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("v") || text.hasPrefix("V") { text.removeFirst() }
        return text
    }

    static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        lhs.components.lexicographicallyPrecedes(rhs.components)
    }
}

/// A newer release on GitHub: what the About page describes and the installer downloads.
struct AvailableUpdate: Codable, Equatable, Sendable {
    var version: String
    var tag: String
    var downloadURL: URL
    var assetId: Int?
    var size: Int64?
    /// The release description, Markdown as written on GitHub.
    var notes: String
    var releasedAt: Date?
    /// The release page, for reading the notes in the browser.
    var pageURL: URL

    var assetAPIURL: URL? {
        guard let assetId else { return nil }
        return URL(string: "https://api.github.com/repos/\(UpdateChecker.repoOwner)/\(UpdateChecker.repoName)/releases/assets/\(assetId)")
    }

    /// Ensures the link points to GitHub, fixing any legacy cached GitLab links.
    var cleanPageURL: URL {
        if pageURL.absoluteString.contains("gitlab") {
            return UpdateChecker.releasesURL.appending(path: "tag/\(tag)")
        }
        return pageURL
    }
}



/// Checks the app's GitLab releases for a newer version and remembers what it found.
///
/// A check reads the public releases API, keeps the newest stable version that ships a disk
/// image, and compares it with the running build. The result is persisted, so the About page
/// shows a known update the moment it opens, and `updateAvailable` is recomputed from the
/// running version, so an update that was installed stops being one. Checks run on launch,
/// every six hours while the app runs, when it comes back to the front after a long
/// while, and whenever the About page opens or asks.
@MainActor
@Observable
final class UpdateChecker {
    static let shared = UpdateChecker()

    /// The project on GitHub.
    nonisolated static let repoOwner = "soumyachk101"
    nonisolated static let repoName = "Ensembyte"
    nonisolated static let projectURL = URL(string: "https://github.com/soumyachk101/Ensembyte")!
    nonisolated static let releasesURL = URL(string: "https://github.com/soumyachk101/Ensembyte/releases")!
    nonisolated static let apiURL = URL(string: "https://api.github.com/repos/soumyachk101/Ensembyte/releases?per_page=20")!
    nonisolated static let latestAPIURL = URL(string: "https://api.github.com/repos/soumyachk101/Ensembyte/releases/latest")!

    /// How often the background check runs, and how stale a check may be before the app
    /// coming to the front runs another.
    private static let checkInterval: TimeInterval = 6 * 60 * 60
    private static let launchDelay: TimeInterval = 8

    private enum Keys {
        static let update = "updateChecker_release"
        static let lastChecked = "updateChecker_lastChecked"
        static let notifiedVersion = "updateChecker_notifiedVersion"
    }

    let currentVersion = AppInfo.version

    private(set) var update: AvailableUpdate?
    private(set) var isChecking = false
    private(set) var lastCheckedAt: Date?
    /// Why the last check found nothing, for the About page after a manual check.
    private(set) var lastError: String?

    /// Only a version newer than the running one is an update; anything else the last check
    /// found is kept for the notes but reads as up to date.
    var updateAvailable: Bool {
        guard let update, let latest = AppVersion(update.version), let current = AppVersion(currentVersion) else { return false }
        return latest > current
    }

    var latestVersion: String? { updateAvailable ? update?.version : nil }

    @ObservationIgnored private var backgroundTask: Task<Void, Never>?
    @ObservationIgnored private var activationObserver: NSObjectProtocol?
    @ObservationIgnored private var previewVersion: String?
    @ObservationIgnored private let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 30
        return URLSession(configuration: configuration)
    }()

    private init() {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: Keys.update),
           let saved = try? JSONDecoder().decode(AvailableUpdate.self, from: data) {
            if saved.pageURL.absoluteString.contains("gitlab") || saved.downloadURL.absoluteString.contains("gitlab") {
                defaults.removeObject(forKey: Keys.update)
            } else {
                update = saved
            }
        }
        lastCheckedAt = defaults.object(forKey: Keys.lastChecked) as? Date
        // `--preview-update 9.9.9` shows the update story without a newer release: the latest
        // real release is offered under that version. Pressing Update & restart then installs
        // that release for real, which only passes verification when its version is the one shown.
        let arguments = CommandLine.arguments
        if let index = arguments.firstIndex(of: "--preview-update"), index + 1 < arguments.count {
            previewVersion = arguments[index + 1]
        }
    }

    // MARK: - Schedule

    /// The launch check, the six-hourly one after it, and a catch-up when the app comes to
    /// the front after a long sleep.
    func startBackgroundChecks() {
        guard backgroundTask == nil, !WebsiteCaptures.isEnabled else { return }
        backgroundTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.launchDelay))
            while !Task.isCancelled {
                await self?.check(background: true)
                try? await Task.sleep(for: .seconds(Self.checkInterval))
            }
        }
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let stale = self.lastCheckedAt.map { Date.now.timeIntervalSince($0) > Self.checkInterval } ?? true
                if stale { await self.check(background: true) }
            }
        }
    }

    // MARK: - Checking

    /// Reads the releases and updates the state. Returns whether an update is available
    /// afterwards. A background check also posts the one notification a new version gets.
    @discardableResult
    func check(background: Bool = false) async -> Bool {
        guard !isChecking else { return updateAvailable }
        isChecking = true
        defer { isChecking = false }
        do {
            let releases = try await fetchReleases()
            guard let newest = Self.newestRelease(in: releases) else {
                throw UpdateError.noRelease
            }
            var found = newest
            if let previewVersion {
                found.version = previewVersion
            }
            if found.size == nil {
                found.size = await downloadSize(of: found.downloadURL)
            }
            update = found
            lastError = nil
            lastCheckedAt = .now
            persist()
            if background, updateAvailable {
                notifyOnce(about: found)
            }
        } catch {
            lastError = (error as? UpdateError)?.errorDescription ?? "Couldn't reach GitHub."
            lastCheckedAt = .now
            UserDefaults.standard.set(lastCheckedAt, forKey: Keys.lastChecked)
        }
        return updateAvailable
    }

    private func fetchReleases() async throws -> [GitHubRelease] {
        var request = URLRequest(url: Self.apiURL)
        request.setValue("Ensembyte/\(AppInfo.version)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        if let token = GitHubAuth.resolveToken(), !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            if status == 404 && GitHubAuth.resolveToken() == nil {
                throw UpdateError.needsToken
            }
            throw UpdateError.badResponse(status)
        }
        var releases = try JSONDecoder().decode([GitHubRelease].self, from: data)

        // GitHub's releases list endpoint can have cached / empty assets for newly published releases.
        // Also fetch the single latest release endpoint to ensure assets are present for the latest version.
        if let latest = try? await fetchLatestRelease() {
            if let index = releases.firstIndex(where: { $0.tagName == latest.tagName }) {
                if releases[index].assets.isEmpty && !latest.assets.isEmpty {
                    releases[index] = latest
                }
            } else if !latest.prerelease && !latest.draft {
                releases.insert(latest, at: 0)
            }
        }

        return releases
    }

    private func fetchLatestRelease() async throws -> GitHubRelease {
        var request = URLRequest(url: Self.latestAPIURL)
        request.setValue("Ensembyte/\(AppInfo.version)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        if let token = GitHubAuth.resolveToken(), !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw UpdateError.badResponse(status)
        }
        return try JSONDecoder().decode(GitHubRelease.self, from: data)
    }

    /// The newest stable release that ships a disk image. Prereleases and drafts
    /// never count, whatever their date.
    static func newestRelease(in releases: [GitHubRelease]) -> AvailableUpdate? {
        var best: (AppVersion, AvailableUpdate)?
        for release in releases {
            guard !release.prerelease, !release.draft, let version = AppVersion(release.tagName) else { continue }
            if let publishedAt = release.publishedAt, publishedAt > .now { continue }
            let asset = release.assets.first(where: { $0.isDiskImage })
            let fallbackDownloadURL = releasesURL.appending(path: "download/\(release.tagName)/Ensembyte-swift.dmg")
            let downloadURL = asset.flatMap({ URL(string: $0.browserDownloadURL) }) ?? fallbackDownloadURL
            let pageURL = release.htmlURL.flatMap(URL.init(string:)) ?? releasesURL.appending(path: "tag/\(release.tagName)")
            let candidate = AvailableUpdate(
                version: AppVersion.text(ofTag: release.tagName),
                tag: release.tagName,
                downloadURL: downloadURL,
                assetId: asset?.id,
                size: asset?.size,
                notes: release.body ?? "",
                releasedAt: release.publishedAt,
                pageURL: pageURL
            )
            if let current = best, current.0 >= version { continue }
            best = (version, candidate)
        }
        return best?.1
    }

    /// The image's size from a HEAD request, for the About page. Nothing depends on it.
    private func downloadSize(of url: URL) async -> Int64? {
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.setValue("Ensembyte/\(AppInfo.version)", forHTTPHeaderField: "User-Agent")
        if let token = GitHubAuth.resolveToken(), !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        guard let (_, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
              http.expectedContentLength > 0 else { return nil }
        return http.expectedContentLength
    }

    private func persist() {
        let defaults = UserDefaults.standard
        if let update, let data = try? JSONEncoder().encode(update) {
            defaults.set(data, forKey: Keys.update)
        } else {
            defaults.removeObject(forKey: Keys.update)
        }
        defaults.set(lastCheckedAt, forKey: Keys.lastChecked)
    }

    // MARK: - Notification

    /// One banner per version, the first time a background check finds it. Tapping it opens
    /// Settings on About, where the update installs.
    private func notifyOnce(about update: AvailableUpdate) {
        let defaults = UserDefaults.standard
        guard defaults.string(forKey: Keys.notifiedVersion) != update.version else { return }
        defaults.set(update.version, forKey: Keys.notifiedVersion)
        let content = UNMutableNotificationContent()
        content.title = "Ensembyte \(update.version) is available"
        content.body = "Open Settings › About to update and restart."
        content.userInfo = ["update": update.version]
        let request = UNNotificationRequest(identifier: "update-\(update.version)", content: content, trigger: nil)
        Task {
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()
            if settings.authorizationStatus == .notDetermined {
                _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
            }
            try? await center.add(request)
        }
    }
}

enum UpdateError: LocalizedError {
    case noRelease
    case needsToken
    case badResponse(Int)

    var errorDescription: String? {
        switch self {
        case .noRelease: "No release with a disk image was found."
        case .needsToken: "GitHub returned 404. For private repos, set a GitHub token in Settings."
        case .badResponse(let status): "GitHub answered with HTTP \(status)."
        }
    }
}

/// The parts of a GitHub release the checker reads.
struct GitHubRelease: Decodable, Sendable {
    struct Asset: Decodable, Sendable {
        var id: Int
        var name: String
        var browserDownloadURL: String
        var size: Int64?

        var isDiskImage: Bool {
            let path = browserDownloadURL.lowercased()
            return path.hasSuffix(".dmg") || name.lowercased().hasSuffix(".dmg")
        }

        private enum CodingKeys: String, CodingKey {
            case id, name, size
            case browserDownloadURL = "browser_download_url"
        }
    }

    var tagName: String
    var name: String?
    var body: String?
    var publishedAt: Date?
    var prerelease: Bool
    var draft: Bool
    var htmlURL: String?
    var assets: [Asset]

    private enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name, body, assets, prerelease, draft
        case publishedAt = "published_at"
        case htmlURL = "html_url"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tagName = try container.decode(String.self, forKey: .tagName)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        body = try container.decodeIfPresent(String.self, forKey: .body)
        publishedAt = try container.decodeIfPresent(String.self, forKey: .publishedAt).flatMap(Self.parseDate)
        prerelease = try container.decodeIfPresent(Bool.self, forKey: .prerelease) ?? false
        draft = try container.decodeIfPresent(Bool.self, forKey: .draft) ?? false
        htmlURL = try container.decodeIfPresent(String.self, forKey: .htmlURL)
        assets = try container.decodeIfPresent([Asset].self, forKey: .assets) ?? []
    }

    /// GitHub writes `2026-09-13T18:28:42Z` or `2026-09-13T18:28:42.057Z`.
    nonisolated static func parseDate(_ text: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: text) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: text)
    }
}
