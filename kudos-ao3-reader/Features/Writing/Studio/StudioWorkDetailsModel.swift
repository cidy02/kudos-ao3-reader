import Foundation

// MARK: - Work details structure in AO3's edit-page order (`Studio-Work-Details`)

/// Sections of `StudioWorkDetailsView` in AO3's own edit-page order:
/// About → Tags → Creators → Connections → Who can see and comment → Give up or delete.
nonisolated enum StudioWorkDetailsSectionID: String, CaseIterable, Identifiable, Hashable, Sendable {
    case about
    case tags
    case creators
    case connections
    case whoCanSeeAndComment
    case giveUpOrDelete

    var id: String { rawValue }

    var title: String {
        switch self {
        case .about: "About"
        case .tags: "Tags"
        case .creators: "Creators"
        case .connections: "Connections"
        case .whoCanSeeAndComment: "Who can see and comment"
        case .giveUpOrDelete: "Give up or delete"
        }
    }
}

nonisolated enum StudioWorkDetailsRowID: Hashable, Sendable {
    case title
    case summary
    case notes
    case language
    case editTags
    case creatorPseud(String)
    case inviteCoCreator
    case removeMeAsCoCreator
    case series
    case collections
    case giftFor
    case inspiredBy
    case whoCanSee
    case whoCanComment
    case approveComments
    case orphanWork
    case deleteWork
}

nonisolated enum StudioWorkDetailsRowTone: Equatable, Hashable, Sendable {
    case standard
    case accent
    case destructive
}

nonisolated struct StudioWorkDetailsRowDescriptor: Identifiable, Equatable, Hashable, Sendable {
    let id: StudioWorkDetailsRowID
    let label: String
    let subtitle: String?
    let value: String?
    let tone: StudioWorkDetailsRowTone
    let showsDisclosure: Bool
}

nonisolated struct StudioWorkDetailsSectionDescriptor: Identifiable, Equatable, Hashable, Sendable {
    let id: StudioWorkDetailsSectionID
    let title: String
    let rows: [StudioWorkDetailsRowDescriptor]
    let footer: String?
}

/// Pure, testable descriptor for `StudioWorkDetailsView`.
/// Ensures AO3's exact edit-page section order and sole-creator vs co-creator action gating.
nonisolated struct StudioWorkDetailsModel: Equatable, Sendable {
    let sections: [StudioWorkDetailsSectionDescriptor]

    var sectionOrder: [StudioWorkDetailsSectionID] {
        sections.map(\.id)
    }

    func section(_ id: StudioWorkDetailsSectionID) -> StudioWorkDetailsSectionDescriptor? {
        sections.first { $0.id == id }
    }

    static func build(form: AO3WorkForm, username: String? = nil) -> StudioWorkDetailsModel {
        var result: [StudioWorkDetailsSectionDescriptor] = [
            aboutSection(for: form),
            tagsSection(for: form),
            creatorsSection(for: form, username: username),
            connectionsSection(for: form),
            whoCanSeeSection(for: form)
        ]
        if let danger = giveUpOrDeleteSection(for: form) {
            result.append(danger)
        }
        return StudioWorkDetailsModel(sections: result)
    }

    private static func aboutSection(for form: AO3WorkForm) -> StudioWorkDetailsSectionDescriptor {
        let languageTitle = form.languageOptions.first { $0.value == form.languageID }?.title
            ?? (form.languageID.isEmpty ? "Not set" : form.languageID)
        let summaryPreview = plainTextSummary(form.summary)
        return StudioWorkDetailsSectionDescriptor(
            id: .about,
            title: StudioWorkDetailsSectionID.about.title,
            rows: [
                StudioWorkDetailsRowDescriptor(
                    id: .title,
                    label: "Title",
                    subtitle: nil,
                    value: form.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? "Untitled"
                        : form.title,
                    tone: .standard,
                    showsDisclosure: true
                ),
                StudioWorkDetailsRowDescriptor(
                    id: .summary,
                    label: "Summary",
                    subtitle: summaryPreview.isEmpty ? "None" : summaryPreview,
                    value: nil,
                    tone: .standard,
                    showsDisclosure: true
                ),
                StudioWorkDetailsRowDescriptor(
                    id: .notes,
                    label: "Notes",
                    subtitle: nil,
                    value: notesValue(notes: form.notes, endnotes: form.endnotes),
                    tone: .standard,
                    showsDisclosure: true
                ),
                StudioWorkDetailsRowDescriptor(
                    id: .language,
                    label: "Language",
                    subtitle: nil,
                    value: languageTitle,
                    tone: .standard,
                    showsDisclosure: true
                )
            ],
            footer: nil
        )
    }

    private static func tagsSection(for form: AO3WorkForm) -> StudioWorkDetailsSectionDescriptor {
        StudioWorkDetailsSectionDescriptor(
            id: .tags,
            title: StudioWorkDetailsSectionID.tags.title,
            rows: [
                StudioWorkDetailsRowDescriptor(
                    id: .editTags,
                    label: "Edit Tags",
                    subtitle: tagSummary(for: form),
                    value: nil,
                    tone: .standard,
                    showsDisclosure: true
                )
            ],
            footer: nil
        )
    }

    private static func creatorsSection(
        for form: AO3WorkForm,
        username: String?
    ) -> StudioWorkDetailsSectionDescriptor {
        var creatorRows: [StudioWorkDetailsRowDescriptor] = []
        for title in listedPseudTitles(form: form, username: username) {
            creatorRows.append(StudioWorkDetailsRowDescriptor(
                id: .creatorPseud(title),
                label: title,
                subtitle: nil,
                value: "You",
                tone: .standard,
                showsDisclosure: false
            ))
        }
        let pendingInvite = form.creators.coauthorByline.trimmingCharacters(in: .whitespacesAndNewlines)
        creatorRows.append(StudioWorkDetailsRowDescriptor(
            id: .inviteCoCreator,
            label: "Invite a Co-Creator",
            subtitle: nil,
            value: pendingInvite.isEmpty ? nil : pendingInvite,
            tone: .accent,
            showsDisclosure: false
        ))
        if form.canRemoveMe {
            creatorRows.append(StudioWorkDetailsRowDescriptor(
                id: .removeMeAsCoCreator,
                label: "Remove Me as Co-Creator",
                subtitle: nil,
                value: nil,
                tone: .destructive,
                showsDisclosure: false
            ))
        }
        let creatorsFooter = form.canRemoveMe
            ? "AO3 takes you off every chapter too, and the work stays with its other creator."
            : "Remove Me appears only when the work has another creator."
        return StudioWorkDetailsSectionDescriptor(
            id: .creators,
            title: StudioWorkDetailsSectionID.creators.title,
            rows: creatorRows,
            footer: creatorsFooter
        )
    }

    private static func connectionsSection(for form: AO3WorkForm) -> StudioWorkDetailsSectionDescriptor {
        StudioWorkDetailsSectionDescriptor(
            id: .connections,
            title: StudioWorkDetailsSectionID.connections.title,
            rows: [
                StudioWorkDetailsRowDescriptor(
                    id: .series,
                    label: "Series",
                    subtitle: nil,
                    value: seriesValue(for: form),
                    tone: .standard,
                    showsDisclosure: true
                ),
                StudioWorkDetailsRowDescriptor(
                    id: .collections,
                    label: "Collections",
                    subtitle: nil,
                    value: collectionsValue(for: form),
                    tone: .standard,
                    showsDisclosure: true
                ),
                StudioWorkDetailsRowDescriptor(
                    id: .giftFor,
                    label: "Gift for",
                    subtitle: nil,
                    value: giftsValue(for: form),
                    tone: .standard,
                    showsDisclosure: true
                ),
                StudioWorkDetailsRowDescriptor(
                    id: .inspiredBy,
                    label: "Inspired by or translated from",
                    subtitle: nil,
                    value: inspiredByValue(for: form),
                    tone: .standard,
                    showsDisclosure: true
                )
            ],
            footer: nil
        )
    }

    private static func whoCanSeeSection(for form: AO3WorkForm) -> StudioWorkDetailsSectionDescriptor {
        StudioWorkDetailsSectionDescriptor(
            id: .whoCanSeeAndComment,
            title: StudioWorkDetailsSectionID.whoCanSeeAndComment.title,
            rows: [
                StudioWorkDetailsRowDescriptor(
                    id: .whoCanSee,
                    label: "Who can see it",
                    subtitle: nil,
                    value: form.restricted ? "Registered users" : "Everyone",
                    tone: .standard,
                    showsDisclosure: true
                ),
                StudioWorkDetailsRowDescriptor(
                    id: .whoCanComment,
                    label: "Who can comment",
                    subtitle: nil,
                    value: commentPermissionTitle(for: form),
                    tone: .standard,
                    showsDisclosure: true
                ),
                StudioWorkDetailsRowDescriptor(
                    id: .approveComments,
                    label: "Approve comments first",
                    subtitle: nil,
                    value: form.moderatedCommenting ? "On" : "Off",
                    tone: .standard,
                    showsDisclosure: false
                )
            ],
            footer: nil
        )
    }

    private static func giveUpOrDeleteSection(for form: AO3WorkForm) -> StudioWorkDetailsSectionDescriptor? {
        guard form.workID != nil else { return nil }
        var dangerRows: [StudioWorkDetailsRowDescriptor] = []
        if form.canOrphan {
            dangerRows.append(StudioWorkDetailsRowDescriptor(
                id: .orphanWork,
                label: "Orphan Work…",
                subtitle: nil,
                value: nil,
                tone: .destructive,
                showsDisclosure: true
            ))
        }
        dangerRows.append(StudioWorkDetailsRowDescriptor(
            id: .deleteWork,
            label: form.isDraft ? "Delete Draft…" : "Delete Work…",
            subtitle: nil,
            value: nil,
            tone: .destructive,
            showsDisclosure: false
        ))
        let dangerFooter = form.canOrphan
            ? "Both happen on AO3. Kudos keeps its own copy of every chapter unless you remove it."
            : "Deletes this draft on AO3. Kudos keeps its own copy of every chapter unless you remove it."
        return StudioWorkDetailsSectionDescriptor(
            id: .giveUpOrDelete,
            title: StudioWorkDetailsSectionID.giveUpOrDelete.title,
            rows: dangerRows,
            footer: dangerFooter
        )
    }

    // MARK: Formatting helpers

    static func tagSummary(for form: AO3WorkForm) -> String {
        var head: [String] = []
        let rating = form.rating.trimmingCharacters(in: .whitespacesAndNewlines)
        if !rating.isEmpty {
            head.append(shortRating(rating))
        }
        if let firstWarning = form.warnings.first {
            head.append(firstWarning)
        }
        if let firstCategory = form.categories.first {
            head.append(firstCategory)
        }
        let extraCount = max(0, form.warnings.count - 1)
            + max(0, form.categories.count - 1)
            + form.fandoms.count
            + form.relationships.count
            + form.characters.count
            + form.additionalTags.count
        if extraCount > 0 {
            head.append("\(extraCount) more")
        }
        return head.isEmpty ? "No tags set" : head.joined(separator: " · ")
    }

    static func notesValue(notes: String, endnotes: String) -> String {
        let hasBegin = !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasEnd = !endnotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        switch (hasBegin, hasEnd) {
        case (true, true): return "Beginning, end"
        case (true, false): return "Beginning"
        case (false, true): return "End"
        case (false, false): return "None"
        }
    }

    static func seriesValue(for form: AO3WorkForm) -> String {
        let current = form.currentSeries.map(\.title)
        let adding = form.series.first(where: \.isSelected)?.title
            ?? AO3WorkForm.newSeriesTitle(form.newSeriesTitle)
        let now = current.joined(separator: ", ")
        switch (now.isEmpty, adding) {
        case (true, nil): return "None"
        case let (true, adding?): return "Adding \(adding)"
        case (false, nil): return now
        case let (false, adding?): return "\(now) + \(adding)"
        }
    }

    static func collectionsValue(for form: AO3WorkForm) -> String {
        let selected: [String]
        if form.collections.isEmpty {
            selected = form.collectionNames
        } else {
            selected = form.collections.filter(\.isSelected).map { offer in
                offer.title.isEmpty ? offer.name : offer.title
            }
        }
        return selected.isEmpty ? "None" : selected.joined(separator: ", ")
    }

    static func giftsValue(for form: AO3WorkForm) -> String {
        let names = form.gifts
            .map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return names.isEmpty ? "None" : names.joined(separator: ", ")
    }

    static func inspiredByValue(for form: AO3WorkForm) -> String {
        if !form.existingParentTitles.isEmpty {
            return form.existingParentTitles.joined(separator: ", ")
        }
        let title = form.parentWork.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty { return title }
        let url = form.parentWork.url.trimmingCharacters(in: .whitespacesAndNewlines)
        if !url.isEmpty { return url }
        return "None"
    }

    static func commentPermissionTitle(for form: AO3WorkForm) -> String {
        switch form.commentPermissions {
        case "enable_all": return "Everyone"
        case "disable_anon": return "Registered users"
        case "disable_all": return "No one"
        default:
            if let option = form.commentPermissionOptions.first(where: { $0.value == form.commentPermissions }),
               !option.title.isEmpty {
                return option.title
            }
            return "Registered users"
        }
    }

    static func defaultSubtitle(for form: AO3WorkForm) -> String {
        var parts: [String] = []
        if form.isDraft {
            parts.append("AO3 draft")
        } else {
            parts.append("Posted")
        }
        if let posted = form.chaptersPosted {
            let total = form.chapterTotal.trimmingCharacters(in: .whitespacesAndNewlines)
            if !total.isEmpty, total != "?" {
                parts.append("\(posted) of \(total) chapters")
            } else {
                parts.append(posted == 1 ? "1 chapter" : "\(posted) chapters")
            }
        }
        return parts.joined(separator: " · ")
    }

    private static func listedPseudTitles(form: AO3WorkForm, username: String?) -> [String] {
        let selected = Set(form.creators.selectedPseudIDs)
        let matched = form.creators.availablePseuds
            .filter { selected.contains($0.value) }
            .map(\.title)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if !matched.isEmpty { return matched }
        let trimmedUser = (username ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedUser.isEmpty { return [trimmedUser] }
        return []
    }

    private static func plainTextSummary(_ html: String) -> String {
        BetaHTMLDocument.parse(html)
            .map(\.plainText)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func shortRating(_ rating: String) -> String {
        switch rating {
        case "Teen And Up Audiences": "Teen And Up"
        case "General Audiences": "General"
        default: rating
        }
    }
}
