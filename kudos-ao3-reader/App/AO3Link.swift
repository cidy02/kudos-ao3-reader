import Foundation

/// AO3's public GET routes. Shared with future multi-link import (T-531).
/// Route shapes: otwcode/otwarchive config/routes.rb @ 41d3878b (cross-checked
/// against master 2026-11-16)
/// (works 369–415, series 434–442, collections 451–463, tags 114–125,
/// users/pseuds 255–312).
nonisolated struct AO3Link: Equatable {
    enum Kind: Equatable {
        case work(id: Int, chapterID: Int?)
        case series(Int)
        case user(username: String, pseud: String?)
        case tag(String)
        case search
        case collection(String)
        case otherAO3
        case notAO3
    }

    let kind: Kind

    init(_ url: URL) {
        guard let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
              url.port == nil, let host = url.host?.lowercased(),
              host == "ao3.org" || host == "archiveofourown.org"
                || host.hasSuffix(".archiveofourown.org")
        else {
            kind = .notAO3
            return
        }

        let parts = url.path(percentEncoded: true).split(separator: "/")
            .map { String($0).removingPercentEncoding ?? String($0) }
        func positiveID(_ value: String) -> Int? {
            guard !value.isEmpty, value.utf8.allSatisfy({ (48...57).contains($0) }),
                  let id = Int(value), id > 0 else { return nil }
            return id
        }
        // Swift has no array patterns: match on the count, then the fixed words.
        switch (parts.count, parts.first) {
        case (2, "works") where parts[1] == "search":
            kind = .search
        case (2, "works"):
            kind = positiveID(parts[1]).map { .work(id: $0, chapterID: nil) } ?? .otherAO3
        case (4, "collections") where parts[2] == "works":
            kind = positiveID(parts[3]).map { .work(id: $0, chapterID: nil) } ?? .otherAO3
        case (4, "works") where parts[2] == "chapters":
            if let workID = positiveID(parts[1]), let chapterID = positiveID(parts[3]) {
                kind = .work(id: workID, chapterID: chapterID)
            } else { kind = .otherAO3 }
        case (2, "series"):
            kind = positiveID(parts[1]).map(Kind.series) ?? .otherAO3
        case (2, "users"):
            kind = ["login", "logout", "new", "password"].contains(parts[1])
                ? .otherAO3 : .user(username: parts[1], pseud: nil)
        case (4, "users") where parts[2] == "pseuds":
            kind = .user(username: parts[1], pseud: parts[3])
        case (2, "tags"):
            kind = .tag(Self.unmungeTag(parts[1]))
        case (3, "tags") where parts[2] == "works":
            kind = .tag(Self.unmungeTag(parts[1]))
        case (2, "collections"):
            kind = .collection(parts[1])
        default:
            kind = .otherAO3
        }
    }

    static func unmungeTag(_ slug: String) -> String {
        slug.replacingOccurrences(of: "*s*", with: "/")
            .replacingOccurrences(of: "*a*", with: "&")
            .replacingOccurrences(of: "*d*", with: ".")
            .replacingOccurrences(of: "*q*", with: "?")
            .replacingOccurrences(of: "*h*", with: "#")
    }
}
