import Foundation
import Testing
@testable import Kudos

/// Pins the pure copy, count, meta-line, and empty-state helpers aligned to the
/// 13 Challenges, Prompt Memes, and AO3 Collections design boards (`T-507`) so
/// the boards' wording does not drift.
@MainActor
struct ChallengesBoardCopyTests {
    private static var gmtCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
    }

    // MARK: - Shared Helpers

    @Test func sharedKindInitialsRangesAndCountdownCopy() throws {
        #expect(ChallengesBoardCopy.challengeKindName(.giftExchange) == "Gift exchange")
        #expect(ChallengesBoardCopy.challengeKindName(.promptMeme) == "Prompt meme")

        #expect(ChallengesBoardCopy.collectionInitial(title: "Winter Lighthouse", fallbackSlug: "winter") == "W")
        #expect(ChallengesBoardCopy.collectionInitial(title: "   ", fallbackSlug: "austen") == "A")
        #expect(ChallengesBoardCopy.collectionInitial(title: "", fallbackSlug: "") == "C")

        #expect(ChallengesBoardCopy.personInitial(for: "quietharbor") == "Q")
        #expect(ChallengesBoardCopy.personInitial(for: "  ") == "?")

        #expect(ChallengesBoardCopy.countRange(1, 3) == "1–3")
        #expect(ChallengesBoardCopy.countRange(2, 2) == "2")

        let calendar = Self.gmtCalendar
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 28, hour: 12)))
        let past = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 1, hour: 12)))
        let sameDayLater = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 28, hour: 18)))
        let tomorrow = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 29, hour: 12)))
        let fourDays = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 12)))
        let fifteenDays = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 12, hour: 12)))

        #expect(ChallengesBoardCopy.daysUntilText(target: past, now: now, calendar: calendar) == "Past due")
        #expect(ChallengesBoardCopy.daysUntilText(target: sameDayLater, now: now, calendar: calendar) == "Today")
        #expect(ChallengesBoardCopy.daysUntilText(target: tomorrow, now: now, calendar: calendar) == "1 day")
        #expect(ChallengesBoardCopy.daysUntilText(target: fifteenDays, now: now, calendar: calendar) == "15 days")

        let doneStatus = ChallengesBoardCopy.scheduleStatusMeta(for: past, now: now, calendar: calendar)
        #expect(doneStatus.text == "Done")
        #expect(doneStatus.isDone)

        let todayStatus = ChallengesBoardCopy.scheduleStatusMeta(for: sameDayLater, now: now, calendar: calendar)
        #expect(todayStatus.text == "Today")
        #expect(!todayStatus.isDone)

        let oneDayStatus = ChallengesBoardCopy.scheduleStatusMeta(for: tomorrow, now: now, calendar: calendar)
        #expect(oneDayStatus.text == "In 1 day")
        #expect(!oneDayStatus.isDone)

        let fourDaysStatus = ChallengesBoardCopy.scheduleStatusMeta(for: fourDays, now: now, calendar: calendar)
        #expect(fourDaysStatus.text == "In 4 days")
        #expect(!fourDaysStatus.isDone)

        let preview = ChallengesBoardCopy.cappedTagPreview(
            ["Persuasion", " Pride and Prejudice ", "", "Emma", "Northanger Abbey", "Sense and Sensibility"],
            limit: 3
        )
        #expect(preview.shown == ["Persuasion", "Pride and Prejudice", "Emma"])
        #expect(preview.extra == 2)
    }

    // MARK: - AO3-Collections

    @Test func collectionsBoardHeadersRowsAndEmptyStates() {
        #expect(ChallengesBoardCopy.collectionsTitle == "Collections")
        #expect(ChallengesBoardCopy.collectionsSubtitle == "On AO3 · your collections and challenges")
        #expect(ChallengesBoardCopy.collectionsFilterHelp == "Sort and filter")
        #expect(ChallengesBoardCopy.collectionsMaintainSectionTitle == "You maintain")
        #expect(ChallengesBoardCopy.collectionsMemberSectionTitle == "You are in")
        #expect(ChallengesBoardCopy.collectionsYourItemsPillTitle == "Your Items")

        #expect(
            ChallengesBoardCopy.collectionsHeaderLine(
                shown: 4, total: 4, isFiltered: false, currentPage: 1, totalPages: 1, partialNote: nil
            ) == "On AO3 · your collections and challenges"
        )
        #expect(
            ChallengesBoardCopy.collectionsHeaderLine(
                shown: 2, total: 6, isFiltered: true, currentPage: 1, totalPages: 1, partialNote: nil
            ) == "2 collections · 6 in all"
        )
        #expect(
            ChallengesBoardCopy.collectionsHeaderLine(
                shown: 1,
                total: 1,
                isFiltered: false,
                currentPage: 2,
                totalPages: 3,
                partialNote: "first 25 of 30 pages"
            ) == "1 collection · page 2 of 3 · first 25 of 30 pages"
        )

        let giftExchange = AO3Collection(
            name: "winter_lighthouse",
            title: "Winter Lighthouse Exchange",
            isModerated: true,
            worksCount: 42,
            challengeKind: .giftExchange
        )
        #expect(
            ChallengesBoardCopy.collectionsRowDetail(for: giftExchange)
                == "Gift exchange · moderated · 42 works"
        )

        let promptMeme = AO3Collection(
            name: "small_weathers",
            title: "Small Weathers Drabbles",
            isClosed: true,
            isModerated: true,
            isUnrevealed: true,
            isAnonymous: true,
            worksCount: 100,
            bookmarksCount: 18,
            challengeKind: .promptMeme
        )
        #expect(
            ChallengesBoardCopy.collectionsRowDetail(for: promptMeme)
                == "Prompt meme · moderated · closed · unrevealed · anonymous · 118 items"
        )

        let bookmarksOnly = AO3Collection(
            name: "recs",
            title: "Recs",
            bookmarksCount: 1
        )
        #expect(ChallengesBoardCopy.collectionsRowDetail(for: bookmarksOnly) == "Collection · 1 bookmark")

        #expect(ChallengesBoardCopy.collectionsEmptyTitle(hasLoadedCollections: false) == "No collections")
        #expect(ChallengesBoardCopy.collectionsEmptyTitle(hasLoadedCollections: true) == "No collections match")
        #expect(
            ChallengesBoardCopy.collectionsEmptyDetail(totalLoadedCount: 0)
                == "Collections you create or maintain on AO3 show up here."
        )
        #expect(
            ChallengesBoardCopy.collectionsEmptyDetail(totalLoadedCount: 1)
                == "1 collection is hidden by the current filters."
        )
        #expect(
            ChallengesBoardCopy.collectionsEmptyDetail(totalLoadedCount: 4)
                == "4 collections are hidden by the current filters."
        )
    }

    // MARK: - AO3-Collection-Page

    @Test func collectionPageKickerMetaAndEmptyStates() {
        #expect(ChallengesBoardCopy.collectionPageParticipantsTitle == "Participants")

        let collection = AO3Collection(
            name: "austen_2026",
            title: "Austen Exchange 2026",
            byline: "elinor_d",
            maintainerNames: ["elinor_d", "saltwindow", "tidewright"],
            isModerated: true,
            summary: "Coastal fic",
            challengeKind: .giftExchange
        )
        #expect(ChallengesBoardCopy.collectionPageKicker(for: collection) == "Gift exchange · moderated")
        #expect(
            ChallengesBoardCopy.collectionMaintainersMeta(
                maintainerNames: ["elinor_d", "saltwindow", "tidewright"],
                byline: ""
            ) == "Maintained by elinor_d and 2 others"
        )
        #expect(
            ChallengesBoardCopy.collectionMaintainersMeta(
                maintainerNames: ["elinor_d", "saltwindow"],
                byline: ""
            ) == "Maintained by elinor_d and 1 other"
        )
        #expect(
            ChallengesBoardCopy.collectionMaintainersMeta(maintainerNames: ["elinor_d"], byline: "")
                == "Maintained by elinor_d"
        )
        #expect(
            ChallengesBoardCopy.collectionMaintainersMeta(maintainerNames: [], byline: "saltwindow")
                == "Maintained by saltwindow"
        )
        #expect(
            ChallengesBoardCopy.collectionPageMeta(for: collection)
                == "Maintained by elinor_d and 2 others · Coastal fic"
        )
        #expect(ChallengesBoardCopy.collectionPersonWorksText(1) == "1 work")
        #expect(ChallengesBoardCopy.collectionPersonWorksText(4) == "4 works")
        #expect(ChallengesBoardCopy.collectionPersonWorksText(nil) == nil)
        #expect(ChallengesBoardCopy.collectionPageEmptyWorks == "This collection has no works yet.")
        #expect(ChallengesBoardCopy.collectionPageEmptyBookmarks == "This collection has no bookmarks yet.")
        #expect(ChallengesBoardCopy.collectionPageEmptyParticipants == "Nobody has joined this collection yet.")
        #expect(
            ChallengesBoardCopy.collectionPageEmptyProfile
                == "This collection has no introduction, FAQ, or rules on AO3."
        )
    }

    // MARK: - AO3-Collection-Form

    @Test func collectionFormBoardCopyAndOptionTitles() {
        #expect(ChallengesBoardCopy.collectionFormPreviewKicker == "Preview")
        #expect(ChallengesBoardCopy.collectionFormUntitledPlaceholder == "Untitled Collection")
        #expect(ChallengesBoardCopy.collectionFormNamesSection == "Names")
        #expect(ChallengesBoardCopy.collectionFormAboutSection == "About")
        #expect(ChallengesBoardCopy.collectionFormSettingsSection == "Settings")
        #expect(ChallengesBoardCopy.collectionFormTypeSection == "Type")
        #expect(ChallengesBoardCopy.collectionFormContactPlaceholder == "Shown to members")
        #expect(ChallengesBoardCopy.collectionFormDescriptionPlaceholder == "A short description of the collection")
        #expect(ChallengesBoardCopy.collectionFormModeratedSubtitle == "You approve every work and bookmark")
        #expect(ChallengesBoardCopy.collectionFormClosedSubtitle == "Nothing new can be added")
        #expect(ChallengesBoardCopy.collectionFormUnrevealedSubtitle == "Works stay hidden until you reveal them")
        #expect(ChallengesBoardCopy.collectionFormAnonymousSubtitle == "Creators stay hidden until you reveal them")

        #expect(
            ChallengesBoardCopy.collectionFormPreviewURL(name: "lighthouse_week_2026")
                == "archiveofourown.org/collections/lighthouse_week_2026"
        )
        #expect(
            ChallengesBoardCopy.collectionFormPreviewURL(name: "   ")
                == "archiveofourown.org/collections/…"
        )
        #expect(
            ChallengesBoardCopy.collectionFormNamesFooter(isLocked: false)
                == "The name is the address on AO3: letters, digits and underscores."
        )
        #expect(
            ChallengesBoardCopy.collectionFormNamesFooter(isLocked: true)
                == "The name is the address on AO3: letters, digits and underscores. "
                    + "You can't change it after creating the collection."
        )
        #expect(ChallengesBoardCopy.collectionFormChallengeOptionTitle(value: "", rawTitle: "") == "None")
        #expect(
            ChallengesBoardCopy.collectionFormChallengeOptionTitle(value: "GiftExchange", rawTitle: "Gift Exchange")
                == "Gift exchange"
        )
        #expect(
            ChallengesBoardCopy.collectionFormChallengeOptionTitle(value: "PromptMeme", rawTitle: "Prompt Meme")
                == "Prompt meme"
        )
    }

    // MARK: - AO3-Collection-Items

    @Test func collectionItemsTabsSubtitlesStatusLinesAndEmptyMessages() {
        #expect(ChallengesBoardCopy.collectionItemsTitle(slug: nil) == "Your Items")
        #expect(ChallengesBoardCopy.collectionItemsTitle(slug: "fest") == "Collection Items")

        #expect(ChallengesBoardCopy.collectionItemsTabTitle(.invited, isAccountWide: true) == "Awaiting you")
        #expect(ChallengesBoardCopy.collectionItemsTabTitle(.unreviewed, isAccountWide: true) == "With moderators")
        #expect(ChallengesBoardCopy.collectionItemsTabTitle(.unreviewed, isAccountWide: false) == "Awaiting collection")
        #expect(ChallengesBoardCopy.collectionItemsTabTitle(.approved, isAccountWide: true) == "Approved")
        #expect(ChallengesBoardCopy.collectionItemsTabTitle(.rejected, isAccountWide: true) == "Rejected")
        #expect(ChallengesBoardCopy.collectionItemsTabTitle(.rejectedByUser, isAccountWide: true) == "Declined")

        #expect(
            ChallengesBoardCopy.collectionItemsActiveChipLabel(
                tab: .invited, isAccountWide: true, count: 2, totalPages: 1, isSelected: true
            ) == "Awaiting you 2"
        )
        #expect(
            ChallengesBoardCopy.collectionItemsActiveChipLabel(
                tab: .invited, isAccountWide: true, count: 2, totalPages: 2, isSelected: true
            ) == "Awaiting you"
        )
        #expect(
            ChallengesBoardCopy.collectionItemsActiveChipLabel(
                tab: .approved, isAccountWide: true, count: 2, totalPages: 1, isSelected: false
            ) == "Approved"
        )

        #expect(
            ChallengesBoardCopy.collectionItemsAccountSubtitle(items: [], currentPage: 1, totalPages: 1)
                == "Your works and bookmarks in AO3 collections"
        )

        let invitedWork = sampleCollectionItem(
            id: 1, slug: "meme", title: "Persuasion Prompt Meme", itemType: "Work",
            creator: .unreviewed, moderator: .approved, dateText: "24 Oct 2026"
        )
        let submittedBookmark = sampleCollectionItem(
            id: 2, slug: "lighthouse", title: "Lighthouse Week 2026", itemType: "Bookmark",
            creator: .approved, moderator: .unreviewed, dateText: "26 Oct 2026"
        )
        #expect(
            ChallengesBoardCopy.collectionItemsAccountSubtitle(
                items: [invitedWork, submittedBookmark], currentPage: 1, totalPages: 1
            ) == "2 works and bookmarks in 2 collections"
        )
        #expect(
            ChallengesBoardCopy.collectionItemsAccountSubtitle(
                items: [invitedWork], currentPage: 2, totalPages: 3
            ) == "1 work in 1 collection · page 2 of 3"
        )

        let invitedDate = WorkStat.displayDate("24 Oct 2026")
        #expect(
            ChallengesBoardCopy.collectionItemAccountStatusLine(for: invitedWork)
                == "A maintainer invited it · \(invitedDate)"
        )
        let submittedDate = WorkStat.displayDate("26 Oct 2026")
        #expect(
            ChallengesBoardCopy.collectionItemAccountStatusLine(for: submittedBookmark)
                == "You submitted it · \(submittedDate)"
        )

        #expect(
            ChallengesBoardCopy.collectionItemsEmptyMessage(tab: .invited, isAccountWide: true)
                == "Nothing awaiting you."
        )
        #expect(
            ChallengesBoardCopy.collectionItemsEmptyMessage(tab: .unreviewed, isAccountWide: true)
                == "Nothing waiting with moderators."
        )
        #expect(
            ChallengesBoardCopy.collectionItemsEmptyMessage(tab: .unreviewed, isAccountWide: false)
                == "Nothing awaiting collection review."
        )
        #expect(
            ChallengesBoardCopy.collectionItemsEmptyMessage(tab: .approved, isAccountWide: true)
                == "No approved items."
        )
        #expect(
            ChallengesBoardCopy.collectionItemsEmptyMessage(tab: .rejected, isAccountWide: true)
                == "No rejected items."
        )
        #expect(
            ChallengesBoardCopy.collectionItemsEmptyMessage(tab: .rejectedByUser, isAccountWide: true)
                == "No declined items."
        )
    }

    // MARK: - AO3-Collection-Maintainers & AO3-Collection-Moderation

    @Test func maintainersAndModerationBoardCopy() {
        #expect(ChallengesBoardCopy.maintainersKicker == "Collection")
        #expect(ChallengesBoardCopy.maintainersSectionTitle == "Maintainers")
        #expect(ChallengesBoardCopy.maintainersMembersSectionTitle == "Members")
        #expect(ChallengesBoardCopy.maintainerOwnerSelfSubtitle == "You · created the collection")
        #expect(ChallengesBoardCopy.maintainerModeratorSubtitle == "Can approve works, cannot delete the collection")
        #expect(ChallengesBoardCopy.maintainerInvitedMeta == "Hasn’t accepted yet")
        #expect(
            ChallengesBoardCopy.maintainersContextMeta(isOwner: true, isModerator: false, maintainerCount: 3)
                == "You own it"
        )
        #expect(
            ChallengesBoardCopy.maintainersContextMeta(isOwner: false, isModerator: true, maintainerCount: 3)
                == "You moderate it"
        )
        #expect(
            ChallengesBoardCopy.maintainersContextMeta(isOwner: false, isModerator: false, maintainerCount: 1)
                == "1 maintainer"
        )

        #expect(ChallengesBoardCopy.moderationKicker == "Collection · moderated")
        #expect(ChallengesBoardCopy.moderationEmptyReviewTitle == "No works waiting for review")
        #expect(
            ChallengesBoardCopy.moderationEmptyReviewBody
                == "All submissions to this collection have been reviewed."
        )
        #expect(ChallengesBoardCopy.moderationWaitingChipLabel(count: 3, totalPages: 1) == "Waiting 3")
        #expect(ChallengesBoardCopy.moderationWaitingChipLabel(count: 3, totalPages: 2) == "Waiting")
        #expect(ChallengesBoardCopy.moderationWaitingChipLabel(count: 0, totalPages: 1) == "Waiting")
        #expect(
            ChallengesBoardCopy.moderationContextMeta(viewerIsOwner: true, isUnrevealed: true, isAnonymous: true)
                == "You own it · unrevealed · anonymous"
        )
        #expect(
            ChallengesBoardCopy.moderationContextMeta(viewerIsOwner: false, isUnrevealed: false, isAnonymous: false)
                == "Maintainer"
        )
    }

    // MARK: - Challenge, Challenge-Settings & Challenge-Assignments

    @Test func challengeHubSettingsAndAssignmentsCopy() {
        #expect(ChallengesBoardCopy.challengeSettingsGenerateMatchesLabel == "Generate Potential Matches")
        #expect(
            ChallengesBoardCopy.challengeHubSubtitle(
                signupOpen: true, closeDateText: "Nov 15", signUpTotal: 64, isLoaded: true
            ) == "Sign-ups open until Nov 15 · 64 signed up"
        )
        #expect(
            ChallengesBoardCopy.challengeHubSubtitle(
                signupOpen: false, closeDateText: "Nov 15", signUpTotal: 64, isLoaded: true
            ) == "Sign-ups closed · 64 signed up"
        )
        #expect(ChallengesBoardCopy.challengeAssignmentsSummary(matched: 0, unmatched: 0) == "Not sent")
        #expect(ChallengesBoardCopy.challengeAssignmentsSummary(matched: 92, unmatched: 2) == "92 matched, 2 unmatched")
        #expect(ChallengesBoardCopy.challengeAssignmentsSummary(matched: nil, unmatched: nil) == "Couldn't load")

        #expect(
            ChallengesBoardCopy.challengeSettingsKicker(kind: .giftExchange, isModerated: true)
                == "Gift exchange · moderated"
        )
        #expect(ChallengesBoardCopy.challengeSettingsKicker(kind: .promptMeme, isModerated: false) == "Prompt meme")
        #expect(
            ChallengesBoardCopy.challengeSettingsContextMeta(closeDateText: "Nov 1", worksDueDateText: "Nov 12")
                == "Sign-ups close Nov 1 · works due Nov 12"
        )
        #expect(
            ChallengesBoardCopy.challengeSettingsContextMeta(closeDateText: nil, worksDueDateText: "Nov 12")
                == "Works due Nov 12"
        )

        #expect(ChallengesBoardCopy.assignmentsPinchHitsOpenHeader == "Pinch hits open")
        #expect(
            ChallengesBoardCopy.assignmentsContextMeta(sentDateText: "Nov 2", dueDateText: "Nov 12")
                == "Assignments sent Nov 2 · works due Nov 12"
        )
        #expect(ChallengesBoardCopy.assignmentsPinchHitOpenTitle(recipient: "elinor_d") == "For elinor_d")
        #expect(ChallengesBoardCopy.assignmentsPinchHitOpenTitle(recipient: "  ") == "For an anonymous sign-up")
        #expect(
            ChallengesBoardCopy.assignmentsPinchHitOpenSubtitle(dueDateText: "Nov 19")
                == "Original writer defaulted · due Nov 19"
        )
        #expect(ChallengesBoardCopy.assignmentsPinchHitOpenSubtitle(dueDateText: nil) == "Original writer defaulted")
        #expect(ChallengesBoardCopy.assignmentsEmptyMatched == "No matched assignments yet.")
        #expect(ChallengesBoardCopy.assignmentsEmptyPinchHits == "No pinch hits open right now.")
        #expect(
            ChallengesBoardCopy.assignmentsEmptyUnmatched
                == "No defaulted assignments are waiting for a pinch hitter."
        )
    }

    // MARK: - Challenge-SignUp & Challenge-SignUps

    @Test func challengeSignUpAndSignUpsCopy() {
        #expect(ChallengesBoardCopy.signUpTitle == "Sign Up")
        #expect(ChallengesBoardCopy.signUpAddRequestLabel == "Add Another Request")
        #expect(ChallengesBoardCopy.signUpAddOfferLabel == "Add Another Offer")
        #expect(ChallengesBoardCopy.signUpYourSectionTitle == "Your sign-up")

        let limits = AO3ChallengeSignUpLimits(
            requestsRequired: 1, requestsAllowed: 3, offersRequired: 1, offersAllowed: 3
        )
        #expect(
            ChallengesBoardCopy.signUpContextMeta(limits: limits, takesOffers: true, requestCount: 1, offerCount: 1)
                == "1–3 requests · 1–3 offers"
        )
        #expect(
            ChallengesBoardCopy.signUpContextMeta(limits: limits, takesOffers: false, requestCount: 1, offerCount: 0)
                == "1–3 requests"
        )
        #expect(
            ChallengesBoardCopy.signUpContextMeta(limits: nil, takesOffers: true, requestCount: 2, offerCount: 1)
                == "2 requests · 1 offer"
        )

        #expect(ChallengesBoardCopy.signUpsTitle == "Sign-ups")

        let requestPrompt = AO3ChallengePrompt(
            id: 1,
            kind: .request,
            fandoms: ["Persuasion - Jane Austen"],
            characters: ["Anne Elliot"],
            relationships: ["Anne Elliot/Frederick Wentworth"]
        )
        let offerPrompt = AO3ChallengePrompt(
            id: 2,
            kind: .offer,
            fandoms: ["Pride and Prejudice - Jane Austen", "Emma - Jane Austen"]
        )
        let signUp = AO3ChallengeSignUp(
            id: 10,
            collectionSlug: "austen",
            pseud: "quietharbor",
            requests: [requestPrompt],
            offers: [offerPrompt]
        )

        let chips = ChallengesBoardCopy.signUpRequestChips(for: signUp, limit: 3)
        #expect(chips.map(\.label) == ["Anne Elliot/Frederick Wentworth", "Persuasion", "Anne Elliot"])
        #expect(chips.map(\.isTinted) == [true, false, false])

        let offersMeta = ChallengesBoardCopy.signUpOfferMeta(offers: [offerPrompt], takesOffers: true)
        #expect(offersMeta?.text == "Offers Pride and Prejudice, Emma")
        #expect(offersMeta?.isWarning == false)

        let missingOffer = ChallengesBoardCopy.signUpOfferMeta(offers: [], takesOffers: true)
        #expect(missingOffer?.text == "No offer yet")
        #expect(missingOffer?.isWarning == true)

        #expect(ChallengesBoardCopy.signUpOfferMeta(offers: [], takesOffers: false) == nil)
        #expect(
            ChallengesBoardCopy.signUpsEmptyTitle(filterName: "All", isAllFilter: true, matchUnavailable: false)
                == "No sign-ups yet"
        )
        #expect(
            ChallengesBoardCopy.signUpsEmptyTitle(filterName: "Matched", isAllFilter: false, matchUnavailable: true)
                == "Match state unavailable"
        )
        #expect(
            ChallengesBoardCopy.signUpsEmptyBody(filterName: "Unmatched", isAllFilter: false, matchUnavailable: false)
                == "No sign-ups in this page match the \"Unmatched\" filter."
        )
    }

    // MARK: - Prompt-Meme & Prompt-Tags (Tag Set)

    @Test func promptMemeAndTagSetBoardCopy() {
        #expect(ChallengesBoardCopy.promptMemeNewPromptLabel == "New Prompt")
        #expect(ChallengesBoardCopy.promptMemeClaimedByMeChipLabel == "Claimed by me")
        #expect(
            ChallengesBoardCopy.promptMemeContextKicker(
                fandoms: [["Persuasion - Jane Austen"], ["Persuasion - Jane Austen"]]
            ) == "Prompt meme · Persuasion"
        )
        #expect(
            ChallengesBoardCopy.promptMemeContextKicker(fandoms: [["Persuasion"], ["Emma"]])
                == "Prompt meme"
        )
        #expect(ChallengesBoardCopy.promptMemeOpenUntil("Dec 31") == "Open for prompts until Dec 31")
        #expect(ChallengesBoardCopy.promptMemeByline(isAnonymous: true, owner: "quietharbor") == "Anonymous")
        #expect(ChallengesBoardCopy.promptMemeByline(isAnonymous: false, owner: "quietharbor") == "by quietharbor")
        #expect(ChallengesBoardCopy.promptMemeByline(isAnonymous: false, owner: nil) == "Unknown poster")

        let claimedByYou = ChallengesBoardCopy.promptMemeStatusMeta(claimedByCurrentUser: true, claimantCount: 2)
        #expect(claimedByYou.text == "Claimed by you")
        #expect(claimedByYou.isAccent)

        let otherClaims = ChallengesBoardCopy.promptMemeStatusMeta(claimedByCurrentUser: false, claimantCount: 2)
        #expect(otherClaims.text == "2 claims")
        #expect(!otherClaims.isAccent)

        let unclaimed = ChallengesBoardCopy.promptMemeStatusMeta(claimedByCurrentUser: false, claimantCount: 0)
        #expect(unclaimed.text == "Unclaimed")
        #expect(!unclaimed.isAccent)

        let promptChips = ChallengesBoardCopy.promptMemeTagChips(
            fandoms: ["Persuasion - Jane Austen"],
            tagSummary: "Future Fic, Anne Elliot/Frederick Wentworth",
            limit: 4
        )
        #expect(promptChips.map(\.label) == ["Anne Elliot/Frederick Wentworth", "Future Fic"])
        #expect(promptChips.map(\.isTinted) == [true, false])

        #expect(ChallengesBoardCopy.promptMemeEmptyTitle(filterName: "All", isAllFilter: true) == "No prompts yet")
        #expect(
            ChallengesBoardCopy.promptMemeEmptyBody(filterName: "Claimed by me", isAllFilter: false)
                == "No prompts on this page match the \"Claimed by me\" filter."
        )

        #expect(ChallengesBoardCopy.tagSetKicker == "Tag set")
        #expect(ChallengesBoardCopy.tagSetNominationsHeader == "Nominations to review")
        #expect(ChallengesBoardCopy.tagSetNewBadge == "New")
        #expect(ChallengesBoardCopy.tagSetLetNominateLabel == "Let participants nominate")
        #expect(ChallengesBoardCopy.tagSetFieldLabel(.fandom) == "Fandom")
        #expect(ChallengesBoardCopy.tagSetFieldLabel(.character) == "Character")
        #expect(ChallengesBoardCopy.tagSetFieldLabel(.relationship) == "Relationship")
        #expect(ChallengesBoardCopy.tagSetFieldLabel(.freeform) == "Additional tag")
        #expect(
            ChallengesBoardCopy.tagSetNominationSubtitle(field: .character, parentTagName: "Persuasion")
                == "Character · Persuasion"
        )
        #expect(
            ChallengesBoardCopy.tagSetNominationSubtitle(field: .fandom, parentTagName: " ")
                == "Fandom"
        )
        #expect(ChallengesBoardCopy.tagSetParsedNames("Persuasion, Emma, , Northanger Abbey") == [
            "Persuasion", "Emma", "Northanger Abbey"
        ])
        #expect(ChallengesBoardCopy.tagSetEmptyNominationsTitle == "No nominations yet")
        #expect(ChallengesBoardCopy.tagSetEmptyNominationsBody == "Nothing has been nominated to this tag set.")
    }

    private func sampleCollectionItem(
        id: Int,
        slug: String,
        title: String,
        itemType: String,
        creator: AO3CollectionItemApproval,
        moderator: AO3CollectionItemApproval,
        dateText: String
    ) -> AO3CollectionItem {
        AO3CollectionItem(
            id: id,
            collectionSlug: slug,
            collectionTitle: title,
            workTitle: "Small Weathers",
            itemType: itemType,
            creatorApproval: creator,
            moderatorApproval: moderator,
            itemDateText: dateText,
            userApprovalField: "collection_items[\(id)][user_approval_status]",
            collectionApprovalField: "collection_items[\(id)][collection_approval_status]",
            unrevealedField: "collection_items[\(id)][unrevealed]",
            anonymousField: "collection_items[\(id)][anonymous]",
            removeField: "collection_items[\(id)][remove]"
        )
    }
}
