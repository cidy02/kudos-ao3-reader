import Foundation
import Testing
@testable import Kudos

/// Shared fixtures for Writing Studio board copy regression tests (T-507).
/// Plain values only: no network, no AO3, no view host.
private enum StudioBoardCopyFixtures {
    static let enUS = Locale(identifier: "en_US")

    static let utcCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        calendar.firstWeekday = 2 // Monday
        calendar.minimumDaysInFirstWeek = 4
        return calendar
    }()

    static func utcDate(
        _ year: Int, _ month: Int, _ day: Int, hour: Int = 12, minute: Int = 0
    ) -> Date {
        let components = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)
        return utcCalendar.date(from: components) ?? .distantPast
    }

    static func makeAO3Work(
        id: Int,
        title: String,
        words: Int? = 2000,
        chapters: String = "1/1",
        isComplete: Bool? = true,
        dateUpdated: String = "2026-10-20",
        fandoms: [String] = ["Harbour Lights"]
    ) -> AO3WorkSummary {
        AO3WorkSummary(
            id: id,
            title: title,
            authors: ["saltwindow"],
            fandoms: fandoms,
            rating: "General Audiences",
            warnings: ["No Archive Warnings Apply"],
            categories: ["Gen"],
            isComplete: isComplete,
            dateUpdated: dateUpdated,
            tags: [],
            summary: "",
            language: "English",
            words: words,
            chapters: chapters,
            comments: nil,
            kudos: nil,
            hits: nil,
            seriesTitle: nil,
            seriesURL: nil,
            seriesPosition: nil
        )
    }

    static func makeChapter(
        title: String,
        status: WritingChapterStatus,
        wordCount: Int,
        ao3ChapterID: Int?,
        updatedAt: Date
    ) -> WritingChapter {
        WritingChapter(
            id: UUID(),
            title: title,
            summary: "",
            notesBefore: "",
            notesAfter: "",
            ao3ChapterID: ao3ChapterID,
            status: status,
            wordCount: wordCount,
            bodySavedAt: updatedAt,
            updatedAt: updatedAt,
            updatedBy: "test"
        )
    }

    static func makeInboxItem(
        id: Int,
        workID: Int?,
        isUnread: Bool,
        isReplied: Bool,
        canReply: Bool = true,
        isUnavailable: Bool = false
    ) -> AO3InboxItem {
        AO3InboxItem(
            id: id,
            commenterName: "quietharbor",
            isGuest: false,
            isAnonymousCreator: false,
            commenterIdentity: nil,
            avatarURL: nil,
            subjectTitle: workID == nil ? "AO3 News" : "Chapter 3 of What the Tide Keeps",
            subjectURL: nil,
            workID: workID,
            excerpt: "Thank you for this chapter.",
            postedAgo: "yesterday",
            isUnread: isUnread,
            isReplied: isReplied,
            canReply: canReply,
            bulkSelectionField: nil,
            isUnavailable: isUnavailable
        )
    }
}

/// Regression tests for `Studio-Overview` and `Studio-Offline` copy and dates.
@MainActor
struct StudioOverviewBoardCopyTests {
    @Test func dateCopyMatchesBoardShortDatesAndEditedPhrases() {
        let now = StudioBoardCopyFixtures.utcDate(2026, 10, 31, hour: 10, minute: 30)
        let cal = StudioBoardCopyFixtures.utcCalendar
        let locale = StudioBoardCopyFixtures.enUS

        let sameDay = StudioBoardCopyFixtures.utcDate(2026, 10, 31, hour: 10, minute: 10)
        let yesterday = StudioBoardCopyFixtures.utcDate(2026, 10, 30, hour: 23, minute: 10)
        let earlierSameYear = StudioBoardCopyFixtures.utcDate(2026, 10, 2, hour: 9, minute: 0)
        let priorYear = StudioBoardCopyFixtures.utcDate(2025, 10, 2, hour: 9, minute: 0)

        #expect(StudioDateCopy.shortDate(sameDay, now: now, calendar: cal, locale: locale) == "today")
        #expect(StudioDateCopy.shortDate(yesterday, now: now, calendar: cal, locale: locale) == "yesterday")
        #expect(StudioDateCopy.shortDate(earlierSameYear, now: now, calendar: cal, locale: locale) == "Oct 2")
        #expect(StudioDateCopy.shortDate(priorYear, now: now, calendar: cal, locale: locale) == "Oct 2, 2025")

        #expect(StudioDateCopy.shortAO3Date("2026-10-20", now: now, calendar: cal, locale: locale) == "Oct 20")
        #expect(StudioDateCopy.shortAO3Date("2025-10-20", now: now, calendar: cal, locale: locale) == "Oct 20, 2025")

        #expect(StudioDateCopy.editedPhrase(sameDay, now: now, calendar: cal, locale: locale) == "edited 20 min ago")
        let expectedTime = yesterday.formatted(
            Date.FormatStyle(calendar: cal, timeZone: cal.timeZone).locale(locale).hour().minute()
        )
        #expect(
            StudioDateCopy.editedPhrase(yesterday, now: now, calendar: cal, locale: locale)
                == "edited yesterday, \(expectedTime)"
        )
        #expect(
            StudioDateCopy.editedPhrase(earlierSameYear, now: now, calendar: cal, locale: locale)
                == "edited Oct 2"
        )
    }

    @Test func todayContinueAndOverviewGlanceCopyMatchesBoards() {
        let cal = StudioBoardCopyFixtures.utcCalendar
        let locale = StudioBoardCopyFixtures.enUS

        #expect(StudioTodayCopy.subtitle(dailyGoal: 500, streak: 6) == "of your 500-word goal · 6-day streak")
        #expect(StudioTodayCopy.subtitle(dailyGoal: nil, streak: 0) == "Daily goal off")
        #expect(
            StudioTodayCopy.accessibilityLabel(wordsToday: 380, dailyGoal: 500, streak: 6)
                == "Today: 380 words, of your 500-word goal, 76 percent, 6-day streak"
        )
        #expect(
            StudioTodayCopy.accessibilityLabel(wordsToday: 1, dailyGoal: nil, streak: 0)
                == "Today: 1 word, daily goal off"
        )

        #expect(StudioContinueCopy.expiryLine(daysLeft: 0) == "AO3 deletes this draft today")
        #expect(StudioContinueCopy.expiryLine(daysLeft: 1) == "AO3 keeps this draft 1 more day")
        #expect(StudioContinueCopy.expiryLine(daysLeft: 22) == "AO3 keeps this draft 22 more days")

        #expect(StudioOverviewCopy.commentsSubtitle(awaitingReplyCount: 1, unreadCount: 5) == "1 needs a reply")
        #expect(StudioOverviewCopy.commentsSubtitle(awaitingReplyCount: 3, unreadCount: 5) == "3 need a reply")
        #expect(StudioOverviewCopy.commentsSubtitle(awaitingReplyCount: 0, unreadCount: 2) == "2 unread")
        #expect(StudioOverviewCopy.commentsSubtitle(awaitingReplyCount: 0, unreadCount: 0) == "All caught up")

        let nov19 = StudioBoardCopyFixtures.utcDate(2026, 11, 19)
        let allYears = StudioOverviewCopy.statsSubtitle(baselineDate: nil, calendar: cal, locale: locale)
        let sinceDate = StudioOverviewCopy.statsSubtitle(baselineDate: nov19, calendar: cal, locale: locale)
        #expect(allYears == "All Years")
        #expect(sinceDate == "since Nov 19")

        #expect(StudioOverviewCopy.statsGlanceValue(total: 380, change: 38) == "+38")
        #expect(StudioOverviewCopy.statsGlanceValue(total: 380, change: 0) == "0")
        #expect(StudioOverviewCopy.statsGlanceValue(total: 380, change: nil) == "380")
    }
}

/// Regression tests for `Studio-Documents`, `Studio-Files`, and `Studio-Work-Files` copy.
@MainActor
struct StudioDocumentsAndFilesBoardCopyTests {
    @Test func documentsRecentMetaLinesMatchBoard() {
        let now = StudioBoardCopyFixtures.utcDate(2026, 10, 31)
        let yesterday = StudioBoardCopyFixtures.utcDate(2026, 10, 30)
        let oct25 = StudioBoardCopyFixtures.utcDate(2026, 10, 25)
        let oct20 = StudioBoardCopyFixtures.utcDate(2026, 10, 20)

        let postedChapter = StudioBoardCopyFixtures.makeChapter(
            title: "Spring Tide", status: .posted, wordCount: 2_170, ao3ChapterID: 3, updatedAt: oct20
        )
        let draftChapter = StudioBoardCopyFixtures.makeChapter(
            title: "Slack Water", status: .ao3Draft, wordCount: 1_240, ao3ChapterID: 4, updatedAt: yesterday
        )
        let localChapter = StudioBoardCopyFixtures.makeChapter(
            title: "Saltwater Letters", status: .local, wordCount: 640, ao3ChapterID: nil, updatedAt: oct25
        )
        let draftWork = WritingWork(
            id: UUID(),
            title: "What the Tide Keeps",
            ao3WorkID: 101,
            createdAt: oct20,
            updatedAt: yesterday,
            updatedBy: "test",
            chapterOrder: [draftChapter.id]
        )
        let postedWork = WritingWork(
            id: UUID(),
            title: "Lantern Season",
            ao3WorkID: 102,
            createdAt: oct20,
            updatedAt: oct20,
            updatedBy: "test",
            chapterOrder: [postedChapter.id]
        )
        let looseWork = WritingWork(
            id: UUID(),
            title: "Saltwater Letters",
            ao3WorkID: nil,
            createdAt: oct25,
            updatedAt: oct25,
            updatedBy: "test",
            chapterOrder: [localChapter.id]
        )

        let snapshot = StudioDocumentsCatalog.build(
            localWorks: [
                StudioLocalWorkSnapshot(work: draftWork, chapters: [draftChapter]),
                StudioLocalWorkSnapshot(work: postedWork, chapters: [postedChapter]),
                StudioLocalWorkSnapshot(work: looseWork, chapters: [localChapter])
            ],
            ao3PostedWorks: [],
            ao3DraftWorks: [],
            deviceName: "iPhone",
            now: now,
            calendar: StudioBoardCopyFixtures.utcCalendar,
            locale: StudioBoardCopyFixtures.enUS
        )
        let metas = Dictionary(uniqueKeysWithValues: snapshot.recent.map { ($0.title, $0.metaLine) })
        #expect(metas["Slack Water"] == "\(1_240.formatted()) words · yesterday")
        #expect(metas["Saltwater Letters"] == "640 words · Oct 25")
        #expect(metas["Spring Tide"] == "\(2_170.formatted()) words · posted Oct 20")
    }

    @Test func featuredManuscriptChapterStatusLinesMatchBoard() {
        let now = StudioBoardCopyFixtures.utcDate(2026, 10, 31)
        let yesterday = StudioBoardCopyFixtures.utcDate(2026, 10, 30)
        let sep3 = StudioBoardCopyFixtures.utcDate(2026, 9, 3)
        let cal = StudioBoardCopyFixtures.utcCalendar
        let locale = StudioBoardCopyFixtures.enUS

        #expect(
            StudioFeaturedManuscriptCopy.chapterStatusLine(
                badge: .posted, updatedAt: sep3, ao3DraftDaysLeft: nil,
                deviceName: "iPhone", now: now, calendar: cal, locale: locale
            ) == "Posted Sep 3"
        )
        #expect(
            StudioFeaturedManuscriptCopy.chapterStatusLine(
                badge: .ao3Draft, updatedAt: yesterday, ao3DraftDaysLeft: 22,
                deviceName: "iPhone", now: now, calendar: cal, locale: locale
            ) == "Draft · edited yesterday · AO3 keeps it 22 more days"
        )
        #expect(
            StudioFeaturedManuscriptCopy.chapterStatusLine(
                badge: .onDevice, updatedAt: yesterday, ao3DraftDaysLeft: nil,
                deviceName: "iPhone", now: now, calendar: cal, locale: locale
            ) == "On this iPhone · edited yesterday"
        )
        #expect(
            StudioFeaturedManuscriptCopy.chapterStatusLine(
                badge: .planned, updatedAt: yesterday, ao3DraftDaysLeft: nil,
                deviceName: "iPhone", now: now, calendar: cal, locale: locale
            ) == "Planned"
        )
    }

    @Test func filesRecentlyDeletedAndWorkHeaderStateLinesMatchBoards() {
        let now = StudioBoardCopyFixtures.utcDate(2026, 10, 31)
        let cal = StudioBoardCopyFixtures.utcCalendar
        let locale = StudioBoardCopyFixtures.enUS

        #expect(StudioRecentlyDeletedHelper.rowSubtitle(count: 0) == "Empty · kept for 30 days")
        #expect(StudioRecentlyDeletedHelper.rowSubtitle(count: 1) == "1 document · kept for 30 days")
        #expect(StudioRecentlyDeletedHelper.rowSubtitle(count: 3) == "3 documents · kept for 30 days")

        let inProgressItem = StudioWorkItem(
            id: "ao3:101",
            localWork: nil,
            localChapters: [],
            storyNotes: [],
            chapterExcerpts: [:],
            ao3PostedWork: StudioBoardCopyFixtures.makeAO3Work(
                id: 101,
                title: "What the Tide Keeps",
                words: 9_800,
                chapters: "3/8",
                isComplete: false,
                dateUpdated: "2026-10-20"
            ),
            ao3DraftWork: nil,
            ao3DraftDaysLeft: nil
        )
        #expect(
            inProgressItem.workFilesStateLine(
                deviceName: "iPhone", now: now, calendar: cal, locale: locale
            ) == "In progress · 3 of 8 posted · \(9_800.formatted()) words · last posted Oct 20"
        )

        let completeItem = StudioWorkItem(
            id: "ao3:202",
            localWork: nil,
            localChapters: [],
            storyNotes: [],
            chapterExcerpts: [:],
            ao3PostedWork: StudioBoardCopyFixtures.makeAO3Work(
                id: 202,
                title: "Keeper of the Northern Light",
                words: 22_410,
                chapters: "7/7",
                isComplete: true,
                dateUpdated: "2026-10-15"
            ),
            ao3DraftWork: nil,
            ao3DraftDaysLeft: nil
        )
        #expect(
            completeItem.workFilesStateLine(
                deviceName: "iPhone", now: now, calendar: cal, locale: locale
            ) == "Complete · 7 chapters · \(22_410.formatted()) words · last posted Oct 15"
        )
    }

    @Test func workFilesChapterNoteAndDetailsMetaLinesMatchBoard() {
        let now = StudioBoardCopyFixtures.utcDate(2026, 10, 31)
        let yesterday = StudioBoardCopyFixtures.utcDate(2026, 10, 30)
        let cal = StudioBoardCopyFixtures.utcCalendar
        let locale = StudioBoardCopyFixtures.enUS

        let postedChapter = StudioWorkChapterItem(
            id: "ch-1", position: 1, title: "Low Water", badge: .posted,
            wordCount: 2_980, dateText: "2026-09-03", updatedAt: nil,
            localWorkID: nil, localChapterID: nil, ao3WorkID: 101, ao3ChapterID: 1
        )
        #expect(
            postedChapter.metaLine(now: now, calendar: cal, locale: locale)
                == "\(2_980.formatted()) words · Sep 3"
        )

        let draftChapter = StudioWorkChapterItem(
            id: "ch-4", position: 4, title: "Slack Water", badge: .ao3Draft,
            wordCount: 1_240, dateText: nil, updatedAt: yesterday,
            localWorkID: UUID(), localChapterID: UUID(), ao3WorkID: 101, ao3ChapterID: 4
        )
        #expect(
            draftChapter.metaLine(now: now, calendar: cal, locale: locale)
                == "\(1_240.formatted()) words · edited yesterday"
        )

        let plannedChapter = StudioWorkChapterItem(
            id: "ch-5", position: 5, title: "", badge: .planned,
            wordCount: 0, dateText: nil, updatedAt: nil,
            localWorkID: UUID(), localChapterID: UUID(), ao3WorkID: 101, ao3ChapterID: nil
        )
        #expect(plannedChapter.metaLine(now: now, calendar: cal, locale: locale) == "Planned")

        let note = WritingStoryNote(
            id: UUID(),
            kind: .character,
            name: "Ines's family",
            detail: "Boatbuilder from Harbour Lights.",
            pinned: false,
            updatedAt: yesterday,
            updatedBy: "test"
        )
        let noteMeta = StudioWorkFilesLogic.storyNoteMetaLine(note: note, deviceName: "iPhone")
        #expect(noteMeta == "Character · 4 words · iPhone")

        #expect(
            StudioWorkFilesLogic.workDetailsSubtitle(
                postedDateText: "2026-10-20", isAO3Draft: false,
                now: now, calendar: cal, locale: locale
            ) == "Summary, tags, rating, notes · as posted Oct 20"
        )
        #expect(
            StudioWorkFilesLogic.workDetailsSubtitle(
                postedDateText: nil, isAO3Draft: true,
                now: now, calendar: cal, locale: locale
            ) == "Summary, tags, rating, notes · AO3 draft"
        )
    }
}

/// Regression tests for `Studio-Select`, `Studio-Comments`, and `Studio-Stats` copy.
@MainActor
struct StudioSelectCommentsAndStatsBoardCopyTests {
    @Test func selectFooterSummaryMatchesBoardWording() {
        let posted1 = StudioWorkItem(
            id: "ao3:1", localWork: nil, localChapters: [], storyNotes: [], chapterExcerpts: [:],
            ao3PostedWork: StudioBoardCopyFixtures.makeAO3Work(id: 1, title: "What the Tide Keeps"),
            ao3DraftWork: nil, ao3DraftDaysLeft: nil
        )
        let posted2 = StudioWorkItem(
            id: "ao3:2", localWork: nil, localChapters: [], storyNotes: [], chapterExcerpts: [:],
            ao3PostedWork: StudioBoardCopyFixtures.makeAO3Work(id: 2, title: "Lantern Season"),
            ao3DraftWork: nil, ao3DraftDaysLeft: nil
        )
        let draft = StudioWorkItem(
            id: "ao3:3", localWork: nil, localChapters: [], storyNotes: [], chapterExcerpts: [:],
            ao3PostedWork: nil,
            ao3DraftWork: StudioBoardCopyFixtures.makeAO3Work(id: 3, title: "Keeper of the Northern Light"),
            ao3DraftDaysLeft: 12
        )
        let capabilities = StudioSelectPolicy.evaluate(selected: [posted1, posted2, draft], isSignedIn: true)
        #expect(
            capabilities.summaryText(deviceName: "iPhone")
                == "2 posted works and 1 AO3 draft · Edit Together changes them all at once on AO3"
        )
    }

    @Test func commentsBoardSupportsUnreadChipCountsAndEmptyState() {
        #expect(StudioCommentsChip.allCases == [.needsReply, .unread, .all, .byWork])
        #expect(StudioCommentsChip.unread.title == "Unread")

        let items = [
            StudioBoardCopyFixtures.makeInboxItem(id: 1, workID: 10, isUnread: true, isReplied: false),
            StudioBoardCopyFixtures.makeInboxItem(id: 2, workID: 10, isUnread: true, isReplied: true),
            StudioBoardCopyFixtures.makeInboxItem(id: 3, workID: 11, isUnread: false, isReplied: false),
            StudioBoardCopyFixtures.makeInboxItem(id: 4, workID: nil, isUnread: true, isReplied: false),
            StudioBoardCopyFixtures.makeInboxItem(
                id: 5, workID: 12, isUnread: true, isReplied: false, isUnavailable: true
            )
        ]

        #expect(StudioCommentsBoard.needsReplyCount(items) == 2)
        #expect(StudioCommentsBoard.unreadCount(items) == 2)
        #expect(StudioCommentsBoard.allWorkCommentsCount(items) == 3)
        #expect(StudioCommentsBoard.comments(items, chip: .unread).map(\.id) == [1, 2])
        #expect(StudioCommentsBoard.emptyMessage(chip: .unread, totalPages: 1) == "No unread comments.")
        #expect(StudioCommentsBoard.emptyMessage(chip: .unread, totalPages: 2) == "No unread comments on this page.")
    }

    @Test func statsAxisLabelsAndTableFormattingMatchBoard() {
        let cal = StudioBoardCopyFixtures.utcCalendar
        let locale = StudioBoardCopyFixtures.enUS
        let start = StudioBoardCopyFixtures.utcDate(2026, 9, 7, hour: 0)
        let twelveWeeks: [StudioStatsWeek] = (0..<12).compactMap { offset in
            guard let date = cal.date(byAdding: .weekOfYear, value: offset, to: start) else { return nil }
            return StudioStatsWeek(start: date, gain: 10 + offset, isEstimate: false)
        }
        let now = StudioBoardCopyFixtures.utcDate(2026, 11, 26)
        let labels = StudioStatsHistory.axisLabels(
            for: twelveWeeks, now: now, calendar: cal, locale: locale
        )
        #expect(labels == ["Sep 7", "Oct 5", "Nov 2", "This week"])
        #expect(StudioStatsHistory.axisLabels(for: [], now: now, calendar: cal, locale: locale).isEmpty)

        #expect(StudioStatsWorksFormatting.figureText(19_200, metric: .hits, locale: locale) == "19.2k")
        #expect(StudioStatsWorksFormatting.figureText(850, metric: .hits, locale: locale) == "850")
        #expect(StudioStatsWorksFormatting.figureText(1_804, metric: .kudos, locale: locale) == "1,804")
        #expect(StudioStatsWorksFormatting.figureText(nil, metric: .comments, locale: locale) == "–")

        let oneWordWork = AO3UserStats.Work(
            id: 42,
            title: "Drabble",
            fandoms: ["Harbour Lights"],
            wordCount: 1,
            hits: 100,
            kudos: 10,
            commentThreads: 1,
            bookmarks: 0,
            subscriptions: 0,
            sourceOrder: 0
        )
        #expect(StudioStatsWorksFormatting.workMeta(oneWordWork) == "Harbour Lights · 1 word")
    }
}
