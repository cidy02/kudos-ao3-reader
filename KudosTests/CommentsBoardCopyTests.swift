import Foundation
import Testing
@testable import Kudos

/// Locks the board-matched copy and helper outputs aligned in T-507
/// (Comments, Comment-Menu, Comment-Thread, CommentThread, Inbox, Inbox-Filter,
/// History-Month, History-Year) so the boards' wording does not drift.
@MainActor
@Suite("Comments, Inbox & History board copy (T-507)")
struct CommentsBoardCopyTests {
    private static let usLocale = Locale(identifier: "en_US")

    private static func utcCalendar(firstWeekday: Int = 2) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        calendar.firstWeekday = firstWeekday
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }

    // MARK: - Comment-Thread & Comment-Menu

    @Test func composerTitleAndFormatBarLabelsMatchCommentThreadBoard() {
        #expect(CommentComposerSheet.title(isEdit: false, parentAuthor: "saltwindow") == "Reply to saltwindow")
        #expect(CommentComposerSheet.title(isEdit: false, parentAuthor: nil) == "New Comment")
        #expect(CommentComposerSheet.title(isEdit: true, parentAuthor: nil) == "Edit Comment")
        #expect(CommentComposerSheet.title(isEdit: true, parentAuthor: "saltwindow") == "Edit Comment")

        #expect(CommentFormatBar.toolbarAccessibilityLabel == "Formatting")
        #expect(CommentFormatBar.moreFormattingLabel == "More formatting")
        #expect(CommentFormatBar.accessibilityLabel(for: .bold) == "Bold")
        #expect(CommentFormatBar.accessibilityLabel(for: .italic) == "Italic")
        #expect(CommentFormatBar.accessibilityLabel(for: .underline) == "Underline")
        #expect(CommentFormatBar.accessibilityLabel(for: .strike) == "Strikethrough")
        #expect(CommentFormatBar.accessibilityLabel(for: .link) == "Link")
        #expect(CommentFormatBar.accessibilityLabel(for: .quote) == "Quote")
    }

    @Test func commentMenuShowThreadSubtitleMatchesReplyCounts() {
        let leaf = AO3Comment(id: 1, author: "marginalia", isGuest: false)
        #expect(CommentMenuItems.showThreadSubtitle(for: leaf) == nil)

        var oneReply = leaf
        oneReply.replies = [AO3Comment(id: 2, author: "saltwindow", isGuest: false)]
        #expect(CommentMenuItems.showThreadSubtitle(for: oneReply) == "1 reply")

        var twoReplies = leaf
        twoReplies.replies = [
            AO3Comment(id: 2, author: "saltwindow", isGuest: false),
            AO3Comment(id: 3, author: "inkwell_moth", isGuest: false)
        ]
        #expect(CommentMenuItems.showThreadSubtitle(for: twoReplies) == "2 replies")

        var cutoff = AO3Comment(id: 900, author: "", isGuest: false)
        cutoff.isThreadCutoff = true
        cutoff.cutoffCount = 7
        var withCutoff = leaf
        withCutoff.replies = [cutoff]
        #expect(CommentMenuItems.showThreadSubtitle(for: withCutoff) == "7 replies")
    }

    // MARK: - Inbox & Inbox-Filter

    @Test func inboxToolbarFilterStateAndSwipeLabelsMatchInboxBoard() throws {
        let form = try sampleInboxFilterForm()
        let allDefault = [
            AO3InboxPill.readField: "all",
            AO3InboxPill.repliedField: "all",
            "filters[date]": "desc"
        ]
        #expect(!AccountInboxCopy.isFilterActive(currentValues: allDefault, filterForm: form))
        #expect(AccountInboxCopy.filterAccessibilityLabel(currentValues: allDefault, filterForm: form) == "Filter")

        let unread = [
            AO3InboxPill.readField: "false",
            AO3InboxPill.repliedField: "all",
            "filters[date]": "desc"
        ]
        #expect(AccountInboxCopy.isFilterActive(currentValues: unread, filterForm: form))
        #expect(
            AccountInboxCopy.filterAccessibilityLabel(currentValues: unread, filterForm: form)
                == "Filter, on: Unread"
        )

        let replied = [
            AO3InboxPill.readField: "all",
            AO3InboxPill.repliedField: "true",
            "filters[date]": "desc"
        ]
        #expect(
            AccountInboxCopy.filterAccessibilityLabel(currentValues: replied, filterForm: form)
                == "Filter, on: Replied"
        )

        let readOnly = [
            AO3InboxPill.readField: "true",
            AO3InboxPill.repliedField: "all",
            "filters[date]": "desc"
        ]
        #expect(AccountInboxCopy.isFilterActive(currentValues: readOnly, filterForm: form))
        #expect(
            AccountInboxCopy.filterAccessibilityLabel(currentValues: readOnly, filterForm: form)
                == "Filter, active"
        )

        let oldestFirst = [
            AO3InboxPill.readField: "all",
            AO3InboxPill.repliedField: "all",
            "filters[date]": "asc"
        ]
        #expect(AccountInboxCopy.isFilterActive(currentValues: oldestFirst, filterForm: form))
        #expect(
            AccountInboxCopy.filterAccessibilityLabel(currentValues: oldestFirst, filterForm: form)
                == "Filter, active"
        )

        #expect(AccountInboxCommentListRow.readSwipeTitle(isUnread: true) == "Read")
        #expect(AccountInboxCommentListRow.readSwipeTitle(isUnread: false) == "Unread")
    }

    @Test func inboxFilterSheetCopyAndDefaultsMatchInboxFilterBoard() throws {
        let form = try sampleInboxFilterForm()
        #expect(InboxFilterSheetCopy.title == "Filter Inbox")
        #expect(InboxFilterSheetCopy.applyTitle == "Apply")
        #expect(InboxFilterSheetCopy.cancelAccessibilityLabel == "Cancel")
        #expect(InboxFilterSheetCopy.resetTitle == "Reset Filters")

        let readField = try #require(form.fields.first { $0.name == AO3InboxPill.readField })
        let repliedField = try #require(form.fields.first { $0.name == AO3InboxPill.repliedField })
        let dateField = try #require(form.fields.first { $0.name == "filters[date]" })

        #expect(InboxFilterSheetCopy.rowLabel(for: readField) == "Read")
        #expect(InboxFilterSheetCopy.rowLabel(for: repliedField) == "Replied")
        #expect(InboxFilterSheetCopy.rowLabel(for: dateField) == "Sort")

        #expect(
            readField.options.map { InboxFilterSheetCopy.segmentLabel(for: $0, in: readField.name) }
                == ["All", "Unread", "Read"]
        )
        #expect(
            repliedField.options.map { InboxFilterSheetCopy.segmentLabel(for: $0, in: repliedField.name) }
                == ["All", "Unreplied", "Replied"]
        )
        #expect(
            dateField.options.map { InboxFilterSheetCopy.segmentLabel(for: $0, in: dateField.name) }
                == ["Newest", "Oldest"]
        )

        let customField = AO3InboxFilterField(
            name: "filters[other]",
            title: "Other",
            options: [AO3InboxFilterOption(value: "x", label: "Custom Option", isSelected: true)]
        )
        #expect(InboxFilterSheetCopy.rowLabel(for: customField) == "Other")
        #expect(
            InboxFilterSheetCopy.segmentLabel(for: customField.options[0], in: customField.name)
                == "Custom Option"
        )

        let defaults = InboxFilterSheetCopy.defaultValues(for: form)
        #expect(defaults == [
            AO3InboxPill.readField: "all",
            AO3InboxPill.repliedField: "all",
            "filters[date]": "desc"
        ])
        #expect(!InboxFilterSheetCopy.canReset(draftValues: defaults, form: form))
        #expect(InboxFilterSheetCopy.canReset(draftValues: form.selectedValues, form: form))
        #expect(!InboxFilterSheetCopy.canReset(draftValues: [:], form: nil))
    }

    // MARK: - History-Month & History-Year

    @Test func historySummaryLineMatchesWeekMonthAndYearBoards() throws {
        let cal = Self.utcCalendar()
        let oct27 = try #require(cal.date(from: DateComponents(year: 2026, month: 10, day: 27, hour: 23)))
        let oct28 = try #require(cal.date(from: DateComponents(year: 2026, month: 10, day: 28, hour: 23)))
        let june12 = try #require(cal.date(from: DateComponents(year: 2026, month: 6, day: 12, hour: 23)))

        let facts = [
            ReadingSessionFacts(
                workID: UUID(),
                startedAt: oct27,
                durationSeconds: 30 * 60,
                wordCount: 50_000,
                didFinish: false,
                fandom: "Original Work",
                wordsRead: 25_000,
                sessionID: UUID(),
                title: "Salt & Starlight"
            ),
            ReadingSessionFacts(
                workID: UUID(),
                startedAt: oct28,
                durationSeconds: 45 * 60,
                wordCount: 118_000,
                didFinish: true,
                fandom: "Persuasion (Jane Austen)",
                wordsRead: 4_075_000,
                sessionID: UUID(),
                title: "Letters Never Sent"
            ),
            ReadingSessionFacts(
                workID: UUID(),
                startedAt: june12,
                durationSeconds: 180 * 60,
                wordCount: 118_000,
                didFinish: true,
                fandom: "Persuasion (Jane Austen)",
                wordsRead: 0,
                sessionID: UUID(),
                title: "Letters Never Sent"
            )
        ]

        let week = ReadingHistoryTimeline.make(
            scope: .week, containing: oct28, facts: facts, now: oct28, calendar: cal
        )
        #expect(week.streakDays == 2)
        #expect(week.summaryLine(locale: Self.usLocale) == "2 works · 1 finished · 2-day streak")

        let month = ReadingHistoryTimeline.make(
            scope: .month, containing: oct28, facts: facts, now: oct28, calendar: cal
        )
        #expect(month.streakDays == 2)
        #expect(month.summaryLine(locale: Self.usLocale) == "2 works · 1 finished · read on 2 of 28 days")

        let year = ReadingHistoryTimeline.make(
            scope: .year, containing: oct28, facts: facts, now: oct28, calendar: cal
        )
        let expectedYearWords = ReadingHistoryTimeline.compactWordCount(year.wordsRead, locale: Self.usLocale)
        #expect(year.summaryLine(locale: Self.usLocale) == "3 works · 2 finished · \(expectedYearWords) words")
        #expect(!year.summaryLine(locale: Self.usLocale).contains("streak"))
    }

    @Test func historyYearFactsAndCompactWordCountMatchHistoryYearBoard() throws {
        #expect(ReadingHistoryTimeline.compactWordCount(950, locale: Self.usLocale) == "950")
        #expect(ReadingHistoryTimeline.compactWordCount(118_000, locale: Self.usLocale) == "118k")
        #expect(ReadingHistoryTimeline.compactWordCount(4_100_000, locale: Self.usLocale) == "4.1M")

        let cal = Self.utcCalendar()
        let oct28 = try #require(cal.date(from: DateComponents(year: 2026, month: 10, day: 28, hour: 12)))
        let emptyYear = ReadingHistoryTimeline.make(
            scope: .year, containing: oct28, facts: [], now: oct28, calendar: cal
        )
        #expect(emptyYear.busiestMonthName(calendar: cal) == nil)
        #expect(emptyYear.yearFacts(calendar: cal, locale: Self.usLocale) == [
            ReadingHistoryTimeline.YearFact(label: "Busiest month", value: "—"),
            ReadingHistoryTimeline.YearFact(label: "Most-read fandom", value: "—"),
            ReadingHistoryTimeline.YearFact(label: "Longest work finished", value: "—"),
            ReadingHistoryTimeline.YearFact(label: "Favourite time", value: "—")
        ])

        let june12Late = try #require(cal.date(from: DateComponents(year: 2026, month: 6, day: 12, hour: 23)))
        let aug3Morning = try #require(cal.date(from: DateComponents(year: 2026, month: 8, day: 3, hour: 9)))
        let facts = [
            ReadingSessionFacts(
                workID: UUID(),
                startedAt: june12Late,
                durationSeconds: 180 * 60,
                wordCount: 118_000,
                didFinish: true,
                fandom: "Persuasion - Jane Austen",
                wordsRead: 118_000,
                sessionID: UUID(),
                title: "Letters Never Sent"
            ),
            ReadingSessionFacts(
                workID: UUID(),
                startedAt: aug3Morning,
                durationSeconds: 30 * 60,
                wordCount: 24_000,
                didFinish: false,
                fandom: "Original Work",
                wordsRead: 12_000,
                sessionID: UUID(),
                title: "Salt & Starlight"
            )
        ]
        let populatedYear = ReadingHistoryTimeline.make(
            scope: .year, containing: oct28, facts: facts, now: oct28, calendar: cal
        )
        #expect(populatedYear.busiestMonthName(calendar: cal) == "June")
        #expect(populatedYear.yearFacts(calendar: cal, locale: Self.usLocale) == [
            ReadingHistoryTimeline.YearFact(label: "Busiest month", value: "June"),
            ReadingHistoryTimeline.YearFact(
                label: "Most-read fandom",
                value: FandomDisplayName.bareTitle("Persuasion - Jane Austen")
            ),
            ReadingHistoryTimeline.YearFact(
                label: "Longest work finished",
                value: "\(ReadingHistoryTimeline.compactWordCount(118_000, locale: Self.usLocale)) words"
            ),
            ReadingHistoryTimeline.YearFact(label: "Favourite time", value: "After 10 pm")
        ])
    }

    // MARK: - Helpers

    private func sampleInboxFilterForm() throws -> AO3InboxFilterForm {
        let actionURL = try #require(URL(string: "https://archiveofourown.org/users/tester/inbox"))
        return AO3InboxFilterForm(
            actionURL: actionURL,
            hiddenFields: [],
            fields: [
                AO3InboxFilterField(
                    name: AO3InboxPill.readField,
                    title: "Read",
                    options: [
                        AO3InboxFilterOption(value: "all", label: "Show all", isSelected: false),
                        AO3InboxFilterOption(value: "false", label: "Show unread", isSelected: true),
                        AO3InboxFilterOption(value: "true", label: "Show read", isSelected: false)
                    ]
                ),
                AO3InboxFilterField(
                    name: AO3InboxPill.repliedField,
                    title: "Replied To",
                    options: [
                        AO3InboxFilterOption(value: "all", label: "Show all", isSelected: true),
                        AO3InboxFilterOption(value: "false", label: "Show without replies", isSelected: false),
                        AO3InboxFilterOption(value: "true", label: "Show replied to", isSelected: false)
                    ]
                ),
                AO3InboxFilterField(
                    name: "filters[date]",
                    title: "Sort by Date",
                    options: [
                        AO3InboxFilterOption(value: "desc", label: "Newest first", isSelected: true),
                        AO3InboxFilterOption(value: "asc", label: "Oldest first", isSelected: false)
                    ]
                )
            ]
        )
    }
}
