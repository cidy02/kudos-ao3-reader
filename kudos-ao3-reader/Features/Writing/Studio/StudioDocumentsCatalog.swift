import Foundation

/// Built catalog backing both Pages and Files views.
nonisolated struct StudioDocumentsSnapshot: Equatable, Sendable {
    var allWorks: [StudioWorkItem]
    var manuscripts: [StudioWorkItem]
    var looseDrafts: [StudioWorkItem]
    var recent: [StudioRecentDocumentItem]
    var chipCounts: [StudioDocumentsFilterChip: Int]

    static let empty = StudioDocumentsSnapshot(
        allWorks: [],
        manuscripts: [],
        looseDrafts: [],
        recent: [],
        chipCounts: [.all: 0, .drafts: 0, .posted: 0, .gifts: 0]
    )

    var localDocumentCount: Int {
        allWorks.reduce(0) { total, item in
            guard item.hasLocalCopy else { return total }
            let chapterDocs = max(1, item.localChapters.count)
            return total + chapterDocs + item.storyNotes.count
        }
    }
}

/// Pure merge, filter, sort, and Recent builder for Writing Studio Documents & Files.
nonisolated enum StudioDocumentsCatalog {
    static let maxRecentCount = 4

    static func build(
        localWorks: [StudioLocalWorkSnapshot],
        ao3PostedWorks: [AO3WorkSummary],
        ao3DraftWorks: [AO3WorkSummary],
        ao3DraftDaysLeft: [Int: Int] = [:],
        deviceName: String = "iPhone",
        now: Date = Date(),
        calendar: Calendar = .current,
        locale: Locale = .autoupdatingCurrent
    ) -> StudioDocumentsSnapshot {
        var postedByID: [Int: AO3WorkSummary] = [:]
        for work in ao3PostedWorks { postedByID[work.id] = work }
        var draftsByID: [Int: AO3WorkSummary] = [:]
        for draft in ao3DraftWorks { draftsByID[draft.id] = draft }

        var consumedAO3IDs: Set<Int> = []
        var merged: [StudioWorkItem] = []

        for snapshot in localWorks {
            let ao3ID = snapshot.work.ao3WorkID
            let posted = ao3ID.flatMap { postedByID[$0] }
            let draft = ao3ID.flatMap { draftsByID[$0] }
            if let ao3ID, posted != nil || draft != nil {
                consumedAO3IDs.insert(ao3ID)
            }
            // A local folder keeps its own id. Two locals linked to the same AO3
            // work must not share an identity, or selecting one selects both.
            let itemID = "local:\(snapshot.work.id.uuidString)"
            merged.append(StudioWorkItem(
                id: itemID,
                localWork: snapshot.work,
                localChapters: snapshot.chapters,
                storyNotes: snapshot.storyNotes,
                chapterExcerpts: snapshot.chapterExcerpts,
                ao3PostedWork: posted,
                ao3DraftWork: draft,
                ao3DraftDaysLeft: ao3ID.flatMap { ao3DraftDaysLeft[$0] }
            ))
        }

        for posted in ao3PostedWorks where !consumedAO3IDs.contains(posted.id) {
            consumedAO3IDs.insert(posted.id)
            merged.append(StudioWorkItem(
                id: "ao3:\(posted.id)",
                localWork: nil,
                localChapters: [],
                storyNotes: [],
                chapterExcerpts: [:],
                ao3PostedWork: posted,
                ao3DraftWork: draftsByID[posted.id],
                ao3DraftDaysLeft: ao3DraftDaysLeft[posted.id]
            ))
        }

        for draft in ao3DraftWorks where !consumedAO3IDs.contains(draft.id) {
            consumedAO3IDs.insert(draft.id)
            merged.append(StudioWorkItem(
                id: "ao3:\(draft.id)",
                localWork: nil,
                localChapters: [],
                storyNotes: [],
                chapterExcerpts: [:],
                ao3PostedWork: nil,
                ao3DraftWork: draft,
                ao3DraftDaysLeft: ao3DraftDaysLeft[draft.id]
            ))
        }

        let sorted = sortFolders(merged, by: .edited)
        let manuscripts = sorted.filter { !$0.isLooseDraft }
        let looseDrafts = sorted.filter(\.isLooseDraft)
        let recent = buildRecent(
            from: sorted,
            deviceName: deviceName,
            dateContext: DateContext(now: now, calendar: calendar, locale: locale)
        )
        let counts: [StudioDocumentsFilterChip: Int] = [
            .all: sorted.count,
            .drafts: sorted.filter(\.hasDraftContent).count,
            .posted: sorted.filter(\.hasPostedBadge).count,
            .gifts: sorted.filter(\.isGift).count
        ]

        return StudioDocumentsSnapshot(
            allWorks: sorted,
            manuscripts: manuscripts,
            looseDrafts: looseDrafts,
            recent: recent,
            chipCounts: counts
        )
    }

    static func filter(
        _ items: [StudioWorkItem],
        chip: StudioDocumentsFilterChip,
        query: String
    ) -> [StudioWorkItem] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return items.filter { item in
            guard matchesChip(item, chip: chip) else { return false }
            guard !needle.isEmpty else { return true }
            return matchesQuery(item, needle: needle)
        }
    }

    static func sortFolders(
        _ items: [StudioWorkItem],
        by sort: StudioFilesSort
    ) -> [StudioWorkItem] {
        items.sorted { lhs, rhs in
            switch sort {
            case .edited:
                if lhs.lastEditedDate != rhs.lastEditedDate {
                    return lhs.lastEditedDate > rhs.lastEditedDate
                }
                return compareTitle(lhs, rhs)
            case .title:
                return compareTitle(lhs, rhs)
            case .words:
                if lhs.totalWordCount != rhs.totalWordCount {
                    return lhs.totalWordCount > rhs.totalWordCount
                }
                return compareTitle(lhs, rhs)
            }
        }
    }

    static func excerpt(fromBodyHTML html: String, maxLength: Int = 220) -> String {
        let plain = html
            .strippingHTML()
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard plain.count > maxLength else { return plain }
        return String(plain.prefix(maxLength)).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }

    // MARK: - Private

    private static func matchesChip(_ item: StudioWorkItem, chip: StudioDocumentsFilterChip) -> Bool {
        switch chip {
        case .all: true
        case .drafts: item.hasDraftContent
        case .posted: item.hasPostedBadge
        case .gifts: item.isGift
        }
    }

    private static func matchesQuery(_ item: StudioWorkItem, needle: String) -> Bool {
        if item.title.lowercased().contains(needle) { return true }
        if item.localChapters.contains(where: { $0.title.lowercased().contains(needle) }) { return true }
        if item.storyNotes.contains(where: { $0.name.lowercased().contains(needle) }) { return true }
        if matchesSummary(item.ao3PostedWork, needle: needle) { return true }
        if matchesSummary(item.ao3DraftWork, needle: needle) { return true }
        return false
    }

    private static func matchesSummary(_ summary: AO3WorkSummary?, needle: String) -> Bool {
        guard let summary else { return false }
        if summary.fandoms.contains(where: { $0.lowercased().contains(needle) }) { return true }
        if summary.summary.lowercased().contains(needle) { return true }
        return summary.giftRecipients.contains(where: { $0.lowercased().contains(needle) })
    }

    private static func compareTitle(_ lhs: StudioWorkItem, _ rhs: StudioWorkItem) -> Bool {
        let order = lhs.title.localizedCaseInsensitiveCompare(rhs.title)
        if order != .orderedSame { return order == .orderedAscending }
        return lhs.id < rhs.id
    }

    private nonisolated struct DateContext {
        let now: Date
        let calendar: Calendar
        let locale: Locale

        func shortDate(_ date: Date) -> String {
            StudioDateCopy.shortDate(date, now: now, calendar: calendar, locale: locale)
        }

        func shortAO3Date(_ rawText: String) -> String {
            StudioDateCopy.shortAO3Date(rawText, now: now, calendar: calendar, locale: locale)
        }
    }

    private static func buildRecent(
        from works: [StudioWorkItem],
        deviceName: String,
        dateContext: DateContext
    ) -> [StudioRecentDocumentItem] {
        var candidates: [StudioRecentDocumentItem] = []

        for item in works {
            if let localWork = item.localWork {
                candidates.append(
                    recentLocalItem(
                        for: item,
                        localWork: localWork,
                        deviceName: deviceName,
                        dateContext: dateContext
                    )
                )
            } else if let draft = item.ao3DraftWork {
                candidates.append(
                    recentAO3DraftItem(for: item, draft: draft, dateContext: dateContext)
                )
            } else if let posted = item.ao3PostedWork {
                candidates.append(
                    recentAO3PostedItem(for: item, posted: posted, dateContext: dateContext)
                )
            }
        }

        let sorted = candidates.sorted { lhs, rhs in
            if lhs.editedAt != rhs.editedAt { return lhs.editedAt > rhs.editedAt }
            return lhs.id < rhs.id
        }
        return Array(sorted.prefix(maxRecentCount))
    }

    private static func recentLocalItem(
        for item: StudioWorkItem,
        localWork: WritingWork,
        deviceName: String,
        dateContext: DateContext
    ) -> StudioRecentDocumentItem {
        guard let latest = latestChapter(in: item.localChapters) else {
            return StudioRecentDocumentItem(
                id: "recent-local-\(localWork.id.uuidString)",
                workItemID: item.id,
                title: item.title,
                paperHeading: item.title,
                excerpt: "Start writing…",
                badgeText: deviceName,
                badgeTone: .onDevice,
                metaLine: dateContext.shortDate(localWork.updatedAt),
                editedAt: localWork.updatedAt,
                target: .localWork(workID: localWork.id, workTitle: item.title)
            )
        }
        let index = item.localChapters.firstIndex(where: { $0.id == latest.id }) ?? 0
        let chapterTitle = latest.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cardTitle = chapterTitle.isEmpty ? item.title : chapterTitle
        let heading: String = if item.localChapters.count > 1 {
            "\(index + 1). \(chapterTitle.isEmpty ? "Untitled" : chapterTitle)"
        } else {
            chapterTitle.isEmpty ? item.title : chapterTitle
        }
        let excerpt = item.chapterExcerpts[latest.id] ?? ""
        let badgeText: String?
        let badgeTone: StudioRecentDocumentItem.BadgeTone
        switch latest.status {
        case .ao3Draft:
            badgeText = "Draft"
            badgeTone = .draft
        case .local:
            badgeText = deviceName
            badgeTone = .onDevice
        case .posted:
            badgeText = nil
            badgeTone = .none
        }
        let shortDate = dateContext.shortDate(latest.updatedAt)
        let dateText = latest.status == .posted ? "posted \(shortDate)" : shortDate
        let meta = latest.wordCount > 0
            ? "\(StudioWorkItem.wordCountLabel(latest.wordCount)) · \(dateText)"
            : dateText
        return StudioRecentDocumentItem(
            id: "recent-ch-\(latest.id.uuidString)",
            workItemID: item.id,
            title: cardTitle,
            paperHeading: heading,
            excerpt: excerpt.isEmpty ? "Empty document" : excerpt,
            badgeText: badgeText,
            badgeTone: badgeTone,
            metaLine: meta,
            editedAt: latest.updatedAt,
            target: .localChapter(workID: localWork.id, chapterID: latest.id, workTitle: item.title)
        )
    }

    private static func recentAO3DraftItem(
        for item: StudioWorkItem,
        draft: AO3WorkSummary,
        dateContext: DateContext
    ) -> StudioRecentDocumentItem {
        let edited = WorkStat.date(from: draft.dateUpdated) ?? .distantPast
        let words = draft.words ?? 0
        let datePart = draft.dateUpdated.isEmpty ? nil : dateContext.shortAO3Date(draft.dateUpdated)
        let parts: [String?] = [words > 0 ? StudioWorkItem.wordCountLabel(words) : nil, datePart]
        let meta = parts.compactMap(\.self).joined(separator: " · ")
        return StudioRecentDocumentItem(
            id: "recent-draft-\(draft.id)",
            workItemID: item.id,
            title: item.title,
            paperHeading: item.title,
            excerpt: draft.summary.isEmpty ? "Saved as an AO3 draft." : draft.summary,
            badgeText: "Draft",
            badgeTone: .draft,
            metaLine: meta.isEmpty ? "AO3 draft" : meta,
            editedAt: edited,
            target: .ao3Draft(workID: draft.id)
        )
    }

    private static func recentAO3PostedItem(
        for item: StudioWorkItem,
        posted: AO3WorkSummary,
        dateContext: DateContext
    ) -> StudioRecentDocumentItem {
        let edited = WorkStat.date(from: posted.dateUpdated) ?? .distantPast
        let words = posted.words ?? 0
        let datePart = posted.dateUpdated.isEmpty
            ? nil
            : "posted \(dateContext.shortAO3Date(posted.dateUpdated))"
        let parts: [String?] = [words > 0 ? StudioWorkItem.wordCountLabel(words) : nil, datePart]
        let meta = parts.compactMap(\.self).joined(separator: " · ")
        return StudioRecentDocumentItem(
            id: "recent-posted-\(posted.id)",
            workItemID: item.id,
            title: item.title,
            paperHeading: item.title,
            excerpt: posted.summary.isEmpty ? "Posted on AO3." : posted.summary,
            badgeText: nil,
            badgeTone: .none,
            metaLine: meta.isEmpty ? "Posted on AO3" : meta,
            editedAt: edited,
            target: .ao3PostedWork(workID: posted.id, workTitle: item.title)
        )
    }

    private static func latestChapter(in chapters: [WritingChapter]) -> WritingChapter? {
        chapters.max { lhs, rhs in
            if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt < rhs.updatedAt }
            return lhs.id.uuidString > rhs.id.uuidString
        }
    }
}
