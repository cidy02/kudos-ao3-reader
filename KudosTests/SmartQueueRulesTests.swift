import Foundation
import Testing
@testable import Kudos

struct SmartQueueRulesTests {
    private func work(
        _ title: String,
        words: Int = 10_000,
        added: TimeInterval = 0,
        complete: Bool = true,
        finished: Bool = false,
        started: Bool = false,
        status: SmartQueueReadingStatus = .notStarted,
        fandoms: [String] = []
    ) -> SmartQueueWorkFacts {
        SmartQueueWorkFacts(
            id: UUID(),
            title: title,
            wordCount: words,
            dateAdded: Date(timeIntervalSince1970: added),
            isComplete: complete,
            isFinished: finished,
            hasStartedReading: started,
            readingStatus: status,
            fandoms: fandoms
        )
    }

    private func document(
        _ rules: [SmartQueueDocument.Rule],
        match: SmartQueueDocument.Match = .all,
        sort: SmartQueueDocument.Sort = .title,
        limit: Int? = nil
    ) -> SmartQueueDocument {
        SmartQueueDocument(match: match, rules: rules, sort: sort, limit: limit)
    }

    @Test func emptyRulesMatchNothing() {
        let works = [work("A"), work("B", words: 100)]
        #expect(document([], match: .all).matching(works).isEmpty)
        #expect(document([], match: .any).matching(works).isEmpty)
    }

    @Test func lengthUnderSkipsUnknownAndTheBoundary() {
        let rule = SmartQueueDocument.Rule.Kind.length.makeDefault()
        #expect(rule.words == 20_000)
        #expect(rule.summary == "Under \(20_000.formatted()) words")
        let short = work("Short", words: 19_999)
        let edge = work("Edge", words: 20_000)
        let unknown = work("Unknown", words: 0)
        let matched = document([rule], sort: .title).matching([edge, unknown, short])
        #expect(matched.map(\.title) == ["Short"])
    }

    @Test func lengthAtLeastIncludesTheBoundaryAndSkipsUnknown() {
        var rule = SmartQueueDocument.Rule.Kind.length.makeDefault()
        rule.lengthComparison = .atLeast
        rule.words = 20_000
        #expect(rule.summary == "At least \(20_000.formatted()) words")
        let below = work("Below", words: 19_999)
        let edge = work("Edge", words: 20_000)
        let unknown = work("Unknown", words: 0)
        let matched = document([rule], sort: .title).matching([unknown, below, edge])
        #expect(matched.map(\.title) == ["Edge"])

        rule.words = 0
        #expect(rule.summary == "At least 0 words")
        let oneWord = work("One", words: 1)
        let zeroMatched = document([rule], sort: .title).matching([unknown, oneWord])
        #expect(zeroMatched.map(\.title) == ["One"])

        rule.words = nil
        #expect(rule.summary == "Choose a word count")
        #expect(document([rule], sort: .title).matching([unknown, oneWord, edge]).isEmpty)
        rule.lengthComparison = .under
        #expect(rule.summary == "Choose a word count")
        #expect(document([rule], sort: .title).matching([unknown, oneWord, edge]).isEmpty)

        var missingStatus = SmartQueueDocument.Rule.Kind.readingStatus.makeDefault()
        missingStatus.readingStatus = nil
        #expect(missingStatus.summary == "Choose a status")
        #expect(document([missingStatus]).matching([work("Any", status: .reading)]).isEmpty)
    }

    @Test func readingStatusMatchesOnlyThatStatus() {
        let works = SmartQueueReadingStatus.allCases.map { status in
            work(status.rawValue, status: status)
        }
        for status in SmartQueueReadingStatus.allCases {
            var rule = SmartQueueDocument.Rule.Kind.readingStatus.makeDefault()
            rule.readingStatus = status
            let matched = document([rule]).matching(works)
            #expect(matched.map(\.title) == [status.rawValue])
        }
    }

    @Test func progressUsesStartedAndFinished() {
        let unread = work("Unread")
        let reading = work("Reading", started: true)
        let done = work("Done", finished: true, started: true)
        let markedFinishedUnread = work("Marked", finished: true)
        func titles(_ progress: SmartQueueDocument.Rule.Progress) -> [String] {
            var rule = SmartQueueDocument.Rule.Kind.progress.makeDefault()
            rule.progress = progress
            return document([rule], sort: .title).matching([reading, done, unread, markedFinishedUnread]).map(\.title)
        }
        #expect(titles(.notStarted) == ["Unread"])
        #expect(titles(.inProgress) == ["Reading"])
        #expect(titles(.finished) == ["Done", "Marked"])
    }

    @Test func completionIsCompleteOrWIP() {
        let done = work("Done", complete: true)
        let wip = work("WIP", complete: false)
        func titles(_ completion: SmartQueueDocument.Rule.Completion) -> [String] {
            var rule = SmartQueueDocument.Rule.Kind.completion.makeDefault()
            rule.completion = completion
            return document([rule], sort: .title).matching([wip, done]).map(\.title)
        }
        #expect(titles(.complete) == ["Done"])
        #expect(titles(.wip) == ["WIP"])
    }

    @Test func fandomIsTrimmedEqualityAndResolvesLearnedAliases() {
        var rule = SmartQueueDocument.Rule.Kind.fandom.makeDefault()
        #expect(rule.summary == "Choose a fandom")
        #expect(document([rule]).matching([work("A", fandoms: ["Harry Potter"])]).isEmpty)
        rule.fandom = "  harry potter "
        let hit = work("Hit", fandoms: ["Other", "Harry Potter"])
        let miss = work("Miss", fandoms: ["Harry"])
        #expect(document([rule]).matching([miss, hit]).map(\.title) == ["Hit"])

        let aliases = TagAliasResolver(entries: [
            TagAliasResolver.Entry(
                name: "HP",
                canonicalName: "Harry Potter - J. K. Rowling",
                kind: .fandom
            )
        ])
        let canonicalWork = work("Canonical", fandoms: ["Harry Potter - J. K. Rowling"])
        let synonymWork = work("Synonym", fandoms: ["HP"])
        let unrelatedWork = work("Other", fandoms: ["Lockwood"])

        rule.fandom = "Harry Potter - J. K. Rowling"
        #expect(
            document([rule], sort: .title)
                .matching([unrelatedWork, synonymWork, canonicalWork], aliases: aliases)
                .map(\.title) == ["Canonical", "Synonym"]
        )

        rule.fandom = "HP"
        #expect(
            document([rule], sort: .title)
                .matching([unrelatedWork, synonymWork, canonicalWork], aliases: aliases)
                .map(\.title) == ["Canonical", "Synonym"]
        )

        // Review 2: a rule typed "hp" and a work tagged "hp" both follow the
        // learned "HP" alias (AO3 tag names are case-insensitive), so learning
        // the alias cannot empty the queue.
        rule.fandom = "hp"
        let lowercaseWork = work("Lowercase", fandoms: ["hp"])
        #expect(
            document([rule], sort: .title)
                .matching([unrelatedWork, synonymWork, canonicalWork, lowercaseWork], aliases: aliases)
                .map(\.title) == ["Canonical", "Lowercase", "Synonym"]
        )
        #expect(aliases.resolveIgnoringCase("hp", kind: .fandom) == "Harry Potter - J. K. Rowling")
        #expect(aliases.resolve("hp", kind: .fandom) == "hp")
    }

    @Test func allRequiresEveryRuleAndAnyRequiresOne() {
        let length = SmartQueueDocument.Rule.Kind.length.makeDefault()
        var status = SmartQueueDocument.Rule.Kind.completion.makeDefault()
        status.completion = .complete
        let shortDone = work("Short done", words: 1_000, complete: true)
        let shortWIP = work("Short WIP", words: 1_000, complete: false)
        let longDone = work("Long done", words: 80_000, complete: true)
        let works = [longDone, shortWIP, shortDone]
        #expect(document([length, status], match: .all, sort: .title).matching(works).map(\.title) == ["Short done"])
        #expect(
            document([length, status], match: .any, sort: .title).matching(works).map(\.title)
                == ["Long done", "Short done", "Short WIP"]
        )
    }

    @Test func sortAndLimit() {
        let rule = SmartQueueDocument.Rule.Kind.completion.makeDefault()
        let unknown = work("Middling", words: 0, added: 30)
        let short = work("Zebra", words: 100, added: 10)
        let long = work("Alpha", words: 500, added: 20)
        let works = [unknown, long, short]
        #expect(document([rule], sort: .shortestFirst).matching(works).map(\.title) == ["Zebra", "Alpha", "Middling"])
        #expect(document([rule], sort: .longestFirst).matching(works).map(\.title) == ["Alpha", "Zebra", "Middling"])
        #expect(document([rule], sort: .recentlyAdded).matching(works).map(\.title) == ["Middling", "Alpha", "Zebra"])
        #expect(document([rule], sort: .title).matching(works).map(\.title) == ["Alpha", "Middling", "Zebra"])
        #expect(document([rule], sort: .title, limit: 2).matching(works).map(\.title) == ["Alpha", "Middling"])
        #expect(document([rule], sort: .title, limit: 0).matching(works).count == 3)
        #expect(document([rule], sort: .title, limit: nil).matching(works).count == 3)
        #expect(SmartQueueDocument.starter.limitTitle == "25 works")
        #expect(SmartQueueDocument(match: .all, rules: [], sort: .title, limit: nil).limitTitle == "No limit")
    }

    @Test func aWorkLeavesWhenItStopsMatching() {
        let rule = SmartQueueDocument.Rule.Kind.length.makeDefault()
        var story = work("Story", words: 12_000)
        let doc = document([rule])
        #expect(doc.matching([story]).map(\.title) == ["Story"])
        story.wordCount = 40_000
        #expect(doc.matching([story]).isEmpty)
    }

    @Test func partialJSONUsesDefaultsAndUnknownKindDoesNotDecode() throws {
        let partial = try #require(SmartQueueRules.decode("{}"))
        #expect(partial == SmartQueueDocument(match: .all, rules: [], sort: .shortestFirst, limit: nil))
        #expect(SmartQueueRules.decode(nil) == nil)
        #expect(SmartQueueRules.decode("") == nil)
        let future = """
        {"match":"all","rules":[{"id":"00000000-0000-0000-0000-000000000001","kind":"future"}],"sort":"title"}
        """
        #expect(SmartQueueRules.decode(future) == nil)
        let encoded = try #require(SmartQueueRules.encode(SmartQueueDocument.starter))
        #expect(SmartQueueRules.decode(encoded) == SmartQueueDocument.starter)
    }

    @Test @MainActor func factsFollowTheWork() {
        let work = SavedWork(title: "Ash", author: "Bee")
        work.wordCount = 100
        work.workFandoms = ["Lockwood"]
        work.isComplete = false
        work.chapters = "3/?"
        work.knownChapterCount = 3
        #expect(SmartQueueWorkFacts(work: work).readingStatus == .notStarted)
        work.lastSpineIndex = 1
        work.lastScrollFraction = 0.2
        #expect(SmartQueueWorkFacts(work: work).readingStatus == .reading)
        work.lastSpineIndex = 2
        work.lastScrollFraction = 1.0
        #expect(SmartQueueWorkFacts(work: work).readingStatus == .caughtUp)
        work.isFinished = true
        #expect(SmartQueueWorkFacts(work: work).readingStatus == .finished)
        work.isFinished = false
        work.setReadingStatus(.onHold)
        #expect(SmartQueueWorkFacts(work: work).readingStatus == .onHold)
        work.setReadingStatus(.stopped)
        #expect(SmartQueueWorkFacts(work: work).readingStatus == .stopped)
        work.setReadingStatus(.stacking)
        #expect(SmartQueueWorkFacts(work: work).readingStatus == .stacking)
    }
}
