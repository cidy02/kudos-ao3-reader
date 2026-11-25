import Foundation
#if os(iOS)
import ReadiumNavigator
import ReadiumShared
#endif
import SwiftData
import Testing
@testable import Kudos

@MainActor
@Suite(.serialized)
struct InsightsD3D4Tests {
    private func makeContext() throws -> ModelContext {
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
        chapter2Prose: String,
        includeTOCNavPoints: Bool = true
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
        let navMap = includeTOCNavPoints
            ? """
            <navPoint id="n1" playOrder="1"><navLabel><text>Preface</text></navLabel><content src="preface.xhtml"/></navPoint>
            <navPoint id="n2" playOrder="2"><navLabel><text>Chapter 1</text></navLabel><content src="chapter1.xhtml"/></navPoint>
            <navPoint id="n3" playOrder="3"><navLabel><text>Chapter 2</text></navLabel><content src="chapter2.xhtml"/></navPoint>
            <navPoint id="n4" playOrder="4"><navLabel><text>Afterword</text></navLabel><content src="afterword.xhtml"/></navPoint>
            """
            : ""
        let ncx = """
        <?xml version="1.0" encoding="UTF-8"?>
        <ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">
          <docTitle><text>Test AO3 Work</text></docTitle>
          <navMap>
            \(navMap)
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
        // Calibre-flattened chapter with classes rewritten, comments stripped, and
        // NO `id="endnotes2"` so `removeCalibreFlattenedApparatus` itself must strip end notes.
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
            <div class="calibre6">
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

    // MARK: - D3: Chapter-only counting, TOC-less EPUBs & unit isolation

    @Test func epubCounterExcludesPrefaceSummariesNotesAndAfterword() throws {
        let epub = try makeAO3FixtureEPUB(
            language: "en",
            chapter1Prose: "<p>Real story one two three</p><blockquote><p>Story letter four</p></blockquote>"
                + "<p>six--seven didn't fold-away</p>",
            chapter2Prose: "<p>Alpha beta gamma delta epsilon zeta.</p>"
        )
        defer { try? FileManager.default.removeItem(at: epub) }

        let analysis = try AO3EPUBChapterWordCounter.analyze(epubURL: epub, language: "English")
        #expect(analysis.wordUnit == .words)
        #expect(analysis.chapterWordCounts == [12, 6])
    }

    @Test func epubCounterLackingTOCMarkersSkipsApparatusAndTrimsOuterZeroBoundaries() throws {
        // Without TOC navPoints, ReaderSectionBuilder classifies preface/afterword as
        // `.chapter`. Pure apparatus spine items stripped to 0 (and `<h3>` headings) must
        // not leave leading/trailing zeros like `[0, 4, 6, 0]` that zero out `prefix(1)`.
        let epub = try makeAO3FixtureEPUB(
            language: "en",
            chapter1Prose: "<h3>Heading Inside Prose</h3><p>Four prose words here.</p>",
            chapter2Prose: "<p>One two three four five six.</p>",
            includeTOCNavPoints: false
        )
        defer { try? FileManager.default.removeItem(at: epub) }

        // Notice Ch 1 uses `<!--chapter content-->` only in the fixture; also test
        // a pure DOM spine chapter lacking `<!--chapter content-->` with leading `<h3>`.
        let plainContainer = """
        <?xml version="1.0" encoding="UTF-8"?>
        <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
          <rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles>
        </container>
        """
        let plainOPF = """
        <?xml version="1.0" encoding="UTF-8"?>
        <package xmlns="http://www.idpf.org/2007/opf" unique-identifier="b" version="2.0">
          <metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:title>Plain</dc:title><dc:identifier id="b">p</dc:identifier></metadata>
          <manifest>
            <item id="p" href="preface.xhtml" media-type="application/xhtml+xml"/>
            <item id="c1" href="c1.xhtml" media-type="application/xhtml+xml"/>
            <item id="a" href="afterword.xhtml" media-type="application/xhtml+xml"/>
          </manifest>
          <spine><itemref idref="p"/><itemref idref="c1"/><itemref idref="a"/></spine>
        </package>
        """
        let plainEPUB = try writeEPUB([
            ("META-INF/container.xml", plainContainer),
            ("OEBPS/content.opf", plainOPF),
            ("OEBPS/preface.xhtml", "<html><body><div id=\"preface\"><p>Ignored preface</p></div></body></html>"),
            ("OEBPS/c1.xhtml", "<html><body><h3>Chapter Title Heading</h3><p>Four prose words here.</p></body></html>"),
            ("OEBPS/afterword.xhtml", "<html><body><div id=\"afterword\"><p>Ignored afterword</p></div></body></html>")
        ])
        defer { try? FileManager.default.removeItem(at: plainEPUB) }

        let fromPlain = try AO3EPUBChapterWordCounter.analyze(epubURL: plainEPUB)
        #expect(fromPlain.chapterWordCounts == [4])

        let noTOCAO3 = try AO3EPUBChapterWordCounter.analyze(epubURL: epub, language: "English")
        #expect(noTOCAO3.chapterWordCounts == [7, 6])
    }

    @Test func charactersUnitIsolatedAcrossOverviewSharesTasteHabitsLibraryTimelineAndAO3Refresh() throws {
        // 1. EPUB detection & AO3 language refresh path (`applyLanguageMetadata`).
        let jaEPUB = try makeAO3FixtureEPUB(
            language: "ja",
            chapter1Prose: "<p>吾輩は猫である</p>",
            chapter2Prose: "<p>名前はまだ無い</p>"
        )
        defer { try? FileManager.default.removeItem(at: jaEPUB) }
        let jaAnalysis = try AO3EPUBChapterWordCounter.analyze(epubURL: jaEPUB)
        #expect(jaAnalysis.wordUnit == .characters)
        #expect(jaAnalysis.chapterWordCounts == [7, 7])

        let zhEPUB = try makeAO3FixtureEPUB(
            language: "",
            chapter1Prose: "<p>春风十里</p>",
            chapter2Prose: "<p>สวัสดี</p>"
        )
        defer { try? FileManager.default.removeItem(at: zhEPUB) }
        let zhAnalysis = try AO3EPUBChapterWordCounter.analyze(epubURL: zhEPUB)
        #expect(zhAnalysis.wordUnit == .characters)
        #expect(zhAnalysis.chapterWordCounts == [4, 6])

        let refreshedWork = SavedWork(title: "Unlabeled JP", author: "Author")
        #expect(refreshedWork.wordUnit == .words)
        refreshedWork.applyLanguageMetadata("日本語")
        #expect(refreshedWork.wordUnitRaw == SavedWork.WordUnit.characters.rawValue)
        #expect(refreshedWork.wordUnit == .characters)

        // 2. Full Insights / Taste / Habits / Library / Timeline separation.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let now = Date(timeIntervalSince1970: 1_710_000_000)
        let prevMonthStart = try #require(calendar.date(byAdding: .month, value: -1, to: now))
        let monthInterval = try #require(calendar.dateInterval(of: .month, for: now))

        let english = SavedWork(title: "EN Fic", author: "A")
        english.language = "English"
        english.wordUnitRaw = SavedWork.WordUnit.words.rawValue
        english.workFandoms = ["Star Wars"]
        english.workRelationships = ["A/B"]
        english.workTags = ["Angst"]
        english.chapterWordCounts = [10_000]
        english.wordCount = 10_000
        english.isFinished = true
        english.dateAdded = now

        let japanese = SavedWork(title: "JA Fic", author: "B")
        japanese.language = "日本語"
        japanese.wordUnitRaw = SavedWork.WordUnit.characters.rawValue
        japanese.workFandoms = ["Original Work"]
        japanese.workRelationships = ["C/D"]
        japanese.workTags = ["Fluff"]
        japanese.chapterWordCounts = [20_000]
        japanese.wordCount = 20_000
        japanese.isFinished = true
        japanese.dateAdded = now

        let unreadJapanese = SavedWork(title: "JA Unread", author: "C")
        unreadJapanese.language = "日本語"
        unreadJapanese.wordUnitRaw = SavedWork.WordUnit.characters.rawValue
        unreadJapanese.wordCount = 50_000
        unreadJapanese.dateAdded = now

        let hiddenJapanese = SavedWork(title: "Concealed JA", author: "D")
        hiddenJapanese.language = "日本語"
        hiddenJapanese.wordUnitRaw = SavedWork.WordUnit.characters.rawValue
        hiddenJapanese.rating = "Explicit"
        hiddenJapanese.chapterWordCounts = [15_000]
        hiddenJapanese.wordCount = 15_000

        let context = try makeContext()
        context.insert(english)
        context.insert(japanese)
        context.insert(unreadJapanese)
        context.insert(hiddenJapanese)

        // Prior month had ONLY Japanese characters -> `previousPeriodWordsRead` must be `nil`.
        let prevJA = ReadingSession(
            workID: japanese.id,
            startedAt: prevMonthStart,
            endedAt: prevMonthStart.addingTimeInterval(3_600),
            durationSeconds: 3_600,
            startProgress: 0,
            endingProgress: 1.0,
            wordCount: 20_000,
            didFinish: true
        )
        let curEN = ReadingSession(
            workID: english.id,
            startedAt: monthInterval.start.addingTimeInterval(18_000),
            endedAt: monthInterval.start.addingTimeInterval(21_600),
            durationSeconds: 3_600,
            startProgress: 0,
            endingProgress: 1.0,
            wordCount: 10_000,
            didFinish: true
        )
        let curJA1 = ReadingSession(
            workID: japanese.id,
            startedAt: monthInterval.start.addingTimeInterval(21_600),
            endedAt: monthInterval.start.addingTimeInterval(25_200),
            durationSeconds: 3_600,
            startProgress: 0,
            endingProgress: 1.0,
            wordCount: 20_000,
            didFinish: true
        )
        let hiddenSession = ReadingSession(
            workID: hiddenJapanese.id,
            startedAt: monthInterval.start.addingTimeInterval(25_200),
            endedAt: monthInterval.start.addingTimeInterval(27_000),
            durationSeconds: 1_800,
            startProgress: 0,
            endingProgress: 1.0,
            wordCount: 15_000,
            didFinish: false
        )
        context.insert(prevJA)
        context.insert(curEN)
        context.insert(curJA1)
        context.insert(hiddenSession)
        try context.save()

        let previousInterval = try #require(calendar.dateInterval(of: .month, for: prevMonthStart))
        let overview = ReadingLogService.insights(
            for: monthInterval,
            previousPeriod: previousInterval,
            works: [english, japanese, unreadJapanese],
            hiddenWorkIDs: [hiddenJapanese.id],
            calendar: calendar,
            context: context
        )
        #expect(overview.totalWordsRead == 10_000)
        #expect(overview.charactersRead == 20_000)
        #expect(overview.wordsPerHour == 10_000)
        #expect(overview.charactersPerHour == 20_000)
        #expect(overview.previousPeriodWordsRead == nil)
        // English fandom share must be 1.0 (100%), not diluted to 10k / (10k + 20k).
        #expect(overview.fandomWordsShares.first?.name == "Star Wars")
        #expect(overview.fandomWordsShares.first?.share == 1.0)

        let periodFacts = ReadingLogService.facts(
            from: [curEN, curJA1],
            works: [english, japanese],
            history: [prevJA, curEN, curJA1]
        )
        let allFacts = ReadingLogService.facts(
            from: [prevJA, curEN, curJA1],
            works: [english, japanese]
        )
        let taste = ReadingTasteInsights.make(works: [english, japanese], facts: periodFacts)
        #expect(taste.relationships.map(\.name) == ["A/B"])
        #expect(taste.tags.map(\.name) == ["Angst"])

        let habits = ReadingHabitsInsights.make(
            works: [english, japanese],
            facts: periodFacts,
            allFacts: allFacts,
            calendar: calendar
        )
        // Japanese work finished twice -> reread entry exists, but word count excludes chars (0).
        #expect(habits.rereads.first?.id == japanese.id)
        #expect(habits.rereads.first?.finishCount == 2)
        #expect(habits.rereads.first?.totalWordsAcrossReads == 0)

        let library = ReadingLibraryInsights.make(
            works: [english, japanese, unreadJapanese],
            facts: periodFacts,
            periodInterval: monthInterval,
            calendar: calendar
        )
        #expect(library.unreadWords == 0)
        #expect(library.unreadWorksCount == 1)
        #expect(library.readWordsInPeriod == 10_000)
        #expect(library.addedWordsInPeriod == 10_000)

        let stats = ReadingStatistics(works: [english, japanese], now: now, calendar: calendar)
        #expect(stats.wordsRead == 10_000)

        let timeline = ReadingHistoryTimeline.make(
            scope: .month,
            containing: monthInterval.start,
            facts: periodFacts,
            calendar: calendar
        )
        #expect(timeline.wordsRead == 10_000)
        #expect(timeline.charactersRead == 20_000)
    }

    // MARK: - D3: 10% fallback & revised/shortened chapter handling

    @Test func chapterCountsValidateWithinTenPercentAndRejectCollapsedTOCsAndMismatchScaling() {
        let withinTolerance = SavedWork(title: "Close", author: "A")
        withinTolerance.chapterWordCounts = [1_000, 2_000]
        withinTolerance.wordCount = 3_150

        let beyondTolerance = SavedWork(title: "Off", author: "A")
        beyondTolerance.chapterWordCounts = [1_000, 1_000]
        beyondTolerance.wordCount = 5_000

        // Collapsed TOC: 1 entry [500] against AO3 "10/10" (50_000 words) must fall back to legacy.
        let collapsedTOC = SavedWork(title: "Collapsed", author: "A")
        collapsedTOC.chapterWordCounts = [500]
        collapsedTOC.chapters = "10/10"
        collapsedTOC.wordCount = 50_000

        // Stale 2-ch EPUB after AO3 grew to 5 chapters / 25_000 words: never multiply s2 by 12.5x.
        let staleWIP = SavedWork(title: "Stale WIP", author: "A")
        staleWIP.chapterWordCounts = [1_000, 1_000]
        staleWIP.chapters = "5/?"
        staleWIP.wordCount = 25_000

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
        let sCollapsed = ReadingSession(
            workID: collapsedTOC.id,
            startedAt: t0,
            endedAt: t0.addingTimeInterval(600),
            durationSeconds: 600,
            startProgress: 0,
            endingProgress: 0.5,
            wordCount: 50_000,
            chapterCountAtVisit: 10
        )
        let sStaleFirst = ReadingSession(
            workID: staleWIP.id,
            startedAt: t0,
            endedAt: t0.addingTimeInterval(600),
            durationSeconds: 600,
            startProgress: 0,
            endingProgress: 0.5,
            wordCount: 2_000,
            chapterCountAtVisit: 2
        )
        let sStaleRefreshed = ReadingSession(
            workID: staleWIP.id,
            startedAt: t0.addingTimeInterval(3_600),
            endedAt: t0.addingTimeInterval(4_200),
            durationSeconds: 600,
            startProgress: 0.5,
            endingProgress: 1.0,
            wordCount: 25_000,
            chapterCountAtVisit: 5
        )

        let read = ReadingLogService.wordsRead(
            sessions: [s1, s2, sCollapsed, sStaleFirst, sStaleRefreshed],
            works: [withinTolerance, beyondTolerance, collapsedTOC, staleWIP]
        )
        #expect(read[s1.id] == 1_000)
        #expect(read[s2.id] == 2_500)
        #expect(read[sCollapsed.id] == 25_000)
        #expect(read[sStaleFirst.id] == 1_000)
        #expect(read[sStaleRefreshed.id] == 1_000)
    }

    @Test func revisedShortenedAndLegacyZeroChapterCountNeverDoubleCountOrSpill() {
        // Case A: Revised Ch 2 (1000 -> 1500) + Ch 3 (1000).
        let revised = SavedWork(title: "Revised", author: "A")
        revised.chapterWordCounts = [1_000, 1_500, 1_000]
        revised.wordCount = 3_500
        revised.chapters = "3/?"
        let r1 = ReadingSession(
            workID: revised.id, startedAt: Date(timeIntervalSince1970: 1_000),
            endedAt: Date(timeIntervalSince1970: 2_000), durationSeconds: 1_000,
            startProgress: 0, endingProgress: 1.0, wordCount: 2_000,
            chapterCountAtVisit: 2, didFinish: true
        )
        let r2 = ReadingSession(
            workID: revised.id, startedAt: Date(timeIntervalSince1970: 3_000),
            endedAt: Date(timeIntervalSince1970: 3_600), durationSeconds: 600,
            startProgress: 1_000.0 / 3_500.0, endingProgress: 2_500.0 / 3_500.0,
            wordCount: 3_500, chapterCountAtVisit: 3
        )
        let r3 = ReadingSession(
            workID: revised.id, startedAt: Date(timeIntervalSince1970: 4_000),
            endedAt: Date(timeIntervalSince1970: 4_600), durationSeconds: 600,
            startProgress: 2_500.0 / 3_500.0, endingProgress: 1.0,
            wordCount: 3_500, chapterCountAtVisit: 3, didFinish: true
        )

        // Case B: Shortened already-read Ch 2 after finish ([1000, 1500] -> [1000, 800]).
        let shortenedAfterFinish = SavedWork(title: "Shortened Ch2", author: "A")
        shortenedAfterFinish.chapterWordCounts = [1_000, 800]
        shortenedAfterFinish.wordCount = 1_800
        shortenedAfterFinish.chapters = "2/2"
        let sf1 = ReadingSession(
            workID: shortenedAfterFinish.id, startedAt: Date(timeIntervalSince1970: 1_000),
            endedAt: Date(timeIntervalSince1970: 2_000), durationSeconds: 1_000,
            startProgress: 0, endingProgress: 1.0, wordCount: 2_500,
            chapterCountAtVisit: 2, didFinish: true
        )
        let sf2 = ReadingSession(
            workID: shortenedAfterFinish.id, startedAt: Date(timeIntervalSince1970: 3_000),
            endedAt: Date(timeIntervalSince1970: 3_600), durationSeconds: 600,
            startProgress: 1_000.0 / 1_800.0, endingProgress: 1.0, wordCount: 1_800,
            chapterCountAtVisit: 2
        )

        // Case C: Legacy session with `chapterCountAtVisit == 0` before Ch 3 posted.
        let legacyZeroCh = SavedWork(title: "Zero Ch", author: "A")
        legacyZeroCh.chapterWordCounts = [1_000, 1_000, 1_000]
        legacyZeroCh.wordCount = 3_000
        legacyZeroCh.chapters = "3/?"
        let lz1 = ReadingSession(
            workID: legacyZeroCh.id, startedAt: Date(timeIntervalSince1970: 1_000),
            endedAt: Date(timeIntervalSince1970: 2_000), durationSeconds: 1_000,
            startProgress: 0, endingProgress: 1.0, wordCount: 2_000,
            chapterCountAtVisit: 0, didFinish: true
        )
        let lz2 = ReadingSession(
            workID: legacyZeroCh.id, startedAt: Date(timeIntervalSince1970: 3_000),
            endedAt: Date(timeIntervalSince1970: 3_600), durationSeconds: 600,
            startProgress: 2_000.0 / 3_000.0, endingProgress: 1.0, wordCount: 3_000,
            chapterCountAtVisit: 3
        )

        // Case D: Shortened Ch 1 ([1000, 1000] -> [500, 1000, 1000]) must not spill into Ch 2.
        let shortenedEarly = SavedWork(title: "No Spill", author: "A")
        shortenedEarly.chapterWordCounts = [500, 1_000, 1_000]
        shortenedEarly.wordCount = 2_500
        shortenedEarly.chapters = "3/?"
        let se1 = ReadingSession(
            workID: shortenedEarly.id, startedAt: Date(timeIntervalSince1970: 1_000),
            endedAt: Date(timeIntervalSince1970: 1_600), durationSeconds: 600,
            startProgress: 0, endingProgress: 0.5, wordCount: 2_000,
            chapterCountAtVisit: 2
        )
        let se2 = ReadingSession(
            workID: shortenedEarly.id, startedAt: Date(timeIntervalSince1970: 2_000),
            endedAt: Date(timeIntervalSince1970: 3_200), durationSeconds: 1_200,
            startProgress: 500.0 / 2_500.0, endingProgress: 1.0, wordCount: 2_500,
            chapterCountAtVisit: 3
        )

        // Case E: Genuine full reread from 0.0 after a finished WIP gained Ch 3 still counts.
        let fullReread = SavedWork(title: "Full Reread", author: "A")
        fullReread.chapterWordCounts = [1_000, 1_000, 1_000]
        fullReread.wordCount = 3_000
        fullReread.chapters = "3/3"
        let fr1 = ReadingSession(
            workID: fullReread.id, startedAt: Date(timeIntervalSince1970: 1_000),
            endedAt: Date(timeIntervalSince1970: 2_000), durationSeconds: 1_000,
            startProgress: 0, endingProgress: 1.0, wordCount: 2_000,
            chapterCountAtVisit: 2, didFinish: true
        )
        let fr2 = ReadingSession(
            workID: fullReread.id, startedAt: Date(timeIntervalSince1970: 3_000),
            endedAt: Date(timeIntervalSince1970: 4_800), durationSeconds: 1_800,
            startProgress: 0.0, endingProgress: 1.0, wordCount: 3_000,
            chapterCountAtVisit: 3, didFinish: true
        )

        let read = ReadingLogService.wordsRead(
            sessions: [r1, r2, r3, sf1, sf2, lz1, lz2, se1, se2, fr1, fr2],
            works: [revised, shortenedAfterFinish, legacyZeroCh, shortenedEarly, fullReread]
        )
        #expect(read[r1.id] == 2_000)
        #expect(read[r2.id] == 0)
        #expect(read[r3.id] == 1_000)

        #expect(read[sf1.id] == 2_500)
        #expect(read[sf2.id] == 0)

        #expect(read[lz1.id] == 2_000)
        #expect(read[lz2.id] == 1_000)

        #expect(read[se1.id] == 1_000)
        #expect(read[se2.id] == 2_000)

        #expect(read[fr1.id] == 2_000)
        #expect(read[fr2.id] == 3_000)
    }

    /// Review 2 P2: an AO3 recount that drops a few words (a typo fix) must not turn a
    /// genuine reread into 0 words. Legacy counting and History both treat it as a reread.
    @Test func rereadAfterSmallWordCountDropStillCounts() {
        func sitting(
            _ work: SavedWork, at time: TimeInterval, start: Double?, end: Double = 1.0,
            words: Int, finish: Bool = true
        ) -> ReadingSession {
            ReadingSession(
                workID: work.id, startedAt: Date(timeIntervalSince1970: time),
                endedAt: Date(timeIntervalSince1970: time + 600), durationSeconds: 600,
                startProgress: start, endingProgress: end, wordCount: words,
                chapterCountAtVisit: 2, didFinish: finish
            )
        }
        func recounted(_ title: String) -> SavedWork {
            let work = SavedWork(title: title, author: "A")
            work.chapterWordCounts = [1_000, 990]
            work.wordCount = 1_990
            work.chapters = "2/2"
            return work
        }
        let fromZero = recounted("Reread from 0")
        let noStart = recounted("Reread, no recorded start")
        let partWay = recounted("Reread from chapter 2")
        let z1 = sitting(fromZero, at: 1_000, start: 0, words: 2_000)
        let z2 = sitting(fromZero, at: 5_000, start: 0, words: 1_990)
        let n1 = sitting(noStart, at: 1_000, start: 0, words: 2_000)
        let n2 = sitting(noStart, at: 5_000, start: nil, words: 1_990)
        let p1 = sitting(partWay, at: 1_000, start: 0, words: 2_000)
        let p2 = sitting(partWay, at: 5_000, start: 1_000.0 / 1_990.0, words: 1_990)

        let read = ReadingLogService.wordsRead(
            sessions: [z1, z2, n1, n2, p1, p2], works: [fromZero, noStart, partWay]
        )
        #expect(read[z1.id] == 1_990)
        #expect(read[z2.id] == 1_990)
        #expect(read[n2.id] == 1_990)
        // Under 10% shrink is a recount, not a revision: reading chapter 2 again counts.
        #expect(read[p2.id] == 990)
        // Legacy counting (no chapter counts) agrees on the from-0 and no-start rereads.
        let legacy = ReadingLogService.wordsRead(sessions: [z1, z2, n1, n2], works: [])
        #expect(legacy[z2.id] == 1_990)
        #expect(legacy[n2.id] == 1_990)
    }

    /// Review 2 P2: a finished work reopens at its end; the reader scrolls back to
    /// chapter 1 and rereads over later sittings. Those sittings must count, as legacy does.
    @Test func chapterModeRereadOpenedAtTheEndThenScrolledBackCounts() {
        let work = SavedWork(title: "Comfort Reread", author: "A")
        work.chapterWordCounts = [1_000, 1_000, 1_000]
        work.wordCount = 3_000
        work.chapters = "3/3"
        func sitting(at time: TimeInterval, start: Double, end: Double, finish: Bool = false) -> ReadingSession {
            ReadingSession(
                workID: work.id, startedAt: Date(timeIntervalSince1970: time),
                endedAt: Date(timeIntervalSince1970: time + 600), durationSeconds: 600,
                startProgress: start, endingProgress: end, wordCount: 3_000,
                chapterCountAtVisit: 3, didFinish: finish
            )
        }
        let s1 = sitting(at: 1_000, start: 0, end: 1.0, finish: true)
        let s2 = sitting(at: 5_000, start: 1.0, end: 0.3)
        let s3 = sitting(at: 9_000, start: 0.3, end: 0.6)
        let s4 = sitting(at: 13_000, start: 0.6, end: 1.0, finish: true)
        let s5 = sitting(at: 17_000, start: 0.2, end: 0.5)

        let read = ReadingLogService.wordsRead(sessions: [s1, s2, s3, s4, s5], works: [work])
        #expect(read[s1.id] == 3_000)
        #expect(read[s2.id] == 0)
        #expect(read[s3.id] == 900)
        #expect(read[s4.id] == 1_200)
        // A second reread straight after the next finish, started part-way in, also counts.
        #expect(read[s5.id] == 900)
        let legacy = ReadingLogService.wordsRead(sessions: [s1, s2, s3, s4, s5], works: [])
        #expect(legacy[s3.id] == read[s3.id])
        #expect(legacy[s4.id] == read[s4.id])
    }

    /// Review 3 P3 #10: a tiny positive AO3 word recount (+0.5%, same chapters) or a small
    /// forward nudge into end notes after a `< 1.0` finish must not zero out a scrolled-back reread.
    @Test func chapterModeRereadSurvivesTinyPositiveRecountAndEndNotesNudge() {
        let recounted = SavedWork(title: "Tiny Recount", author: "A")
        recounted.chapterWordCounts = [1_000, 1_010]
        recounted.wordCount = 2_010
        recounted.chapters = "2/2"
        let r1 = ReadingSession(
            workID: recounted.id, startedAt: Date(timeIntervalSince1970: 1_000),
            endedAt: Date(timeIntervalSince1970: 2_000), durationSeconds: 1_000,
            startProgress: 0, endingProgress: 1.0, wordCount: 2_000,
            chapterCountAtVisit: 2, didFinish: true
        )
        let r2 = ReadingSession(
            workID: recounted.id, startedAt: Date(timeIntervalSince1970: 3_000),
            endedAt: Date(timeIntervalSince1970: 3_100), durationSeconds: 100,
            startProgress: 1.0, endingProgress: 0.3, wordCount: 2_010,
            chapterCountAtVisit: 2, didFinish: false
        )
        let r3 = ReadingSession(
            workID: recounted.id, startedAt: Date(timeIntervalSince1970: 4_000),
            endedAt: Date(timeIntervalSince1970: 5_000), durationSeconds: 1_000,
            startProgress: 0.3, endingProgress: 1.0, wordCount: 2_010,
            chapterCountAtVisit: 2, didFinish: true
        )

        let endNotes = SavedWork(title: "End Notes Finish", author: "A")
        endNotes.chapterWordCounts = [1_000, 1_000]
        endNotes.wordCount = 2_000
        endNotes.chapters = "2/2"
        let e1 = ReadingSession(
            workID: endNotes.id, startedAt: Date(timeIntervalSince1970: 1_000),
            endedAt: Date(timeIntervalSince1970: 2_000), durationSeconds: 1_000,
            startProgress: 0, endingProgress: 0.95, wordCount: 2_000,
            chapterCountAtVisit: 2, didFinish: true
        )
        let e2 = ReadingSession(
            workID: endNotes.id, startedAt: Date(timeIntervalSince1970: 3_000),
            endedAt: Date(timeIntervalSince1970: 3_200), durationSeconds: 200,
            startProgress: 0.95, endingProgress: 0.99, wordCount: 2_000,
            chapterCountAtVisit: 2, didFinish: false
        )
        let e3 = ReadingSession(
            workID: endNotes.id, startedAt: Date(timeIntervalSince1970: 4_000),
            endedAt: Date(timeIntervalSince1970: 4_100), durationSeconds: 100,
            startProgress: 0.99, endingProgress: 0.2, wordCount: 2_000,
            chapterCountAtVisit: 2, didFinish: false
        )
        let e4 = ReadingSession(
            workID: endNotes.id, startedAt: Date(timeIntervalSince1970: 5_000),
            endedAt: Date(timeIntervalSince1970: 5_600), durationSeconds: 600,
            startProgress: 0.2, endingProgress: 0.6, wordCount: 2_000,
            chapterCountAtVisit: 2, didFinish: false
        )

        let read = ReadingLogService.wordsRead(
            sessions: [r1, r2, r3, e1, e2, e3, e4], works: [recounted, endNotes]
        )
        #expect(read[r3.id] == 1_407)
        #expect(read[e2.id] == 80)
        #expect(read[e4.id] == 800)
    }

    // MARK: - D4: Mode split, sub-15s guard, pause/finish preservation & speech wiring

    @Test func modeSwitchMidSittingSplitsDropsSub15sKeepsPausedAndPreservesFinish() throws {
        ReadingLogService.resetOpenSessionsForTests()
        let context = try makeContext()
        let work = SavedWork(title: "Mixed Sitting", author: "A")
        work.wordCount = 10_000
        context.insert(work)
        try context.save()

        let t0 = Date(timeIntervalSince1970: 100_000)
        ReadingLogService.startSession(for: work, now: t0)
        // Sub-15s pre-switch (5s) where finish flips: must NOT emit a <15s row and
        // must carry `wasFinishedAtStart` so the following >=15s segment records `didFinish`.
        ReadingLogService.noteActivity(for: work, now: t0.addingTimeInterval(5))
        work.isFinished = true
        ReadingLogService.setMode(
            .listen, for: work, playbackRate: 1.25, now: t0.addingTimeInterval(5)
        )
        ReadingLogService.noteActivity(for: work, now: t0.addingTimeInterval(35))
        work.readiumLocator = #"{"locations":{"totalProgression":0.4}}"#
        ReadingLogService.setMode(.read, for: work, now: t0.addingTimeInterval(35))
        ReadingLogService.noteActivity(for: work, now: t0.addingTimeInterval(65))
        work.readiumLocator = #"{"locations":{"totalProgression":0.8}}"#
        ReadingLogService.endSession(for: work, now: t0.addingTimeInterval(65))

        let rows = try context.fetch(
            FetchDescriptor<ReadingSession>(sortBy: [SortDescriptor(\.startedAt)])
        )
        #expect(rows.count == 2)
        #expect(rows[0].mode == .listen)
        #expect(rows[0].durationSeconds == 30)
        #expect(rows[0].didFinish)
        #expect(rows[1].mode == .read)
        #expect(rows[1].durationSeconds == 30)
        #expect(rows[1].startProgress == 0.4)
        #expect(!rows[1].didFinish)
        #expect(ReadingLogService.finishCount(of: work.id, in: context) == 1)

        // Switching mode while paused keeps the replacement segment paused.
        let t1 = Date(timeIntervalSince1970: 200_000)
        ReadingLogService.startSession(for: work, now: t1)
        ReadingLogService.pauseSession(for: work, now: t1.addingTimeInterval(20))
        ReadingLogService.setMode(.listen, for: work, playbackRate: 1.5, now: t1.addingTimeInterval(30))
        ReadingLogService.endSession(for: work, now: t1.addingTimeInterval(90))
        let allRows = try context.fetch(
            FetchDescriptor<ReadingSession>(sortBy: [SortDescriptor(\.startedAt)])
        )
        // Paused `.listen` segment had 0 active seconds -> dropped, only the 20s `.read` row saved.
        #expect(allRows.count == 3)
        #expect(allRows.last?.mode == .read)
        #expect(allRows.last?.durationSeconds == 20)
    }

    @Test func paceExcludesListeningUsingRealReadingSessionRows() {
        let work = SavedWork(title: "Mixed Pace", author: "A")
        work.wordCount = 20_000
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)

        let readRow = ReadingSession(
            workID: work.id,
            startedAt: t0,
            endedAt: t0.addingTimeInterval(1_800),
            durationSeconds: 1_800,
            startProgress: 0,
            modeRaw: "read",
            endingProgress: 0.5,
            wordCount: 20_000
        )
        let listenRow = ReadingSession(
            workID: work.id,
            startedAt: t0.addingTimeInterval(3_600),
            endedAt: t0.addingTimeInterval(7_200),
            durationSeconds: 3_600,
            startProgress: 0.5,
            modeRaw: "listen",
            endingProgress: 0.95,
            wordCount: 20_000,
            didFinish: false
        )

        #expect(ReadingLogService.wordsPerHour(sessions: [readRow, listenRow], works: [work]) == 20_000)
        #expect(ReadingLogService.wordsPerHour(sessions: [listenRow], works: [work]) == 0)

        let facts = ReadingLogService.facts(from: [readRow, listenRow], works: [work])
        let insights = ReadingInsights.make(facts: facts)
        #expect(insights.wordsPerHour == 20_000)
        #expect(insights.totalWordsRead == 19_000)
        #expect(insights.silentReadingSeconds == 1_800)
        #expect(insights.listeningSeconds == 3_600)
        #expect(insights.readingSeconds == 5_400)
    }
}

#if os(iOS)
extension InsightsD3D4Tests {
    @MainActor
    private final class StubTTSService: TTSService {
        var status: TTSServiceStatus = .stopped
        var spokenText: String = ""
        var speechEnergy: Double = 0
        var speechEnergySeed: Double = 0
        var availableVoices: [TTSVoice] = []
        var onStatusChange: ((TTSServiceStatus) -> Void)?
        var onSpokenTextChange: ((String) -> Void)?
        var onSpeechEnergyPulse: ((Double, Double) -> Void)?
        var onSpeechSpectrum: ((SpeechSpectrum) -> Void)?
        var onAudible: ((Locator) -> Void)?
        var onSpokenRange: ((Locator) -> Void)?

        var speakHandler: ([TTSSpeechUnit]) -> Bool = { _ in true }
        var speakCallCount = 0
        var resumeCallCount = 0
        var stopCallCount = 0

        func speak(units: [TTSSpeechUnit]) async throws -> Bool {
            speakCallCount += 1
            // Mirror real engines: resetPlayback(notifyStopped: false) before checking speakability.
            status = .stopped
            let started = speakHandler(units)
            if started {
                status = .playing
                onStatusChange?(.playing)
                if let first = units.first(where: \.hasSpeakableText) ?? units.first {
                    if let locator = first.locator {
                        onAudible?(locator)
                    }
                    spokenText = first.text
                    onSpokenTextChange?(first.text)
                }
            }
            return started
        }

        func pause() {
            guard status == .playing else { return }
            status = .paused
            onStatusChange?(.paused)
        }

        func resume() {
            resumeCallCount += 1
            guard status == .paused else { return }
            status = .playing
            onStatusChange?(.playing)
        }

        func stop() {
            stopCallCount += 1
            let wasStopped = status == .stopped
            status = .stopped
            if !wasStopped {
                onStatusChange?(.stopped)
            }
        }

        func setVoice(id _: String) {}
        func setRate(_: Float) {}
        func setPitch(_: Float) {}
    }

    private func chapterLocator(_ href: String) -> Locator {
        Locator(href: AnyURL(string: href)!, mediaType: .xhtml)
    }

    /// Review 2 P2, Review 3 P2 #6 & #8, T-535d: real `startSpeech` wiring. A finished
    /// chapter continues to the next *speakable* one, found inside the controller
    /// (the reader is never asked to move first), and only that chapter reaches the engine.
    @Test func startSpeechWiringAdvancesOverUnspeakableChapterWithoutTheReader() async throws {
        let engine = SystemTTSService()
        let symbolsOnly = [TTSSpeechUnit(text: "* * *  ♡  ~~~", locator: nil)]
        #expect(try await engine.speak(units: symbolsOnly) == false)
        #expect(engine.status == .stopped)

        // Ch 2 finishes while playing; Ch 3 is a scene break only; Ch 4 has prose.
        let stub = StubTTSService()
        stub.speakHandler = { units in units.contains { $0.text.contains("Prose") } }
        let locators = [1, 2, 3, 4].map { chapterLocator("ch\($0).xhtml") }
        var readerSkips = 0
        var pageMoves: [String] = []
        let controller = ReaderSpeechController()
        controller.seedSessionForTests(
            workID: UUID(),
            status: .playing,
            isReaderOpen: true,
            ttsService: stub,
            unitProvider: { locator in
                switch locator?.href.string {
                case "ch3.xhtml":
                    return [TTSSpeechUnit(text: "* * *", locator: locator)]
                case "ch4.xhtml":
                    return [TTSSpeechUnit(text: "Prose in chapter 4.", locator: locator)]
                default:
                    return []
                }
            },
            resumeLocator: locators[1],
            chapterStartLocators: locators,
            onSkipNext: { readerSkips += 1; return true }
        )
        controller.onAdvance = { pageMoves.append($0.href.string) }

        controller.handleEngineStatusChange(.stopped)
        await controller.waitForStartTaskForTests()
        #expect(readerSkips == 0)
        #expect(stub.speakCallCount == 1)
        #expect(pageMoves == ["ch4.xhtml"])
        #expect(controller.status == .playing)
        #expect(controller.resumeLocator?.href.string == "ch4.xhtml")

        // Nothing speakable after a finished last-but-one chapter: the session ends
        // quietly (end of book), no alert, and the page stays where it was.
        let endStub = StubTTSService()
        let end = ReaderSpeechController()
        var endMoves = 0
        end.seedSessionForTests(
            workID: UUID(), status: .playing, isReaderOpen: true,
            ttsService: endStub,
            unitProvider: { locator in [TTSSpeechUnit(text: "* * *", locator: locator)] },
            resumeLocator: locators[2], chapterStartLocators: locators
        )
        end.onAdvance = { _ in endMoves += 1 }
        end.handleEngineStatusChange(.stopped)
        await end.waitForStartTaskForTests()
        #expect(end.status == .stopped)
        #expect(endMoves == 0)
        #expect(endStub.speakCallCount == 0)
        #expect(!end.showsNothingToSpeakAlert)

        // A fresh Play where nothing is speakable to the end: stays `.stopped`, never
        // asks the reader to skip, never hands the engine anything, and says why.
        let idleStub = StubTTSService()
        let idle = ReaderSpeechController()
        var idleSkips = 0
        idle.seedSessionForTests(
            workID: UUID(), status: .stopped, isReaderOpen: true,
            ttsService: idleStub,
            unitProvider: { loc in [TTSSpeechUnit(text: "* * *", locator: loc)] },
            resumeLocator: locators[0], chapterStartLocators: locators,
            onSkipNext: { idleSkips += 1; return true }
        )
        idle.toggle(from: locators[0])
        await idle.waitForStartTaskForTests()
        #expect(idle.status == .stopped)
        #expect(idleSkips == 0)
        #expect(idleStub.speakCallCount == 0)
        #expect(idle.showsNothingToSpeakAlert)
    }

    /// Review 3 P2 #6, T-535d: a paused skip onto an unspeakable chapter with nothing
    /// speakable beyond it leaves the paused session exactly where it was (engine
    /// untouched), so Play resumes it. Never wedged, never a dead button.
    @Test func pausedReanchorOntoUnspeakableChapterStaysPausedWhereItWas() async throws {
        let locators = [1, 2, 3, 4].map { chapterLocator("ch\($0).xhtml") }
        for chapterThree in [[TTSSpeechUnit(text: "* * *", locator: locators[2])], []] {
            let pausedStub = StubTTSService()
            pausedStub.status = .paused
            let controller = ReaderSpeechController()
            controller.seedSessionForTests(
                workID: UUID(), status: .paused, isReaderOpen: true,
                ttsService: pausedStub,
                unitProvider: { locator in
                    locator?.href.string == "ch2.xhtml"
                        ? [TTSSpeechUnit(text: "Prose in chapter 2.", locator: locator)]
                        : chapterThree
                },
                resumeLocator: locators[1],
                chapterStartLocators: Array(locators.prefix(3))
            )
            controller.reanchor(to: locators[2], resumePlaying: false)
            await controller.waitForStartTaskForTests()
            #expect(controller.status == .paused)
            #expect(pausedStub.status == .paused)
            #expect(pausedStub.speakCallCount == 0)
            #expect(controller.resumeLocator?.href.string == "ch2.xhtml")
            #expect(controller.showsNothingToSpeakAlert)

            controller.toggle(from: nil)
            #expect(pausedStub.resumeCallCount == 1)
            #expect(controller.status == .playing)
        }
    }

    @Test func readSpeechControllerAutoAdvanceDetachedReopenBackgroundAndAudition() async throws {
        ReadingLogService.resetOpenSessionsForTests()
        let context = try makeContext()
        let work = SavedWork(title: "Speech Wired", author: "A")
        context.insert(work)
        try context.save()

        var clock = Date(timeIntervalSince1970: 300_000)
        var isBackgrounded = false
        let controller = ReaderSpeechController()
        controller.onStatusTransition = { _, newStatus, isReaderOpen in
            let state: ReadingLogService.DetachedSpeechState = switch newStatus {
            case .playing: .playing
            case .paused: .paused
            case .stopped, .unavailable: .stopped
            }
            ReadingLogService.handleSpeechStatusChange(
                state,
                isReaderOpen: isReaderOpen,
                isBackgrounded: isBackgrounded,
                for: work,
                playbackRate: 1.25,
                now: clock
            )
        }

        let stub = StubTTSService()
        let chapters = [1, 2].map { chapterLocator("ch\($0).xhtml") }
        controller.seedSessionForTests(
            workID: work.id,
            status: .playing,
            isReaderOpen: true,
            ttsService: stub,
            resumeLocator: chapters[0],
            chapterStartLocators: chapters
        )
        ReadingLogService.handleReaderOpen(
            for: work,
            isSpeechPlaying: controller.status == .playing,
            isSpeechStopped: false,
            playbackRate: 1.25,
            now: clock
        )

        // Chapter 1 finishes in 10s (<15s) and auto-advances to Chapter 2 -> MUST NOT
        // flip status to `.stopped`, drop the <15s chapter, or split the sitting.
        clock = clock.addingTimeInterval(10)
        controller.handleEngineStatusChange(.stopped)
        #expect(controller.status == .playing)
        #expect(ReadingLogService.openSessionMode(for: work.id) == .listen)

        // Background pause routed through the controller must flush/pause synchronously.
        clock = clock.addingTimeInterval(20)
        isBackgrounded = true
        controller.handleEngineStatusChange(.paused)
        isBackgrounded = false
        let flushed = try context.fetch(FetchDescriptor<ReadingSession>())
        #expect(flushed.count == 1)
        #expect(flushed.first?.mode == .listen)
        #expect(flushed.first?.durationSeconds == 30)

        // Real `audition(text:)` while a detached session exists must keep `isAuditioning`
        // active after `speak()` returns until `.stopped` arrives, so it never ends the log sitting.
        controller.seedSessionForTests(
            workID: work.id, status: .paused, isReaderOpen: false, ttsService: stub
        )
        controller.audition(text: "Voice sample")
        await controller.waitForStartTaskForTests()
        controller.handleEngineStatusChange(.stopped)
        #expect(ReadingLogService.hasOpenSession(for: work.id))

        // Re-opening reader while detached Read Aloud is `.paused` must resume tracking.
        clock = clock.addingTimeInterval(60)
        ReadingLogService.handleReaderOpen(
            for: work, isSpeechPlaying: false, isSpeechStopped: false,
            playbackRate: 1.25, now: clock
        )
        clock = clock.addingTimeInterval(40)
        ReadingLogService.noteActivity(for: work, now: clock)

        // Last chapter ends (no chapter after it) while open -> splits back to `.read`.
        controller.seedSessionForTests(
            workID: work.id, status: .playing, isReaderOpen: true, ttsService: stub,
            resumeLocator: chapters[1], chapterStartLocators: chapters
        )
        controller.handleEngineStatusChange(.stopped)
        #expect(controller.status == .stopped)
        #expect(ReadingLogService.openSessionMode(for: work.id) == .read)

        clock = clock.addingTimeInterval(25)
        ReadingLogService.endSession(for: work, now: clock)
        let finalRows = try context.fetch(
            FetchDescriptor<ReadingSession>(sortBy: [SortDescriptor(\.startedAt)])
        )
        #expect(finalRows.count == 2)
        #expect(finalRows[0].mode == .listen)
        #expect(finalRows[0].durationSeconds == 70)
        #expect(finalRows[1].mode == .read)
        #expect(finalRows[1].durationSeconds == 25)
    }
}
#endif
