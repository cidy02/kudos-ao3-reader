import SwiftUI

// Blocks of artboard 1a's page: the serif summary, the ON AO3 chips, the
// state-aware quick-action grid, and the series card. Pure presentation over
// WorkDetailView's existing display values and actions — no new data flow.
//
// The four page blocks here are deliberately not `private`. `WorkDetailView`
// assembles the page in `pageSections`, and 1a's eleven blocks are spread over
// four files — `private` is file-scoped in Swift, so anything the assembly
// names has to be at least internal. The helpers each block uses stay private,
// which is the line worth keeping: a block is part of the page's contract, a
// helper is not.

extension WorkDetailView {
    // MARK: - Overview section

    @ViewBuilder
    var overviewSections: some View {
        summarySection
        ao3ActionsSection
        quickActionsSection
        // Artboard 1a's own order from here: the grouped facts, the archive
        // tallies, the page's two actions, then everything local behind one row.
        factsCardSection
        archiveStatsSection
        pageActionsSection
        seriesSection
        // Local-only: a remote work has no origin to report and nothing converted.
        if let work = localWork {
            WorkProvenanceSections(work: work)
        }
        myCopySection
    }

    // MARK: Summary

    /// Spec 1a sets the summary in a serif face at 16pt over the page wash, with
    /// no card and no "Summary" heading — it is the first prose after the resume
    /// card and nothing else on the page could be mistaken for it. The serif is
    /// doing real work rather than decoration: this is the only run of the
    /// author's own writing on the screen, and setting it apart from the app's
    /// own labels is the point.
    ///
    /// Show More survives the restyle. The artboard's example summary is one
    /// sentence; real ones run for paragraphs, and an uncollapsed wall of them
    /// would push every fact on the page below the fold.
    @ViewBuilder
    var summarySection: some View {
        // Bound once per render: a local work's summary strips HTML on read.
        let summary = displaySummary
        if !summary.isEmpty {
            let collapses = WorkDetailPresentation.summaryCollapses(summary)
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text(summary)
                        .font(.system(size: 16, design: .serif))
                        // CSS line-height 1.6 on 16px is 25.6pt of line box; a
                        // 16pt line is about 20 of that on its own, so the rest
                        // is added here.
                        .lineSpacing(5.5)
                        .foregroundStyle(Color.primary.opacity(0.82))
                        .fixedSize(horizontal: false, vertical: true)
                        .lineLimit(collapses && !summaryExpanded ? 8 : nil)
                    if collapses {
                        Button(summaryExpanded ? "Show Less" : "Show More") {
                            withAnimationUnlessReduced(reduceMotion: reduceMotion) { summaryExpanded.toggle() }
                        }
                        .font(.subheadline.weight(.medium))
                        .buttonStyle(.borderless)
                        .accessibilityHint("Expands or collapses the work summary")
                    }
                }
                .pageBodyRow(top: 20)
            }
        }
    }

    // MARK: On AO3

    /// Artboard 1a's ON AO3 chips. Shown only to a signed-in reader with an AO3
    /// work to act on: every one of these four is a write that fails with
    /// `AO3WriteError.notSignedIn` otherwise, and four chips that cannot work is
    /// worse than the overflow menu they also live in. Nothing is lost signed
    /// out — the toolbar still carries them, and the work's kudos and comment
    /// tallies are facts the figure strip states regardless.
    @ViewBuilder
    var ao3ActionsSection: some View {
        if let id = ao3WorkID, auth.isLoggedIn {
            Section {
                WorkAO3ActionChips(
                    workID: id,
                    kudosCount: displayKudos,
                    actions: workActions,
                    palette: workPalette
                )
                .pageBodyRow(top: 24)
            }
        }
    }

    // MARK: Quick actions

    /// Three columns normally; two at accessibility Dynamic Type sizes so the
    /// tile labels keep room to grow instead of scaling away.
    private var quickActionColumns: [GridItem] {
        let count = dynamicTypeSize.isAccessibilitySize ? 2 : 3
        return Array(repeating: GridItem(.flexible(), spacing: 10), count: count)
    }

    var quickActionsSection: some View {
        Section {
            LazyVGrid(columns: quickActionColumns, spacing: 10) {
                // No Read tile: artboard 1a's resume card at the top of the page
                // owns that action now (see `WorkDetailView.resumeCardRow`), and
                // the grid would offer a second, quieter copy of it.
                if let ao3URL {
                    quickAction(title: "Open on AO3", systemImage: "safari") {
                        router.open(ao3URL)
                    }
                }
                savedQuickAction
                laterQuickAction
                queueQuickAction
                collectionQuickAction
                finishedQuickAction
                commentsQuickAction
            }
            // Each tile owns its card chrome (same treatment as Account's
            // shortcut grid); the containing row stays transparent.
            .listRowInsets(EdgeInsets(
                top: 6,
                leading: CardListMetrics.sideMargin,
                bottom: 6,
                trailing: CardListMetrics.sideMargin
            ))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
        } header: {
            Text("Quick Actions")
        }
    }

    private func quickAction(
        title: String, systemImage: String, detail: String? = nil,
        isBusy: Bool = false, disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            WorkQuickActionTile(
                title: title, systemImage: systemImage,
                detail: detail, isBusy: isBusy
            )
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }

    private var savedQuickAction: some View {
        let label = WorkDetailPresentation.savedAction(isSaved: localWork?.isSaved ?? false)
        return quickAction(
            title: label.title, systemImage: label.systemImage,
            disabled: working, action: toggleSaved
        )
    }

    private var laterQuickAction: some View {
        let queued = localWork?.isInSavedForLaterQueue ?? false
        let label = WorkDetailPresentation.laterAction(isQueued: queued)
        return quickAction(
            title: label.title, systemImage: label.systemImage,
            isBusy: preservingStatusIsBusy && !working,
            disabled: working || preservingStatusIsBusy
        ) {
            if queued {
                removeFromSavedForLater()
            } else {
                saveForLater()
            }
        }
    }

    private var queueQuickAction: some View {
        quickAction(
            title: WorkDetailPresentation.queueLabel(count: localWork?.queueMemberships.count ?? 0),
            systemImage: "list.bullet.rectangle",
            disabled: working
        ) {
            withLocalWork { _ in showingAddToQueue = true }
        }
    }

    private var collectionQuickAction: some View {
        quickAction(
            title: WorkDetailPresentation.collectionLabel(count: localWork?.collections.count ?? 0),
            systemImage: "square.stack",
            disabled: working
        ) {
            withLocalWork { _ in showingAddToCollection = true }
        }
    }

    private var finishedQuickAction: some View {
        let label = WorkActionLabels.finished(isFinished: localWork?.isFinished ?? false)
        return quickAction(
            title: label.title, systemImage: label.systemImage,
            disabled: working, action: toggleFinished
        )
    }

    private var commentsQuickAction: some View {
        quickAction(
            title: "Comments",
            systemImage: "bubble.left.and.bubble.right",
            detail: displayComments.map { $0.formatted() }
        ) {
            workActions.startViewingComments(context: commentsWorkContext)
        }
    }

    // MARK: Series

    @ViewBuilder
    var seriesSection: some View {
        if !displaySeriesTitle.isEmpty {
            Section {
                Group {
                    VStack(alignment: .leading, spacing: 10) {
                        LabeledContent("Series", value: displaySeriesTitle)
                        if displaySeriesPosition > 0 {
                            LabeledContent("Part", value: "\(displaySeriesPosition)")
                        }
                    }

                    ForEach(seriesWorks) { other in
                        NavigationLink {
                            WorkDetailView(work: other)
                        } label: {
                            HStack {
                                if other.seriesPosition > 0 {
                                    Text("\(other.seriesPosition).")
                                        .foregroundStyle(.secondary)
                                        .monospacedDigit()
                                }
                                Text(other.title).lineLimit(1)
                            }
                        }
                    }

                    if !displaySeriesURL.isEmpty {
                        // Downloading a whole series needs a local anchor record;
                        // offered once the work itself is in the library.
                        if localWork != nil {
                            Button {
                                Task { await downloadSeries() }
                            } label: {
                                HStack {
                                    Label(
                                        queuingSeries ? "Fetching series…" : "Download Whole Series",
                                        systemImage: "arrow.down.circle"
                                    )
                                    Spacer()
                                    if queuingSeries { ProgressView() }
                                }
                            }
                            .disabled(queuingSeries)
                        }

                        Button {
                            if let url = URL(string: displaySeriesURL) { router.open(url) }
                        } label: {
                            Label("View Full Series on AO3", systemImage: "safari")
                        }
                    }
                }
                .cardRow()
            } header: {
                Text("Series")
            } footer: {
                if localWork != nil, seriesWorks.isEmpty {
                    Text("Other works in this series will appear here once you download them.")
                }
            }
        }
    }
}
