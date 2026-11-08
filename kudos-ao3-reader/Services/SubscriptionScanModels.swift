import Foundation

/// User-started subscriptions scan. The service, the on-device file, and the
/// Waiting rows all speak these types. A later backup source can encode
/// `SubscriptionScanFile` as-is; it is not in `.kudosbackup` or folder sync.
enum SubscriptionScanPhase: Equatable, Sendable {
    case idle
    case running
    case paused
    case finished
    case stopped
}

/// What the signed-in user's own subscriptions page says a follow is.
/// That page has no stats — only the work link and byline.
struct SubscriptionScanFollow: Equatable, Sendable, Identifiable {
    var workID: Int
    var title: String
    var author: String

    var id: Int { workID }
}

struct SubscriptionScanListPage: Equatable, Sendable {
    var works: [SubscriptionScanFollow]
    var totalPages: Int
}

/// Chapter, word, date, and completion facts from one work page.
struct SubscriptionScanWorkFacts: Equatable, Sendable {
    var title: String
    var author: String
    var chaptersPosted: Int?
    var chaptersTotal: Int?
    var words: Int?
    var updatedText: String
    var updatedAt: Date?
    var isComplete: Bool?

    init(
        title: String,
        author: String,
        chaptersPosted: Int?,
        chaptersTotal: Int?,
        words: Int?,
        updatedText: String,
        updatedAt: Date?,
        isComplete: Bool?
    ) {
        self.title = title
        self.author = author
        self.chaptersPosted = chaptersPosted
        self.chaptersTotal = chaptersTotal
        self.words = words
        self.updatedText = updatedText
        self.updatedAt = updatedAt
        self.isComplete = isComplete
    }

    /// Maps the existing work-page parse. `chapters` is AO3's `posted/expected`
    /// string (`12/?`, `1,002/1,002`). An empty string stays unknown — it is not
    /// zero chapters.
    init(metadata: AO3WorkMetadata) {
        let counts = Self.chapterCounts(metadata.chapters)
        title = metadata.title
        author = metadata.authorText
        chaptersPosted = counts.posted
        chaptersTotal = counts.total
        words = metadata.words
        updatedText = metadata.dateUpdated
        updatedAt = Self.parseUpdatedDate(metadata.dateUpdated)
        isComplete = metadata.isComplete
    }

    static func chapterCounts(_ chapters: String) -> (posted: Int?, total: Int?) {
        let parts = chapters.split(separator: "/", omittingEmptySubsequences: false)
        guard let first = parts.first else { return (nil, nil) }
        let posted = integer(String(first))
        let total = parts.count > 1 ? integer(String(parts[1])) : nil
        return (posted, total)
    }

    /// `work_meta_list` localizes the revised date. The app's work-page fixtures
    /// use `02 Jan 2026`; Rails' `%d %b %Y` also yields an unpadded day.
    static func parseUpdatedDate(_ text: String) -> Date? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        for format in ["dd MMM yyyy", "d MMM yyyy"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: trimmed) { return date }
        }
        return nil
    }

    private static func integer(_ raw: String) -> Int? {
        let digits = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: "")
        guard !digits.isEmpty, digits != "?" else { return nil }
        return Int(digits)
    }
}

/// Read-only look at a library copy. The scan never writes `SavedWork`.
struct SubscriptionScanLibraryHint: Equatable, Sendable {
    var postedChapters: Int?
    var lastChecked: Date?
}

/// One follow as last checked, for this signed-in account only.
struct SubscriptionScanSnapshot: Codable, Equatable, Sendable, Identifiable {
    var workID: Int
    var title: String
    var author: String
    var chaptersPosted: Int?
    var chaptersTotal: Int?
    var words: Int?
    var updatedText: String
    var updatedAt: Date?
    var isComplete: Bool?
    var gone: Bool
    var checkedAt: Date
    /// Posted count already turned into a Waiting row. A later check at the
    /// same count must not claim the chapter again.
    var lastReportedPosted: Int?

    var id: Int { workID }
}

/// schemaVersion 1. Dates use `JSONEncoder`'s default (seconds since the
/// reference date) so a later backup source can copy the file without a
/// private encoder.
struct SubscriptionScanFile: Codable, Equatable, Sendable {
    static let currentSchema = 1

    var schemaVersion: Int
    var authenticationScope: String
    var followedWorkIDs: [Int]
    var snapshots: [SubscriptionScanSnapshot]
    var updates: [SubscriptionUpdate]
    var nextUpdateUID: UInt32

    static func empty(scope: String) -> SubscriptionScanFile {
        SubscriptionScanFile(
            schemaVersion: currentSchema,
            authenticationScope: scope,
            followedWorkIDs: [],
            snapshots: [],
            updates: [],
            nextUpdateUID: 1
        )
    }

    func snapshot(for workID: Int) -> SubscriptionScanSnapshot? {
        snapshots.first { $0.workID == workID }
    }

    mutating func upsert(_ snapshot: SubscriptionScanSnapshot) {
        if let index = snapshots.firstIndex(where: { $0.workID == snapshot.workID }) {
            snapshots[index] = snapshot
        } else {
            snapshots.append(snapshot)
        }
    }
}

struct SubscriptionScanDecision: Equatable, Sendable {
    var snapshot: SubscriptionScanSnapshot
    var update: SubscriptionUpdate?
    var nextUpdateUID: UInt32
}

/// Decides what one successful work-page check is allowed to say.
enum SubscriptionScanJudge {
    static func decide(
        follow: SubscriptionScanFollow,
        previous: SubscriptionScanSnapshot?,
        facts: SubscriptionScanWorkFacts,
        localPosted: Int?,
        now: Date,
        nextUpdateUID: UInt32
    ) -> SubscriptionScanDecision {
        var snapshot = observed(
            follow: follow,
            previous: previous,
            facts: facts,
            now: now,
            gone: false
        )
        guard let claim = waitingClaim(
            previous: previous,
            posted: facts.chaptersPosted,
            localPosted: localPosted
        ), nextUpdateUID < .max else {
            return SubscriptionScanDecision(
                snapshot: snapshot,
                update: nil,
                nextUpdateUID: nextUpdateUID
            )
        }
        snapshot.lastReportedPosted = claim.posted
        let update = makeUpdate(
            workID: follow.workID,
            facts: facts,
            posted: claim.posted,
            chapterNumber: claim.chapterNumber,
            now: now,
            uid: nextUpdateUID
        )
        return SubscriptionScanDecision(
            snapshot: snapshot,
            update: update,
            nextUpdateUID: nextUpdateUID + 1
        )
    }

    private struct Claim {
        var posted: Int
        var chapterNumber: Int?
    }

    /// A first look is only a baseline. A later look is waiting when AO3's
    /// posted count grew past that baseline, or past the library copy.
    private static func waitingClaim(
        previous: SubscriptionScanSnapshot?,
        posted: Int?,
        localPosted: Int?
    ) -> Claim? {
        guard let posted, let previous, previous.gone == false,
              let baseline = previous.chaptersPosted
        else { return nil }
        if let reported = previous.lastReportedPosted, posted <= reported { return nil }
        let grew = posted > baseline
        let aheadOfLibrary = localPosted.map { posted > $0 } ?? false
        guard grew || aheadOfLibrary else { return nil }
        let chapterNumber = grew && posted - baseline == 1 ? posted : nil
        return Claim(posted: posted, chapterNumber: chapterNumber)
    }

    /// A 404 names this follow gone and keeps whatever we already recorded.
    static func gone(
        follow: SubscriptionScanFollow,
        previous: SubscriptionScanSnapshot?,
        now: Date
    ) -> SubscriptionScanSnapshot {
        SubscriptionScanSnapshot(
            workID: follow.workID,
            title: title(previous?.title, follow.title),
            author: author(previous?.author, follow.author),
            chaptersPosted: previous?.chaptersPosted,
            chaptersTotal: previous?.chaptersTotal,
            words: previous?.words,
            updatedText: previous?.updatedText ?? "",
            updatedAt: previous?.updatedAt,
            isComplete: previous?.isComplete,
            gone: true,
            checkedAt: now,
            lastReportedPosted: previous?.lastReportedPosted
        )
    }

    private static func observed(
        follow: SubscriptionScanFollow,
        previous: SubscriptionScanSnapshot?,
        facts: SubscriptionScanWorkFacts,
        now: Date,
        gone: Bool
    ) -> SubscriptionScanSnapshot {
        SubscriptionScanSnapshot(
            workID: follow.workID,
            title: title(facts.title, title(previous?.title, follow.title)),
            author: author(facts.author, author(previous?.author, follow.author)),
            chaptersPosted: facts.chaptersPosted ?? previous?.chaptersPosted,
            chaptersTotal: facts.chaptersTotal ?? previous?.chaptersTotal,
            words: facts.words ?? previous?.words,
            updatedText: facts.updatedText.isEmpty ? (previous?.updatedText ?? "") : facts.updatedText,
            updatedAt: facts.updatedAt ?? previous?.updatedAt,
            isComplete: facts.isComplete ?? previous?.isComplete,
            gone: gone,
            checkedAt: now,
            lastReportedPosted: previous?.lastReportedPosted
        )
    }

    private static func makeUpdate(
        workID: Int,
        facts: SubscriptionScanWorkFacts,
        posted: Int,
        chapterNumber: Int?,
        now: Date,
        uid: UInt32
    ) -> SubscriptionUpdate {
        SubscriptionUpdate(
            uid: uid,
            workID: UInt64(workID),
            chapterID: nil,
            chapterNumber: chapterNumber,
            isNewWork: false,
            isContested: false,
            isAnchoredToWork: true,
            workTitle: facts.title,
            author: facts.author,
            at: now,
            source: .work,
            words: facts.words.flatMap { UInt64(exactly: $0) },
            chaptersPosted: UInt32(exactly: posted),
            chaptersTotal: facts.chaptersTotal.flatMap { UInt32(exactly: $0) }
        )
    }

    private static func title(_ primary: String?, _ fallback: String) -> String {
        let candidate = primary?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return candidate.isEmpty ? fallback : candidate
    }

    private static func author(_ primary: String?, _ fallback: String) -> String {
        let candidate = primary?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return candidate.isEmpty ? fallback : candidate
    }
}

enum SubscriptionScanCopy {
    static let alphabeticalHonesty =
        "AO3 pages alphabetically, so what is checked so far is the start of the alphabet, "
        + "not what changed most recently."
    static let maintenance = AO3Error.maintenance.errorDescription
        ?? "AO3 is down for maintenance. Check status.archiveofourown.org."
}

enum SubscriptionScanClock {
    static func seconds(_ duration: Duration) -> TimeInterval {
        let parts = duration.components
        return TimeInterval(parts.seconds) + TimeInterval(parts.attoseconds) / 1_000_000_000_000_000_000
    }

    static func duration(seconds: TimeInterval) -> Duration {
        .seconds(seconds)
    }

    static func nanoseconds(_ duration: Duration) -> UInt64 {
        let seconds = seconds(duration)
        guard seconds > 0 else { return 0 }
        let nanos = seconds * 1_000_000_000
        guard nanos < TimeInterval(UInt64.max) else { return .max }
        return UInt64(nanos)
    }
}

struct SubscriptionScanTiming: Sendable {
    var now: @Sendable () -> Date
    var sleep: @Sendable (Duration) async throws -> Void
    var pause: Duration

    static let live = SubscriptionScanTiming(
        now: Date.init,
        sleep: { try await Task.sleep(nanoseconds: SubscriptionScanClock.nanoseconds($0)) },
        pause: SubscriptionScanClock.duration(
            seconds: TimeInterval(ReadingQueueService.preservationRequestPauseNanos) / 1_000_000_000
        )
    )
}

@MainActor
protocol SubscriptionScanFetching {
    func subscriptionPage(_ page: Int) async throws -> SubscriptionScanListPage
    func workFacts(workID: Int) async throws -> SubscriptionScanWorkFacts
}
