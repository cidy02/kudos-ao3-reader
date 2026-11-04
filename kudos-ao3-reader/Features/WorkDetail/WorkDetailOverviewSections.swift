import SwiftUI

// Blocks of board 19's page: the Summary and the Series card, plus the Library
// rows of the ••• menu. Pure presentation over WorkDetailView's existing display
// values and actions — no new data flow.
//
// The page blocks here are deliberately not `private`: `WorkDetailView` assembles
// the page (`pageSections`, `WorkDetailLayout`), and its blocks are spread over
// several files — `private` is file-scoped in Swift, so anything the assembly
// names has to be at least internal. The helpers each block uses stay private,
// which is the line worth keeping: a block is part of the page's contract, a
// helper is not.

extension WorkDetailView {
    // MARK: Summary

    /// Board 19's Summary: a Title 3 header, the author's text in the body face,
    /// and a Notes link. The old serif face is gone with the board's own sans.
    ///
    /// Show More survives the restyle. The board's example summary is two
    /// sentences; real ones run for paragraphs, and an uncollapsed wall of them
    /// would push every fact on the page below the fold.
    ///
    /// Notes: the app holds the summary but not the author's notes (AO3 prints
    /// them on the work page, and the EPUB carries them in the reader), so the
    /// link opens the work on AO3, where they are, rather than pretending to
    /// show something this screen does not have.
    @ViewBuilder
    var summarySection: some View {
        // Bound once per render: a local work's summary strips HTML on read.
        let summary = displaySummary
        if !summary.isEmpty {
            let collapses = WorkDetailPresentation.summaryCollapses(summary)
            Section {
                SectionRuleHeader(title: "Summary")
                    .accessibilityAddTraits(.isHeader)
                    .pageBodyRow(top: 24, gutter: 0)

                VStack(alignment: .leading, spacing: 8) {
                    Text(summary)
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineLimit(collapses && !summaryExpanded ? 8 : nil)
                    HStack(spacing: 16) {
                        if collapses {
                            Button(summaryExpanded ? "Show Less" : "Show More") {
                                withAnimationUnlessReduced(reduceMotion: reduceMotion) { summaryExpanded.toggle() }
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint("Expands or collapses the work summary")
                        }
                        if let id = ao3WorkID {
                            Button("Notes") { router.open(AO3Client.workURL(workID: id)) }
                                .buttonStyle(.plain)
                                .accessibilityHint("Opens this work on AO3, where the author's notes are")
                        }
                    }
                    .font(.body)
                    .foregroundStyle(.accentInk)
                }
                .pageBodyRow(top: 6)
            }
        }
    }

    // MARK: Quick actions

    /// Spec board 20: Library section rows in the Work Detail "…" menu. When the work is
    /// not on AO3 its icon row holds Want to Read, Favorite and Finished instead, so they
    /// are left out here (`includesQuickToggles: false`).
    @ViewBuilder
    func localWorkMenuItems(includesQuickToggles: Bool = true) -> some View {
        if includesQuickToggles {
            let queued = localWork?.isInSavedForLaterQueue ?? false
            let later = WorkActionLabels.savedForLater(isQueued: queued)
            Button(action: toggleWantToRead) {
                Label(later.title, systemImage: later.systemImage)
            }
            .disabled(working || preservingStatusIsBusy)

            let favLabels = WorkActionLabels.favorite(isFavorite: localWork?.isFavorite ?? false)
            Button(action: toggleFavorite) {
                Label(favLabels.title, systemImage: favLabels.systemImage)
            }

            let finishedLabels = WorkActionLabels.finished(isFinished: localWork?.isFinished ?? false)
            Button(action: toggleFinished) {
                Label(finishedLabels.title, systemImage: finishedLabels.systemImage)
            }
            .disabled(working)
        }

        Button {
            withLocalWork { _ in showingAddToQueue = true }
        } label: {
            Label("Add to Queue", systemImage: "list.bullet.rectangle")
        }
        .disabled(working)

        Button {
            withLocalWork { _ in showingAddToCollection = true }
        } label: {
            Label("Add to Collection", systemImage: "square.stack")
        }
        .disabled(working)

        let download = localWork.flatMap(WorkDownload.action(for:))
        let downloadLabel = download.map(WorkDownload.label) ?? WorkDownload.label(.download)
        Button(action: toggleSaved) {
            Label(downloadLabel.title, systemImage: downloadLabel.systemImage)
        }
        .disabled(working || download?.isInformational == true)
    }

    /// Board 20's icon row for a work that is not on AO3 (no Kudos / Bookmark /
    /// Subscribe to offer): the library toggles, then Share when there is a link.
    @ViewBuilder
    func localWorkTopRow(share: URL?) -> some View {
        MenuTopRow {
            let later = MenuTopRowRules.wantToRead(isQueued: localWork?.isInSavedForLaterQueue ?? false)
            Button(action: toggleWantToRead) {
                Label(later.title, systemImage: later.systemImage)
            }
            .accessibilityLabel(later.accessibilityLabel)
            .disabled(working || preservingStatusIsBusy)

            let fav = MenuTopRowRules.favorite(isFavorite: localWork?.isFavorite ?? false)
            Button(action: toggleFavorite) {
                Label(fav.title, systemImage: fav.systemImage)
            }
            .accessibilityLabel(fav.accessibilityLabel)

            let finished = MenuTopRowRules.finished(isFinished: localWork?.isFinished ?? false)
            Button(action: toggleFinished) {
                Label(finished.title, systemImage: finished.systemImage)
            }
            .accessibilityLabel(finished.accessibilityLabel)
            .disabled(working)

            if let share {
                ShareLink(item: share) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
            }
        }
    }

    private func toggleWantToRead() {
        if localWork?.isInSavedForLaterQueue ?? false { removeFromSavedForLater() } else { saveForLater() }
    }

    private func toggleFavorite() {
        withLocalWork { work in
            work.isFavorite.toggle()
            work.markModified()
            context.saveBestEffort(reason: "Saving favorite state failed")
        }
    }

    // MARK: Series

    /// One line of the Series card.
    private enum SeriesRow: Identifiable {
        case header
        case entry(SeriesEntry)
        case download
        case openOnAO3

        var id: String {
            switch self {
            case .header: "header"
            case let .entry(entry): entry.id
            case .download: "download"
            case .openOnAO3: "open"
            }
        }
    }

    /// A numbered work in the series: the ones downloaded here and this work.
    private struct SeriesEntry: Identifiable {
        let id: String
        let position: Int
        let title: String
        let work: SavedWork?
    }

    /// The works of this series this device knows — the downloaded others, and
    /// this work at its own position — in series order. A position of 0 means
    /// "unknown" and sorts last, in the order the works were found.
    private var seriesEntries: [SeriesEntry] {
        var entries: [SeriesEntry] = seriesWorks.map {
            SeriesEntry(id: $0.id.uuidString, position: $0.seriesPosition, title: $0.title, work: $0)
        }
        entries.append(SeriesEntry(id: "current", position: displaySeriesPosition, title: displayTitle, work: nil))
        return entries.enumerated()
            .sorted { lhs, rhs in
                let left = lhs.element.position > 0 ? lhs.element.position : Int.max
                let right = rhs.element.position > 0 ? rhs.element.position : Int.max
                return left == right ? lhs.offset < rhs.offset : left < right
            }
            .map(\.element)
    }

    /// The card's lines in order. Downloading a whole series needs a local anchor
    /// record, so that line is offered once the work itself is in the library.
    private var seriesRows: [SeriesRow] {
        var rows: [SeriesRow] = [.header]
        rows += seriesEntries.map { SeriesRow.entry($0) }
        let hasSeriesURL = !displaySeriesURL.isEmpty
        if hasSeriesURL, localWork != nil { rows.append(.download) }
        if hasSeriesURL { rows.append(.openOnAO3) }
        return rows
    }

    @ViewBuilder
    var seriesSection: some View {
        if !displaySeriesTitle.isEmpty {
            let rows = seriesRows
            Section {
                SectionRuleHeader(title: "Series")
                    .accessibilityAddTraits(.isHeader)
                    .pageBodyRow(top: 24, gutter: 0)

                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    seriesRowView(row)
                        .panelSegment(index, of: rows.count, gutter: SubjectMetrics.gutter)
                }

                if localWork != nil, seriesWorks.isEmpty {
                    Text("When you download more works from this series, they will appear here.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .pageBodyRow(top: 8)
                }
            }
        }
    }

    @ViewBuilder
    private func seriesRowView(_ row: SeriesRow) -> some View {
        switch row {
        case .header:
            // A row that states the series and, when AO3 gave its address, opens it.
            if let url = URL(string: displaySeriesURL) {
                Button { router.open(url) } label: { seriesHeaderLine(opens: true) }
                    .buttonStyle(.plain)
            } else {
                seriesHeaderLine(opens: false)
            }
        case let .entry(entry):
            seriesEntryRow(entry)
        case .download:
            Button {
                Task { await downloadSeries() }
            } label: {
                HStack(spacing: 10) {
                    Label(
                        queuingSeries ? "Fetching series…" : "Download Whole Series",
                        systemImage: "arrow.down.circle"
                    )
                    .foregroundStyle(.accentInk)
                    Spacer(minLength: 0)
                    if queuingSeries { ProgressView().accentFill() }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(queuingSeries)
        case .openOnAO3:
            Button {
                if let url = URL(string: displaySeriesURL) { router.open(url) }
            } label: {
                Label("View Full Series on AO3", systemImage: "safari")
                    .foregroundStyle(.accentInk)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private func seriesHeaderLine(opens: Bool) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 0) {
                Text(displaySeriesTitle).font(.body)
                if displaySeriesPosition > 0 {
                    Text("Part \(displaySeriesPosition)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if opens { seriesChevron }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    private var seriesChevron: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Color.secondary.opacity(0.7))
            .accessibilityHidden(true)
    }

    /// A numbered line: "2." then the title, "This work" for the open one, a
    /// chevron for the others. A mature work under Blur is unnamed until revealed,
    /// and the tap reveals (it used to give the title and open the page unrevealed).
    @ViewBuilder
    private func seriesEntryRow(_ entry: SeriesEntry) -> some View {
        let number = entry.position > 0 ? "\(entry.position)." : ""
        if let other = entry.work {
            if gate.isBlurred(other, enabled: hideMature, mode: matureMode) {
                Button {
                    gate.reveal(other)
                } label: {
                    seriesEntryLine(number: number, title: "Hidden mature work", isCurrent: false, dimmed: true)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Hidden mature work. Activate to reveal.")
            } else {
                seriesEntryLine(number: number, title: other.title, isCurrent: false, dimmed: false)
                    .subjectRowNavigation(accessibilityLabel: other.title) {
                        WorkDetailView(work: other)
                    }
            }
        } else {
            seriesEntryLine(number: number, title: entry.title, isCurrent: true, dimmed: false)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isSelected)
        }
    }

    private func seriesEntryLine(number: String, title: String, isCurrent: Bool, dimmed: Bool) -> some View {
        HStack(spacing: 10) {
            Text(number)
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(minWidth: 22, alignment: .leading)
            Text(title)
                .font(.body.weight(isCurrent ? .semibold : .regular))
                .foregroundStyle(dimmed ? .secondary : .primary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            if isCurrent {
                Text("This work")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if !dimmed {
                seriesChevron
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
    }
}
