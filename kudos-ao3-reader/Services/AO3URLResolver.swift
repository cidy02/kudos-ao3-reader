import Foundation

/// Single source of truth for turning an AO3-scraped `href`/`src` attribute into a
/// normalized absolute `URL`. Consolidates ~10 near-duplicate implementations that
/// grew independently across `AO3Client.swift`, `AO3Client+Preferences.swift`,
/// `AO3Client+Authors.swift`, `AO3Client+Inbox.swift`, and `AO3WriteActions.swift`.
enum AO3URLResolver {
    /// Resolves a relative or absolute AO3 href/src to a normalized absolute `URL`
    /// against `https://archiveofourown.org`.
    ///
    /// - `nil`, empty, or whitespace-only input returns `nil`.
    /// - A relative path resolves correctly whether or not it has a leading `/`
    ///   ("works/1" and "/works/1" both become ".../works/1") and whether or not
    ///   it carries a query string or fragment ("/works/1?page=2#chapter" round-trips
    ///   intact). This uses `URL(string:relativeTo:)` RFC-3986 resolution rather
    ///   than naive string concatenation, so it never produces a malformed
    ///   "https://archiveofourown.orgworks/1" or double-slash
    ///   "https://archiveofourown.org//foo" result.
    /// - An already-absolute `https` AO3 href is parsed and returned as-is
    ///   (subject to the host check below). Cleartext `http://` AO3 URLs are
    ///   rejected (Android `AO3BrowseUrls.isAo3Url` requires `scheme == "https"`).
    /// - A protocol-relative href (`//host/path`) is resolved per RFC 3986 against
    ///   the https base, which means it can name a *different* host than
    ///   archiveofourown.org — that's exactly what the `allowExternalHost` check
    ///   below guards.
    /// - Any non-`http`/`https` scheme (`javascript:`, `mailto:`, `tel:`, …) is
    ///   always rejected, regardless of `allowExternalHost`.
    /// - By default (`allowExternalHost: false`) the resolved URL must be
    ///   `https` and its host must equal `archiveofourown.org` or be a subdomain
    ///   of it, or this returns `nil` — this is what stops a protocol-relative or
    ///   spoofed-absolute href from resolving to a foreign host and being treated
    ///   as a legitimate AO3 destination.
    /// - Pass `allowExternalHost: true` only at a call site that deliberately
    ///   allows off-site links, such as rendering an author's rich-text bio, where
    ///   a link to the author's own external website is expected and safe. Off-site
    ///   links may still be `http` or `https`; AO3 destinations remain https-only.
    static func resolve(_ href: String?, allowExternalHost: Bool = false) -> URL? {
        guard let trimmed = href?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty,
              let base = URL(string: "https://archiveofourown.org"),
              let url = URL(string: trimmed, relativeTo: base)?.absoluteURL,
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme)
        else { return nil }
        if allowExternalHost {
            // Off-site bios may legitimately link to http external sites; AO3
            // itself still requires https so a cleartext AO3 absolute URL is not
            // smuggled through this flag.
            if let host = url.host?.lowercased(),
               host == "archiveofourown.org" || host.hasSuffix(".archiveofourown.org") {
                return scheme == "https" ? url : nil
            }
            return url
        }
        guard scheme == "https", let host = url.host?.lowercased() else { return nil }
        return (host == "archiveofourown.org" || host.hasSuffix(".archiveofourown.org")) ? url : nil
    }
}
