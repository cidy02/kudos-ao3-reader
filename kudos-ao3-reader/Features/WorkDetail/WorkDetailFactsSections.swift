import SwiftUI

// The lower half of board 19: the 3×3 stats card and the My copy card. Built from
// the shared form family (`UIComponents/SubjectForm.swift`) rather than from
// anything of its own — these rows are the same shape the spec's form and
// settings artboards are made of.

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

    /// Everything local about this work that fits on a row, then one row into the
    /// full My copy sheet for the rest (status toggles, activity dates, origin,
    /// conversion, suggestions). Shown only once there *is* a local copy — a work
    /// being browsed from Search has nothing behind it yet, and its Add to Queue
    /// and Add to Collection stay in the ••• menu.
    @ViewBuilder
    var myCopySection: some View {
        if let work = localWork {
            Section {
                SectionRuleHeader(title: "My copy", note: "Private to this device")
                    .accessibilityAddTraits(.isHeader)
                    .pageBodyRow(top: 24, gutter: 0)

                VStack(spacing: 0) {
                    ForEach(myCopyRows(for: work)) { row in
                        if row.kind != .progress { SubjectRowSeparator() }
                        myCopyRowView(row)
                    }
                    SubjectRowSeparator()
                    SubjectFormRow(
                        label: "Storage and history",
                        value: "",
                        showsDisclosure: true,
                        action: { showingMyCopy = true }
                    )
                    .accessibilityValue(WorkDetailPresentation.myCopySummary(
                        isDownloaded: work.isDownloaded,
                        queueCount: work.activeQueueMemberships.count,
                        tagCount: work.tags.count,
                        collectionCount: work.activeCollections.count
                    ))
                }
                .subjectPanel()
                .pageBodyRow(top: 8)
            }
        }
    }

    private func myCopyRows(for work: SavedWork) -> [WorkDetailPresentation.MyCopyRow] {
        let hasFile = WorkReaderPreparation.hasReadableEPUB(for: work)
        return WorkDetailPresentation.myCopyRows(
            progress: work.publicationProgress,
            chapterTitle: work.hasStartedReading ? WorkReadingPosition.title(from: work.readiumLocator) : nil,
            downloadedAt: work.downloadedAt,
            tags: work.tags.map(\.name).sorted(),
            collections: work.activeCollections.map(\.name).sorted(),
            queues: work.activeQueueMemberships.compactMap { $0.queue?.name }.sorted(),
            hasFile: hasFile,
            fileSize: hasFile ? WorkDetailPresentation.fileSizeLabel(forFileAt: work.fileURL) : nil
        )
    }

    private func myCopyRowView(_ row: WorkDetailPresentation.MyCopyRow) -> some View {
        SubjectFormRow(label: row.label) {
            HStack(spacing: 10) {
                SubjectFormValue(text: row.value)
                if let action = row.action {
                    Button(action.title) { performMyCopyAction(row.kind) }
                        .buttonStyle(.plain)
                        .font(.system(size: 15))
                        .foregroundStyle(.accentInk)
                        .accessibilityLabel(action.title + " " + row.label.lowercased())
                }
            }
        }
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
