import SwiftUI

// Version E keeps the 3×3 stats card and folds local facts into a persistent
// My copy disclosure. Progress remains in the reading card; all other facts
// become the board's compact two-column cells.

extension WorkDetailPresentation {
    /// Version E's two-column cells: Progress lives in the reading card, while
    /// every other page-level My copy fact remains.
    static func myCopyCells(from rows: [MyCopyRow]) -> [MyCopyRow] {
        let order: [MyCopyRow.Kind] = [.downloaded, .file, .tags, .collections, .queues]
        return order.compactMap { kind in rows.first { $0.kind == kind } }
    }
}

private struct WorkDetailMyCopyCell: View {
    let row: WorkDetailPresentation.MyCopyRow
    let action: () -> Void

    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(row.label)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let editAction = row.action {
                    Button(editAction.title, action: action)
                        .buttonStyle(.plain)
                        .foregroundStyle(.accentInk)
                        .layoutFreeHitTarget(action: action)
                        .accessibilityLabel(editAction.title + " " + row.label.lowercased())
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            Text(row.value)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                .truncationMode(.middle)
        }
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            themeManager.appTheme.glassFill(0.09),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .accessibilityElement(children: .contain)
    }
}

extension WorkDetailView {
    // MARK: Stats

    /// The nine-figure card under the Resume card. Kudos carries a filled heart
    /// once the reader has given them: what this device recorded
    /// (`SavedWork.hasGivenKudos`, set by `markKudosGiven`), or the give this
    /// screen's own actions model just made, which the saved record may not
    /// hold yet.
    var statsSection: some View {
        let givenNow = ao3WorkID.map { workActions.kudosGivenWorkID == $0 } ?? false
        let cells = WorkDetailStats.cells(
            words: displayWords,
            chapters: displayChapters,
            kudos: displayKudos,
            kudosGiven: (localWork?.hasGivenKudos ?? false) || givenNow,
            hits: displayHits,
            comments: displayComments,
            bookmarks: displayBookmarks,
            published: displayPublishedDate,
            updated: displayUpdatedDate,
            language: displayLanguage
        )
        return Section {
            WorkDetailStatsCard(cells: cells)
                .pageBodyRow(top: 14)
        }
    }

    // MARK: My copy

    /// Everything local about this work that fits in a cell, then one cell into
    /// the full My copy sheet for the rest (status toggles, activity dates, origin,
    /// conversion, suggestions). Shown only once there *is* a local copy — a work
    /// being browsed from Search has nothing behind it yet, and its Add to Queue
    /// and Add to Collection stay in the ••• menu.
    @ViewBuilder
    var myCopySection: some View {
        if let work = localWork {
            let rows = myCopyRows(for: work)
            let columns = Array(
                repeating: GridItem(.flexible(), spacing: 8),
                count: dynamicTypeSize.isAccessibilitySize ? 1 : 2
            )
            Section {
                WorkDetailDisclosureHeader(
                    title: "My copy", digest: "Private to this device", isExpanded: $myCopyExpanded
                )
                .pageBodyRow(top: 0)

                if myCopyExpanded {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                        ForEach(rows) { row in
                            WorkDetailMyCopyCell(row: row) { performMyCopyAction(row.kind) }
                        }
                        Button { showingMyCopy = true } label: {
                            WorkDetailMyCopyCell(
                                row: .init(
                                    kind: .file, label: "Storage and History",
                                    value: "View details", action: nil
                                ),
                                action: {}
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Storage and History")
                        .accessibilityAddTraits(.isButton)
                        .accessibilityValue(WorkDetailPresentation.myCopySummary(
                            isDownloaded: work.isDownloaded,
                            queueCount: work.activeQueueMemberships.count,
                            tagCount: work.tags.count,
                            collectionCount: work.activeCollections.count
                        ))
                    }
                    .padding(.bottom, 14)
                    .pageBodyRow(top: 2)
                }
            }
        }
    }

    private func myCopyRows(for work: SavedWork) -> [WorkDetailPresentation.MyCopyRow] {
        let hasFile = WorkReaderPreparation.hasReadableEPUB(for: work)
        let rows = WorkDetailPresentation.myCopyRows(
            progress: nil,
            chapterNumber: nil,
            downloadedAt: work.downloadedAt,
            tags: work.tags.map(\.name).sorted(),
            collections: work.activeCollections.map(\.name).sorted(),
            queues: work.activeQueueMemberships.compactMap { $0.queue?.name }.sorted(),
            hasFile: hasFile,
            fileSize: hasFile ? WorkDetailPresentation.fileSizeLabel(forFileAt: work.fileURL) : nil
        )
        return WorkDetailPresentation.myCopyCells(from: rows)
    }

    private func performMyCopyAction(_ kind: WorkDetailPresentation.MyCopyRow.Kind) {
        switch kind {
        case .downloaded: showingPageDateEditor = true
        case .tags: showingAddTag = true
        case .collections: withLocalWork { _ in showingAddToCollection = true }
        case .queues: withLocalWork { _ in showingAddToQueue = true }
        case .progress, .file: break
        }
    }
}
