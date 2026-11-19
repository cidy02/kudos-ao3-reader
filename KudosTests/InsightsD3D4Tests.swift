import Foundation
import SwiftData
import Testing
@testable import Kudos

@MainActor
@Suite(.serialized)
struct InsightsD3D4Tests {
    private func context() throws -> ModelContext {
        let schema = Schema([
            SavedWork.self, Tag.self, Bookmark.self, CustomFont.self,
            WorkCollection.self, ReadingQueue.self, ReadingQueueMembership.self,
            SavedSearch.self, QueueSavedSearchLink.self, SyncTombstone.self, ReadingAnnotation.self,
            ReadingSession.self, ReadingFavorite.self, FandomReadWatermark.self
        ])
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        return ModelContext(container)
    }

    private func writeEPUB(_ entries: [(path: String, content: String)]) throws -> URL {
        var zipEntries: [(name: String, data: Data)] = [
            ("mimetype", Data("application/epub+zip".utf8))
        ]
        zipEntries.append(contentsOf: entries.map { ($0.path, Data($0.content.utf8)) })
        let data = try MiniZip.archiveData(zipEntries)
        let epubURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("fixture-\(UUID().uuidString).epub")
        try data.write(to: epubURL)
        return epubURL
    }

    private func makeAO3FixtureEPUB(
        language: String = "en",
        chapter1Prose: String,
        chapter2Prose: String
    ) throws -> URL {
        let containerXML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
          <rootfiles>
            <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
          </rootfiles>
        </container>
        """
        let opf = """
        <?xml version="1.0" encoding="UTF-8"?>
        <package xmlns="http://www.idpf.org/2007/opf" unique-identifier="bookid" version="2.0">
          <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
            <dc:title>Test AO3 Work</dc:title>
            <dc:creator>Test Writer</dc:creator>
            <dc:language>\(language)</dc:language>
            <dc:identifier id="bookid">urn:uuid:1234</dc:identifier>
          </metadata>
          <manifest>
            <item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>
            <item id="preface" href="preface.xhtml" media-type="application/xhtml+xml"/>
            <item id="ch1" href="chapter1.xhtml" media-type="application/xhtml+xml"/>
            <item id="ch2" href="chapter2.xhtml" media-type="application/xhtml+xml"/>
            <item id="afterword" href="afterword.xhtml" media-type="application/xhtml+xml"/>
          </manifest>
          <spine toc="ncx">
            <itemref idref="preface"/>
            <itemref idref="ch1"/>
            <itemref idref="ch2"/>
            <itemref idref="afterword"/>
          </spine>
        </package>
        """
        let ncx = """
        <?xml version="1.0" encoding="UTF-8"?>
        <ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">
          <docTitle><text>Test AO3 Work</text></docTitle>
          <navMap>
            <navPoint id="n1" playOrder="1"><navLabel><text>Preface</text></navLabel><content src="preface.xhtml"/></navPoint>
            <navPoint id="n2" playOrder="2"><navLabel><text>Chapter 1</text></navLabel><content src="chapter1.xhtml"/></navPoint>
            <navPoint id="n3" playOrder="3"><navLabel><text>Chapter 2</text></navLabel><content src="chapter2.xhtml"/></navPoint>
            <navPoint id="n4" playOrder="4"><navLabel><text>Afterword</text></navLabel><content src="afterword.xhtml"/></navPoint>
          </navMap>
        </ncx>
        """
        let preface = """
        <html xmlns="http://www.w3.org/1999/xhtml"><body>
          <div id="preface">
            <h1>Test AO3 Work</h1>
            <p class="byline">by Test Writer</p>
            <p>Summary</p>
            <blockquote class="userstuff"><p>Work summary words that must not count.</p></blockquote>
            <p>Notes</p>
            <blockquote class="userstuff"><p>Work pre-notes words that must not count.</p></blockquote>
          </div>
        </body></html>
        """
        let ch1 = """
        <html xmlns="http://www.w3.org/1999/xhtml"><body>
          <div id="chapters" class="userstuff">
            <div class="meta group">
              <h2 class="heading">Chapter 1: First</h2>
              <p>Chapter Summary</p>
              <blockquote class="userstuff"><p>Chapter one summary words excluded.</p></blockquote>
              <p>Chapter Notes</p>
              <blockquote class="userstuff"><p>Chapter one beginning notes excluded.</p></blockquote>
              <div class="endnote-link"><p>See the end of the chapter for <a href="#endnotes1">notes</a>.</p></div>
            </div>
            <!--chapter content-->
            <div class="userstuff">
              \(chapter1Prose)
            </div>
            <!--/chapter content-->
            <div class="meta" id="endnotes1">
              <p>Chapter End Notes</p>
              <blockquote class="userstuff"><p>Chapter one end notes excluded.</p></blockquote>
            </div>
          </div>
        </body></html>
        """
        // Calibre-flattened chapter: class names rewritten and comments stripped.
        let ch2 = """
        <html xmlns="http://www.w3.org/1999/xhtml"><body>
          <div id="chapters" class="calibre1">
            <h2 class="calibre2">Chapter 2: Flattened</h2>
            <p class="calibre3">Chapter by Test Writer</p>
            <p class="calibre3">Chapter Summary</p>
            <blockquote class="calibre4"><p>Flattened chapter summary excluded.</p></blockquote>
            <p class="calibre3">Chapter Notes</p>
            <blockquote class="calibre4"><p>Flattened chapter notes excluded.</p></blockquote>
            <p class="calibre3">See the end of the chapter for <a href="#endnotes2">notes</a>.</p>
            <div class="calibre5">
              \(chapter2Prose)
            </div>
            <div id="endnotes2" class="calibre6">
              <p class="calibre3">Chapter End Notes</p>
              <blockquote class="calibre4"><p>Flattened end notes excluded.</p></blockquote>
            </div>
          </div>
        </body></html>
        """
        let afterword = """
        <html xmlns="http://www.w3.org/1999/xhtml"><body>
          <div id="afterword">
            <p>End Notes</p>
            <blockquote class="userstuff"><p>Work endnotes must not count.</p></blockquote>
            <p class="message">Please drop by the Archive and comment to let the creator know if you enjoyed their work!</p>
          </div>
        </body></html>
        """
        return try writeEPUB([
            ("META-INF/container.xml", containerXML),
            ("OEBPS/content.opf", opf),
            ("OEBPS/toc.ncx", ncx),
            ("OEBPS/preface.xhtml", preface),
            ("OEBPS/chapter1.xhtml", ch1),
            ("OEBPS/chapter2.xhtml", ch2),
            ("OEBPS/afterword.xhtml", afterword)
        ])
    }

    // MARK: - D3: Chapter-only counting & unit classification

    @Test func epubCounterExcludesPrefaceSummariesNotesAndAfterword() throws {
        // Chapter 1: 9 words (story blockquote + hyphens/contractions match AO3WordCounter).
        // Chapter 2 (Calibre-flattened): 6 words.
        let epub = try makeAO3FixtureEPUB(
            language: "en",
            chapter1Prose: "<p>Real story one two three</p><blockquote><p>Story letter four</p></blockquote><p>six--seven didn't fold-away</p>",
            chapter2Prose: "<p>Alpha beta gamma delta epsilon zeta.</p>"
        )
        defer { try? FileManager.default.removeItem(at: epub) }

        let analysis = try AO3EPUBChapterWordCounter.analyze(epubURL: epub, language: "English")
        #expect(analysis.wordUnit == .words)
        // "Real"(1) "story"(2) "one"(3) "two"(4) "three"(5) "Story"(6) "letter"(7) "four"(8)
        // "six"(9) "seven"(10) "didn't"->"didnt"(11) "fold-away"->"foldaway"(12) = 12 words in Ch 1.
        #expect(analysis.chapterWordCounts == [12, 6])
    }

    @Test func charactersUnitUsedForNoSpaceLanguagesAndKeptSeparateFromWords() throws {
        // Japanese fixture ("吾輩は猫である" = 7 chars; "名前はまだ無い" = 7 chars)
        let jaEPUB = try makeAO3FixtureEPUB(
            language: "ja",
            chapter1Prose: "<p>吾輩は猫である</p>",
            chapter2Prose: "<p>名前はまだ無い</p>"
        )
        defer { try? FileManager.default.removeItem(at: jaEPUB) }

        let ja = try AO3EPUBChapterWordCounter.analyze(epubURL: jaEPUB)
        #expect(ja.wordUnit == .characters)
        #expect(ja.chapterWordCounts == [7, 7])

        // No language tag on Chinese/Thai EPUB still detects script characters cleanly.
        let zhEPUB = try makeAO3FixtureEPUB(
            language: "",
            chapter1Prose: "<p>春风十里</p>",
            chapter2Prose: "<p>สวัสดี</p>"
        )
        defer { try? FileManager.default.removeItem(at: zhEPUB) }
        let zh = try AO3EPUBChapterWordCounter.analyze(epubURL: zhEPUB)
        #expect(zh.wordUnit == .characters)
        #expect(zh.chapterWordCounts == [4, 6])

        #expect(SavedWork.wordUnit(forLanguage: "中文-普通话 國語") == .characters)
        #expect(SavedWork.wordUnit(forLanguage: "ไทย") == .characters)
        #expect(SavedWork.wordUnit(forLanguage: "한국어") == .words)
        #expect(SavedWork.wordUnit(forLanguage: "English") == .words)

        // Insights never mix characters into totalWordsRead or wordsPerHour.
        let english = SavedWork(title: "EN", author: "A")
        english.language = "English"
        english.wordUnitRaw = SavedWork.WordUnit.words.rawValue
        english.chapterWordCounts = [5_000, 5_000]
        english.wordCount = 10_000

        let japanese = SavedWork(title: "JA", author: "B")
        japanese.language = "日本語"
        japanese.wordUnitRaw = SavedWork.WordUnit.characters.rawValue
        japanese.chapterWordCounts = [12_000, 12_000]
        japanese.wordCount = 24_000

        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let enSession = ReadingSession(
            workID: english.id,
            startedAt: t0,
            endedAt: t0.addingTimeInterval(3_600),
            durationSeconds: 3_600,
            startProgress: 0,
            endingProgress: 1.0,
            wordCount: 10_000,
            didFinish: true
        )
        let jaSession = ReadingSession(
            workID: japanese.id,
            startedAt: t0.addingTimeInterval(4_000),
            endedAt: t0.addingTimeInterval(7_600),
            durationSeconds: 3_600,
            startProgress: 0,
            endingProgress: 1.0,
            wordCount: 24_000,
            didFinish: true
        )

        let facts = ReadingLogService.facts(
            from: [enSession, jaSession],
            works: [english, japanese]
        )
        let insights = ReadingInsights.make(facts: facts)
        #expect(insights.totalWordsRead == 10_000)
        #expect(insights.charactersRead == 24_000)
        #expect(insights.wordsPerHour == 10_000)
        #expect(insights.charactersPerHour == 24_000)
        #expect(insights.dailyWords.reduce(0) { $0 + $1.words } == 10_000)
    }

    // MARK: - D3: 10% fallback & revised-chapter non-double-count

    @Test func chapterCountsWithinTenPercentAreUsedElseFallBackToProgressTimesWords() {
        let withinTolerance = SavedWork(title: "Close", author: "A")
        withinTolerance.chapterWordCounts = [1_000, 2_000] // sum = 3_000
        withinTolerance.wordCount = 3_150 // 5% off (<= 10%)

        let beyondTolerance = SavedWork(title: "Off", author: "A")
        beyondTolerance.chapterWordCounts = [1_000, 1_000] // sum = 2_000
        beyondTolerance.wordCount = 5_000 // 60% off (> 10%)

        let t0 = Date(timeIntervalSince1970: 86_400)
        let s1 = ReadingSession(
            workID: withinTolerance.id,
            startedAt: t0,
            endedAt: t0.addingTimeInterval(600),
            durationSeconds: 600,
            startProgress: 0,
            endingProgress: 1.0 / 3.0,
            wordCount: 3_150
        )
        let s2 = ReadingSession(
            workID: beyondTolerance.id,
            startedAt: t0,
            endedAt: t0.addingTimeInterval(600),
            durationSeconds: 600,
            startProgress: 0,
            endingProgress: 0.5,
            wordCount: 5_000
        )

        let read = ReadingLogService.wordsRead(
            sessions: [s1, s2],
            works: [withinTolerance, beyondTolerance]
        )
        // Within 10%: uses chapterWordCounts (`1_000`, not 0.333 * 3_150 = 1_050).
        #expect(read[s1.id] == 1_000)
        // Beyond 10%: falls back to progress * wordCount (`2_500`, not 1_000).
        #expect(read[s2.id] == 2_500)
    }

    @Test func revisedChapterAlreadyReadIsNotCountedAgain() {
        let work = SavedWork(title: "Revised WIP", author: "A")
        // Chapter 2 originally 1_000 words when user finished 2/2, then revised
        // to 1_500 words and Chapter 3 (1_000 words) was posted.
        work.chapterWordCounts = [1_000, 1_500, 1_000]
        work.wordCount = 3_500
        work.chapters = "3/?"

        let s1CaughtUp = ReadingSession(
            workID: work.id,
            startedAt: Date(timeIntervalSince1970: 86_400),
            endedAt: Date(timeIntervalSince1970: 90_000),
            durationSeconds: 3_600,
            startProgress: 0,
            endingProgress: 1.0,
            wordCount: 2_000,
            chapterCountAtVisit: 2,
            didFinish: true
        )
        let s2RereadRevisedCh2 = ReadingSession(
            workID: work.id,
            startedAt: Date(timeIntervalSince1970: 2 * 86_400),
            endedAt: Date(timeIntervalSince1970: 2 * 86_400 + 600),
            durationSeconds: 600,
            startProgress: 1_000.0 / 3_500.0,
            endingProgress: 2_500.0 / 3_500.0,
            wordCount: 3_500,
            chapterCountAtVisit: 3,
            didFinish: false
        )
        let s3NewChapter3 = ReadingSession(
            workID: work.id,
            startedAt: Date(timeIntervalSince1970: 3 * 86_400),
            endedAt: Date(timeIntervalSince1970: 3 * 86_400 + 600),
            durationSeconds: 600,
            startProgress: 2_500.0 / 3_500.0,
            endingProgress: 1.0,
            wordCount: 3_500,
            chapterCountAtVisit: 3,
            didFinish: true
        )

        let read = ReadingLogService.wordsRead(
            sessions: [s1CaughtUp, s2RereadRevisedCh2, s3NewChapter3],
            works: [work]
        )
        #expect(read[s1CaughtUp.id] == 2_000)
        // Revised chapter 2 was already read in s1 -> 0 credited when revisiting.
        #expect(read[s2RereadRevisedCh2.id] == 0)
        // Only the unread Chapter 3 (1_000 words) is credited.
        #expect(read[s3NewChapter3.id] == 1_000)
    }

    // MARK: - D4: Mode split, detached Read Aloud, Pace without listening

    @Test func modeSwitchMidSittingSplitsIntoSeparateRowsAndPreservesFinishOnce() throws {
        ReadingLogService.resetOpenSessionsForTests()
        let context = try context()
        let work = SavedWork(title: "Mixed Sitting", author: "A")
        work.wordCount = 10_000
        context.insert(work)
        try context.save()

        let t0 = Date(timeIntervalSince1970: 100_000)
        ReadingLogService.startSession(for: work, now: t0)
        // Read silently for 60s -> reach 0.30.
        ReadingLogService.noteActivity(for: work, now: t0.addingTimeInterval(60))
        work.readiumLocator = #"{"locations":{"totalProgression":0.3}}"#
        work.isFinished = true
        ReadingLogService.setMode(
            .listen, for: work, playbackRate: 1.25, now: t0.addingTimeInterval(60)
        )

        // Listen for 90s -> reach 0.65.
        ReadingLogService.noteActivity(for: work, now: t0.addingTimeInterval(150))
        work.readiumLocator = #"{"locations":{"totalProgression":0.65}}"#
        ReadingLogService.setMode(.read, for: work, now: t0.addingTimeInterval(150))

        // Finish with 30s of reading -> end at 0.80.
        ReadingLogService.noteActivity(for: work, now: t0.addingTimeInterval(180))
        work.readiumLocator = #"{"locations":{"totalProgression":0.8}}"#
        ReadingLogService.endSession(for: work, now: t0.addingTimeInterval(180))

        let rows = try context.fetch(
            FetchDescriptor<ReadingSession>(sortBy: [SortDescriptor(\.startedAt)])
        )
        #expect(rows.count == 3)
        #expect(rows[0].mode == .read)
        #expect(rows[0].playbackRate == nil)
        #expect(rows[0].durationSeconds == 60)
        #expect(rows[0].endingProgress == 0.3)
        #expect(rows[0].didFinish)

        #expect(rows[1].mode == .listen)
        #expect(rows[1].playbackRate == 1.25)
        #expect(rows[1].durationSeconds == 90)
        #expect(rows[1].startProgress == 0.3)
        #expect(rows[1].endingProgress == 0.65)
        // Segment 1 already recorded the finish; subsequent split segments do not double-count.
        #expect(!rows[1].didFinish)

        #expect(rows[2].mode == .read)
        #expect(rows[2].playbackRate == nil)
        #expect(rows[2].durationSeconds == 30)
        #expect(rows[2].startProgress == 0.65)
        #expect(rows[2].endingProgress == 0.8)
        #expect(!rows[2].didFinish)
        #expect(ReadingLogService.finishCount(of: work.id, in: context) == 1)
    }

    @Test func detachedReadAloudKeepsListeningSessionOpenAndClosesOnStop() throws {
        ReadingLogService.resetOpenSessionsForTests()
        let context = try context()
        let work = SavedWork(title: "Detached Audio", author: "A")
        work.wordCount = 8_000
        context.insert(work)
        try context.save()

        let t0 = Date(timeIntervalSince1970: 200_000)
        ReadingLogService.startSession(for: work, now: t0)
        // User enables Read Aloud right away and exits the reader 20s later.
        ReadingLogService.setMode(.listen, for: work, playbackRate: 1.5, now: t0)
        ReadingLogService.noteActivity(for: work, now: t0.addingTimeInterval(20))
        ReadingLogService.handleReaderClose(
            for: work,
            detachListening: true,
            isSpeechPlaying: true,
            playbackRate: 1.5,
            now: t0.addingTimeInterval(20)
        )
        #expect(ReadingLogService.hasOpenSession(for: work.id))
        #expect(ReadingLogService.openSessionMode(for: work.id) == .listen)

        // Detached playback continues for 40s then pauses on mini player (20+40 = 60s).
        ReadingLogService.noteActivity(for: work, now: t0.addingTimeInterval(60))
        ReadingLogService.handleDetachedSpeech(
            .paused, for: work, playbackRate: 1.5, now: t0.addingTimeInterval(60)
        )
        let afterPause = try context.fetch(FetchDescriptor<ReadingSession>())
        #expect(afterPause.count == 1)
        #expect(afterPause.first?.mode == .listen)
        #expect(afterPause.first?.durationSeconds == 60)

        // Paused idle gap [60..120], then resumed [120..150] (30s) and stopped.
        ReadingLogService.handleDetachedSpeech(
            .playing, for: work, playbackRate: 1.5, now: t0.addingTimeInterval(120)
        )
        ReadingLogService.noteActivity(for: work, now: t0.addingTimeInterval(150))
        ReadingLogService.handleDetachedSpeech(
            .stopped, for: work, playbackRate: 1.5, now: t0.addingTimeInterval(150)
        )
        #expect(!ReadingLogService.hasOpenSession(for: work.id))

        let finalRows = try context.fetch(FetchDescriptor<ReadingSession>())
        #expect(finalRows.count == 1)
        #expect(finalRows.first?.mode == .listen)
        #expect(finalRows.first?.playbackRate == 1.5)
        #expect(finalRows.first?.durationSeconds == 90)
        #expect(finalRows.first?.activeSeconds == 90)
    }

    @Test func paceExcludesListeningSittingsWhileKeepingListeningTimeInTotal() {
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let readFact = ReadingSessionFacts(
            workID: UUID(),
            startedAt: t0,
            durationSeconds: 1_800,
            wordCount: 20_000,
            didFinish: false,
            wordsRead: 10_000,
            mode: .read,
            wordUnit: .words
        )
        let listenFact = ReadingSessionFacts(
            workID: UUID(),
            startedAt: t0.addingTimeInterval(3_600),
            durationSeconds: 3_600,
            wordCount: 20_000,
            didFinish: true,
            wordsRead: 9_000,
            mode: .listen,
            wordUnit: .words
        )

        #expect(ReadingInsights.wordsPerHour(of: [readFact, listenFact]) == 20_000)
        #expect(ReadingInsights.wordsPerHour(of: [listenFact]) == 0)

        let insights = ReadingInsights.make(facts: [readFact, listenFact])
        #expect(insights.wordsPerHour == 20_000)
        #expect(insights.totalWordsRead == 19_000)
        #expect(insights.silentReadingSeconds == 1_800)
        #expect(insights.listeningSeconds == 3_600)
        #expect(insights.readingSeconds == 5_400)
    }
}
