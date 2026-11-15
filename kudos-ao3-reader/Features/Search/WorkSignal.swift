import Foundation

/// A quality signal displayed on ranked search results (Quality-Results board).
///
/// Contains the tone, badge label, and quiet note describing reader response
/// computed purely from the figures AO3 blurbs already carry.
struct WorkSignal: Equatable, Hashable, Sendable {
    enum Tone: String, Equatable, Hashable, CaseIterable, Sendable {
        case high
        case good
        case late
        case neutral
        case unusual
    }

    let label: String
    let note: String?
    let tone: Tone

    /// VoiceOver reads the signal as one phrase, e.g. "2.4× kudos per hit, Steady · 26% saved".
    var accessibilityText: String {
        if let note, !note.isEmpty {
            return "\(label), \(note)"
        }
        return label
    }
}

extension WorkSignal: ExpressibleByStringLiteral {
    init(stringLiteral value: String) {
        self.init(label: value, note: nil, tone: .neutral)
    }
}

/// Pure logic for choosing signal tone, label, and secondary note (FID40).
enum QualitySignalTones {
    /// §4.2. Under 50 is Early, 50–199 is Settling, 200 and up is Steady.
    static let settlingKudos = 50
    static let steadyKudos = 200

    /// The one confidence cut-off. The row note and the Reader Response sheet both call this.
    static func confidenceWord(forKudos kudos: Int) -> String {
        if kudos >= steadyKudos { return "Steady" }
        if kudos >= settlingKudos { return "Settling" }
        return "Early"
    }

    /// Evaluates the tone and visible copy from a work's figures and ranking state.
    ///
    /// Hard rule: every number, label and confidence word comes strictly from existing
    /// blurb figures (kudos, hits, bookmarks, comments) and computed ratios.
    static func chooseTone(
        rank: LoadedWorksRank,
        shown: Double?,
        figures: LoadedWorksRanker.Figures,
        setAside: Bool,
        hasPrevious: Bool = false
    ) -> WorkSignal? {
        guard rank != .ao3Order else { return nil }

        if setAside {
            let note: String
            if let kudos = figures.kudos, LoadedWorksRanker.kudosExceedHits(kudos: kudos, hits: figures.hits) {
                note = "More kudos than hits"
            } else if let kudos = figures.kudos, kudos >= LoadedWorksRanker.unusualKudosFloor,
                      let bookmarks = figures.bookmarks, bookmarks * 100 < kudos {
                note = "Thousands of kudos and almost no bookmarks"
            } else {
                note = "Unusual stats"
            }
            return WorkSignal(label: "Unusual stats", note: note, tone: .unusual)
        }

        guard let shown else {
            return WorkSignal(label: "Not enough figures to rank", note: nil, tone: .neutral)
        }

        let kudos = figures.kudos ?? 0
        let confidenceWord = confidenceWord(forKudos: kudos)

        switch rank {
        case .ao3Order:
            return nil

        case .kudosPerHitAdjusted:
            let label = "\(decimal(shown))× kudos per hit"
            let tone: WorkSignal.Tone = {
                // 1.0× is typical (spec §4.1): only a clearly higher figure stands out;
                // a check mark on an average work would read as praise.
                if shown >= 1.2 { return .high }
                return .neutral
            }()

            let note: String
            if confidenceWord == "Early" && (figures.hits ?? 0) < 3_000 && (figures.bookmarks ?? 0) == 0 {
                note = "Early · few readers yet"
            } else if let bookmarks = figures.bookmarks, kudos > 0 {
                let pct = Int(round(Double(bookmarks) / Double(kudos) * 100))
                note = "\(confidenceWord) · \(pct)% saved"
            } else {
                note = confidenceWord
            }
            return WorkSignal(label: label, note: note, tone: tone)

        case .savesPerKudos:
            let pct = decimal(shown * 100)
            let label = "\(pct)% saved"
            let tone: WorkSignal.Tone = shown >= 0.20 ? .high : .neutral
            return WorkSignal(label: label, note: confidenceWord, tone: tone)

        case .commentsPerKudos:
            let pct = decimal(shown * 100)
            let label = "\(pct)% comments"
            let tone: WorkSignal.Tone = shown >= 0.05 ? .high : .neutral
            return WorkSignal(label: label, note: confidenceWord, tone: tone)

        case .momentum:
            if hasPrevious {
                let gainText = shown.formatted(.number.precision(.fractionLength(0)))
                let label = shown > 0 ? "+\(gainText) kudos" : "No new kudos"
                let tone: WorkSignal.Tone = shown > 0 ? .high : .neutral
                return WorkSignal(label: label, note: "Since you last saw it", tone: tone)
            } else {
                return WorkSignal(label: "First time seen", note: "No earlier sighting", tone: .neutral)
            }

        case .kudosPerThousandWords:
            let label = "\(decimal(shown)) kudos/1k words"
            let tone: WorkSignal.Tone = shown >= 15 ? .high : .neutral
            return WorkSignal(label: label, note: confidenceWord, tone: tone)
        }
    }

    /// One decimal below ten, none above ("2.4", "0.8", "26").
    static func decimal(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(value < 10 ? 1 : 0)))
    }

    /// §4.6 schedule word. The interval is the held cadence (median of the last
    /// five gaps), never the lifetime mean. Nil when that cadence is unknown,
    /// except one posted chapter, which is "Just started" and needs no interval.
    static func wipScheduleWord(
        chaptersPosted: Int,
        chaptersExpected: Int?,
        daysSinceUpdate: Int,
        cadenceDays: Double?
    ) -> String? {
        if chaptersPosted == 1 { return "Just started" }
        guard chaptersPosted >= 2, let cadenceDays, cadenceDays >= 0 else { return nil }
        if daysSinceUpdate > 365 { return "Long pause" }
        let late = Double(daysSinceUpdate) / max(14, cadenceDays)
        if late <= 1.5 {
            if let chaptersExpected, chaptersExpected > 0,
               Double(chaptersPosted) / Double(chaptersExpected) >= 0.8 {
                return "Nearly done"
            }
            return "On schedule"
        }
        if late <= 4 { return "Slower than usual" }
        return "Long pause"
    }
}

extension LoadedWorksRanker {
    /// Comments ÷ kudos, counting readers only, from comments this work's thread
    /// has already been opened to. Nil when the thread was never opened, kudos
    /// are missing or zero, or a held comment cannot be told from the creator's:
    /// the author's share is never guessed, and the blurb total is never scaled.
    /// An opened thread with no comments is 0.
    static func readersOnlyCommentsPerKudos(
        openedComments: [AO3Comment]?,
        kudos: Int?,
        workAuthors: [String],
        workAuthorUsernames: [String] = [],
        currentUsername: String? = nil
    ) -> Double? {
        guard let openedComments, let kudos, kudos > 0 else { return nil }
        guard let readers = readerCommentCount(
            in: openedComments,
            workAuthors: workAuthors,
            workAuthorUsernames: workAuthorUsernames,
            currentUsername: currentUsername
        ) else { return nil }
        return Double(readers) / Double(kudos)
    }

    /// Median of the last five consecutive posting gaps, in days.
    /// Nil before 3 chapters spanning 7 days, or when any date in the run is
    /// unknown. A hole is not zero and is not skipped.
    static func chapterCadenceDays(publishedOn dates: [Date?]) -> Double? {
        guard dates.count >= 3 else { return nil }
        let known = dates.compactMap { $0 }
        guard known.count == dates.count, let first = known.first, let last = known.last else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        guard let span = calendar.dateComponents([.day], from: first, to: last).day, span >= 7 else {
            return nil
        }
        var gaps: [Double] = []
        gaps.reserveCapacity(known.count - 1)
        for index in 1 ..< known.count {
            guard let gap = calendar.dateComponents([.day], from: known[index - 1], to: known[index]).day else {
                return nil
            }
            gaps.append(Double(gap))
        }
        return median(Array(gaps.suffix(5)))
    }

    static func chapterCadenceDays(_ chapters: [AO3ChapterRef]) -> Double? {
        chapterCadenceDays(publishedOn: chapters.map(\.publishedOn))
    }

    /// Nil when the creator cannot be told apart. Deleted tombstones and thread
    /// cutoffs are not comments.
    private static func readerCommentCount(
        in comments: [AO3Comment],
        workAuthors: [String],
        workAuthorUsernames: [String],
        currentUsername: String?
    ) -> Int? {
        var readers = 0
        var stack = comments
        while let comment = stack.popLast() {
            stack.append(contentsOf: comment.replies)
            if comment.isDeleted || comment.isThreadCutoff { continue }
            guard let byCreator = isCreatorReply(
                comment,
                workAuthors: workAuthors,
                workAuthorUsernames: workAuthorUsernames,
                currentUsername: currentUsername
            ) else { return nil }
            if !byCreator { readers += 1 }
        }
        return readers
    }

    private static func isCreatorReply(
        _ comment: AO3Comment,
        workAuthors: [String],
        workAuthorUsernames: [String],
        currentUsername: String?
    ) -> Bool? {
        let username = commenterUsername(of: comment)
        let role = AO3CommentParticipantRole.resolve(
            name: comment.author,
            isGuest: comment.isGuest,
            isAnonymousCreator: comment.isAnonymousCreator,
            commenterUsername: username,
            currentUsername: currentUsername,
            workAuthors: workAuthors,
            workAuthorUsernames: workAuthorUsernames
        )
        switch role {
        case .author:
            return true
        case .user, .guest:
            return false
        case .me:
            // "Me" wins over "Author", so the viewer's own comment hides whether
            // they wrote the work. Known only when the work's accounts are known.
            guard let currentUsername,
                  !currentUsername.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !workAuthorUsernames.isEmpty else { return nil }
            return workAuthorUsernames.contains {
                $0.localizedCaseInsensitiveCompare(currentUsername) == .orderedSame
            }
        }
    }

    /// Same account parse as the comment byline. No second path matcher.
    private static func commenterUsername(of comment: AO3Comment) -> String? {
        guard !comment.isGuest, !comment.isDeleted, let path = comment.userPath else { return nil }
        return AO3AuthorIdentity(displayName: comment.author, href: path)?.username
    }
}
