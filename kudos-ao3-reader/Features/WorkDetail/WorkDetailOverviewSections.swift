import SwiftUI

// The Overview section of the redesigned Work Details hub: summary, the
// state-aware quick-action grid, the purpose-based metadata cards
// (Publication / Work / Stats), and the series card. Pure presentation over
// WorkDetailView's existing display values and actions — no new data flow.

extension WorkDetailView {
    // MARK: - Overview section

    @ViewBuilder
    var overviewSections: some View {
        summarySection
        quickActionsSection
        publicationCardSection
        workInfoCardSection
        statsCardSection
        seriesSection
    }

    // MARK: Summary

    @ViewBuilder
    private var summarySection: some View {
        // Bound once per render: a local work's summary strips HTML on read.
        let summary = displaySummary
        if !summary.isEmpty {
            let collapses = WorkDetailPresentation.summaryCollapses(summary)
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(summary)
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
                .cardRow()
            } header: {
                Text("Summary")
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

    private var quickActionsSection: some View {
        Section {
            LazyVGrid(columns: quickActionColumns, spacing: 10) {
                readQuickAction
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

    private var readQuickAction: some View {
        let label = WorkDetailPresentation.readAction(
            hasEPUB: localWork?.hasEPUB ?? false, working: working,
            continueReading: (localWork?.hasStartedReading ?? false)
                && !(localWork?.isFinished ?? false)
        )
        return quickAction(
            title: label.title, systemImage: label.systemImage,
            isBusy: working, disabled: working, action: read
        )
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
            withAnimationUnlessReduced(reduceMotion: reduceMotion) { selectedTab = .discussion }
        }
    }

    // MARK: Details cards (Publication / Work / Stats)

    @ViewBuilder
    private var publicationCardSection: some View {
        let hasAny = !displayPublishedDate.isEmpty || !displayUpdatedDate.isEmpty
            || !displayLanguage.isEmpty || localWork != nil
        if hasAny {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    if !displayPublishedDate.isEmpty {
                        LabeledContent("Published", value: displayPublishedDate)
                    }
                    if !displayUpdatedDate.isEmpty {
                        LabeledContent("Updated", value: displayUpdatedDate)
                    }
                    if !displayLanguage.isEmpty {
                        LabeledContent("Language", value: displayLanguage)
                    }
                    if let work = localWork {
                        LabeledContent(
                            "Added",
                            value: work.dateAdded.formatted(date: .abbreviated, time: .shortened)
                        )
                    }
                }
                .cardRow()
            } header: {
                Text("Publication")
            }
        }
    }

    @ViewBuilder
    private var workInfoCardSection: some View {
        let hasAny = !displayRating.isEmpty || !displayCategories.isEmpty
            || displayStatus != nil || displayWords != nil || !displayChapters.isEmpty
        if hasAny {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    if !displayRating.isEmpty {
                        LabeledContent("Rating", value: displayRating)
                    }
                    if !displayCategories.isEmpty {
                        LabeledContent("Category", value: displayCategories.joined(separator: ", "))
                    }
                    if let status = displayStatus {
                        LabeledContent("Status", value: status)
                    }
                    if let words = displayWords {
                        LabeledContent("Words", value: words.formatted())
                    }
                    if !displayChapters.isEmpty {
                        LabeledContent("Chapters", value: displayChapters)
                    }
                }
                .cardRow()
            } header: {
                Text("Work")
            }
        }
    }

    @ViewBuilder
    private var statsCardSection: some View {
        if displayKudos != nil || displayComments != nil || displayHits != nil || ao3WorkID != nil {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    if let hits = displayHits {
                        LabeledContent("Hits", value: hits.formatted())
                    }
                    if let kudos = displayKudos {
                        LabeledContent("Kudos", value: kudos.formatted())
                    }
                    if ao3WorkID != nil {
                        // Tappable: jumps to the Discussion section, which owns
                        // the full comments entry points.
                        Button {
                            withAnimationUnlessReduced(reduceMotion: reduceMotion) { selectedTab = .discussion }
                        } label: {
                            HStack {
                                Text("Comments")
                                    .foregroundStyle(.primary)
                                Spacer()
                                Text(displayComments.map { $0.formatted() } ?? "Open")
                                    .foregroundStyle(.secondary)
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Comments")
                        .accessibilityValue(displayComments.map { $0.formatted() } ?? "Open")
                        .accessibilityHint("Opens the Discussion section")
                    } else if let comments = displayComments {
                        LabeledContent("Comments", value: comments.formatted())
                    }
                }
                .cardRow()
            } header: {
                Text("Stats")
            }
        }
    }

    // MARK: Series

    @ViewBuilder
    private var seriesSection: some View {
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
