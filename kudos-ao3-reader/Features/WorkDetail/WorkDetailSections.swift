import SwiftUI

// The Tags, Discussion, and Library sections of the redesigned Work Details
// hub. Tags carries the AO3 classification chips (unchanged tap-to-search
// behavior); Discussion is the native comments entry point (no comment pages
// are fetched until the user opens them); Library holds every piece of
// local/personal state, clearly separated from AO3 metadata.

extension WorkDetailView {
    // MARK: - Tags section

    private struct TagGroup {
        let title: String
        let tags: [String]
        let field: AO3TagSearch.Field
    }

    private var tagGroups: [TagGroup] {
        let categorized: [TagGroup] = [
            TagGroup(title: "Archive Warnings", tags: displayWarnings, field: .warning),
            TagGroup(title: "Fandoms", tags: displayFandoms, field: .fandom),
            TagGroup(title: "Relationships", tags: displayRelationships, field: .relationship),
            TagGroup(title: "Characters", tags: displayCharacters, field: .character),
            TagGroup(title: "Additional Tags", tags: displayFreeforms, field: .freeform)
        ].filter { !$0.tags.isEmpty }
        if !categorized.isEmpty { return categorized }
        // Un-refreshed local imports carry only a flat, uncategorized tag list.
        if let flat = localWork?.workTags, !flat.isEmpty {
            return [TagGroup(title: "Tags", tags: flat, field: .freeform)]
        }
        return []
    }

    @ViewBuilder
    var tagSections: some View {
        let groups = tagGroups
        if groups.isEmpty {
            Section {
                // Only offer an AO3 refresh when a refresh can actually succeed;
                // a plain imported EPUB has no AO3 identity to fetch from.
                Text(ao3WorkID != nil
                    ? "No AO3 tags are available for this work yet. "
                        + "Pull to refresh to fetch the latest details from AO3."
                    : "This imported work isn't linked to AO3, so it has no AO3 tags.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .cardRow()
            }
        } else {
            ForEach(Array(groups.enumerated()), id: \.element.title) { index, group in
                Section {
                    FlowLayout(spacing: 8, rowSpacing: 4) {
                        ForEach(group.tags, id: \.self) { tag in
                            // Tap a tag → search AO3 for works carrying it. Full
                            // canonical text wraps (no truncation).
                            Button { router.searchAO3(group.field, tag) } label: {
                                TagChip(text: tag, multiline: true)
                            }
                            .buttonStyle(.plain)
                            .minimumHitTarget(28)
                        }
                    }
                    .padding(.vertical, 2)
                    .cardRow()
                } header: {
                    Text(group.title)
                } footer: {
                    if index == groups.count - 1 {
                        Text("Tags from AO3. Tap one to search AO3 for works with that tag.")
                    }
                }
            }
        }
    }

    // MARK: - Discussion section

    @ViewBuilder
    var discussionSections: some View {
        if let id = ao3WorkID {
            Section {
                Group {
                    NavigationLink {
                        CommentsView(workID: id, context: commentsWorkContext)
                    } label: {
                        HStack {
                            Label("All Comments", systemImage: "bubble.left.and.bubble.right")
                            Spacer()
                            if let comments = displayComments {
                                Text(comments.formatted())
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                        }
                    }
                    .accessibilityValue(displayComments.map { "\($0.formatted()) comments" } ?? "")

                    // A single-chapter work has no per-chapter view worth opening;
                    // unknown totals ("5/?") keep the entry available.
                    if SavedWork.totalChapterCount(from: displayChapters) != 1 {
                        NavigationLink {
                            CommentsView(
                                workID: id, context: commentsWorkContext,
                                initialFocusesChapter: true
                            )
                        } label: {
                            Label("Chapter Comments", systemImage: "book")
                        }
                    }

                    NavigationLink {
                        CommentsView(
                            workID: id, context: commentsWorkContext,
                            initialComposes: true
                        )
                    } label: {
                        Label("Write a Comment", systemImage: "pencil")
                    }
                }
                .cardRow()
            } header: {
                Text("Comments")
            } footer: {
                Text("Comment pages load when you open them; nothing is fetched in advance.")
            }
        } else {
            Section {
                Text("This work isn't linked to AO3, so its comments aren't available here.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .cardRow()
            }
        }
    }

    // MARK: - Library section

    @ViewBuilder
    var librarySections: some View {
        if let work = localWork {
            libraryStatusSection(for: work)
            libraryStorageSection(for: work)
            libraryActivitySection(for: work)
        } else {
            Section {
                Text("Not in your Library yet. Save it, queue it, or start reading "
                    + "and your download, progress, and tags will appear here.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .cardRow()
            } footer: {
                // The pre-redesign remote lifecycle guidance (reading downloads
                // the file; finishing frees it unless saved/favorited).
                Text(statusFooter)
            }
        }
        myTagsSection
    }

    private func libraryStatusSection(for work: SavedWork) -> some View {
        Section {
            Group {
                stateToggleRow(
                    WorkDetailPresentation.savedAction(isSaved: work.isSaved),
                    isOn: work.isSaved,
                    disabled: working,
                    action: toggleSaved
                )

                savedForLaterRow(for: work)

                if work.isQueuedForLater,
                   work.epubPreservationStatus == .failed || work.epubPreservationStatus == .missingFile {
                    Button {
                        retryPreservation(work)
                    } label: {
                        Label("Retry Queue Preservation", systemImage: "arrow.clockwise")
                    }
                }

                queuesRow(for: work)
                collectionsRow(for: work)

                stateToggleRow(
                    WorkActionLabels.finished(isFinished: work.isFinished),
                    isOn: work.isFinished,
                    disabled: working,
                    action: toggleFinished
                )
            }
            .cardRow()
        } header: {
            Text("Status")
        } footer: {
            Text(statusFooter)
        }
    }

    /// Binary-state row: label + trailing checkmark state indicator (no chevron —
    /// tapping toggles in place, it doesn't navigate).
    private func stateToggleRow(
        _ label: (title: String, systemImage: String),
        isOn: Bool, disabled: Bool, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack {
                Label(label.title, systemImage: label.systemImage)
                Spacer()
                if isOn {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
        }
        .disabled(disabled)
        .accessibilityValue(isOn ? "On" : "Off")
    }

    private func savedForLaterRow(for work: SavedWork) -> some View {
        let queued = work.isInSavedForLaterQueue
        let label = WorkActionLabels.savedForLater(isQueued: queued)
        return Button {
            if queued {
                removeFromSavedForLater()
            } else {
                saveForLater()
            }
        } label: {
            HStack {
                Label(label.title, systemImage: label.systemImage)
                Spacer()
                if preservingStatusIsBusy {
                    ProgressView()
                } else if queued {
                    Text(WorkDetailPresentation.preservationStatusLabel(work.epubPreservationStatus))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
        }
        .disabled(working || preservingStatusIsBusy)
    }

    private func queuesRow(for work: SavedWork) -> some View {
        Button {
            withLocalWork { _ in showingAddToQueue = true }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                // No trailing chevron: this row opens a sheet, not a hierarchical
                // push — HIG reserves the disclosure indicator for the latter.
                Label(
                    WorkDetailPresentation.queueLabel(count: work.queueMemberships.count),
                    systemImage: "list.bullet.rectangle"
                )
                ForEach(queueMembershipLines(for: work)) { line in
                    Text(line.text)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 30)
                }
            }
            .contentShape(Rectangle())
        }
        .disabled(working)
    }

    /// One display line per membership. Identified by the membership's UUID, not
    /// the rendered text — two same-named queues can produce identical strings.
    private struct QueueMembershipLine: Identifiable {
        let id: UUID
        let text: String
    }

    /// "Queue name — #position of count" per queue, using the same ordering
    /// projection the queue screen itself renders.
    private func queueMembershipLines(for work: SavedWork) -> [QueueMembershipLine] {
        work.queueMemberships
            .filter { !$0.isPendingDeletion }
            .compactMap { membership -> QueueMembershipLine? in
                guard let queue = membership.queue, !queue.isPendingDeletion else { return nil }
                let orderedWorks = ReadingQueueService.orderedWorks(in: queue)
                guard let index = orderedWorks.firstIndex(where: { $0.id == work.id }) else {
                    return QueueMembershipLine(id: membership.id, text: queue.name)
                }
                return QueueMembershipLine(
                    id: membership.id,
                    text: "\(queue.name) — #\(index + 1) of \(orderedWorks.count)"
                )
            }
            .sorted { $0.text < $1.text }
    }

    private func collectionsRow(for work: SavedWork) -> some View {
        let names = work.collections.map(\.name).sorted()
        return Button {
            withLocalWork { _ in showingAddToCollection = true }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                // No trailing chevron: this row opens a sheet, not a hierarchical
                // push — HIG reserves the disclosure indicator for the latter.
                Label(
                    WorkDetailPresentation.collectionLabel(count: work.collections.count),
                    systemImage: "square.stack"
                )
                if !names.isEmpty {
                    Text(names.joined(separator: ", "))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 30)
                }
            }
            .contentShape(Rectangle())
        }
        .disabled(working)
    }

    private func libraryStorageSection(for work: SavedWork) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                LabeledContent("Download", value: downloadStatusText(for: work))
                if work.isQueuedForLater {
                    LabeledContent(
                        "Preservation",
                        value: WorkDetailPresentation.preservationStatusLabel(work.epubPreservationStatus)
                    )
                }
            }
            .cardRow()
        } header: {
            Text("Storage")
        }
    }

    private func downloadStatusText(for work: SavedWork) -> String {
        if WorkReaderPreparation.hasReadableEPUB(for: work) {
            if let size = WorkDetailPresentation.fileSizeLabel(forFileAt: work.fileURL) {
                return "Downloaded · \(size)"
            }
            return "Downloaded"
        }
        // Only an AO3-identified work can actually re-download; an imported EPUB
        // with a missing file has no recovery path to promise.
        return ao3WorkID != nil
            ? "File freed — re-downloads when you read"
            : "File missing — imported EPUBs can't be re-downloaded"
    }

    private func libraryActivitySection(for work: SavedWork) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                LabeledContent(
                    "Added",
                    value: work.dateAdded.formatted(date: .abbreviated, time: .shortened)
                )
                LabeledContent(
                    "Last Opened",
                    value: work.lastReadDate
                        .map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "Never"
                )
                if let progressLabel = work.readingProgressLabel {
                    LabeledContent("Progress", value: progressLabel)
                    if let progress = work.readingProgress {
                        ProgressView(value: progress)
                    }
                }
            }
            .cardRow()
        } header: {
            Text("Activity")
        }
    }

    // MARK: My Tags

    private var myTagsSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                let myTags = localWork?.tags ?? []
                if myTags.isEmpty {
                    Text("No tags yet — add some to organize your Library.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(myTags.sorted { $0.name < $1.name }) { tag in
                        HStack {
                            Button { router.filterLibrary(.userTag, tag.name) } label: {
                                Text(tag.name).foregroundStyle(.primary)
                            }
                            .buttonStyle(.plain)
                            Spacer()
                            Button {
                                removeTag(tag)
                            } label: {
                                Image(systemName: "minus.circle.fill").foregroundStyle(.red)
                            }
                            .buttonStyle(.borderless)
                            // 28pt, not the 44pt default: this row is one of several
                            // stacked inside a single shared .cardRow() (myTagsSection),
                            // not its own independent List row, so nothing here already
                            // enforces a 44pt floor — the default would inflate every
                            // tag row's height to 44pt via HStack's tallest-child sizing.
                            // Matches the suggestion-chip row below, which uses the same
                            // 28pt floor for the identical reason.
                            .minimumHitTarget(28)
                            .accessibilityLabel("Remove tag \(tag.name)")
                        }
                    }
                }

                HStack {
                    TextField("Add a tag", text: $newTagName)
                        .onSubmit(addTypedTag)
                    Button("Add", action: addTypedTag)
                        .buttonStyle(.borderless)
                        .disabled(newTagName.trimmingCharacters(in: .whitespaces).isEmpty)
                }

                if !suggestions.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(suggestions, id: \.self) { name in
                                Button { apply(named: name) } label: { TagChip(text: name) }
                                    .buttonStyle(.plain)
                                    .minimumHitTarget(28)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            .cardRow()
        } header: {
            Text("My Tags")
        } footer: {
            Text("My Tags are private to your Library on this device and separate from AO3's tags.")
        }
    }
}
