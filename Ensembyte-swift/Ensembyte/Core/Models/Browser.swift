import Foundation

/// What the address bar and chat links refused, in the words the UI shows.
enum BrowserAddressError: Error, Equatable, Sendable {
    case empty
    case invalidCharacters
    case invalidAddress
    case unsupportedScheme
    case embeddedCredentials
    case invalidLinkAddress
    case invalidEscape
    case nonExplicitLink

    var message: String {
        switch self {
        case .empty: "Enter a website or localhost address."
        case .invalidCharacters: "This address contains invalid characters."
        case .invalidAddress: "Enter a valid website or localhost address."
        case .unsupportedScheme: "Only http and https addresses are supported."
        case .embeddedCredentials: "Use an address without an embedded username or password."
        case .invalidLinkAddress: "This link contains an invalid address."
        case .invalidEscape: "This link contains an invalid escape."
        case .nonExplicitLink: "Only explicit http and https links are supported."
        }
    }
}

/// The URL policy every browser navigation and chat link is checked against:
/// only http/https web content, never a scheme that leaves the page.
enum BrowserURLPolicy {
    /// A bare host:port looks like a URI scheme to a URL parser. Whether the input's
    /// single colon is such a suffix: the part before the last colon in the authority
    /// has a non-empty, all-digit port.
    private static func explicitHostPortSuffix(_ text: String) -> Bool {
        // The authority: up to the first `/`, `?` or `#`.
        let separators: Set<Character> = ["/", "?", "#"]
        let end = text.firstIndex(where: separators.contains) ?? text.endIndex
        let authority = text[..<end]
        guard let lastColon = authority.lastIndex(of: ":") else { return false }
        let port = authority[authority.index(after: lastColon)...]
        return !port.isEmpty && port.allSatisfy { $0.isASCII && $0.isNumber }
    }

    /// Trims the input and settles it into the URL it names: an explicit input keeps
    /// its scheme, a bare host or localhost address gets https — or http, loopback only.
    static func normalizeAddress(_ input: String) -> Result<String, BrowserAddressError> {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return .failure(.empty) }
        if text.rangeOfCharacter(from: .controlCharacters) != nil {
            return .failure(.invalidCharacters)
        }
        // A space in a host is no address at all; the Rust crate the policy was
        // ported from fails on them, and Swift's URL is too lenient to see it.
        if text.contains(where: { $0.isWhitespace }) {
            return .failure(.invalidAddress)
        }
        let explicit = text.contains("://") || (text.contains(":") && !explicitHostPortSuffix(text) && !text.hasPrefix("["))
        let candidate = explicit ? text : "https://" + text
        guard let parsed = URL(string: candidate) else {
            return .failure(.invalidAddress)
        }
        guard let scheme = parsed.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return .failure(.unsupportedScheme)
        }
        guard parsed.host != nil else {
            // No host at all (a bare "https://, say): the reference calls it an
            // unsupported web address, not a bad one.
            return .failure(.unsupportedScheme)
        }
        if !(parsed.user ?? "").isEmpty || parsed.password != nil {
            return .failure(.embeddedCredentials)
        }
        // A bare loopback address is served over http, the way a local dev server
        // expects; an explicit https one keeps what the user wrote.
        let finalScheme = (!explicit && isLoopbackURL(parsed)) ? "http" : scheme
        return .success(canonical(parsed, scheme: finalScheme))
    }

    /// The URL written the way the policy's own reference writes it: the scheme, the
    /// host (lowercased, in brackets when it is an IPv6 one), the port, the path (a
    /// bare host carries a slash), then the query and the fragment.
    private static func canonical(_ url: URL, scheme: String) -> String {
        var out = scheme + "://"
        let host = (url.host ?? "").lowercased()
        if host.contains(":") {
            out += "[" + host + "]"
        } else {
            out += host
        }
        if let port = url.port {
            out += ":\(port)"
        }
        let path = url.path
        out += path.isEmpty ? "/" : path
        if let query = url.query {
            out += "?" + query
        }
        if let fragment = url.fragment {
            out += "#" + fragment
        }
        return out
    }

    /// Chat links require an explicit web authority; never infer a scheme or
    /// silently strip controls, credentials, malformed escapes or backslashes.
    static func transcriptAddress(_ input: String) -> Result<String, BrowserAddressError> {
        let lower = input.lowercased()
        let authority: String
        if lower.hasPrefix("https://") {
            authority = String(lower.dropFirst("https://".count))
        } else if lower.hasPrefix("http://") {
            authority = String(lower.dropFirst("http://".count))
        } else {
            return .failure(.nonExplicitLink)
        }
        // Any control character or whitespace, a backslash, an empty authority, or an
        // authority that actually starts the path/query/fragment — all make it no link.
        if input.rangeOfCharacter(from: .controlCharacters.union(.whitespacesAndNewlines)) != nil
            || input.contains("\\")
            || authority.isEmpty
            || authority.hasPrefix("/") || authority.hasPrefix("?") || authority.hasPrefix("#") {
            return .failure(.invalidLinkAddress)
        }
        // Every `%` must be the start of a two-digit hex escape.
        let chars = Array(input)
        for (i, char) in chars.enumerated() where char == "%" {
            let hex = chars.dropFirst(i + 1).prefix(2)
            guard hex.count == 2, hex.allSatisfy(\.isHexDigit) else {
                return .failure(.invalidEscape)
            }
        }
        return normalizeAddress(input)
    }

    /// Top-frame navigations: web content only, never a scheme that leaves the page.
    static func allowedNavigation(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return false }
        guard url.host != nil, (url.user ?? "").isEmpty, url.password == nil else { return false }
        return true
    }

    /// Subframe navigations: web content, including a frame's own documents
    /// (`about:blank`, `about:srcdoc`, `data:`, `blob:`) — never a scheme that
    /// leaves the page (`file:`, `javascript:`, app links).
    static func allowedFrameNavigation(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        if allowedNavigation(url) { return true }
        return scheme == "about" || scheme == "data" || scheme == "blob"
    }

    /// `localhost`, `*.localhost` and the loopback address ranges.
    static func isLoopbackHost(_ host: String) -> Bool {
        let lower = host.lowercased()
        if lower == "localhost" || lower.hasSuffix(".localhost") { return true }
        if lower == "::1" { return true }
        // 127.0.0.0/8: a dotted host with 127 in its first octet.
        if lower.first == "1" {
            let octets = lower.split(separator: ".").map(String.init)
            if octets.count == 4, octets[0] == "127" { return true }
        }
        return false
    }

    static func isLoopbackURL(_ url: URL) -> Bool {
        guard let host = url.host else { return false }
        return isLoopbackHost(host)
    }
}

/// One tab's face: what it shows, and whether the chrome's buttons work.
struct BrowserPageState: Equatable, Sendable {
    var url: String?
    var title: String
    var loading: Bool
    var canBack: Bool
    var canForward: Bool
    var error: String?

    init(url: String? = nil, title: String = "", loading: Bool = false, canBack: Bool = false, canForward: Bool = false, error: String? = nil) {
        self.url = url
        self.title = title
        self.loading = loading
        self.canBack = canBack
        self.canForward = canForward
        self.error = error
    }

    /// The tab's name: the page's title, else its host, else a placeholder.
    func label() -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        if let url, let parsed = URL(string: url), let host = parsed.host { return host }
        return "Browser"
    }
}

/// Where in-app links go. The UI layer reaches this without importing App: the
/// app wires the handler to its coordinator at launch.
@MainActor
final class BrowserLinkRouter {
    static let shared = BrowserLinkRouter()

    /// Opens the URL in the app's browser. Set by the app; nil in UI-layer previews.
    var handler: ((URL) -> Bool)?

    /// Hands the URL to the handler when there is one: whether it was taken up.
    @discardableResult
    func handle(_ url: URL) -> Bool {
        handler?(url) ?? false
    }
}
