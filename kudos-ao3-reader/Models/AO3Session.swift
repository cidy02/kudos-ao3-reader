import Foundation

/// A serializable representation of an HTTP cookie. `HTTPCookie` itself is not
/// Codable, so AO3 sessions use this value type for Keychain persistence and for
/// building authenticated requests outside WebKit.
struct AO3StoredCookie: Codable, Hashable {
    let name: String
    let value: String
    let domain: String
    let path: String
    let expiresDate: Date?
    let isSecure: Bool
    let isHTTPOnly: Bool
    /// Raw `HTTPCookieStringPolicy` (`"lax"` / `"strict"`). Optional so
    /// Keychain blobs written before this field still decode (synthesized
    /// `Decodable` treats a missing optional key as `nil`).
    let sameSitePolicy: String?

    init(_ cookie: HTTPCookie) {
        name = cookie.name
        value = cookie.value
        domain = cookie.domain
        path = cookie.path
        expiresDate = cookie.expiresDate
        isSecure = cookie.isSecure
        let httpOnlyKey = HTTPCookiePropertyKey(rawValue: "HttpOnly")
        isHTTPOnly = cookie.properties?[httpOnlyKey] != nil
        // Public Foundation API (`HTTPCookie.sameSitePolicy` /
        // `HTTPCookiePropertyKey.sameSitePolicy`, iOS 13+). This deployment
        // target is 26.5+, so no availability gate. Unlike HttpOnly, this is
        // not a private property key. Foundation only recognises Lax and
        // Strict (`NSHTTPCookieSameSiteLax` / `NSHTTPCookieSameSiteStrict`);
        // any other value — including SameSite=None — is ignored by
        // `HTTPCookie` and will not survive capture (see NSHTTPCookie.h).
        sameSitePolicy = cookie.sameSitePolicy?.rawValue
    }

    init(
        name: String,
        value: String,
        domain: String = ".archiveofourown.org",
        path: String = "/",
        expiresDate: Date? = nil,
        isSecure: Bool = true,
        isHTTPOnly: Bool = true,
        sameSitePolicy: String? = nil
    ) {
        self.name = name
        self.value = value
        self.domain = domain
        self.path = path
        self.expiresDate = expiresDate
        self.isSecure = isSecure
        self.isHTTPOnly = isHTTPOnly
        self.sameSitePolicy = sameSitePolicy
    }

    var isExpired: Bool {
        if let expiresDate { expiresDate <= Date() } else { false }
    }

    /// `HTTPCookie` wants its `.secure` flag as a "TRUE"/"FALSE" string, and there is
    /// no public property key for HttpOnly — Foundation only recognises the literal
    /// "HttpOnly" key. Both are long-standing Foundation contracts; documented here
    /// because the string/private-key reliance is otherwise surprising.
    ///
    /// SameSite is the public counterpart: `HTTPCookiePropertyKey.sameSitePolicy`
    /// takes an `HTTPCookieStringPolicy` (`"lax"` / `"strict"`). Setting it is
    /// what makes `httpCookie.sameSitePolicy` survive a Keychain restore; omitting
    /// it is how a pre-fix blob silently dropped Lax.
    var httpCookie: HTTPCookie? {
        var properties: [HTTPCookiePropertyKey: Any] = [
            .name: name,
            .value: value,
            .domain: domain,
            .path: path,
            .secure: isSecure ? "TRUE" : "FALSE"
        ]
        if let expiresDate { properties[.expires] = expiresDate }
        if let sameSitePolicy { properties[.sameSitePolicy] = HTTPCookieStringPolicy(rawValue: sameSitePolicy) }
        if isHTTPOnly {
            properties[HTTPCookiePropertyKey(rawValue: "HttpOnly")] = "TRUE"
        }
        if let sameSitePolicy {
            properties[.sameSitePolicy] = sameSitePolicy
        }
        return HTTPCookie(properties: properties)
    }

    func applies(to url: URL) -> Bool {
        guard !isExpired, let host = url.host()?.lowercased() else { return false }
        let normalizedDomain = domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        let hostMatches = host == normalizedDomain || host.hasSuffix(".\(normalizedDomain)")
        let requestPath = url.path.isEmpty ? "/" : url.path
        let pathMatches = requestPath == path
            || (requestPath.hasPrefix(path)
                && (path.hasSuffix("/") || requestPath.dropFirst(path.count).first == "/"))
        let schemeMatches = !isSecure || url.scheme?.lowercased() == "https"
        return hostMatches && pathMatches && schemeMatches
    }

    static func isAO3Domain(_ domain: String) -> Bool {
        let normalized = domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return normalized == "archiveofourown.org"
            || normalized.hasSuffix(".archiveofourown.org")
    }
}

/// The authenticated AO3 session persisted by the app. It intentionally contains
/// cookies and the resolved account name only—never the user's password.
struct AO3Session: Codable, Equatable {
    let username: String
    let cookies: [AO3StoredCookie]
    let savedAt: Date

    init(username: String, cookies: [AO3StoredCookie], savedAt: Date = Date()) {
        self.username = username
        self.cookies = cookies
        self.savedAt = savedAt
    }

    var validCookies: [AO3StoredCookie] {
        cookies.filter { !$0.isExpired && AO3StoredCookie.isAO3Domain($0.domain) }
    }

    var hasSessionCookie: Bool {
        validCookies.contains { $0.name == AO3RequestDefaults.sessionCookieName }
    }

    func cookieHeader(for url: URL) -> String? {
        let pairs = validCookies
            .filter { $0.applies(to: url) }
            .sorted { $0.path.count > $1.path.count }
            .map { "\($0.name)=\($0.value)" }
        return pairs.isEmpty ? nil : pairs.joined(separator: "; ")
    }
}
