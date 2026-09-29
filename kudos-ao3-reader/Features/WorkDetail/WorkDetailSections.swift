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
        /// Spec 1a tints exactly one cluster — the relationships — and leaves
        /// characters and freeforms neutral. That is the accent staying scarce:
        /// the relationship is what a reader picks a fic for, and if every
        /// cluster took the colour none of them would mean anything by it.
        var isTinted = false
    }

    private var tagGroups: [TagGroup] {
        let categorized: [TagGroup] = [
            TagGroup(title: "Archive Warnings", tags: displayWarnings, field: .warning),
            TagGroup(title: "Fandoms", tags: displayFandoms, field: .fandom),
            TagGroup(title: "Relationships", tags: displayRelationships,
                     field: .relationship, isTinted: true),
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
                    .pageBodyRow(top: 20)
            }
        } else {
            ForEach(Array(groups.enumerated()), id: \.element.title) { index, group in
                Section {
                    tagCluster(group)
                        .pageBodyRow(top: index == 0 ? 20 : 22)

                    if index == groups.count - 1 {
                        Text("Tags come from AO3. Tap one to search the archive for works carrying it.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .pageBodyRow(top: 16)
                    }
                }
            }
        }
    }

    /// Artboard 1a's tag cluster: the field label, then the chips, straight on
    /// the page wash.
    ///
    /// The card that used to hold each group is gone. Five stacked cards made
    /// the page read as five things when it is one — a work's classification —
    /// and the label plus the chips' own shapes already separate the groups.
    ///
    /// The count is printed only where it tells the reader something they cannot
    /// see at a glance. Two relationships are two chips; nineteen freeforms are
    /// a paragraph, and knowing it is nineteen is worth a line.
    private func tagCluster(_ group: TagGroup) -> some View {
        var printedCount: Int?
        if group.tags.count > 4 {
            printedCount = group.tags.count
        }
        return VStack(alignment: .leading, spacing: 9) {
            SubjectFieldLabel(text: group.title, count: printedCount)

            FlowLayout(spacing: 7, rowSpacing: 7) {
                ForEach(group.tags, id: \.self) { tag in
                    // Tap a tag → search AO3 for works carrying it.
                    Button { router.searchAO3(group.field, tag) } label: {
                        SubjectChip(
                            text: tag,
                            style: group.isTinted ? .tinted : .neutral,
                            palette: workPalette
                        )
                    }
                    .buttonStyle(.plain)
                    .minimumHitTarget(30)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Comments

    /// The ways into the discussion, as a labelled group of form rows.
    ///
    /// Artboard 1a offers only the accented COMMENTS cell in its tally strip,
    /// and that cell is wired — but it is one way in, and this screen has three.
    /// Chapter comments and Write a Comment are reachable from nowhere else on
    /// the page, so dropping them to match a mock would be exactly the
    /// scanability regression `AGENTS.md` forbids.
    ///
    /// The links stay value-based. A destination-based `NavigationLink` would
    /// sit outside the stack's path and be discarded by the author-byline push
    /// made from inside Comments — see `AO3CommentsRoute`.
    @ViewBuilder
    var commentsSection: some View {
        if let id = ao3WorkID {
            Section {
                SubjectFieldLabel(text: "Comments", style: .formGroup)
                    .padding(.bottom, 9)
                    .pageBodyRow(top: 24)

                commentsRows(workID: id)

                Text("Comment pages load when you open them; nothing is fetched in advance.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .pageBodyRow(top: 9)
            }
        }
    }

    /// One `List` row per link.
    ///
    /// The three ways in shared a single `VStack` row, and `List` gives a row
    /// one tap target — so a tap anywhere on the card fired every
    /// `subjectRowNavigation` inside it and pushed Comments two or three deep,
    /// with a Back press owed for each. `panelSegment` is the same card drawn
    /// as separate rows, which is the shape the rest of the app now uses.
    @ViewBuilder
    private func commentsRows(workID id: Int) -> some View {
        // A single-chapter work has no per-chapter view worth opening; an
        // unknown total ("5/?") is not one chapter, so it keeps the entry.
        let hasChapterComments = SavedWork.totalChapterCount(from: displayChapters) != 1
        let count = hasChapterComments ? 3 : 2

        SubjectFormRow(
            label: "All comments",
            value: displayComments.map { $0.formatted() } ?? "",
            showsDisclosure: true
        )
        .subjectRowNavigation(
            to: AO3CommentsRoute(workID: id, context: commentsWorkContext),
            accessibilityLabel: "All comments"
        )
        .panelSegment(0, of: count, gutter: SubjectMetrics.headerGutter)

        if hasChapterComments {
            SubjectFormRow(label: "Chapter comments", value: "", showsDisclosure: true)
                .subjectRowNavigation(
                    to: AO3CommentsRoute(
                        workID: id, context: commentsWorkContext, focusesChapter: true
                    ),
                    accessibilityLabel: "Chapter comments"
                )
                .panelSegment(1, of: count, gutter: SubjectMetrics.headerGutter)
        }

        SubjectFormRow(label: "Write a comment", value: "", showsDisclosure: true)
            .subjectRowNavigation(
                to: AO3CommentsRoute(
                    workID: id, context: commentsWorkContext, composes: true
                ),
                accessibilityLabel: "Write a comment"
            )
            .panelSegment(count - 1, of: count, gutter: SubjectMetrics.headerGutter)
    }

    // MARK: - Library section

    @ViewBuilder
    var librarySections: some View {
        if let work = localWork {
            myCopyStripSection(for: work)
            libraryStatusSection(for: work)
            libraryQueuesSection(for: work)
            libraryCollectionsSection(for: work)
            libraryStorageSection(for: work)
            libraryActivitySection(for: work)
            // Origin and conversion are facts about the local file, and 1a puts
            // everything local behind this sheet rather than on the page.
            WorkProvenanceSections(work: work)
        } else {
            Section {
                Text("Not in your Library yet. Save it, queue it, or start reading "
                    + "and your download, progress, and tags will appear here.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .myCopyRow()
            } footer: {
                // The pre-redesign remote lifecycle guidance (reading downloads
                // the file; finishing frees it unless saved/favorited).
                Text(statusFooter)
            }
        }
        myTagsSection
    }

    /// 1a's three figures under the sheet's title: how far in, how much is on the
    /// device, and whether it is kept (never freed on finishing).
    private func myCopyStripSection(for work: SavedWork) -> some View {
        let hasFile = WorkReaderPreparation.hasReadableEPUB(for: work)
        let progress = work.publicationProgress.map { "\(Int(($0 * 100).rounded()))%" } ?? "—"
        let size = hasFile ? WorkDetailPresentation.fileSizeLabel(forFileAt: work.fileURL) ?? "—" : "—"
        let kept = hasFile && work.isProtected
        return Group {
            SubjectStatStrip(
                cells: [
                    .init(value: progress, label: "Progress"),
                    .init(value: size, label: "On device"),
                    .init(value: kept ? "Kept" : "No", label: "Preserved", tint: kept ? .green : nil)
                ],
                palette: workPalette
            )
            .myCopyRow(top: 0, bottom: 0)
        }
    }

    private func libraryStatusSection(for work: SavedWork) -> some View {
        Group {
            myCopyHeader("Status")
            let download = WorkDetailPresentation.downloadState(WorkDownload.action(for: work))
            myCopyToggleRow(download.title, isOn: download.isOn, disabled: working || !download.isEnabled,
                            action: toggleSaved)
            savedForLaterRow(for: work)
            if work.isQueuedForLater,
               work.epubPreservationStatus == .failed || work.epubPreservationStatus == .missingFile {
                Button {
                    retryPreservation(work)
                } label: {
                    myCopyAddLabel("Retry Queue Preservation", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .myCopyRow()
            }
            // 1a names the state and checks it, rather than a verb.
            myCopyToggleRow(
                "Finished",
                isOn: work.isFinished,
                disabled: working,
                action: toggleFinished
            )
        }
    }

    func myCopyHeader(_ title: String, note: String? = nil) -> some View {
        MyCopyGroupHeader(title: title, note: note)
    }

    /// Binary-state row: the name, and 1a's filled check in the work's colour
    /// when on. Tapping toggles in place, so no chevron.
    private func myCopyToggleRow(
        _ title: String, isOn: Bool, value: String? = nil, busy: Bool = false,
        disabled: Bool, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text(title)
                    .font(.system(size: 14.5))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if isOn {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)
                }
                if busy {
                    ProgressView().controlSize(.small)
                } else if let value {
                    myCopyValue(value)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .accessibilityValue(isOn ? "On" : "Off")
        .myCopyRow()
    }

    /// A fact row: name on the left, the value dim and tabular on the right.
    func myCopyValueRow(_ title: String, _ value: String) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.system(size: 14.5))
                .frame(maxWidth: .infinity, alignment: .leading)
            myCopyValue(value)
        }
        .accessibilityElement(children: .combine)
        .myCopyRow()
    }

    private func myCopyValue(_ value: String) -> some View {
        Text(value)
            .font(.system(size: 13))
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
    }

    /// 1a's "+ Add to queue": an accent plus and label, the group's last row.
    private func myCopyAddLabel(_ title: String, systemImage: String = "plus") -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
            Text(title)
                .font(.system(size: 14, weight: .medium))
        }
        .foregroundStyle(.tint)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func savedForLaterRow(for work: SavedWork) -> some View {
        let queued = work.isInSavedForLaterQueue
        return myCopyToggleRow(
            "Saved for Later",
            isOn: queued,
            value: queued ? WorkDetailPresentation.preservationStatusLabel(work.epubPreservationStatus) : nil,
            busy: preservingStatusIsBusy,
            disabled: working || preservingStatusIsBusy
        ) {
            if queued { removeFromSavedForLater() } else { saveForLater() }
        }
    }

    /// One row per queue ("Neon reread · #3 of 12"), then Add to queue — 1a.
    private func libraryQueuesSection(for work: SavedWork) -> some View {
        Group {
            myCopyHeader("Queues")
            ForEach(queueMembershipLines(for: work)) { line in
                myCopyValueRow(line.name, line.position ?? "")
            }
            Button {
                withLocalWork { _ in showingAddToQueue = true }
            } label: {
                myCopyAddLabel("Add to queue")
            }
            .buttonStyle(.plain)
            .disabled(working)
            .myCopyRow(top: 6, bottom: 6)
        }
    }

    /// One display line per membership. Identified by the membership's UUID, not
    /// the rendered text — two same-named queues can produce identical strings.
    private struct QueueMembershipLine: Identifiable {
        let id: UUID
        let name: String
        let position: String?
    }

    /// Queue name and "#position of count", using the same ordering projection
    /// the queue screen itself renders. Counted from the live memberships: a
    /// soft-deleted queue keeps its memberships and must not be listed.
    private func queueMembershipLines(for work: SavedWork) -> [QueueMembershipLine] {
        work.activeQueueMemberships
            .compactMap { membership -> QueueMembershipLine? in
                guard let queue = membership.queue else { return nil }
                let orderedWorks = ReadingQueueService.orderedWorks(in: queue)
                let position = orderedWorks.firstIndex(where: { $0.id == work.id })
                    .map { "#\($0 + 1) of \(orderedWorks.count)" }
                return QueueMembershipLine(id: membership.id, name: queue.name, position: position)
            }
            .sorted { $0.name < $1.name }
    }

    private func libraryCollectionsSection(for work: SavedWork) -> some View {
        // A collection in Recently Deleted keeps its works, so only live ones.
        let names = work.activeCollections.map(\.name).sorted()
        return Group {
            myCopyHeader("Collections")
            ForEach(names, id: \.self) { name in
                Text(name)
                    .font(.system(size: 14.5))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .myCopyRow()
            }
            Button {
                withLocalWork { _ in showingAddToCollection = true }
            } label: {
                myCopyAddLabel("Add to collection")
            }
            .buttonStyle(.plain)
            .disabled(working)
            .myCopyRow(top: 6, bottom: 6)
        }
    }

    private func libraryStorageSection(for work: SavedWork) -> some View {
        Group {
            myCopyHeader("Storage")
            myCopyValueRow("Download", downloadStatusText(for: work))
            if work.isQueuedForLater {
                myCopyValueRow(
                    "Preservation",
                    WorkDetailPresentation.preservationStatusLabel(work.epubPreservationStatus)
                )
            }
            myCopyValueRow("Source", work.origin.displayName)
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
        Group {
            myCopyHeader("Activity")
            myCopyValueRow("Added", work.dateAdded.formatted(date: .abbreviated, time: .shortened))
            myCopyValueRow(
                "Last opened",
                work.lastReadDate.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "Never"
            )
            // Bar and label share one source: `readingProgress`'s chapter
            // fallback draws a bar for works never opened.
            if let progress = work.publicationProgress,
               let progressLabel = WorkReadingPosition.cardProgressLabel(progress: progress) {
                VStack(spacing: 8) {
                    HStack(spacing: 10) {
                        Text("Progress")
                            .font(.system(size: 14.5))
                            .frame(maxWidth: .infinity, alignment: .leading)
                        myCopyValue(progressLabel)
                    }
                    ProgressView(value: progress)
                }
                .accessibilityElement(children: .combine)
                .myCopyRow()
            }
        }
    }

    // MARK: My Tags

    /// 1a: chosen tags as tinted chips with a remove mark, an "Add a tag"
    /// field, then suggestions as plain chips. Private to this device.
    private var myTagsSection: some View {
        Group {
            myCopyHeader("My tags", note: "private")
            VStack(alignment: .leading, spacing: 9) {
                let myTags = (localWork?.tags ?? []).sorted { $0.name < $1.name }
                if !myTags.isEmpty {
                    FlowLayout(spacing: 7, rowSpacing: 7) {
                        ForEach(myTags) { tag in
                            myTagChip(tag)
                        }
                    }
                }

                HStack(spacing: 10) {
                    TextField("Add a tag", text: $newTagName)
                        .font(.system(size: 14))
                        .onSubmit(addTypedTag)
                    Button("Add", action: addTypedTag)
                        .font(.system(size: 14, weight: .medium))
                        .buttonStyle(.borderless)
                        .disabled(newTagName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .subjectPanel(cornerRadius: 10)

                if !suggestions.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 7) {
                            ForEach(suggestions, id: \.self) { name in
                                Button { apply(named: name) } label: {
                                    Text(name)
                                        .font(.system(size: 13.5))
                                        .foregroundStyle(.primary)
                                        .padding(.horizontal, 11)
                                        .padding(.vertical, 6)
                                        .subjectPanel(cornerRadius: 8)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Add tag \(name)")
                            }
                        }
                    }
                }
            }
            .myCopyRow(bottom: 24)
        }
    }

    /// Tapping the name filters the Library by it; the minus removes it.
    private func myTagChip(_ tag: Tag) -> some View {
        HStack(spacing: 7) {
            Button { router.filterLibrary(.userTag, tag.name) } label: {
                Text(tag.name)
                    .font(.system(size: 13.5, weight: .medium))
            }
            .buttonStyle(.plain)
            Button { removeTag(tag) } label: {
                Image(systemName: "minus")
                    .font(.system(size: 11, weight: .semibold))
                    .opacity(0.6)
            }
            .buttonStyle(.plain)
            .layoutFreeHitTarget { removeTag(tag) }
            .accessibilityLabel("Remove tag \(tag.name)")
        }
        .foregroundStyle(.tint)
        .padding(.leading, 11)
        .padding(.trailing, 9)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.tint.opacity(0.16))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(.tint.opacity(0.22), lineWidth: 0.5)
                )
        )
    }
}

extension View {
    /// A My copy row: flush to the sheet's 22pt margins, no card, no separator.
    func myCopyRow(top: CGFloat = 3, bottom: CGFloat = 3) -> some View {
        listRowInsets(EdgeInsets(top: top, leading: 22, bottom: bottom, trailing: 22))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }
}
