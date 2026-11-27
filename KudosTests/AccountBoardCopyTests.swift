import Foundation
import Testing
@testable import Kudos

/// Pins the copy and row-meta helpers aligned to `Account-Sheet.dc.html` and `Author.dc.html`
/// (T-507 Account & Author detail sweep) so the boards' wording does not drift.
@MainActor
struct AccountBoardCopyTests {
    private static let usLocale = Locale(identifier: "en_US")
    private static var gmtCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
    }

    @Test func accountSheetSignedOutAndSectionCopy() {
        #expect(AccountSheetCopy.signedOutTitle == "Not logged in")
        #expect(
            AccountSheetCopy.signedOutSubtitle(deviceName: "iPhone")
                == "Your library and reading stay on this iPhone either way."
        )
        #expect(
            AccountSheetCopy.signedOutSubtitle(deviceName: "Mac")
                == "Your library and reading stay on this Mac either way."
        )
        #expect(AccountSheetCopy.signedOutLoginTitle == "Log In to AO3")
        #expect(AccountSheetCopy.signedOutLoggingInTitle == "Logging In…")
        #expect(AccountSheetCopy.onAO3SectionTitle == "On AO3")
        #expect(AccountSheetCopy.kudosSectionTitle == "Kudos")
        #expect(AccountSheetCopy.openAO3Title == "Open AO3 in Kudos")
        #expect(AccountSheetCopy.aboutKudosTitle == "About Kudos")
        #expect(AccountSheetCopy.editProfileAccessibilityLabel == "Edit your profile on AO3")
        #expect(AccountSheetCopy.accountCountsAccessibilityLabel == "Your AO3 account")
        #expect(
            AccountSheetCopy.sessionFootnote(deviceName: "iPhone")
                == "Logged in to archiveofourown.org. Kudos keeps the session on this iPhone only."
        )
        #expect(
            AccountSheetCopy.sessionFootnote(deviceName: "iPad")
                == "Logged in to archiveofourown.org. Kudos keeps the session on this iPad only."
        )
        #expect(AccountSheetCopy.inboxHeaderAccessibilityLabel(unreadCount: 3) == "Inbox, 3 unread")
        #expect(AccountSheetCopy.inboxHeaderAccessibilityLabel(unreadCount: 0) == "Inbox")
        #expect(AccountSheetCopy.inboxHeaderAccessibilityLabel(unreadCount: nil) == "Inbox")
        #expect(AccountSheetCopy.inboxUnreadAccessibilityValue(3) == "3 unread")
        #expect(AccountSheetCopy.inboxUnreadAccessibilityValue(0) == nil)
        #expect(AccountSheetCopy.inboxUnreadAccessibilityValue(nil) == nil)
    }

    @Test func backupSyncDetailReflectsFolderSyncState() throws {
        let calendar = Self.gmtCalendar
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 27)))
        let sameYear = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 21)))
        let priorYear = try #require(calendar.date(from: DateComponents(year: 2025, month: 10, day: 21)))

        let disconnected = FolderSyncSnapshot(
            isConnected: false, folderDisplayName: "", folderPath: "",
            lastSyncAt: sameYear, lastError: "", isDirty: false, autoSyncEnabled: true
        )
        #expect(
            AccountSheetCopy.backupSyncDetail(disconnected, now: now, calendar: calendar, locale: Self.usLocale) == nil
        )

        let errored = FolderSyncSnapshot(
            isConnected: true, folderDisplayName: "Sync", folderPath: "/Sync",
            lastSyncAt: sameYear, lastError: "Disk full", isDirty: true, autoSyncEnabled: true
        )
        #expect(
            AccountSheetCopy.backupSyncDetail(errored, now: now, calendar: calendar, locale: Self.usLocale) == "Error"
        )

        let syncedSameYear = FolderSyncSnapshot(
            isConnected: true, folderDisplayName: "Sync", folderPath: "/Sync",
            lastSyncAt: sameYear, lastError: "", isDirty: false, autoSyncEnabled: true
        )
        let expectedSameYear = sameYear.formatted(
            Date.FormatStyle(locale: Self.usLocale, calendar: calendar, timeZone: calendar.timeZone)
                .month(.abbreviated)
                .day()
        )
        #expect(
            AccountSheetCopy.backupSyncDetail(syncedSameYear, now: now, calendar: calendar, locale: Self.usLocale)
                == expectedSameYear
        )

        let syncedPriorYear = FolderSyncSnapshot(
            isConnected: true, folderDisplayName: "Sync", folderPath: "/Sync",
            lastSyncAt: priorYear, lastError: "", isDirty: false, autoSyncEnabled: true
        )
        #expect(
            AccountSheetCopy.backupSyncDetail(syncedPriorYear, now: now, calendar: calendar, locale: Self.usLocale)
                == WorkStat.displayDate(priorYear, locale: Self.usLocale, timeZone: calendar.timeZone)
        )

        let pendingOn = FolderSyncSnapshot(
            isConnected: true, folderDisplayName: "Sync", folderPath: "/Sync",
            lastSyncAt: nil, lastError: "", isDirty: false, autoSyncEnabled: true
        )
        #expect(
            AccountSheetCopy.backupSyncDetail(pendingOn, now: now, calendar: calendar, locale: Self.usLocale) == "On"
        )

        let pendingPaused = FolderSyncSnapshot(
            isConnected: true, folderDisplayName: "Sync", folderPath: "/Sync",
            lastSyncAt: nil, lastError: "", isDirty: false, autoSyncEnabled: false
        )
        #expect(
            AccountSheetCopy.backupSyncDetail(pendingPaused, now: now, calendar: calendar, locale: Self.usLocale)
                == "Paused"
        )
    }

    @Test func inboxPreviewAccessibilityUsesFormattedTimeAndUnavailableFallback() {
        let item = AO3InboxItem(
            id: 7,
            commenterName: "anne_at_lyme",
            isGuest: false,
            subjectTitle: "Lantern Season",
            excerpt: "Bookmarking for the winter.",
            postedAgo: "2 hours ago",
            isUnread: true,
            isReplied: false,
            canReply: true
        )
        let timeLabel = AO3InboxTimeLabel.Label(display: "2h", spoken: "2 hours ago")
        #expect(
            AccountInboxPreviewRow.previewAccessibilityLabel(for: item, timeLabel: timeLabel)
                == "Unread. anne_at_lyme. on Lantern Season. Bookmarking for the winter.. 2 hours ago"
        )

        var unavailable = item
        unavailable.isUnavailable = true
        #expect(
            AccountInboxPreviewRow.previewAccessibilityLabel(for: unavailable, timeLabel: timeLabel)
                == "A comment here is unavailable"
        )
    }

    @Test func authorAvatarInitialAndPseudAccessibilityValue() throws {
        #expect(AO3AuthorAvatar.initial(for: "saltwindow") == "S")
        #expect(AO3AuthorAvatar.initial(for: "  fogandlamplight ") == "F")
        #expect(AO3AuthorAvatar.initial(for: "   ") == nil)

        let account = try #require(AO3AuthorRoute(username: "fogandlamplight"))
        let pseud = try #require(AO3AuthorRoute(username: "fogandlamplight", pseud: "BakerStreet"))
        #expect(AuthorProfileOverviewHeader.pseudAccessibilityValue(route: account, pseudCount: 3) == "All 3 pseuds")
        #expect(AuthorProfileOverviewHeader.pseudAccessibilityValue(route: account, pseudCount: 1) == "All Pseuds")
        #expect(AuthorProfileOverviewHeader.pseudAccessibilityValue(route: pseud, pseudCount: 3) == "BakerStreet")
    }

    @Test func latestCardKickerAndStatsForAuthorAndAccount() {
        let accountWork = sampleWork(
            title: "What the Tide Keeps",
            fandoms: ["Original Work"],
            dateUpdated: "20 Oct 2026",
            words: 18_400,
            chapters: "3/8",
            comments: 63,
            kudos: 412,
            hits: 4_108
        )
        #expect(AuthorProfileLatestCard.kicker(for: accountWork) == "Original Work · Chapter 3")
        let postedDate = WorkStat.displayDate("20 Oct 2026", locale: Self.usLocale)
        let expectedAccountStats = [
            "Posted \(postedDate)",
            "3 of 8",
            "♥ \(412.formatted())",
            "\(4_108.formatted()) hits",
            "\(63.formatted()) comments"
        ].joined(separator: " · ")
        #expect(
            AuthorProfileLatestCard.statsLine(for: accountWork, style: .account, locale: Self.usLocale)
                == expectedAccountStats
        )

        let authorWork = sampleWork(
            title: "The Hound, Revisited",
            fandoms: ["Sherlock Holmes (2009)"],
            dateUpdated: "23 Oct 2026",
            words: 30_600,
            chapters: "5/?",
            comments: 1,
            kudos: 760,
            hits: 9_300
        )
        #expect(AuthorProfileLatestCard.kicker(for: authorWork) == "Sherlock Holmes · Chapter 5")
        let updatedDate = WorkStat.displayDate("23 Oct 2026", locale: Self.usLocale)
        let expectedAuthorStats = [
            "Updated \(updatedDate)",
            "\(30_600.formatted()) words",
            "♥ \(760.formatted())",
            "\(9_300.compactCount) hits"
        ].joined(separator: " · ")
        #expect(
            AuthorProfileLatestCard.statsLine(for: authorWork, style: .author, locale: Self.usLocale)
                == expectedAuthorStats
        )

        #expect(AuthorProfileLatestCard.chapterProgress(from: "1/1") == "1 chapter")
        #expect(AuthorProfileLatestCard.chapterProgress(from: "5/?") == "5 chapters")
        #expect(AuthorProfileLatestCard.chapterProgress(from: "1,002/?") == "\(1_002.formatted()) chapters")
    }

    @Test func authorOverviewCountsOverflowAndChipLabels() {
        #expect(AuthorProfileOverviewSections.worksCountText(1) == "1 work")
        #expect(AuthorProfileOverviewSections.worksCountText(42) == "42 works")
        #expect(AuthorProfileOverviewSections.remainingCount(total: 42, visible: 3) == 39)
        #expect(AuthorProfileOverviewSections.remainingCount(total: 6, visible: 2) == 4)
        #expect(AuthorProfileOverviewSections.remainingCount(total: 2, visible: 2) == nil)
        #expect(AuthorProfileOverviewSections.remainingCount(total: nil, visible: 2) == nil)
        #expect(AuthorProfileOverviewSections.moreWorksAccessibilityLabel(1) == "1 more work")
        #expect(AuthorProfileOverviewSections.moreWorksAccessibilityLabel(38) == "38 more works")
        #expect(AuthorProfileOverviewSections.moreSeriesText(4) == "4 more")
        #expect(
            AuthorProfileOverviewSections.fandomChipAccessibilityLabel(name: "Sherlock Holmes", count: 31)
                == "Sherlock Holmes, 31 works"
        )
        #expect(
            AuthorProfileOverviewSections.fandomChipAccessibilityLabel(name: "Original Work", count: 1)
                == "Original Work, 1 work"
        )
        #expect(
            AuthorProfileOverviewSections.fandomChipAccessibilityLabel(name: "Jane Eyre", count: nil)
                == "Jane Eyre"
        )
    }

    @Test func seriesAndBookmarkNoteCardMetaHelpers() throws {
        let completeSeries = AO3SeriesSummary(
            id: 10,
            title: "The Lamplighter Papers",
            creatorNames: ["fogandlamplight"],
            creatorIdentities: [],
            fandoms: ["Original Work"],
            summary: "",
            words: 61_200,
            workCount: 4,
            bookmarkCount: nil,
            dateUpdated: "23 Oct 2026",
            isComplete: true,
            isRestricted: false,
            url: try #require(URL(string: "https://archiveofourown.org/series/10"))
        )
        #expect(
            AuthorProfileSeriesCard.metaText(for: completeSeries, locale: Self.usLocale)
                == "4 parts · \(61_200.compactCount) words · complete"
        )

        var wipSeries = completeSeries
        wipSeries.workCount = 1
        wipSeries.isComplete = false
        let seriesDate = WorkStat.displayDate("23 Oct 2026", locale: Self.usLocale)
        #expect(
            AuthorProfileSeriesCard.metaText(for: wipSeries, locale: Self.usLocale)
                == "1 part · \(61_200.compactCount) words · \(seriesDate)"
        )

        let bookmarkedWork = sampleWork(
            title: "The Sign of Five",
            authors: ["mrshudson221"],
            fandoms: ["Sherlock Holmes"],
            dateUpdated: "23 Oct 2026",
            words: 18_400,
            chapters: "1/1",
            comments: nil,
            kudos: nil,
            hits: nil
        )
        #expect(
            AuthorProfileBookmarkNoteCard.metaText(for: bookmarkedWork)
                == "mrshudson221 · Sherlock Holmes · \(18_400.formatted()) words"
        )
        let noteRun = AO3RichText.Run(
            text: "The best Mary Morstan in the fandom.",
            isBold: false,
            isItalic: false,
            link: nil
        )
        let richNote = AO3RichText(blocks: [
            AO3RichText.Block(kind: .paragraph, runs: [noteRun], id: 0)
        ])
        #expect(AuthorProfileBookmarkNoteCard.quotedNote(for: richNote) == "“The best Mary Morstan in the fandom.”")
        #expect(AuthorProfileBookmarkNoteCard.quotedNote(for: AO3RichText()) == nil)
    }

    private func sampleWork(
        title: String,
        authors: [String] = ["saltwindow"],
        fandoms: [String],
        dateUpdated: String,
        words: Int?,
        chapters: String,
        comments: Int?,
        kudos: Int?,
        hits: Int?
    ) -> AO3WorkSummary {
        AO3WorkSummary(
            id: 42,
            title: title,
            authors: authors,
            fandoms: fandoms,
            rating: "Teen And Up Audiences",
            warnings: [],
            categories: [],
            isComplete: false,
            dateUpdated: dateUpdated,
            tags: [],
            summary: "",
            language: "English",
            words: words,
            chapters: chapters,
            comments: comments,
            kudos: kudos,
            bookmarks: nil,
            hits: hits,
            seriesTitle: nil,
            seriesURL: nil,
            seriesPosition: nil
        )
    }
}
