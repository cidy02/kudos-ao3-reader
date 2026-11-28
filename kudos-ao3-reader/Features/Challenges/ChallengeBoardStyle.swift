import SwiftUI

/// Pure copy, count, and metadata helpers aligned to the 13 Challenges,
/// Prompt Memes, and AO3 Collections design boards (`T-507`).
///
/// Every helper builds strictly from fields AO3 already returned — never
/// inventing counts, dates, or roles the model does not carry.
nonisolated enum ChallengesBoardCopy {

    // MARK: - Shared

    /// Sentence-case challenge kind matching the boards ("Gift exchange", "Prompt meme").
    static func challengeKindName(_ kind: AO3ChallengeKind) -> String {
        switch kind {
        case .giftExchange: "Gift exchange"
        case .promptMeme: "Prompt meme"
        }
    }

    /// Leading single-character monogram for a collection tile (`AO3-Collections`).
    static func collectionInitial(title: String, fallbackSlug: String) -> String {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if let first = trimmedTitle.first {
            return String(first).uppercased()
        }
        let trimmedSlug = fallbackSlug.trimmingCharacters(in: .whitespacesAndNewlines)
        if let first = trimmedSlug.first {
            return String(first).uppercased()
        }
        return "C"
    }

    /// Leading single-character monogram for a participant avatar.
    static func personInitial(for name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else { return "?" }
        return String(first).uppercased()
    }

    /// En-dash range matching `Challenge-Settings` ("1–3") and `Challenge-SignUp`.
    static func countRange(_ lower: Int, _ upper: Int) -> String {
        lower == upper ? "\(lower)" : "\(lower)–\(upper)"
    }

    /// Whole-day countdown for the Assignments and Sign-ups stat strips ("15 days", "1 day", "Today", "Past due").
    static func daysUntilText(
        target: Date,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> String {
        let startNow = calendar.startOfDay(for: now)
        let startTarget = calendar.startOfDay(for: target)
        let days = calendar.dateComponents([.day], from: startNow, to: startTarget).day ?? 0
        if days < 0 { return "Past due" }
        if days == 0 { return "Today" }
        return days == 1 ? "1 day" : "\(days) days"
    }

    /// Relative schedule status under a date row on `Challenge-Settings` ("Done" / "In 4 days" / "Today").
    static func scheduleStatusMeta(
        for target: Date,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> (text: String, isDone: Bool) {
        if target <= now { return ("Done", true) }
        let startNow = calendar.startOfDay(for: now)
        let startTarget = calendar.startOfDay(for: target)
        let days = calendar.dateComponents([.day], from: startNow, to: startTarget).day ?? 0
        if days <= 0 { return ("Today", false) }
        return (days == 1 ? "In 1 day" : "In \(days) days", false)
    }

    /// Caps a list of tags for inline chip previews (`Prompt-Tags`: shown tags + "+N" overflow).
    static func cappedTagPreview(_ tags: [String], limit: Int) -> (shown: [String], extra: Int) {
        let cleaned = tags
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let cappedLimit = max(0, limit)
        let shown = Array(cleaned.prefix(cappedLimit))
        let extra = max(0, cleaned.count - shown.count)
        return (shown, extra)
    }

    static func plural(_ count: Int, singular: String, plural pluralWord: String? = nil) -> String {
        let word = count == 1 ? singular : (pluralWord ?? "\(singular)s")
        return "\(count.formatted()) \(word)"
    }

    // MARK: - AO3-Collections

    static let collectionsTitle = "Collections"
    static let collectionsSubtitle = "On AO3 · your collections and challenges"
    static let collectionsFilterHelp = "Sort and filter"
    static let collectionsMaintainSectionTitle = "You maintain"
    static let collectionsMemberSectionTitle = "You are in"
    static let collectionsYourItemsPillTitle = "Your Items"

    static func collectionsHeaderLine(
        shown: Int,
        total: Int,
        isFiltered: Bool,
        currentPage: Int,
        totalPages: Int,
        partialNote: String?
    ) -> String {
        guard isFiltered || totalPages > 1 || partialNote != nil else {
            return collectionsSubtitle
        }
        var parts = [plural(shown, singular: "collection")]
        if shown != total {
            parts.append("\(total.formatted()) in all")
        }
        if totalPages > 1 {
            parts.append("page \(currentPage) of \(totalPages)")
        }
        if let partialNote, !partialNote.isEmpty {
            parts.append(partialNote)
        }
        return parts.joined(separator: " · ")
    }

    /// Board-aligned detail line for an `AO3Collection` row (`AO3-Collections.dc.html`):
    /// e.g. `"Gift exchange · moderated · 42 works"` or `"Prompt meme · moderated · 118 items"`.
    static func collectionsRowDetail(for collection: AO3Collection) -> String {
        var parts: [String] = [
            collection.challengeKind.map(challengeKindName) ?? "Collection"
        ]
        if collection.isModerated { parts.append("moderated") }
        if collection.isClosed { parts.append("closed") }
        if collection.isUnrevealed { parts.append("unrevealed") }
        if collection.isAnonymous { parts.append("anonymous") }
        if let works = collection.worksCount, let bookmarks = collection.bookmarksCount, bookmarks > 0 {
            parts.append(plural(works + bookmarks, singular: "item"))
        } else if let works = collection.worksCount {
            parts.append(plural(works, singular: "work"))
        } else if let bookmarks = collection.bookmarksCount, bookmarks > 0 {
            parts.append(plural(bookmarks, singular: "bookmark"))
        }
        return parts.joined(separator: " · ")
    }

    static func collectionsEmptyTitle(hasLoadedCollections: Bool) -> String {
        hasLoadedCollections ? "No collections match" : "No collections"
    }

    static func collectionsEmptyDetail(totalLoadedCount: Int) -> String {
        if totalLoadedCount <= 0 {
            return "Collections you create or maintain on AO3 show up here."
        }
        let verb = totalLoadedCount == 1 ? "is" : "are"
        return "\(plural(totalLoadedCount, singular: "collection")) \(verb) hidden by the current filters."
    }

    // MARK: - AO3-Collection-Page

    static let collectionPageParticipantsTitle = "Participants"

    static func collectionPageKicker(for collection: AO3Collection) -> String {
        var parts: [String] = [
            collection.challengeKind.map(challengeKindName) ?? "Collection"
        ]
        if collection.isModerated { parts.append("moderated") }
        if collection.isClosed { parts.append("closed") }
        if collection.isUnrevealed { parts.append("unrevealed") }
        if collection.isAnonymous { parts.append("anonymous") }
        return parts.joined(separator: " · ")
    }

    static func collectionMaintainersMeta(maintainerNames: [String], byline: String) -> String? {
        let names = maintainerNames
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if names.count > 1 {
            let others = names.count - 1
            let suffix = others == 1 ? "1 other" : "\(others) others"
            return "Maintained by \(names[0]) and \(suffix)"
        }
        if let sole = names.first {
            return "Maintained by \(sole)"
        }
        let fallback = byline.trimmingCharacters(in: .whitespacesAndNewlines)
        return fallback.isEmpty ? nil : "Maintained by \(fallback)"
    }

    static func collectionPageMeta(for collection: AO3Collection) -> String {
        let parts: [String?] = [
            collectionMaintainersMeta(maintainerNames: collection.maintainerNames, byline: collection.byline),
            collection.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? nil
                : collection.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        ]
        return parts.compactMap { $0 }.joined(separator: " · ")
    }

    static func collectionPersonWorksText(_ workCount: Int?) -> String? {
        guard let workCount else { return nil }
        return plural(workCount, singular: "work")
    }

    static let collectionPageEmptyWorks = "This collection has no works yet."
    static let collectionPageEmptyBookmarks = "This collection has no bookmarks yet."
    static let collectionPageEmptyParticipants = "Nobody has joined this collection yet."
    static let collectionPageEmptyProfile = "This collection has no introduction, FAQ, or rules on AO3."

    // MARK: - AO3-Collection-Form

    static let collectionFormPreviewKicker = "Preview"
    static let collectionFormUntitledPlaceholder = "Untitled Collection"
    static let collectionFormNamesSection = "Names"
    static let collectionFormAboutSection = "About"
    static let collectionFormSettingsSection = "Settings"
    static let collectionFormTypeSection = "Type"
    static let collectionFormImagesSection = "Images"
    static let collectionFormProfileSection = "Profile"
    static let collectionFormContactPlaceholder = "Shown to members"
    static let collectionFormDescriptionPlaceholder = "A short description of the collection"
    static let collectionFormModeratedSubtitle = "You approve every work and bookmark"
    static let collectionFormClosedSubtitle = "Nothing new can be added"
    static let collectionFormUnrevealedSubtitle = "Works stay hidden until you reveal them"
    static let collectionFormAnonymousSubtitle = "Creators stay hidden until you reveal them"
    static let collectionFormEmailNotifySubtitle = "Send new-item notifications to the contact email"

    /// Sentence-case challenge-type segment labels matching `AO3-Collection-Form.dc.html`
    /// ("None", "Gift exchange", "Prompt meme") while preserving AO3's wire values.
    static func collectionFormChallengeOptionTitle(value: String, rawTitle: String) -> String {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedValue.isEmpty { return "None" }
        if let kind = AO3ChallengeKind(otwarchiveType: trimmedValue) {
            return challengeKindName(kind)
        }
        let trimmedTitle = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if let kind = AO3ChallengeKind(otwarchiveType: trimmedTitle.lowercased()) {
            return challengeKindName(kind)
        }
        return trimmedTitle.isEmpty ? "None" : trimmedTitle
    }

    static func collectionFormPreviewURL(name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return "archiveofourown.org/collections/\(trimmed.isEmpty ? "…" : trimmed)"
    }

    static func collectionFormNamesFooter(isLocked: Bool) -> String {
        let base = "The name is the address on AO3: letters, digits and underscores."
        return isLocked ? "\(base) You can't change it after creating the collection." : base
    }

    // MARK: - AO3-Collection-Items

    static func collectionItemsTitle(slug: String?) -> String {
        slug == nil ? "Your Items" : "Collection Items"
    }

    static func collectionItemsTabTitle(_ tab: AO3CollectionItemTab, isAccountWide: Bool) -> String {
        switch tab {
        case .invited: "Awaiting you"
        case .unreviewed: isAccountWide ? "With moderators" : "Awaiting collection"
        case .approved: "Approved"
        case .rejected: "Rejected"
        case .rejectedByUser: "Declined"
        }
    }

    static func collectionItemsActiveChipLabel(
        tab: AO3CollectionItemTab,
        isAccountWide: Bool,
        count: Int,
        totalPages: Int,
        isSelected: Bool
    ) -> String {
        let base = collectionItemsTabTitle(tab, isAccountWide: isAccountWide)
        guard isSelected, totalPages == 1, count > 0 else { return base }
        return "\(base) \(count)"
    }

    static func collectionItemsAccountSubtitle(
        items: [AO3CollectionItem],
        currentPage: Int,
        totalPages: Int
    ) -> String {
        let base: String
        if items.isEmpty {
            base = "Your works and bookmarks in AO3 collections"
        } else {
            let hasBookmark = items.contains { $0.itemType.localizedCaseInsensitiveContains("bookmark") }
            let hasWork = items.contains { !$0.itemType.localizedCaseInsensitiveContains("bookmark") }
            let count = items.count
            let itemPhrase: String
            if hasWork && hasBookmark {
                itemPhrase = "\(count.formatted()) works and bookmarks"
            } else if hasBookmark {
                itemPhrase = plural(count, singular: "bookmark")
            } else {
                itemPhrase = plural(count, singular: "work")
            }
            let collectionCount = Set(items.map { $0.collectionSlug.isEmpty ? $0.collectionTitle : $0.collectionSlug })
                .filter { !$0.isEmpty }
                .count
            if collectionCount > 0 {
                base = "\(itemPhrase) in \(plural(collectionCount, singular: "collection"))"
            } else {
                base = itemPhrase
            }
        }
        return totalPages > 1 ? "\(base) · page \(currentPage) of \(totalPages)" : base
    }

    static func collectionItemAccountStatusLine(
        for item: AO3CollectionItem,
        dateDisplay: (String) -> String = { WorkStat.displayDate($0) }
    ) -> String? {
        let status: String?
        if item.creatorApproval == .unreviewed && item.moderatorApproval == .approved {
            status = "A maintainer invited it"
        } else if item.creatorApproval == .approved && item.moderatorApproval == .unreviewed {
            status = "You submitted it"
        } else {
            status = nil
        }
        let dateTrimmed = item.itemDateText.trimmingCharacters(in: .whitespacesAndNewlines)
        let datePart = dateTrimmed.isEmpty ? nil : dateDisplay(dateTrimmed)
        let parts: [String?] = [status, datePart]
        let joined = parts.compactMap { $0 }.joined(separator: " · ")
        return joined.isEmpty ? nil : joined
    }

    static func collectionItemsEmptyMessage(tab: AO3CollectionItemTab, isAccountWide: Bool) -> String {
        switch tab {
        case .invited: "Nothing awaiting you."
        case .unreviewed: isAccountWide ? "Nothing waiting with moderators." : "Nothing awaiting collection review."
        case .approved: "No approved items."
        case .rejected: "No rejected items."
        case .rejectedByUser: "No declined items."
        }
    }

    // MARK: - AO3-Collection-Maintainers

    static let maintainersKicker = "Collection"
    static let maintainersSectionTitle = "Maintainers"
    static let maintainersMembersSectionTitle = "Members"
    static let maintainerOwnerSelfSubtitle = "You · created the collection"
    static let maintainerModeratorSubtitle = "Can approve works, cannot delete the collection"
    static let maintainerInvitedMeta = "Hasn’t accepted yet"

    static func maintainersContextMeta(isOwner: Bool, isModerator: Bool, maintainerCount: Int) -> String {
        if isOwner { return "You own it" }
        if isModerator { return "You moderate it" }
        return plural(maintainerCount, singular: "maintainer")
    }

    // MARK: - AO3-Collection-Moderation

    static let moderationKicker = "Collection · moderated"
    static let moderationEmptyReviewTitle = "No works waiting for review"
    static let moderationEmptyReviewBody = "All submissions to this collection have been reviewed."

    static func moderationWaitingChipLabel(count: Int, totalPages: Int) -> String {
        count > 0 && totalPages == 1 ? "Waiting \(count)" : "Waiting"
    }

    static func moderationContextMeta(
        viewerIsOwner: Bool,
        isUnrevealed: Bool,
        isAnonymous: Bool
    ) -> String {
        var parts = [viewerIsOwner ? "You own it" : "Maintainer"]
        if isUnrevealed { parts.append("unrevealed") }
        if isAnonymous { parts.append("anonymous") }
        return parts.joined(separator: " · ")
    }

    // MARK: - Challenge & Challenge-Settings

    static let challengeSettingsGenerateMatchesLabel = "Generate Potential Matches"

    static func challengeHubSubtitle(
        signupOpen: Bool,
        closeDateText: String?,
        signUpTotal: Int?,
        isLoaded: Bool
    ) -> String {
        var parts: [String] = []
        if isLoaded {
            if signupOpen {
                if let closeDateText, !closeDateText.isEmpty {
                    parts.append("Sign-ups open until \(closeDateText)")
                } else {
                    parts.append("Sign-ups open")
                }
            } else {
                parts.append("Sign-ups closed")
            }
        }
        if let signUpTotal {
            parts.append("\(signUpTotal.formatted()) signed up")
        }
        return parts.joined(separator: " · ")
    }

    static func challengeAssignmentsSummary(matched: Int?, unmatched: Int?) -> String {
        guard let matched, let unmatched else { return "Couldn't load" }
        if matched == 0, unmatched == 0 { return "Not sent" }
        return "\(matched) matched, \(unmatched) unmatched"
    }

    static func challengeSettingsKicker(kind: AO3ChallengeKind, isModerated: Bool?) -> String {
        let base = challengeKindName(kind)
        return isModerated == true ? "\(base) · moderated" : base
    }

    static func challengeSettingsContextMeta(
        closeDateText: String?,
        worksDueDateText: String?
    ) -> String {
        var parts: [String] = []
        if let close = closeDateText, !close.isEmpty {
            parts.append("Sign-ups close \(close)")
        }
        if let due = worksDueDateText, !due.isEmpty {
            parts.append(parts.isEmpty ? "Works due \(due)" : "works due \(due)")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Challenge-Assignments

    static let assignmentsPinchHitsOpenHeader = "Pinch hits open"

    static func assignmentsContextMeta(sentDateText: String?, dueDateText: String?) -> String {
        var parts: [String] = []
        if let sent = sentDateText, !sent.isEmpty {
            parts.append("Assignments sent \(sent)")
        }
        if let due = dueDateText, !due.isEmpty {
            parts.append(parts.isEmpty ? "Works due \(due)" : "works due \(due)")
        }
        return parts.joined(separator: " · ")
    }

    static func assignmentsPinchHitOpenTitle(recipient: String) -> String {
        let trimmed = recipient.trimmingCharacters(in: .whitespacesAndNewlines)
        return "For \(trimmed.isEmpty ? "an anonymous sign-up" : trimmed)"
    }

    static func assignmentsPinchHitOpenSubtitle(dueDateText: String?) -> String {
        guard let due = dueDateText, !due.isEmpty else { return "Original writer defaulted" }
        return "Original writer defaulted · due \(due)"
    }

    // MARK: - Challenge-SignUp

    static let signUpTitle = "Sign Up"
    static let signUpAddRequestLabel = "Add Another Request"
    static let signUpAddOfferLabel = "Add Another Offer"
    static let signUpYourSectionTitle = "Your sign-up"

    static func signUpContextMeta(
        limits: AO3ChallengeSignUpLimits?,
        takesOffers: Bool,
        requestCount: Int,
        offerCount: Int
    ) -> String {
        if let limits {
            let reqRange = countRange(limits.requestsRequired, limits.requestsAllowed)
            let reqWord = limits.requestsAllowed == 1 ? "request" : "requests"
            guard takesOffers else { return "\(reqRange) \(reqWord)" }
            let offRange = countRange(limits.offersRequired, limits.offersAllowed)
            let offWord = limits.offersAllowed == 1 ? "offer" : "offers"
            return "\(reqRange) \(reqWord) · \(offRange) \(offWord)"
        }
        let reqText = plural(requestCount, singular: "request")
        guard takesOffers else { return reqText }
        return "\(reqText) · \(plural(offerCount, singular: "offer"))"
    }

    // MARK: - Challenge-SignUps

    static let signUpsTitle = "Sign-ups"

    struct TagChipItem: Hashable, Identifiable, Sendable {
        let label: String
        let isTinted: Bool
        var id: String { "\(isTinted ? "t" : "n"):\(label)" }
    }

    static func signUpRequestChips(for signUp: AO3ChallengeSignUp, limit: Int = 3) -> [TagChipItem] {
        var seen = Set<String>()
        var result: [TagChipItem] = []

        func append(_ raw: String, isTinted: Bool) {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed.lowercased()).inserted else { return }
            result.append(TagChipItem(label: trimmed, isTinted: isTinted))
        }

        for prompt in signUp.requests {
            for rel in prompt.relationships { append(rel, isTinted: true) }
        }
        for prompt in signUp.requests {
            for fandom in prompt.fandoms { append(FandomDisplayName.bareTitle(fandom), isTinted: false) }
            if prompt.anyFandom { append("Any Fandom", isTinted: false) }
        }
        for prompt in signUp.requests {
            for character in prompt.characters { append(character, isTinted: false) }
        }
        return Array(result.prefix(max(0, limit)))
    }

    static func signUpOfferMeta(
        offers: [AO3ChallengePrompt],
        takesOffers: Bool
    ) -> (text: String, isWarning: Bool)? {
        guard takesOffers else { return nil }
        if offers.isEmpty {
            return ("No offer yet", true)
        }
        var seen = Set<String>()
        var fandoms: [String] = []
        for offer in offers {
            for fandom in offer.fandoms {
                let bare = FandomDisplayName.bareTitle(fandom)
                if seen.insert(bare.lowercased()).inserted {
                    fandoms.append(bare)
                }
            }
            if offer.anyFandom, seen.insert("any fandom").inserted {
                fandoms.append("Any Fandom")
            }
        }
        if !fandoms.isEmpty {
            let shown = fandoms.prefix(3).joined(separator: ", ")
            let suffix = fandoms.count > 3 ? " +\(fandoms.count - 3)" : ""
            return ("Offers \(shown)\(suffix)", false)
        }
        return (AO3ChallengeCountText.plural(offers.count, "offer"), false)
    }

    static func signUpsEmptyTitle(filterName: String, isAllFilter: Bool, matchUnavailable: Bool) -> String {
        if matchUnavailable && !isAllFilter { return "Match state unavailable" }
        if isAllFilter { return "No sign-ups yet" }
        return "No \(filterName.lowercased()) sign-ups"
    }

    static func signUpsEmptyBody(filterName: String, isAllFilter: Bool, matchUnavailable: Bool) -> String {
        if matchUnavailable && !isAllFilter {
            return "No sign-up can be shown as matched or unmatched without assignments."
        }
        if isAllFilter { return "Sign-ups will appear here as people join the challenge." }
        return "No sign-ups in this page match the \"\(filterName)\" filter."
    }

    // MARK: - Prompt-Meme

    static let promptMemeNewPromptLabel = "New Prompt"
    static let promptMemeClaimedByMeChipLabel = "Claimed by me"

    static func promptMemeEmptyTitle(filterName: String, isAllFilter: Bool) -> String {
        isAllFilter ? "No prompts yet" : "No \(filterName.lowercased()) prompts"
    }

    static func promptMemeEmptyBody(filterName: String, isAllFilter: Bool) -> String {
        if isAllFilter { return "Prompts will appear here once someone posts one." }
        return "No prompts on this page match the \"\(filterName)\" filter."
    }

    static func promptMemeContextKicker(fandoms: [[String]]) -> String {
        let nonEmpty = fandoms.compactMap(\.first).map(FandomDisplayName.bareTitle)
        let unique = Set(nonEmpty)
        if unique.count == 1, let sole = unique.first, !sole.isEmpty {
            return "Prompt meme · \(sole)"
        }
        return "Prompt meme"
    }

    static func promptMemeOpenUntil(_ dateText: String) -> String {
        "Open for prompts until \(dateText)"
    }

    static func promptMemeByline(isAnonymous: Bool, owner: String?) -> String {
        if isAnonymous { return "Anonymous" }
        let trimmed = owner?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "Unknown poster" : "by \(trimmed)"
    }

    static func promptMemeStatusMeta(
        claimedByCurrentUser: Bool,
        claimantCount: Int
    ) -> (text: String, isAccent: Bool) {
        if claimedByCurrentUser { return ("Claimed by you", true) }
        if claimantCount > 0 { return (AO3ChallengeCountText.plural(claimantCount, "claim"), false) }
        return ("Unclaimed", false)
    }

    static func promptMemeTagChips(
        fandoms: [String],
        tagSummary: String,
        limit: Int = 4
    ) -> [TagChipItem] {
        var seen = Set<String>()
        var result: [TagChipItem] = []

        func append(_ raw: String, isTinted: Bool) {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed.lowercased()).inserted else { return }
            result.append(TagChipItem(label: trimmed, isTinted: isTinted))
        }

        let summaryTags = tagSummary
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        for tag in summaryTags where tag.contains("/") {
            append(tag, isTinted: true)
        }
        for tag in summaryTags where !tag.contains("/") {
            append(tag, isTinted: false)
        }
        if result.isEmpty {
            for fandom in fandoms {
                append(FandomDisplayName.bareTitle(fandom), isTinted: false)
            }
        }
        return Array(result.prefix(max(0, limit)))
    }

    // MARK: - Prompt-Tags (Tag Set)

    static let tagSetKicker = "Tag set"
    static let tagSetNominationsHeader = "Nominations to review"
    static let tagSetNewBadge = "New"
    static let tagSetLetNominateLabel = "Let participants nominate"

    static func tagSetFieldLabel(_ field: AO3TagSetField) -> String {
        switch field {
        case .fandom: "Fandom"
        case .character: "Character"
        case .relationship: "Relationship"
        case .freeform: "Additional tag"
        }
    }

    static func tagSetNominationSubtitle(field: AO3TagSetField, parentTagName: String) -> String {
        let base = tagSetFieldLabel(field)
        let parent = parentTagName.trimmingCharacters(in: .whitespacesAndNewlines)
        return parent.isEmpty ? base : "\(base) · \(parent)"
    }

    static func tagSetParsedNames(_ raw: String) -> [String] {
        raw.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    static let tagSetEmptyNominationsTitle = "No nominations yet"
    static let tagSetEmptyNominationsBody = "Nothing has been nominated to this tag set."
    static let assignmentsEmptyMatched = "No matched assignments yet."
    static let assignmentsEmptyPinchHits = "No pinch hits open right now."
    static let assignmentsEmptyUnmatched = "No defaulted assignments are waiting for a pinch hitter."
}

// MARK: - Theme-Aware Semantic Board Colours

/// Adaptive status inks and badge pairs across Light, Sepia, Dark, and OLED themes.
/// Never substitutes a hardcoded Light-only hex from a design board.
enum ChallengeBoardColors {
    static func warningInk(for theme: ReaderTheme) -> Color {
        switch theme {
        case .light: Color(red: 0.76, green: 0.37, blue: 0.00)
        case .sepia: Color(red: 0.60, green: 0.29, blue: 0.02)
        case .dark, .oled: Color(red: 1.00, green: 0.67, blue: 0.30)
        }
    }

    static func warningBadge(for theme: ReaderTheme) -> (foreground: Color, background: Color) {
        switch theme {
        case .light:
            return (Color(red: 0.42, green: 0.23, blue: 0.00), Color.orange.opacity(0.16))
        case .sepia:
            return (Color(red: 0.45, green: 0.24, blue: 0.02), Color.orange.opacity(0.16))
        case .dark, .oled:
            return (Color(red: 1.00, green: 0.76, blue: 0.42), Color.orange.opacity(0.22))
        }
    }

    static func infoBadge(for theme: ReaderTheme) -> (foreground: Color, background: Color) {
        switch theme {
        case .light:
            return (Color(red: 0.12, green: 0.31, blue: 0.60), Color.blue.opacity(0.13))
        case .sepia:
            return (Color(red: 0.16, green: 0.32, blue: 0.52), Color.blue.opacity(0.14))
        case .dark, .oled:
            return (Color(red: 0.54, green: 0.76, blue: 1.00), Color.blue.opacity(0.24))
        }
    }

    static func successBadge(for theme: ReaderTheme) -> (foreground: Color, background: Color) {
        (theme.statusSuccessColor, theme.statusSuccessColor.opacity(theme.isDarkFamily ? 0.22 : 0.14))
    }

    static func destructiveBadge(for theme: ReaderTheme) -> (foreground: Color, background: Color) {
        (theme.errorColor, theme.errorColor.opacity(theme.isDarkFamily ? 0.22 : 0.12))
    }
}

// MARK: - Shared Board Surfaces & Components

/// Visual ground style for `ChallengeBoardContextCard` and `ChallengeBoardStatStrip`.
enum ChallengeBoardSurfaceKind {
    /// On a plain `ListScreen` (`contentBackdrop`): muted grey fill (`glassFill(0.09)`).
    case list
    /// On a grouped `FormScreen` (`cardBackdrop`): elevated `cardSurface` with hairline border.
    case form
}

/// Elevated grouped card surface matching `FormScreen`, `AO3-Collections`, and `Challenge`
/// (`#FFFFFF` on `#F2F2F7` in Light; themed `cardSurface` on `cardBackdrop` in Dark, OLED, and Sepia).
private struct ChallengeBoardCardModifier: ViewModifier {
    var cornerRadius: CGFloat = SubjectMetrics.cornerRadius

    @Environment(ThemeManager.self) private var theme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background(shape.fill(theme.appTheme.cardSurface))
            .clipShape(shape)
            .overlay(shape.strokeBorder(theme.appTheme.cardBorder, lineWidth: 0.5))
    }
}

extension View {
    func challengeBoardCard(cornerRadius: CGFloat = SubjectMetrics.cornerRadius) -> some View {
        modifier(ChallengeBoardCardModifier(cornerRadius: cornerRadius))
    }
}

/// Sentence-case 13 pt regular grouped section heading matching `FormScreen.dc.html`
/// and `AO3-Collections.dc.html` (`margin: 0 16px`, `#6C6C70`).
struct ChallengeBoardSectionHeader: View {
    let title: String
    var horizontalInset: CGFloat = SubjectMetrics.accountGutter + 16

    var body: some View {
        Text(title)
            .font(.footnote)
            .foregroundStyle(.secondaryInk)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, horizontalInset)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Sentence-case 13 pt footnote matching `FormScreen.dc.html` (`margin: 0 16px`, `#6C6C70`).
struct ChallengeBoardSectionFooter: View {
    let text: String
    var horizontalInset: CGFloat = 16

    var body: some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.secondaryInk)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, horizontalInset)
    }
}

/// Context header card matching `ListScreen.dc.html` and `FormScreen.dc.html`:
/// 52×52 rounded-14 colored icon tile, 11 pt uppercase kicker, 18 pt serif title, 13 pt meta line.
struct ChallengeBoardContextCard: View {
    let systemImage: String
    let kicker: String
    let title: String
    var meta: String?
    let palette: SubjectPalette
    var surface: ChallengeBoardSurfaceKind = .list

    @Environment(ThemeManager.self) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .headline) private var titleSize: CGFloat = 18
    @ScaledMetric(relativeTo: .caption2) private var kickerSize: CGFloat = 11

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 10) {
                    iconTile
                    textColumn
                }
            } else {
                HStack(alignment: .center, spacing: 12) {
                    iconTile
                    textColumn
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
        .accessibilityElement(children: .combine)
    }

    private var iconTile: some View {
        Image(systemName: systemImage)
            .font(.system(size: 22, weight: .semibold))
            .foregroundStyle(ThemeManager.label(on: palette.accent))
            .frame(width: 52, height: 52)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(palette.accent)
            )
            .accessibilityHidden(true)
    }

    private var textColumn: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(kicker.uppercased())
                .font(.system(size: kickerSize, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(palette.accent)
                .fixedSize(horizontal: false, vertical: true)

            Text(title)
                .font(.system(size: titleSize, weight: .semibold, design: .serif))
                .foregroundStyle(.primary)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                .fixedSize(horizontal: false, vertical: true)

            if let meta, !meta.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(meta)
                    .font(.footnote)
                    .foregroundStyle(.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var cardBackground: some View {
        let shape = RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous)
        switch surface {
        case .list:
            shape
                .fill(theme.appTheme.glassFill(0.09))
                .overlay(shape.strokeBorder(theme.appTheme.glassStroke(0.12), lineWidth: 0.5))
        case .form:
            shape
                .fill(theme.appTheme.cardSurface)
                .overlay(shape.strokeBorder(theme.appTheme.cardBorder, lineWidth: 0.5))
        }
    }
}

/// Multi-column stat strip matching `ListScreen.dc.html` and `FormScreen.dc.html`:
/// 16 pt radius, 19 pt bold tabular numbers, 11 pt sentence-case labels, 0.5 pt dividers.
/// Wraps to two cells per row at accessibility text sizes.
struct ChallengeBoardStatStrip: View {
    struct Cell: Identifiable {
        let id = UUID()
        let value: String
        let label: String
        var tint: Color?
        var accessibilityText: String?

        init(
            value: String,
            label: String,
            tint: Color? = nil,
            accessibilityText: String? = nil
        ) {
            self.value = value
            self.label = label
            self.tint = tint
            self.accessibilityText = accessibilityText
        }
    }

    let cells: [Cell]
    var surface: ChallengeBoardSurfaceKind = .list

    @Environment(ThemeManager.self) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .title3) private var numberSize: CGFloat = 19
    @ScaledMetric(relativeTo: .caption2) private var labelSize: CGFloat = 11

    var body: some View {
        if !cells.isEmpty {
            Group {
                if dynamicTypeSize.isAccessibilitySize, cells.count > 2 {
                    VStack(spacing: 0) {
                        ForEach(Array(stride(from: 0, to: cells.count, by: 2)), id: \.self) { start in
                            if start > 0 {
                                Rectangle()
                                    .fill(theme.appTheme.glassStroke(0.13))
                                    .frame(height: 0.5)
                            }
                            row(Array(cells[start ..< min(start + 2, cells.count)]))
                        }
                    }
                } else {
                    row(cells)
                }
            }
            .background(stripBackground)
            .clipShape(RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous))
        }
    }

    private func row(_ rowCells: [Cell]) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(rowCells.enumerated()), id: \.offset) { index, cell in
                if index > 0 {
                    Rectangle()
                        .fill(theme.appTheme.glassStroke(0.13))
                        .frame(width: 0.5)
                }
                VStack(spacing: 2) {
                    Text(cell.value)
                        .font(.system(size: numberSize, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(cell.tint ?? Color.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    Text(cell.label)
                        .font(.system(size: labelSize))
                        .foregroundStyle(.secondaryInk)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                        .minimumScaleFactor(0.8)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .padding(.horizontal, 4)
                .combinedAccessibilityRow(cell.accessibilityText ?? "\(cell.value) \(cell.label)")
            }
        }
    }

    @ViewBuilder
    private var stripBackground: some View {
        let shape = RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous)
        switch surface {
        case .list:
            shape
                .fill(theme.appTheme.glassFill(0.09))
                .overlay(shape.strokeBorder(theme.appTheme.glassStroke(0.12), lineWidth: 0.5))
        case .form:
            shape
                .fill(theme.appTheme.cardSurface)
                .overlay(shape.strokeBorder(theme.appTheme.cardBorder, lineWidth: 0.5))
        }
    }
}

/// Compact pill badge matching `ListScreen.dc.html` and `FormScreen.dc.html`
/// (`padding: 2×7`, `12 pt bold`, sentence case).
struct ChallengeBoardBadge: View {
    enum Style {
        case accentFill
        case tinted(foreground: Color, background: Color)
        case neutral
    }

    let text: String
    var style: Style = .neutral

    @Environment(ThemeManager.self) private var theme
    @ScaledMetric(relativeTo: .caption) private var fontSize: CGFloat = 12

    var body: some View {
        Text(text)
            .font(.system(size: fontSize, weight: .bold))
            .lineLimit(1)
            .fixedSize()
            .foregroundStyle(foreground)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(Capsule().fill(background))
            .accessibilityLabel(text)
    }

    private var foreground: AnyShapeStyle {
        switch style {
        case .accentFill:
            return AnyShapeStyle(theme.onEffectiveTint)
        case let .tinted(fg, _):
            return AnyShapeStyle(fg)
        case .neutral:
            return AnyShapeStyle(.secondaryInk)
        }
    }

    private var background: Color {
        switch style {
        case .accentFill:
            return theme.effectiveTint
        case let .tinted(_, bg):
            return bg
        case .neutral:
            return theme.appTheme.glassFill(0.12)
        }
    }
}

/// Compact tag pill matching `ListScreen.dc.html` (`12 pt`, tinted crimson for relationships,
/// neutral fill for fandoms/characters/freeforms).
struct ChallengeBoardTagPill: View {
    let text: String
    var isTinted: Bool = false

    @Environment(ThemeManager.self) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .caption) private var fontSize: CGFloat = 12

    var body: some View {
        let tintedFill = theme.accentInk.opacity(theme.appTheme.isDarkFamily ? 0.18 : 0.11)
        Text(text)
            .font(.system(size: fontSize, weight: isTinted ? .semibold : .regular))
            .foregroundStyle(isTinted ? AnyShapeStyle(theme.accentInk) : AnyShapeStyle(.primary))
            .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(
                SubjectMetrics.controlShape(dynamicTypeSize)
                    .fill(isTinted ? tintedFill : theme.appTheme.glassFill(0.10))
            )
    }
}

/// Plain-list section heading matching `ListScreen.dc.html` (`20 pt bold` title + `15 pt` count).
struct ChallengeBoardListSectionHeader: View {
    let title: String
    var count: Int?
    var countText: String?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .title3) private var titleSize: CGFloat = 20
    @ScaledMetric(relativeTo: .subheadline) private var countSize: CGFloat = 15

    var body: some View {
        let countDisplay = countText ?? count.map { $0.formatted() }
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 8))
        layout {
            Text(title)
                .font(.system(size: titleSize, weight: .bold))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            if let countDisplay, !countDisplay.isEmpty {
                Text(countDisplay)
                    .font(.system(size: countSize))
                    .monospacedDigit()
                    .foregroundStyle(.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// Filter pill matching `ListScreen.dc.html` (`34 pt` height, `13 pt` horizontal padding,
/// `14 pt semibold`, solid accent fill when selected, neutral fill when inactive).
struct ChallengeBoardChipLabel: View {
    let text: String
    let isSelected: Bool
    var systemImage: String?

    @Environment(ThemeManager.self) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .subheadline) private var fontSize: CGFloat = 14

    var body: some View {
        HStack(spacing: 5) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: fontSize * 0.85, weight: .semibold))
            }
            Text(text)
                .font(.system(size: fontSize, weight: .semibold))
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                .fixedSize(horizontal: !dynamicTypeSize.isAccessibilitySize, vertical: true)
        }
        .foregroundStyle(isSelected ? AnyShapeStyle(theme.onEffectiveTint) : AnyShapeStyle(.primary))
        .padding(.horizontal, 13)
        .padding(.vertical, 7)
        .frame(minHeight: 34)
        .background(
            SubjectMetrics.controlShape(dynamicTypeSize)
                .fill(isSelected ? theme.effectiveTint : theme.appTheme.glassFill(0.10))
        )
    }
}

/// Compact inline row action pill matching `ListScreen.dc.html` (`30 pt` min height,
/// `14 pt semibold`, `primary` / `softAccent` / `destructive` / `secondary`).
struct ChallengeBoardInlineActionButton: View {
    enum Role {
        case primary
        case softAccent
        case destructive
        case secondary
    }

    let title: String
    var systemImage: String?
    var role: Role
    var isBusy: Bool = false
    var isDisabled: Bool = false
    let action: () -> Void

    @Environment(ThemeManager.self) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .subheadline) private var fontSize: CGFloat = 14

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if isBusy {
                    ProgressView()
                        .controlSize(.small)
                        .tint(spinnerTint)
                } else if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: fontSize * 0.82, weight: .semibold))
                }
                Text(title)
                    .font(.system(size: fontSize, weight: .semibold))
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                    .fixedSize(horizontal: !dynamicTypeSize.isAccessibilitySize, vertical: true)
            }
            .foregroundStyle(foregroundStyle)
            .padding(.horizontal, role == .softAccent ? 12 : 14)
            .padding(.vertical, 6)
            .frame(minHeight: 30)
            .background(
                SubjectMetrics.controlShape(dynamicTypeSize)
                    .fill(backgroundColor)
            )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled || isBusy)
        .opacity(isDisabled && !isBusy ? 0.45 : 1)
        .accessibilityLabel(title)
    }

    private var foregroundStyle: AnyShapeStyle {
        switch role {
        case .primary:
            return AnyShapeStyle(theme.onEffectiveTint)
        case .softAccent:
            return AnyShapeStyle(theme.accentInk)
        case .destructive:
            return AnyShapeStyle(theme.appTheme.errorColor)
        case .secondary:
            return AnyShapeStyle(.primary)
        }
    }

    private var spinnerTint: Color {
        switch role {
        case .primary:
            return theme.onEffectiveTint
        case .softAccent:
            return theme.accentInk
        case .destructive:
            return theme.appTheme.errorColor
        case .secondary:
            return theme.accentInk
        }
    }

    private var backgroundColor: Color {
        switch role {
        case .primary:
            return theme.effectiveTint
        case .softAccent:
            return theme.accentInk.opacity(theme.appTheme.isDarkFamily ? 0.20 : 0.11)
        case .destructive:
            return theme.appTheme.errorColor.opacity(theme.appTheme.isDarkFamily ? 0.20 : 0.11)
        case .secondary:
            return theme.appTheme.glassFill(0.10)
        }
    }
}

/// Decorative 34×46 rounded-5 cover gradient tile matching `ListScreen.dc.html` rows.
struct ChallengeBoardCoverTile: View {
    let seed: String

    @Environment(ThemeManager.self) private var theme

    var body: some View {
        let hue = CoverArt.hue(for: seed)
        let dark = Color(hue: hue, saturation: 0.46, brightness: theme.appTheme.isDarkFamily ? 0.34 : 0.32)
        let light = Color(hue: (hue + 0.06).truncatingRemainder(dividingBy: 1.0), saturation: 0.50, brightness: 0.48)
        RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [dark, light],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: 34, height: 46)
            .accessibilityHidden(true)
    }
}

/// Leading-icon navigation row matching `Challenge.dc.html` (`48 pt` min height, `16 pt` horizontal
/// padding, `12 pt` gap, `20 pt` accent icon, `16 pt` title, `15 pt` secondary detail, chevron).
struct ChallengeBoardHubRow: View {
    let systemImage: String
    let title: String
    var detail: String?
    var showsDisclosure: Bool = true

    @Environment(ThemeManager.self) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var titleSize: CGFloat = 16
    @ScaledMetric(relativeTo: .subheadline) private var detailSize: CGFloat = 15

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                HStack(alignment: .top, spacing: 12) {
                    iconView.padding(.top, 2)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.system(size: titleSize))
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                        if let detail, !detail.isEmpty {
                            Text(detail)
                                .font(.system(size: detailSize))
                                .foregroundStyle(.secondaryInk)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if showsDisclosure { chevronView.padding(.top, 4) }
                }
            } else {
                HStack(spacing: 12) {
                    iconView
                    Text(title)
                        .font(.system(size: titleSize))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    if let detail, !detail.isEmpty {
                        Text(detail)
                            .font(.system(size: detailSize))
                            .foregroundStyle(.secondaryInk)
                            .lineLimit(1)
                    }
                    if showsDisclosure { chevronView }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(minHeight: 48)
        .contentShape(Rectangle())
    }

    private var iconView: some View {
        Image(systemName: systemImage)
            .font(.system(size: 17, weight: .medium))
            .foregroundStyle(theme.accentInk)
            .frame(width: 22, alignment: .center)
            .accessibilityHidden(true)
    }

    private var chevronView: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.tertiary)
            .accessibilityHidden(true)
    }
}

/// Grouped toggle row with optional subtitle matching `FormScreen.dc.html` (`16 pt` label,
/// `13 pt` secondary subtitle, trailing switch; stacks at accessibility text sizes).
struct ChallengeBoardToggleRow: View {
    let title: String
    var subtitle: String?
    @Binding var isOn: Bool
    var isDisabled: Bool = false

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var titleSize: CGFloat = 16
    @ScaledMetric(relativeTo: .footnote) private var subtitleSize: CGFloat = 13

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 6) {
                    labelStack
                        .accessibilityHidden(true)
                    Toggle(title, isOn: $isOn)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .accentFill()
                        .disabled(isDisabled)
                        .accessibilityLabel(title)
                        .accessibilityHint(subtitle ?? "")
                }
            } else {
                Toggle(isOn: $isOn) {
                    labelStack
                }
                .toggleStyle(.switch)
                .accentFill()
                .disabled(isDisabled)
                .accessibilityLabel(title)
                .accessibilityHint(subtitle ?? "")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .frame(minHeight: 46)
        .opacity(isDisabled ? 0.45 : 1)
    }

    private var labelStack: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: titleSize))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.system(size: subtitleSize))
                    .foregroundStyle(.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Solid avatar circle (36×36) or rounded tile (40×40 / 44×44) with contrast-checked monogram or glyph.
struct ChallengeBoardAvatar: View {
    enum ShapeKind {
        case circle(size: CGFloat)
        case roundedSquare(size: CGFloat, radius: CGFloat)
    }

    let text: String?
    var systemImage: String?
    let color: Color
    var shapeKind: ShapeKind = .circle(size: 36)

    var body: some View {
        let fg = ThemeManager.label(on: color)
        Group {
            switch shapeKind {
            case let .circle(size):
                content(size: size, foreground: fg)
                    .frame(width: size, height: size)
                    .background(Circle().fill(color))
            case let .roundedSquare(size, radius):
                content(size: size, foreground: fg)
                    .frame(width: size, height: size)
                    .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(color))
            }
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func content(size: CGFloat, foreground: Color) -> some View {
        if let systemImage {
            Image(systemName: systemImage)
                .font(.system(size: size * 0.44, weight: .semibold))
                .foregroundStyle(foreground)
        } else if let text {
            Text(text)
                .font(.system(size: size * 0.42, weight: .bold))
                .foregroundStyle(foreground)
        }
    }
}

/// Top-right confirm action matching `FormScreen.dc.html` (filled accent checkmark circle on iOS,
/// standard confirmation button on macOS).
struct ChallengeBoardConfirmToolbarButton: View {
    let title: String
    var isBusy: Bool = false
    var isDisabled: Bool = false
    let action: () -> Void

    @Environment(ThemeManager.self) private var theme

    var body: some View {
        Button(action: action) {
            if isBusy {
                ProgressView()
                    .controlSize(.small)
                    #if os(iOS)
                    .tint(theme.onEffectiveTint)
                    #endif
            } else {
                #if os(iOS)
                Image(systemName: "checkmark")
                #else
                Text(title)
                #endif
            }
        }
        .sheetConfirmStyle()
        .disabled(isDisabled || isBusy)
        .accessibilityLabel(title)
    }
}
