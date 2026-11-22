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

    /// The grey note beside a schedule word (Quality-WIPs). The word is
    /// `wipScheduleWord`; this only formats the figures that word was chosen from.
    /// Nil when there is no schedule word. "Running late" is not a note.
    static func wipScheduleNote(
        chaptersPosted: Int,
        chaptersExpected: Int?,
        daysSinceUpdate: Int,
        cadenceDays: Double?
    ) -> String? {
        guard let word = wipScheduleWord(
            chaptersPosted: chaptersPosted,
            chaptersExpected: chaptersExpected,
            daysSinceUpdate: daysSinceUpdate,
            cadenceDays: cadenceDays
        ) else { return nil }
        switch word {
        case "Just started":
            let chapters = chaptersPosted == 1 ? "1 chapter" : "\(chaptersPosted) chapters"
            return "\(chapters) · \(ago(daysSinceUpdate))"
        case "Nearly done":
            let progress: String
            if let chaptersExpected, chaptersExpected > 0 {
                progress = "\(chaptersPosted) of \(chaptersExpected)"
            } else {
                progress = "\(chaptersPosted) chapters"
            }
            guard let cadenceDays else { return progress }
            return "\(progress) · \(cadencePhrase(cadenceDays, capitalized: false))"
        case "On schedule":
            guard let cadenceDays else { return word }
            return cadencePhrase(cadenceDays, capitalized: true)
        case "Slower than usual":
            guard let cadenceDays else { return since(daysSinceUpdate) }
            return "\(usualPhrase(cadenceDays)) · \(since(daysSinceUpdate))"
        case "Long pause":
            if daysSinceUpdate > 365 { return "Over a year since the last chapter" }
            return since(daysSinceUpdate)
        default:
            return nil
        }
    }

    /// 14 days is "every 2 weeks", 7 is "every week". Other counts stay in days,
    /// because the board's 9 and 12 are not rounded onto a week.
    private static func everySpan(_ days: Double) -> String {
        switch Int(round(days)) {
        case ...1: "every day"
        case 7: "every week"
        case 14: "every 2 weeks"
        case let rounded: "every \(rounded) days"
        }
    }

    private static func cadencePhrase(_ days: Double, capitalized: Bool) -> String {
        let span = everySpan(days)
        return capitalized ? "About \(span)" : "about \(span)"
    }

    private static func usualPhrase(_ days: Double) -> String {
        "Usually \(everySpan(days))"
    }

    private static func ago(_ days: Int) -> String {
        if days <= 0 { return "today" }
        if days == 1 { return "1 day ago" }
        return "\(days) days ago"
    }

    private static func since(_ days: Int) -> String {
        if days == 1 { return "1 day since" }
        return "\(days) days since"
    }
}

/// Reader-facing Reader Response copy. One source for the sheet, Sort By, and
/// the results line, so a wording change has a test that fails when it reverts.
enum ReaderResponseCopy {
    /// Sort By › Set Aside Unusual Stats. Names the margin Appendix D added.
    /// The Search-Sort board still says "More kudos than hits" with no margin;
    /// that sentence describes the rule from before 13 Nov 2026.
    static let unusualStatsSubtitle =
        "At least 20 more kudos than hits, with at least 20 hits, or thousands of kudos and almost no bookmarks"

    /// How Reader Response Works › Unusual Stats.
    static let unusualStatsExplainer =
        "A work is set aside when its kudos are at least 20 above its hits and it has at least 20 hits, or when it has 1,000 kudos and almost no bookmarks. Downloads and apps add kudos and no hits, so a smaller gap is not unusual. Set-aside works are listed under “Not ranked”. Kudos makes no claim about why."

    /// How Reader Response Works › confidence. Steady, Settling, and Early are
    /// the only bands §4.2 names.
    static let confidenceExplainer =
        "Confidence is Steady at 200 kudos or more, Settling from 50 to 199, and Early under 50. Those are the only bands. A difference under 10% is a tie."

    /// Under the kudos-per-hit bars. The first sentence is the board's. The
    /// percentage is not yet the §4.1 cell: the ranker compares loaded works by
    /// length and updated-age, and this says so.
    static let kudosPerHitFooter =
        "AO3 counts one hit per reader per day, so long and serialized works collect more hits for each reader. The line under Similar works names this work’s shape: chapters, length, status and posting year. The percentage is the median of the loaded works of similar length and age."

    /// Steady is 200 kudos, not "thousands of readers". The Quality-Response
    /// board still has the older sentence under the Steady badge.
    static func confidenceSubtitle(forKudos kudos: Int) -> String {
        switch QualitySignalTones.confidenceWord(forKudos: kudos) {
        case "Steady":
            "200 or more kudos; the figure is unlikely to move much"
        case "Settling":
            "50 to 199 kudos; the figure is still settling"
        default:
            "Under 50 kudos; few readers yet"
        }
    }

    struct HighlightedStat: Equatable {
        let value: String
        let label: String
        let accessibilityText: String
    }

    /// The sheet's first figure. A "×" is kudos per hit against its own prior.
    /// Momentum's score is growth relative to the earlier count; printing it as
    /// "1.0×" was the old sheet. `cautiousScore` is accepted so a caller cannot
    /// pass it in and have it become the figure: it is never read.
    static func highlightedStat(
        rankTitle: String?,
        ownKudosPerHit: Double?,
        prior: Double?,
        cautiousScore: Double?,
        signal: WorkSignal?
    ) -> HighlightedStat {
        _ = cautiousScore
        if rankTitle == LoadedWorksRank.momentum.title {
            let value = signal?.label ?? "—"
            return HighlightedStat(
                value: value,
                label: "Momentum",
                accessibilityText: signal?.accessibilityText ?? "Momentum unavailable"
            )
        }
        if rankTitle == nil || rankTitle == LoadedWorksRank.kudosPerHitAdjusted.title,
           let text = kudosPerHitMultiplier(own: ownKudosPerHit, prior: prior) {
            return HighlightedStat(
                value: text,
                label: "Kudos per hit vs similar",
                accessibilityText: "Kudos per hit versus similar: \(text)"
            )
        }
        return HighlightedStat(
            value: "—",
            label: "Kudos per hit vs similar",
            accessibilityText: "Kudos per hit versus similar is unavailable"
        )
    }

    /// Shown multiplier, own rate ÷ prior. Not the cautious score.
    static func kudosPerHitMultiplier(own: Double?, prior: Double?) -> String? {
        guard let own, let prior, prior > 0, own.isFinite else { return nil }
        return "\(QualitySignalTones.decimal(own / prior))×"
    }

    /// "What the ranking uses", and only for kudos per hit. Other scores are
    /// not multipliers.
    static func cautiousDetail(rankTitle: String?, score: Double?) -> String? {
        guard rankTitle == LoadedWorksRank.kudosPerHitAdjusted.title,
              let score, score.isFinite else { return nil }
        return "\(QualitySignalTones.decimal(score))×"
    }

    /// "Similar works 14% · public bookmarks only", or the footnote alone when
    /// this ranking has no such prior.
    static func rateSubtitle(similar: Double?, footnote: String) -> String {
        guard let similar, similar > 0, similar.isFinite else { return footnote }
        return "Similar works \(QualitySignalTones.decimal(similar * 100))% · \(footnote)"
    }

    /// Comments row. Readers-only is appended only when the thread was opened
    /// and the rate is known; it is never guessed from the blurb total.
    static func commentsSubtitle(similar: Double?, readersOnly: Double?) -> String {
        var parts: [String] = []
        if let similar, similar > 0, similar.isFinite {
            parts.append("Similar works \(QualitySignalTones.decimal(similar * 100))%")
        }
        parts.append("replies included")
        if let readersOnly, readersOnly >= 0, readersOnly.isFinite {
            parts.append("readers only \(QualitySignalTones.decimal(readersOnly * 100))%")
        }
        return parts.joined(separator: " · ")
    }

    /// Quality-Results / Quality-WIPs order line. Nil while AO3's own order is on.
    /// Momentum appends "N of 40 seen before" when the partition has one.
    /// Does not say "on schedule first": the ranker does not order by schedule.
    static func rankedWorksLine(
        loaded: Int,
        rank: LoadedWorksRank,
        seenBeforeLine: String?
    ) -> String? {
        guard rank != .ao3Order, loaded > 0 else { return nil }
        let count = loaded.formatted()
        let noun = loaded == 1 ? "work" : "works"
        let by: String
        switch rank {
        case .ao3Order:
            return nil
        case .kudosPerHitAdjusted:
            by = "by kudos per hit against similar works"
        case .savesPerKudos:
            by = "by saves per kudos"
        case .commentsPerKudos:
            by = "by comments per kudos"
        case .momentum:
            by = "by kudos growth since you last saw them"
        case .kudosPerThousandWords:
            by = "by kudos per 1,000 words"
        }
        var line = "Ranked \(count) loaded \(noun) \(by)"
        if let seenBeforeLine, !seenBeforeLine.isEmpty {
            line += ". \(seenBeforeLine)"
        }
        return line
    }
}

/// §4.1 shape, and no other. The sheet used to name "Under 10,000 words" and
/// "updated within a year", which this list does not contain.
enum ReaderResponseBands {
    static func chaptersPhrase(posted: Int) -> String? {
        guard posted > 0 else { return nil }
        return switch posted {
        case 1: "1 chapter"
        case 2 ... 5: "2 to 5 chapters"
        case 6 ... 20: "6 to 20 chapters"
        default: "21 or more chapters"
        }
    }

    static func lengthPhrase(words: Int) -> String? {
        guard words >= 0 else { return nil }
        return switch words {
        case ..<5_000: "Under 5,000 words"
        case ..<20_000: "5,000 to 20,000 words"
        case ..<60_000: "20,000 to 60,000 words"
        case ..<150_000: "60,000 to 150,000 words"
        default: "150,000 or more words"
        }
    }

    static func statusPhrase(isComplete: Bool?) -> String? {
        switch isComplete {
        case true: "complete"
        case false: "WIP"
        case nil: nil
        }
    }

    /// Posting year, not the updated date. 2020 is its own band.
    static func yearPhrase(_ year: Int) -> String {
        switch year {
        case ...2014: "posted 2014 or earlier"
        case 2015 ... 2017: "posted 2015 to 2017"
        case 2018 ... 2019: "posted 2018 to 2019"
        case 2020: "posted 2020"
        case 2021 ... 2022: "posted 2021 to 2022"
        case 2023 ... 2024: "posted 2023 to 2024"
        default: "posted 2025 or later"
        }
    }

    /// "6 to 20 chapters · 20,000 to 60,000 words · complete · posted 2025 or later".
    /// A missing part is left out. With nothing known, the comparison the ranker
    /// actually makes, which is not a shape band.
    static func similarWorksLine(
        chaptersPosted: Int?,
        words: Int?,
        isComplete: Bool?,
        postedYear: Int?
    ) -> String {
        var parts: [String] = []
        if let chaptersPosted, let phrase = chaptersPhrase(posted: chaptersPosted) {
            parts.append(phrase)
        }
        if let words, let phrase = lengthPhrase(words: words) {
            parts.append(phrase)
        }
        if let status = statusPhrase(isComplete: isComplete) {
            parts.append(status)
        }
        if let postedYear {
            parts.append(yearPhrase(postedYear))
        }
        if parts.isEmpty {
            return "Loaded works of similar length and age"
        }
        return parts.joined(separator: " · ")
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
