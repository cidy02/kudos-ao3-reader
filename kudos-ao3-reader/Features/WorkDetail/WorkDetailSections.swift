import SwiftData
import SwiftUI

// The Tags, Comments, and Library sections of the Work Details hub. Tags carries
// the AO3 classification links (tap-to-search); Comments is the native
// comments entry point (no comment pages are fetched until the user opens
// them); Library holds every piece of local/personal state — the My copy
// sheet's rows, clearly separated from AO3 metadata.

extension WorkDetailView {
    // MARK: - Tags section

    private struct TagGroup {
        let title: String
        let tags: [String]
        let field: AO3TagSearch.Field
    }

    /// Version E's three groups lead; archive warnings and fandoms keep their
    /// place after them. Fandoms are links too: the label above the title names
    /// only the first, and these are how a reader reaches the others.
    private var tagGroups: [TagGroup] {
        let categorized: [TagGroup] = [
            TagGroup(title: "Relationships", tags: displayRelationships, field: .relationship),
            TagGroup(title: "Characters", tags: displayCharacters, field: .character),
            TagGroup(title: "Additional tags", tags: displayFreeforms, field: .freeform),
            TagGroup(title: "Warnings", tags: displayWarnings, field: .warning),
            TagGroup(title: "Fandoms", tags: displayFandoms, field: .fandom)
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
        Section {
            WorkDetailDisclosureHeader(
                title: "Tags", digest: tagDigest(groups), isExpanded: $tagsExpanded
            )
            .pageBodyRow(top: 14)

            if tagsExpanded {
                if groups.isEmpty {
                    // A plain imported EPUB has no AO3 identity, so it says why it
                    // has no AO3 tags rather than that AO3 hasn't sent them yet.
                    Text(ao3WorkID != nil
                        ? "AO3 hasn't provided tags for this work yet."
                        : "This imported work isn't linked to AO3, so you won't see AO3 tags here.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .pageBodyRow(top: 6)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(groups, id: \.title) { tagRow($0) }
                    }
                    .padding(.bottom, 14)
                    .pageBodyRow(top: 2)
                }
            }
        }
    }

    private func tagDigest(_ groups: [TagGroup]) -> String {
        let digest = WorkDetailDisclosure.tagsDigest(
            relationships: displayRelationships.count,
            characters: displayCharacters.count,
            additional: displayFreeforms.count
        )
        let total = groups.reduce(0) { $0 + $1.tags.count }
        guard digest == "No AO3 tags", total > 0 else { return digest }
        return "\(total) tag\(total == 1 ? "" : "s")"
    }

    /// Version E: AO3's compact label column, then comma-separated search links.
    @ViewBuilder
    private func tagRow(_ group: TagGroup) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 0) {
                tagGroupLabel(group)
                WorkDetailTagLinks(tags: group.tags, field: group.field)
            }
        } else {
            HStack(alignment: .top, spacing: 10) {
                tagGroupLabel(group)
                    .frame(width: 92, alignment: .leading)
                WorkDetailTagLinks(tags: group.tags, field: group.field)
            }
        }
    }

    private func tagGroupLabel(_ group: TagGroup) -> some View {
        Text(group.title)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .padding(.top, 1)
            .accessibilityAddTraits(.isHeader)
    }

    // MARK: - Comments

    /// Board 19's Comments row: the name, the count, a chevron into the
    /// discussion.
    ///
    /// The row replaces three (All comments, Chapter comments, Write a comment).
    /// Nothing is lost: the native Comments screen opens on all comments and
    /// carries the By Chapter picker and the write bar itself, and the ••• menu
    /// still lists Comments under On AO3.
    ///
    /// The link stays value-based. A destination-based `NavigationLink` would
    /// sit outside the stack's path and be discarded by the author-byline push
    /// made from inside Comments — see `AO3CommentsRoute`.
    @ViewBuilder
    var commentsSection: some View {
        if let id = ao3WorkID {
            Section {
                // Space above the card, as its own row: padding on the segment
                // would stretch the card's row background into it.
                Color.clear
                    .frame(height: 24)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .accessibilityHidden(true)

                SubjectFormRow(
                    label: "Comments",
                    value: displayComments.map { $0.formatted() } ?? "",
                    showsDisclosure: true
                )
                .subjectRowNavigation(
                    to: AO3CommentsRoute(workID: id, context: commentsWorkContext),
                    accessibilityLabel: "Comments"
                )
                .accessibilityHint("Comments load only when you open them")
                .panelSegment(0, of: 1, gutter: SubjectMetrics.gutter)
            }
        }
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
                Text("This work isn't in your Library yet.")
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
                    .font(.system(size: myCopyRowTitleSize))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if isOn {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)
                }
                if busy {
                    ProgressView().controlSize(.small).accentFill()
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
                .font(.system(size: myCopyRowTitleSize))
                .frame(maxWidth: .infinity, alignment: .leading)
            myCopyValue(value)
        }
        .accessibilityElement(children: .combine)
        .myCopyRow()
    }

    private func myCopyValue(_ value: String) -> some View {
        Text(value)
            .font(.system(size: myCopyValueSize))
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
                .font(.system(size: myCopyActionSize, weight: .medium))
        }
        .foregroundStyle(.tint)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func savedForLaterRow(for work: SavedWork) -> some View {
        let queued = work.isInSavedForLaterQueue
        return myCopyToggleRow(
            "Want to Read",
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
                    .font(.system(size: myCopyRowTitleSize))
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
        // A copy fetched only to read is not "Downloaded" (owner, 2026-10-01).
        if work.isDownloaded, WorkReaderPreparation.hasReadableEPUB(for: work) {
            if let size = WorkDetailPresentation.fileSizeLabel(forFileAt: work.fileURL) {
                return "Downloaded · \(size)"
            }
            return "Downloaded"
        }
        // A copy fetched only to read: here for now, but not kept.
        if WorkReaderPreparation.hasReadableEPUB(for: work) { return "Not downloaded" }
        // Only an AO3-identified work can actually re-download; an imported EPUB
        // with a missing file has no recovery path to promise.
        return ao3WorkID != nil
            ? "Removed to save space. Kudos gets it again when you read it"
            : "File missing. An imported work can't be downloaded again"
    }

    private func libraryActivitySection(for work: SavedWork) -> some View {
        Group {
            myCopyHeader("Activity")
            myCopyValueRow("Added", work.dateAdded.formatted(date: .abbreviated, time: .shortened))
            Button { showingDownloadedDateEditor = true } label: {
                HStack(spacing: 10) {
                    Text("Downloaded")
                        .font(.system(size: myCopyRowTitleSize))
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    myCopyValue(
                        work.downloadedAt?.formatted(date: .abbreviated, time: .omitted)
                            ?? "Not recorded"
                    )
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Edit downloaded date")
            .myCopyRow()
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
                            .font(.system(size: myCopyRowTitleSize))
                            .frame(maxWidth: .infinity, alignment: .leading)
                        myCopyValue(progressLabel)
                    }
                    ProgressView(value: progress).accentFill()
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
                        .font(.system(size: myCopyActionSize))
                        .onSubmit(addTypedTag)
                    Button("Add", action: addTypedTag)
                        .font(.system(size: myCopyActionSize, weight: .medium))
                        .buttonStyle(.borderless)
                        .disabled(newTagName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .subjectPanel()

                if !suggestions.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 7) {
                            ForEach(suggestions, id: \.self) { name in
                                Button { apply(named: name) } label: {
                                    Text(name)
                                        .font(.system(size: tagChipSize))
                                        .foregroundStyle(.primary)
                                        .padding(.horizontal, 11)
                                        .padding(.vertical, 6)
                                        .subjectPanel(cornerRadius: SubjectMetrics.capsuleRadius)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Add tag \(name)")
                            }
                        }
                    }
                    .horizontalScrollViewport()
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
                    .font(.system(size: tagChipSize, weight: .medium))
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
            SubjectMetrics.controlShape(dynamicTypeSize)
                .fill(.accentFill.opacity(0.16))
                .overlay(
                    SubjectMetrics.controlShape(dynamicTypeSize)
                        .strokeBorder(.tint.opacity(0.22), lineWidth: 0.5)
                )
        )
    }
}

struct DownloadedDateEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    let work: SavedWork
    @State private var date: Date

    init(work: SavedWork) {
        self.work = work
        _date = State(initialValue: work.downloadedAt ?? work.dateAdded)
    }

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Downloaded", selection: $date, in: ...Date(), displayedComponents: .date).accentFill()
                    .appThemedRows()
            }
            .appThemedScroll()
            .navigationTitle("Downloaded")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        work.downloadedAt = date
                        work.markModified()
                        context.saveBestEffort(reason: "Saving downloaded date failed")
                        dismiss()
                    }
                    .buttonStyle(.kudosPrimary)
                }
            }
        }
    }
}

extension View {
    /// A My copy row: flush to the sheet's edge, no card, no separator.
    func myCopyRow(top: CGFloat = 3, bottom: CGFloat = 3) -> some View {
        let edge = SubjectMetrics.gutter
        return listRowInsets(EdgeInsets(top: top, leading: edge, bottom: bottom, trailing: edge))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }
}

/// Version E: one group's tags as wrapping text with inline links, the way AO3
/// prints them. Not a Button per tag in a flow layout: those caught taps well
/// below their own line, on the next section's header (seen on Lane E, 11-10).
struct WorkDetailTagLinks: View {
    let tags: [String]
    let field: AO3TagSearch.Field

    @Environment(AppRouter.self) private var router
    @Environment(\.accentInk) private var accentInk

    var body: some View {
        Text(WorkDetailTagLink.text(tags))
            .font(.subheadline)
            .tint(accentInk)
            .frame(maxWidth: .infinity, alignment: .leading)
            .environment(\.openURL, OpenURLAction { url in
                guard let tag = WorkDetailTagLink.tag(from: url) else { return .discarded }
                router.searchAO3(field, tag)
                return .handled
            })
    }
}

/// The in-app link a tag carries: any tag text survives the round trip
/// ("Tenth Doctor & Donna Noble", "Ben Solo/Rey").
enum WorkDetailTagLink {
    static let scheme = "kudos-tag"

    static func url(for tag: String) -> URL? {
        tag.addingPercentEncoding(withAllowedCharacters: .alphanumerics)
            .flatMap { URL(string: scheme + ":" + $0) }
    }

    static func tag(from url: URL) -> String? {
        guard url.scheme == scheme else { return nil }
        return String(url.absoluteString.dropFirst(scheme.count + 1)).removingPercentEncoding
    }

    static func text(_ tags: [String]) -> AttributedString {
        var text = AttributedString()
        for (index, tag) in tags.enumerated() {
            if index > 0 { text += AttributedString(", ") }
            var link = AttributedString(tag)
            link.link = url(for: tag)
            text += link
        }
        return text
    }
}
