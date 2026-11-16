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
              let host = url.host?.lowercased(),
              host == "ao3.org" || host == "archiveofourown.org"
                || host.hasSuffix(".archiveofourown.org")
        else {
            kind = .notAO3
            return
        }

        let parts = url.pathComponents.filter { $0 != "/" }
        func positiveID(_ value: String) -> Int? {
            guard let id = Int(value), id > 0 else { return nil }
            return id
        }
        switch parts {
        case ["works", "search"]:
            kind = .search
        case ["works", let id], ["collections", _, "works", let id]:
            kind = positiveID(id).map { .work(id: $0, chapterID: nil) } ?? .otherAO3
        case ["works", let id, "chapters", let chapter]:
            if let workID = positiveID(id), let chapterID = positiveID(chapter) {
                kind = .work(id: workID, chapterID: chapterID)
            } else { kind = .otherAO3 }
        case ["series", let id]:
            kind = positiveID(id).map(Kind.series) ?? .otherAO3
        case ["users", let username]:
            kind = .user(username: username.removingPercentEncoding ?? username, pseud: nil)
        case ["users", let username, "pseuds", let pseud]:
            kind = .user(
                username: username.removingPercentEncoding ?? username,
                pseud: pseud.removingPercentEncoding ?? pseud
            )
        case ["tags", let tag, "works"]:
            kind = .tag(tag)
        case ["collections", let slug]:
            kind = .collection(slug)
        default:
            kind = .otherAO3
        }
    }
}
