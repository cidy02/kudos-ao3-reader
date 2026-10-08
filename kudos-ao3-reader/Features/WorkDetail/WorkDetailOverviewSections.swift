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
        // Artboard 1a's own order from here: the grouped facts, the archive
        // tallies, the page's two actions, then everything local behind one row.
        factsCardSection
        archiveStatsSection
        pageActionsSection
        seriesSection
        // Origin and conversion live in My copy (1a); the page ends at the row.
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
                        .font(.system(size: summarySize, design: .serif))
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
                    palette: workPalette,
                    onSubscribeSuccess: downloadIfSubscribedWithoutEPUB
                )
                .pageBodyRow(top: 24)
            }
        }
    }

    // MARK: Quick actions

    /// 1a: the local half lives behind "…" and the My copy row, not in a grid
    /// on the page. Open on AO3, Mark as Finished and Comments already have
    /// their own places on the page.
    @ViewBuilder
    var localWorkMenuItems: some View {
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
        let queued = localWork?.isInSavedForLaterQueue ?? false
        let later = WorkActionLabels.savedForLater(isQueued: queued)
        Button {
            if queued { removeFromSavedForLater() } else { saveForLater() }
        } label: {
            Label(later.title, systemImage: later.systemImage)
        }
        .disabled(working || preservingStatusIsBusy)
        let download = localWork.flatMap(WorkDownload.action(for:))
        let downloadLabel = download.map(WorkDownload.label) ?? WorkDownload.label(.download)
        Button(action: toggleSaved) {
            Label(downloadLabel.title, systemImage: downloadLabel.systemImage)
        }
        .disabled(working || download?.isInformational == true)
        if let ao3URL {
            Divider()
            ShareLink(item: ao3URL) {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            Button {
                router.open(ao3URL)
            } label: {
                Label("Open on AO3", systemImage: "safari")
            }
        }
    }

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
                    Text("When you download more works from this series, they will appear here.")
                }
            }
        }
    }
}
