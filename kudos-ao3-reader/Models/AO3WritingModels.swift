import Foundation

// MARK: - Form parameter keys (otwarchive Work / Chapter / Series forms)

/// Named constants for the work, chapter, series, and bulk-edit POST keys
/// otwarchive actually emits. Values come from
/// `app/views/works/_standard_form.html.erb`, `_work_form_tags.html.erb`,
/// `_chapter_form.html.erb`, `series/edit.html.erb`, and
/// `works/edit_multiple.html.erb`.
enum AO3WorkFormField {
    static let authenticityToken = "authenticity_token"
    static let methodOverride = "_method"

    static let title = "work[title]"
    static let rating = "work[rating_string]"
    static let warnings = "work[archive_warning_strings][]"
    static let categories = "work[category_strings][]"
    static let fandoms = "work[fandom_string]"
    static let relationships = "work[relationship_string]"
    static let characters = "work[character_string]"
    static let additionalTags = "work[freeform_string]"
    static let languageID = "work[language_id]"
    static let summary = "work[summary]"
    static let notes = "work[notes]"
    static let endnotes = "work[endnotes]"
    static let collectionNames = "work[collection_names]"
    static let collectionsToAdd = "work[collections_to_add]"
    static let collectionsToRemove = "work[collections_to_remove][]"
    static let recipients = "work[recipients]"
    static let wipLength = "work[wip_length]"
    static let backdate = "work[backdate]"
    static let restricted = "work[restricted]"
    static let moderatedCommenting = "work[moderated_commenting_enabled]"
    static let commentPermissions = "work[comment_permissions]"
    static let anonymous = "work[anonymous]"
    static let collectionInbox = "work[collection_inbox]"
    static let workSkinID = "work[work_skin_id]"
    static let seriesID = "work[series_attributes][id]"
    static let seriesTitle = "work[series_attributes][title]"
    static let parentURL = "work[parent_work_relationships_attributes][0][url]"
    static let parentTitle = "work[parent_work_relationships_attributes][0][title]"
    static let parentAuthor = "work[parent_work_relationships_attributes][0][author]"
    static let parentLanguageID = "work[parent_work_relationships_attributes][0][language_id]"
    static let parentTranslation = "work[parent_work_relationships_attributes][0][translation]"
    static let chapterTitle = "work[chapter_attributes][title]"
    static let chapterSummary = "work[chapter_attributes][summary]"
    static let chapterContent = "work[chapter_attributes][content]"
    static let chapterPublishedYear = "work[chapter_attributes][published_at(1i)]"
    static let chapterPublishedMonth = "work[chapter_attributes][published_at(2i)]"
    static let chapterPublishedDay = "work[chapter_attributes][published_at(3i)]"
    static let authorIDs = "work[author_attributes][ids][]"
    static let coauthors = "work[author_attributes][coauthors][]"
    static let authorByline = "work[author_attributes][byline]"
    static let pseudsToAdd = "work[pseuds_to_add]"
    static let workIDs = "work_ids[]"

    static let chapterOnlyTitle = "chapter[title]"
    static let chapterPosition = "chapter[position]"
    static let chapterWipLength = "chapter[wip_length]"
    static let chapterOnlySummary = "chapter[summary]"
    static let chapterNotes = "chapter[notes]"
    static let chapterEndnotes = "chapter[endnotes]"
    static let chapterOnlyContent = "chapter[content]"
    static let chapterAuthorIDs = "chapter[author_attributes][ids][]"
    static let chapterPublishedYear = "chapter[published_at(1i)]"
    static let chapterPublishedMonth = "chapter[published_at(2i)]"
    static let chapterPublishedDay = "chapter[published_at(3i)]"

    static let seriesFormTitle = "series[title]"
    static let seriesSummary = "series[summary]"
    static let seriesNotes = "series[series_notes]"
    static let seriesComplete = "series[complete]"
    static let seriesAuthorIDs = "series[author_attributes][ids][]"
    static let serialOrder = "serial[]"
    static let serialWorks = "serial_works[]"

    static let saveButton = "save_button"
    static let previewButton = "preview_button"
    static let postButton = "post_button"
    static let updateButton = "update_button"
    static let editButton = "edit_button"
    static let postWithoutPreviewButton = "post_without_preview_button"
}

/// Which posting-fieldset submit the form should send. Names match
/// `_posting_fieldset.html.erb` / `chapters/_posting_fieldset.html.erb`.
enum AO3WorkSubmitAction: String, Equatable, Sendable {
    case saveDraft = "save_button"
    case preview = "preview_button"
    case post = "post_button"
    case update = "update_button"
    case edit = "edit_button"
    case postWithoutPreview = "post_without_preview_button"
}

/// New work, posted edit, unposted draft, or the tags-only page.
enum AO3WorkFormKind: String, Equatable, Sendable {
    case new
    case edit
    case draft
    case editTags
}

// MARK: - Editor tags (1bu / 1bp)

/// One tag in the work editor. Autocomplete is suggestion, not a whitelist —
/// a free-typed name still POSTs. Suggestions from AO3's autocomplete JSON
/// are treated as canonical when the payload has no canonical flag.
nonisolated struct AO3EditorTag: Equatable, Hashable, Identifiable, Sendable {
    var name: String
    var isCanonical: Bool
    var workCount: Int?

    var id: String { name }
}

/// Ordered tag lists AO3 stores as comma-separated strings (`fandom_string`,
/// `relationship_string`, `character_string`, `freeform_string`). Order is
/// preserved because AO3 keeps entry order.
nonisolated struct AO3WorkTagSet: Equatable, Sendable {
    var rating: String = ""
    var warnings: [String] = []
    var categories: [String] = []
    var fandoms: [String] = []
    var relationships: [String] = []
    var characters: [String] = []
    var additionalTags: [String] = []

    /// Removing a chip is a diff against this set, not a delete-tag API.
    func diff(toward desired: AO3WorkTagSet) -> AO3WorkTagDiff {
        AO3WorkTagDiff(
            rating: rating == desired.rating ? nil : desired.rating,
            warningsAdded: AO3TagListDiff.added(from: warnings, to: desired.warnings),
            warningsRemoved: AO3TagListDiff.removed(from: warnings, to: desired.warnings),
            categoriesAdded: AO3TagListDiff.added(from: categories, to: desired.categories),
            categoriesRemoved: AO3TagListDiff.removed(from: categories, to: desired.categories),
            fandomsAdded: AO3TagListDiff.added(from: fandoms, to: desired.fandoms),
            fandomsRemoved: AO3TagListDiff.removed(from: fandoms, to: desired.fandoms),
            relationshipsAdded: AO3TagListDiff.added(from: relationships, to: desired.relationships),
            relationshipsRemoved: AO3TagListDiff.removed(from: relationships, to: desired.relationships),
            charactersAdded: AO3TagListDiff.added(from: characters, to: desired.characters),
            charactersRemoved: AO3TagListDiff.removed(from: characters, to: desired.characters),
            additionalAdded: AO3TagListDiff.added(from: additionalTags, to: desired.additionalTags),
            additionalRemoved: AO3TagListDiff.removed(from: additionalTags, to: desired.additionalTags)
        )
    }

    func parameters() -> [(String, String)] {
        var pairs: [(String, String)] = []
        if !rating.isEmpty {
            pairs.append((AO3WorkFormField.rating, rating))
        }
        if warnings.isEmpty {
            pairs.append((AO3WorkFormField.warnings, ""))
        } else {
            for warning in warnings {
                pairs.append((AO3WorkFormField.warnings, warning))
            }
        }
        for category in categories {
            pairs.append((AO3WorkFormField.categories, category))
        }
        pairs.append((AO3WorkFormField.fandoms, AO3TagListDiff.joined(fandoms)))
        pairs.append((AO3WorkFormField.relationships, AO3TagListDiff.joined(relationships)))
        pairs.append((AO3WorkFormField.characters, AO3TagListDiff.joined(characters)))
        pairs.append((AO3WorkFormField.additionalTags, AO3TagListDiff.joined(additionalTags)))
        return pairs
    }
}

/// Add/remove lists produced by comparing two ordered tag sets. Used by
/// `editTags` so a chip removal is a diff, then the full replacement AO3
/// expects is submitted.
nonisolated struct AO3WorkTagDiff: Equatable, Sendable {
    var rating: String?
    var warningsAdded: [String]
    var warningsRemoved: [String]
    var categoriesAdded: [String]
    var categoriesRemoved: [String]
    var fandomsAdded: [String]
    var fandomsRemoved: [String]
    var relationshipsAdded: [String]
    var relationshipsRemoved: [String]
    var charactersAdded: [String]
    var charactersRemoved: [String]
    var additionalAdded: [String]
    var additionalRemoved: [String]

    var isEmpty: Bool {
        rating == nil
            && warningsAdded.isEmpty && warningsRemoved.isEmpty
            && categoriesAdded.isEmpty && categoriesRemoved.isEmpty
            && fandomsAdded.isEmpty && fandomsRemoved.isEmpty
            && relationshipsAdded.isEmpty && relationshipsRemoved.isEmpty
            && charactersAdded.isEmpty && charactersRemoved.isEmpty
            && additionalAdded.isEmpty && additionalRemoved.isEmpty
    }
}

enum AO3TagListDiff {
    static func added(from current: [String], to desired: [String]) -> [String] {
        let have = Set(current.map(normalize))
        return desired.filter { !have.contains(normalize($0)) }
    }

    static func removed(from current: [String], to desired: [String]) -> [String] {
        let keep = Set(desired.map(normalize))
        return current.filter { !keep.contains(normalize($0)) }
    }

    /// Apply add-then-remove to one work's current list, preserving remaining
    /// order and appending adds at the end.
    static func applying(
        current: [String], adding: [String], removing: [String]
    ) -> [String] {
        let drop = Set(removing.map(normalize))
        var seen = Set<String>()
        var result: [String] = []
        for name in current + adding {
            let key = normalize(name)
            guard !key.isEmpty, !drop.contains(key), seen.insert(key).inserted else {
                continue
            }
            result.append(name.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return result
    }

    static func split(_ raw: String) -> [String] {
        raw.split(separator: ",", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    static func joined(_ names: [String]) -> String {
        names
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }

    private static func normalize(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

// MARK: - Collections / gifts / series (1bw)

/// How 1bw labels a collection row. Closed wins over moderated so a closed
/// moderated collection is shown as closed to new works.
enum AO3CollectionRowState: String, Equatable, Sendable {
    case open
    case closed
    case moderated
    case unknown
}

nonisolated struct AO3CollectionAccess: Equatable, Sendable {
    var isOpen: Bool = true
    var isModerated: Bool = false
    var isUnrevealed: Bool = false
    var isAnonymous: Bool = false

    var rowState: AO3CollectionRowState {
        if !isOpen { return .closed }
        if isModerated { return .moderated }
        return .open
    }
}

/// A collection the work can join, with state on the row so submitting to a
/// moderated collection can be shown as pending before the tap.
nonisolated struct AO3CollectionOffer: Equatable, Identifiable, Sendable {
    var name: String
    var title: String
    var access: AO3CollectionAccess
    var isSelected: Bool = false

    var id: String { name }
}

nonisolated struct AO3GiftRecipient: Equatable, Identifiable, Sendable {
    var name: String
    var id: String { name }
}

nonisolated struct AO3SeriesMembership: Equatable, Identifiable, Sendable {
    var seriesID: Int
    var title: String
    var position: Int?
    var workCount: Int?
    var isSelected: Bool = false

    var id: Int { seriesID }
}

nonisolated struct AO3ParentWorkDraft: Equatable, Sendable {
    var url: String = ""
    var title: String = ""
    var author: String = ""
    var languageID: String = ""
    var isTranslation: Bool = false
}

nonisolated struct AO3FormOption: Equatable, Identifiable, Sendable {
    var value: String
    var title: String
    var isSelected: Bool = false
    var id: String { value }
}

nonisolated struct AO3WorkChapterDraft: Equatable, Sendable {
    var title: String = ""
    var summary: String = ""
    var content: String = ""
    var publishedYear: String = ""
    var publishedMonth: String = ""
    var publishedDay: String = ""
}

nonisolated struct AO3CreatorDraft: Equatable, Sendable {
    var selectedPseudIDs: [String] = []
    var availablePseuds: [AO3FormOption] = []
    var coauthorByline: String = ""
}

nonisolated struct AO3WorkHiddenField: Equatable, Hashable, Sendable {
    var name: String
    var value: String
}

// MARK: - Work form (1bo / 1bs)

/// Parsed `/works/new`, `/works/:id/edit`, or a draft of the same form.
/// Grouped the way 1bo draws it: Required, Tags, Association, Text, Publication.
nonisolated struct AO3WorkForm: Equatable, Sendable {
    var kind: AO3WorkFormKind
    var workID: Int?
    var actionURL: URL
    var httpMethodOverride: String?
    var csrfToken: String
    var isDraft: Bool
    var isPosted: Bool

    // Required
    var title: String = ""
    var rating: String = ""
    var ratingOptions: [AO3FormOption] = []
    var warnings: [String] = []
    var warningOptions: [AO3FormOption] = []
    var fandoms: [String] = []
    var languageID: String = ""
    var languageOptions: [AO3FormOption] = []

    // Tags
    var categories: [String] = []
    var categoryOptions: [AO3FormOption] = []
    var relationships: [String] = []
    var characters: [String] = []
    var additionalTags: [String] = []

    // Association
    var collections: [AO3CollectionOffer] = []
    var collectionNames: [String] = []
    var gifts: [AO3GiftRecipient] = []
    var series: [AO3SeriesMembership] = []
    var newSeriesTitle: String = ""
    var parentWork: AO3ParentWorkDraft = AO3ParentWorkDraft()
    var existingParentTitles: [String] = []

    // Text
    var summary: String = ""
    var notes: String = ""
    var endnotes: String = ""
    var chapter: AO3WorkChapterDraft?
    var creators: AO3CreatorDraft = AO3CreatorDraft()

    // Publication
    var chaptersPosted: Int?
    var chapterTotal: String = ""
    var isChaptered: Bool = false
    var backdate: Bool = false
    var restricted: Bool = false
    var moderatedCommenting: Bool = false
    var commentPermissions: String = ""
    var commentPermissionOptions: [AO3FormOption] = []
    var anonymous: Bool?
    var collectionInbox: Bool?
    var workSkinID: String = ""
    var workSkinOptions: [AO3FormOption] = []
    var hiddenFields: [AO3WorkHiddenField] = []

    var tagSet: AO3WorkTagSet {
        AO3WorkTagSet(
            rating: rating,
            warnings: warnings,
            categories: categories,
            fandoms: fandoms,
            relationships: relationships,
            characters: characters,
            additionalTags: additionalTags
        )
    }

    /// Names the UI can show when Post is blocked locally. Draft save is not
    /// gated here — AO3 still validates on the server.
    func missingRequiredFields() -> [String] {
        var missing: [String] = []
        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            missing.append("Title")
        }
        if rating.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            missing.append("Rating")
        }
        if warnings.isEmpty {
            missing.append("Archive Warning")
        }
        if fandoms.isEmpty {
            missing.append("Fandoms")
        }
        if languageID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            missing.append("Language")
        }
        if kind == .new || isDraft, let chapter, chapter.content
            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            missing.append("Work Text")
        }
        return missing
    }

    func applyingCollectionStates(_ offers: [AO3CollectionOffer]) -> AO3WorkForm {
        var copy = self
        let selected = Set(collectionNames.map { $0.lowercased() })
        var merged: [AO3CollectionOffer] = []
        var seen = Set<String>()
        for offer in offers {
            var row = offer
            row.isSelected = selected.contains(offer.name.lowercased())
                || selected.contains(offer.title.lowercased())
            merged.append(row)
            seen.insert(offer.name.lowercased())
        }
        for name in collectionNames where !seen.contains(name.lowercased()) {
            merged.append(
                AO3CollectionOffer(
                    name: name,
                    title: name,
                    access: AO3CollectionAccess(),
                    isSelected: true
                )
            )
        }
        copy.collections = merged
        return copy
    }

    /// Full replacement body AO3's work form expects, plus the chosen submit.
    func parameters(submit: AO3WorkSubmitAction) -> [(String, String)] {
        var pairs: [(String, String)] = [
            (AO3WorkFormField.authenticityToken, csrfToken)
        ]
        if let method = httpMethodOverride, !method.isEmpty {
            pairs.append((AO3WorkFormField.methodOverride, method))
        }
        pairs.append((AO3WorkFormField.title, title))
        pairs.append(contentsOf: tagSet.parameters())
        pairs.append((AO3WorkFormField.languageID, languageID))
        pairs.append((AO3WorkFormField.summary, summary))
        pairs.append((AO3WorkFormField.notes, notes))
        pairs.append((AO3WorkFormField.endnotes, endnotes))
        pairs.append(
            (AO3WorkFormField.collectionNames, AO3TagListDiff.joined(collectionNames))
        )
        pairs.append(
            (AO3WorkFormField.recipients, AO3TagListDiff.joined(gifts.map(\.name)))
        )
        if let selected = series.first(where: \.isSelected) {
            pairs.append((AO3WorkFormField.seriesID, String(selected.seriesID)))
        } else if !newSeriesTitle.isEmpty {
            pairs.append((AO3WorkFormField.seriesTitle, newSeriesTitle))
        } else {
            pairs.append((AO3WorkFormField.seriesID, ""))
            pairs.append((AO3WorkFormField.seriesTitle, ""))
        }
        if !parentWork.url.isEmpty || !parentWork.title.isEmpty {
            pairs.append((AO3WorkFormField.parentURL, parentWork.url))
            pairs.append((AO3WorkFormField.parentTitle, parentWork.title))
            pairs.append((AO3WorkFormField.parentAuthor, parentWork.author))
            pairs.append((AO3WorkFormField.parentLanguageID, parentWork.languageID))
            if parentWork.isTranslation {
                pairs.append((AO3WorkFormField.parentTranslation, "1"))
            }
        }
        pairs.append((AO3WorkFormField.wipLength, chapterTotal))
        pairs.append((AO3WorkFormField.backdate, backdate ? "1" : "0"))
        pairs.append((AO3WorkFormField.restricted, restricted ? "1" : "0"))
        pairs.append(
            (AO3WorkFormField.moderatedCommenting, moderatedCommenting ? "1" : "0")
        )
        if !commentPermissions.isEmpty {
            pairs.append((AO3WorkFormField.commentPermissions, commentPermissions))
        }
        if let anonymous {
            pairs.append((AO3WorkFormField.anonymous, anonymous ? "1" : "0"))
        }
        if let collectionInbox {
            pairs.append((AO3WorkFormField.collectionInbox, collectionInbox ? "1" : "0"))
        }
        if !workSkinID.isEmpty {
            pairs.append((AO3WorkFormField.workSkinID, workSkinID))
        }
        if let chapter {
            pairs.append((AO3WorkFormField.chapterTitle, chapter.title))
            pairs.append((AO3WorkFormField.chapterSummary, chapter.summary))
            pairs.append((AO3WorkFormField.chapterContent, chapter.content))
            if !chapter.publishedYear.isEmpty {
                pairs.append((AO3WorkFormField.chapterPublishedYear, chapter.publishedYear))
                pairs.append((AO3WorkFormField.chapterPublishedMonth, chapter.publishedMonth))
                pairs.append((AO3WorkFormField.chapterPublishedDay, chapter.publishedDay))
            }
        }
        for id in creators.selectedPseudIDs {
            pairs.append((AO3WorkFormField.authorIDs, id))
        }
        if !creators.coauthorByline.isEmpty {
            pairs.append((AO3WorkFormField.authorByline, creators.coauthorByline))
        }
        var overridden = Set(pairs.map(\.0))
        for hidden in hiddenFields where !overridden.contains(hidden.name) {
            pairs.append((hidden.name, hidden.value))
            overridden.insert(hidden.name)
        }
        pairs.append((submit.rawValue, "1"))
        return pairs
    }
}

// MARK: - Tags-only page (1bp)

nonisolated struct AO3EditTagsForm: Equatable, Sendable {
    var workID: Int
    var actionURL: URL
    var httpMethodOverride: String?
    var csrfToken: String
    var tags: AO3WorkTagSet
    var warningOptions: [AO3FormOption] = []
    var categoryOptions: [AO3FormOption] = []
    var ratingOptions: [AO3FormOption] = []
    var languageID: String = ""
    var languageOptions: [AO3FormOption] = []

    func parameters(submit: AO3WorkSubmitAction) -> [(String, String)] {
        var pairs: [(String, String)] = [
            (AO3WorkFormField.authenticityToken, csrfToken)
        ]
        if let method = httpMethodOverride, !method.isEmpty {
            pairs.append((AO3WorkFormField.methodOverride, method))
        }
        pairs.append(contentsOf: tags.parameters())
        if !languageID.isEmpty {
            pairs.append((AO3WorkFormField.languageID, languageID))
        }
        pairs.append((submit.rawValue, "1"))
        return pairs
    }
}

// MARK: - Chapter form (1bq)

nonisolated struct AO3ChapterForm: Equatable, Sendable {
    var workID: Int
    var chapterID: Int?
    var actionURL: URL
    var httpMethodOverride: String?
    var csrfToken: String
    var title: String = ""
    var position: String = ""
    /// When false (one-shot), position is omitted rather than sending a dummy.
    var includePosition: Bool = true
    var wipLength: String = ""
    var summary: String = ""
    var notes: String = ""
    var endnotes: String = ""
    var content: String = ""
    var publishedYear: String = ""
    var publishedMonth: String = ""
    var publishedDay: String = ""
    var isDraft: Bool = false
    var creators: AO3CreatorDraft = AO3CreatorDraft()

    func parameters(submit: AO3WorkSubmitAction) -> [(String, String)] {
        var pairs: [(String, String)] = [
            (AO3WorkFormField.authenticityToken, csrfToken)
        ]
        if let method = httpMethodOverride, !method.isEmpty {
            pairs.append((AO3WorkFormField.methodOverride, method))
        }
        pairs.append((AO3WorkFormField.chapterOnlyTitle, title))
        if includePosition, !position.isEmpty {
            pairs.append((AO3WorkFormField.chapterPosition, position))
        }
        if !wipLength.isEmpty {
            pairs.append((AO3WorkFormField.chapterWipLength, wipLength))
        }
        pairs.append((AO3WorkFormField.chapterOnlySummary, summary))
        pairs.append((AO3WorkFormField.chapterNotes, notes))
        pairs.append((AO3WorkFormField.chapterEndnotes, endnotes))
        pairs.append((AO3WorkFormField.chapterOnlyContent, content))
        if !publishedYear.isEmpty {
            pairs.append((AO3WorkFormField.chapterPublishedYear, publishedYear))
            pairs.append((AO3WorkFormField.chapterPublishedMonth, publishedMonth))
            pairs.append((AO3WorkFormField.chapterPublishedDay, publishedDay))
        }
        for id in creators.selectedPseudIDs {
            pairs.append((AO3WorkFormField.chapterAuthorIDs, id))
        }
        pairs.append((submit.rawValue, "1"))
        return pairs
    }
}

// MARK: - Series (1br)

nonisolated struct AO3SeriesForm: Equatable, Sendable {
    var seriesID: Int?
    var actionURL: URL
    var httpMethodOverride: String?
    var csrfToken: String
    var title: String = ""
    var summary: String = ""
    var notes: String = ""
    var isComplete: Bool = false
    var creators: AO3CreatorDraft = AO3CreatorDraft()
    var works: [AO3SeriesWorkRow] = []
    /// When true, the new-series form is too sparse to POST from the app.
    var openOnAO3ForCreate: Bool = false

    func parameters() -> [(String, String)] {
        var pairs: [(String, String)] = [
            (AO3WorkFormField.authenticityToken, csrfToken),
            (AO3WorkFormField.seriesFormTitle, title),
            (AO3WorkFormField.seriesSummary, summary),
            (AO3WorkFormField.seriesNotes, notes),
            (AO3WorkFormField.seriesComplete, isComplete ? "1" : "0")
        ]
        if let method = httpMethodOverride, !method.isEmpty {
            pairs.insert((AO3WorkFormField.methodOverride, method), at: 1)
        }
        for id in creators.selectedPseudIDs {
            pairs.append((AO3WorkFormField.seriesAuthorIDs, id))
        }
        return pairs
    }
}

nonisolated struct AO3SeriesWorkRow: Equatable, Identifiable, Sendable {
    var workID: Int?
    var serialWorkID: Int
    var title: String
    var position: Int
    var isDraft: Bool = false

    var id: Int { serialWorkID }
}

/// One write in a series reorder. Position lives on `SerialWork`, so three
/// works are three sequential POSTs. Each payload carries the full ordered
/// `serial[]` list AO3's `update_positions` ajax path expects
/// (`series_controller.rb`).
nonisolated struct AO3SeriesPositionWrite: Equatable, Sendable {
    var seriesID: Int
    var serialWorkID: Int
    var workID: Int?
    var position: Int
    var orderedSerialWorkIDs: [Int]

    var path: String { "/series/\(seriesID)/update_positions" }

    func parameters(csrfToken: String) -> [(String, String)] {
        var pairs: [(String, String)] = [
            (AO3WorkFormField.authenticityToken, csrfToken)
        ]
        for id in orderedSerialWorkIDs {
            pairs.append((AO3WorkFormField.serialOrder, String(id)))
        }
        return pairs
    }
}

enum AO3SeriesReorderPlan {
    /// Builds N writes in the given work order. `serialByWorkID` maps a work
    /// to its `SerialWork` id from the manage page.
    static func writes(
        seriesID: Int,
        orderedWorkIDs: [Int],
        serialByWorkID: [Int: Int]
    ) -> [AO3SeriesPositionWrite] {
        let orderedSerial = orderedWorkIDs.compactMap { serialByWorkID[$0] }
        return orderedWorkIDs.enumerated().compactMap { index, workID in
            guard let serialID = serialByWorkID[workID] else { return nil }
            return AO3SeriesPositionWrite(
                seriesID: seriesID,
                serialWorkID: serialID,
                workID: workID,
                position: index + 1,
                orderedSerialWorkIDs: orderedSerial
            )
        }
    }

    /// Same plan when the caller already has serial-work ids in the desired
    /// order (manage-page drag result).
    static func writes(
        seriesID: Int,
        orderedSerialWorkIDs: [Int]
    ) -> [AO3SeriesPositionWrite] {
        orderedSerialWorkIDs.enumerated().map { index, serialID in
            AO3SeriesPositionWrite(
                seriesID: seriesID,
                serialWorkID: serialID,
                workID: nil,
                position: index + 1,
                orderedSerialWorkIDs: orderedSerialWorkIDs
            )
        }
    }
}

// MARK: - Bulk edit (1bn)

/// AO3 `/works/edit_multiple` is add-and-remove, not replace, except for the
/// two single-value fields that overwrite: rating and language.
nonisolated struct AO3BulkEditChanges: Equatable, Sendable {
    var workIDs: [Int] = []
    var tagsToAdd: AO3WorkTagSet = AO3WorkTagSet()
    var tagsToRemove: AO3WorkTagSet = AO3WorkTagSet()
    /// Overwrites whatever each work had when non-nil. Empty / nil leaves
    /// every work untouched.
    var rating: String?
    var languageID: String?
    var collectionsToAdd: [String] = []
    var collectionsToRemove: [String] = []
    var restricted: String?
    var moderatedCommenting: String?
    var commentPermissions: String?
    var workSkinID: String?
    var pseudsToAdd: String = ""

    /// Rating and language are the only single-value fields that overwrite.
    static let overwriteFieldKeys = [
        AO3WorkFormField.rating,
        AO3WorkFormField.languageID
    ]

    func isOverwriteField(_ name: String) -> Bool {
        Self.overwriteFieldKeys.contains(name)
    }

    /// Encode for `update_multiple`. Blank groups are omitted so AO3 leaves
    /// those fields untouched. Tag add/remove is resolved against one work's
    /// current lists via `applying(to:)`; the bulk POST itself only sends
    /// *add* strings (AO3's tag fields replace when filled) plus the
    /// overwrite scalars.
    func parameters(csrfToken: String, methodOverride: String = "patch") -> [(String, String)] {
        var pairs: [(String, String)] = [
            (AO3WorkFormField.authenticityToken, csrfToken),
            (AO3WorkFormField.methodOverride, methodOverride)
        ]
        for id in workIDs {
            pairs.append((AO3WorkFormField.workIDs, String(id)))
        }
        func sendJoined(field: String, names: [String]) {
            let joined = AO3TagListDiff.joined(names)
            guard !joined.isEmpty else { return }
            pairs.append((field, joined))
        }
        sendJoined(field: AO3WorkFormField.fandoms, names: tagsToAdd.fandoms)
        sendJoined(field: AO3WorkFormField.relationships, names: tagsToAdd.relationships)
        sendJoined(field: AO3WorkFormField.characters, names: tagsToAdd.characters)
        sendJoined(field: AO3WorkFormField.additionalTags, names: tagsToAdd.additionalTags)
        for warning in tagsToAdd.warnings {
            pairs.append((AO3WorkFormField.warnings, warning))
        }
        for category in tagsToAdd.categories {
            pairs.append((AO3WorkFormField.categories, category))
        }
        if let rating, !rating.isEmpty {
            pairs.append((AO3WorkFormField.rating, rating))
        }
        if let languageID, !languageID.isEmpty {
            pairs.append((AO3WorkFormField.languageID, languageID))
        }
        sendJoined(field: AO3WorkFormField.collectionsToAdd, names: collectionsToAdd)
        for name in collectionsToRemove {
            pairs.append((AO3WorkFormField.collectionsToRemove, name))
        }
        if let restricted, !restricted.isEmpty {
            pairs.append((AO3WorkFormField.restricted, restricted))
        }
        if let moderatedCommenting, !moderatedCommenting.isEmpty {
            pairs.append((AO3WorkFormField.moderatedCommenting, moderatedCommenting))
        }
        if let commentPermissions, !commentPermissions.isEmpty {
            pairs.append((AO3WorkFormField.commentPermissions, commentPermissions))
        }
        if let workSkinID, !workSkinID.isEmpty {
            pairs.append((AO3WorkFormField.workSkinID, workSkinID))
        }
        if !pseudsToAdd.isEmpty {
            pairs.append((AO3WorkFormField.pseudsToAdd, pseudsToAdd))
        }
        return pairs
    }

    /// Per-work replacement lists when remove is in play (bulk POST cannot
    /// send a different replacement per work).
    func applying(to current: AO3WorkTagSet) -> AO3WorkTagSet {
        AO3WorkTagSet(
            rating: rating ?? current.rating,
            warnings: AO3TagListDiff.applying(
                current: current.warnings,
                adding: tagsToAdd.warnings,
                removing: tagsToRemove.warnings
            ),
            categories: AO3TagListDiff.applying(
                current: current.categories,
                adding: tagsToAdd.categories,
                removing: tagsToRemove.categories
            ),
            fandoms: AO3TagListDiff.applying(
                current: current.fandoms,
                adding: tagsToAdd.fandoms,
                removing: tagsToRemove.fandoms
            ),
            relationships: AO3TagListDiff.applying(
                current: current.relationships,
                adding: tagsToAdd.relationships,
                removing: tagsToRemove.relationships
            ),
            characters: AO3TagListDiff.applying(
                current: current.characters,
                adding: tagsToAdd.characters,
                removing: tagsToRemove.characters
            ),
            additionalTags: AO3TagListDiff.applying(
                current: current.additionalTags,
                adding: tagsToAdd.additionalTags,
                removing: tagsToRemove.additionalTags
            )
        )
    }
}

nonisolated struct AO3BulkEditForm: Equatable, Sendable {
    var actionURL: URL
    var httpMethodOverride: String?
    var csrfToken: String
    var workIDs: [Int]
    var workTitles: [String]
    var ratingOptions: [AO3FormOption] = []
    var warningOptions: [AO3FormOption] = []
    var categoryOptions: [AO3FormOption] = []
    var languageOptions: [AO3FormOption] = []
    var currentCollections: [AO3FormOption] = []
}

// MARK: - Delete confirm (1bo / 1bs)

nonisolated struct AO3DeleteImplications: Equatable, Sendable {
    var title: String
    var isDraft: Bool
    var actionURL: URL
    var csrfToken: String
    var httpMethodOverride: String?
    var chapters: Int?
    var kudos: Int?
    var comments: Int?
    var bookmarks: Int?
    var words: Int?
    var cautionText: String
}

nonisolated struct AO3PreviewHTML: Equatable, Sendable {
    var html: String
}

// MARK: - Errors

/// Work/chapter/series write failures. Separate from `AO3WriteError` so kudos
/// / comments keep their existing surface.
enum AO3WorkWriteError: LocalizedError, Equatable {
    case notSignedIn
    case noCSRFToken
    case missingRequiredFields([String])
    case rejected(String)
    case unconfirmed
    case previewUnavailable
    case seriesCreateUnavailable

    var errorDescription: String? {
        switch self {
        case .notSignedIn: "Log in to AO3 first."
        case .noCSRFToken:
            "Couldn't prepare the request. Try again, or open the form on AO3."
        case let .missingRequiredFields(names):
            "AO3 still needs \(names.joined(separator: " and "))."
        case let .rejected(reason): reason
        case .unconfirmed:
            "AO3 replied but didn't confirm the change went through. "
                + "Check on AO3 before trying again."
        case .previewUnavailable:
            "AO3 didn't return a preview. Try opening the work on AO3."
        case .seriesCreateUnavailable:
            "Creating a series from scratch still happens on AO3."
        }
    }
}
