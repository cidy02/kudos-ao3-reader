import SwiftData
import SwiftUI

/// Artboard **1bh**'s tag manager, minus the half that needs collaboration.
///
/// 1bh is the *shared* queue's tag manager, and its own label says what makes it
/// different: "tags on a shared queue have an author, so every row carries who
/// added it — that is the only thing that separates this from a private queue's
/// tag list". There is no sharing in this app, so there is no author to name, and
/// a "you" on every row would be a column that never says anything else.
/// Everything else the board draws is about tags and works, and all of it is
/// local.
///
/// Reached from Queue Details, which 1h calls "Manage all tags as the way out to
/// the shared vocabulary" — the same `Tag` a work carries, not a queue-only copy.
struct QueueTagManagerView: View {
    let queue: ReadingQueue
    var onShowOnlyTag: (Tag) -> Void = { _ in }

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(ThemeManager.self) private var themeManager
    @Query(filter: #Predicate<ReadingQueue> { !$0.isPendingDeletion }, sort: \ReadingQueue.sortOrder)
    private var allQueues: [ReadingQueue]
    @State private var newTagName = ""
    @State private var editing: Tag?
    /// "Remove from N works" asks first, like every other removal (T-288).
    @State private var pendingRemoval: Tag?

    @ScaledMetric(relativeTo: .subheadline) private var countSize: CGFloat = 15
    @ScaledMetric(relativeTo: .subheadline) private var inputSize: CGFloat = 15
    @ScaledMetric(relativeTo: .headline) private var buttonLabelSize: CGFloat = 15
    @ScaledMetric(relativeTo: .caption) private var footnoteSize: CGFloat = 11.5

    /// The queue's own colour, as Queue Details draws it — this screen is
    /// pushed from there, and 1bh's wash is the queue's.
    private var palette: SubjectPalette {
        themeManager.appTheme.subjectPalette(hue: queue.displayHue, pickedHex: queue.colorHex)
    }

    private var gutter: CGFloat { SubjectMetrics.gutter }

    var body: some View {
        // Counted once per body rather than per row and per sort comparison,
        // which walked every work in the queue for every tag, twice per compare.
        let counts = queue.workCountsByTag()
        let used = queue.tags.filter { counts[$0.persistentModelID, default: 0] > 0 }
            .sorted { counts[$0.persistentModelID, default: 0] > counts[$1.persistentModelID, default: 0] }
        let unused = queue.tags.filter { counts[$0.persistentModelID, default: 0] == 0 }
            .sorted { $0.name < $1.name }
        return List {
            Section {
                SubjectHeaderBlock(
                    kicker: queue.displayName,
                    title: "Tags",
                    subtitle: tally,
                    palette: palette,
                    gutter: gutter
                )
                .pageBodyRow(top: 20, gutter: 0)
            }

            if !used.isEmpty {
                Section {
                    groupLabel("In this queue")
                    tagPanel(used, counts: counts).pageBodyRow(top: 8, gutter: gutter)
                }
            }

            // 1bh keeps these in their own group rather than sweeping them up,
            // and says why: on a shared queue "a collaborator may still be
            // filling an empty tag". The grouping is still right for one person —
            // a tag you have made but not applied yet is not rubbish.
            if !unused.isEmpty {
                Section {
                    groupLabel("Unused")
                    tagPanel(unused, counts: counts).pageBodyRow(top: 8, gutter: gutter)
                    footnote("Unused tags stay here until you remove them. You can apply them later.")
                }
            }

            // Last, where 1bh draws it — below the tags it adds to.
            Section {
                groupLabel("Add")
                addPanel.pageBodyRow(top: 8, gutter: gutter)
                footnote("A tag you use here is the same tag on your works.")
            }
        }
        .cardList()
        // Rows at their own padding, not the List minimum (L3-FORM-1).
        .environment(\.defaultMinListRowHeight, 0)
        .subjectScreenWash(palette: palette)
        // The wash's empty bar title is iOS-only; macOS's split view still
        // needs a real one, as `ReadingQueueSettingsView` gives itself.
        #if os(macOS)
        .navigationTitle("Manage tags")
        #endif
        .sheet(item: $editing) { tag in
            QueueTagEditSheet(
                tag: tag,
                queue: queue,
                siblings: queue.tags.filter { $0.persistentModelID != tag.persistentModelID }
            )
        }
        // The same ask as the edit sheet's Remove row.
        .confirmationDialog(
            removalTitle(counts: counts),
            isPresented: Binding(
                get: { pendingRemoval != nil },
                set: { if !$0 { pendingRemoval = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingRemoval
        ) { tag in
            Button("Remove", role: .destructive) {
                queue.removeTagFromWorks(tag)
                context.saveBestEffort(reason: "Removing tag failed")
            }
            Button("Cancel", role: .cancel) {}
        }
            .screenTint(palette)
    }

    private func removalTitle(counts: [PersistentIdentifier: Int]) -> String {
        guard let tag = pendingRemoval else { return "" }
        let count = counts[tag.persistentModelID, default: 0]
        return count == 0
            ? "Remove “\(tag.name)” from this queue?"
            : "Remove “\(tag.name)” from \(count) work\(count == 1 ? "" : "s")?"
    }

    /// 1bh's subtitle, minus its "everyone can add, only you can rename": there
    /// is no sharing in this app, so there is no one else to say it about.
    private var tally: String {
        let tags = queue.tags.count
        let works = ReadingQueueService.orderedWorks(in: queue).count
        guard tags > 0 else { return "No tags on this queue yet" }
        return "\(tags) tag\(tags == 1 ? "" : "s") across "
            + "\(works) work\(works == 1 ? "" : "s")"
    }

    private func groupLabel(_ text: String) -> some View {
        SubjectFieldLabel(text: text, style: .formGroup)
            .pageBodyRow(top: 18, gutter: gutter)
    }

    /// 1bh's rows: name, how many works IN THIS QUEUE carry the tag, and the
    /// prescribed five-item menu. `Tag` has no colour, so no colour dot is
    /// invented from its name.
    private func tagPanel(_ tags: [Tag], counts: [PersistentIdentifier: Int]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(tags.enumerated()), id: \.element.persistentModelID) { index, tag in
                if index > 0 { SubjectRowSeparator() }
                let count = counts[tag.persistentModelID, default: 0]
                Menu {
                    tagMenu(tag, workCount: count)
                } label: {
                    SubjectFormRow(label: tag.name) {
                        HStack(spacing: 10) {
                            Text(count.compactCount)
                                .font(.system(size: countSize))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                            Image(systemName: "ellipsis")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .accessibilityHidden(true)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tag.name)
                .accessibilityValue("\(count) work\(count == 1 ? "" : "s") in this queue")
            }
        }
        .subjectPanel()
    }

    @ViewBuilder
    private func tagMenu(_ tag: Tag, workCount: Int) -> some View {
        Button {
            editing = tag
        } label: {
            Label("Rename", systemImage: "pencil")
        }
        Button {
            editing = tag
        } label: {
            Label("Merge into…", systemImage: "arrow.triangle.merge")
        }
        Button {
            dismiss()
            onShowOnlyTag(tag)
        } label: {
            Label("Show only this tag", systemImage: "line.3.horizontal.decrease.circle")
        }
        Menu {
            ForEach(otherQueues) { destination in
                Button(destination.displayName) { copy(tag, to: destination) }
            }
        } label: {
            Label("Copy tag to another queue", systemImage: "square.on.square")
        }
        .disabled(otherQueues.isEmpty)
        Divider()
        Button(role: .destructive) {
            pendingRemoval = tag
        } label: {
            Label(
                "Remove from \(workCount.compactCount) work\(workCount == 1 ? "" : "s")",
                systemImage: "trash"
            )
        }
    }

    private var otherQueues: [ReadingQueue] {
        allQueues.filter { $0.persistentModelID != queue.persistentModelID }
    }

    private func copy(_ tag: Tag, to destination: ReadingQueue) {
        guard destination.addTag(named: tag.name, in: context) != nil else { return }
        context.saveBestEffort(reason: "Copying queue tag failed")
    }

    private var addPanel: some View {
        HStack(spacing: 10) {
            Image(systemName: "plus")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(palette.accent)
                .frame(width: 20)
                .accessibilityHidden(true)
            TextField("New tag", text: $newTagName)
                .font(.system(size: inputSize))
                .onSubmit(addTypedTag)
            // Always present, dimmed while empty, as the old screen had it —
            // appearing only once typing starts put a submit control into a
            // panel VoiceOver had already read past.
            Button("Add", action: addTypedTag)
                .font(.system(size: buttonLabelSize, weight: .semibold))
                .foregroundStyle(palette.accent)
                .buttonStyle(.plain)
                .disabled(trimmedNewTag.isEmpty)
                .opacity(trimmedNewTag.isEmpty ? 0.35 : 1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .subjectPanel()
    }

    private func footnote(_ text: String) -> some View {
        Text(text)
            .font(.system(size: footnoteSize))
            .foregroundStyle(.secondary.opacity(0.7))
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .pageBodyRow(top: 8, gutter: gutter)
    }

    private var trimmedNewTag: String {
        newTagName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Looked up by name before being created: `Tag.name` is
    /// `@Attribute(.unique)`, so inserting a second one by the same name throws.
    private func addTypedTag() {
        guard queue.addTag(named: trimmedNewTag, in: context) != nil else { return }
        context.saveBestEffort(reason: "Adding queue tag failed")
        newTagName = ""
    }
}

extension ReadingQueue {
    /// How many of this queue's works — `orderedWorks`, the set a reader sees,
    /// so Recently Deleted is excluded — carry each tag. One pass over the
    /// works, shared by the tag manager and its edit sheet so their figures
    /// cannot disagree.
    @MainActor
    func workCountsByTag() -> [PersistentIdentifier: Int] {
        var counts: [PersistentIdentifier: Int] = [:]
        for work in ReadingQueueService.orderedWorks(in: self) {
            for tag in work.tags {
                counts[tag.persistentModelID, default: 0] += 1
            }
        }
        return counts
    }

    /// Removes a tag from every visible member work and from this queue's tag
    /// vocabulary. Recently Deleted works keep their data, matching the count
    /// and merge population shown by the tag manager.
    @MainActor
    func removeTagFromWorks(_ tag: Tag) {
        for work in ReadingQueueService.orderedWorks(in: self) {
            guard work.tags.contains(where: { $0.persistentModelID == tag.persistentModelID })
            else { continue }
            work.tags.removeAll { $0.persistentModelID == tag.persistentModelID }
            work.markModified()
        }
        removeTag(tag)
    }
}

/// 1bh's second sheet: "one tag: rename, merge into a sibling with its count, or
/// strip it from all 18 works".
struct QueueTagEditSheet: View {
    let tag: Tag
    let queue: ReadingQueue
    let siblings: [Tag]

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(ThemeManager.self) private var themeManager
    @Query(sort: \Tag.name) private var allTags: [Tag]
    @State private var name: String
    @State private var confirmStrip = false
    @State private var mergeTarget: Tag?

    init(tag: Tag, queue: ReadingQueue, siblings: [Tag]) {
        self.tag = tag
        self.queue = queue
        self.siblings = siblings
        self._name = State(initialValue: tag.name)
    }

    @ScaledMetric(relativeTo: .caption) private var footnoteSize: CGFloat = 11.5

    private var palette: SubjectPalette {
        themeManager.appTheme.subjectPalette(hue: queue.displayHue, pickedHex: queue.colorHex)
    }

    private var gutter: CGFloat { SubjectMetrics.gutter }

    private var trimmed: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The tag this rename would collide with. `Tag.name` is
    /// `@Attribute(.unique)`, and `rename()` used to write the new name
    /// straight in. Measured (`collidingTagRenameCollapsesTheTwoTags`): the
    /// save does not throw — SwiftData's unique constraint silently collapses
    /// the two tags into one across the whole library, carrying both tags'
    /// works and queues onto the survivor. Nothing is lost, but a
    /// library-wide merge was happening under a button labelled Save, with no
    /// word of it. Blocked instead, case-insensitively: the store's constraint
    /// is case-sensitive, so "Angst" and "angst" would coexist, which every
    /// in-app add path refuses.
    private var renameConflict: Tag? {
        Tag.renameConflict(for: tag, proposedName: trimmed, among: allTags)
    }

    var body: some View {
        let counts = queue.workCountsByTag()
        let workCount = counts[tag.persistentModelID, default: 0]
        return NavigationStack {
            List {
                Section {
                    groupLabel("Name")
                    SubjectFormRow(label: "Name", arrangement: .control) {
                        TextField("Name", text: $name)
                            .multilineTextAlignment(.trailing)
                            .onSubmit(rename)
                    }
                    .subjectPanel()
                    .pageBodyRow(top: 8, gutter: gutter)
                    if let renameConflict {
                        footnote(conflictNote(renameConflict))
                    } else {
                        // The rename is global because the Tag is: this is the
                        // same word the reader's works carry.
                        footnote("Renaming this tag also renames it on your works and other queues.")
                    }
                }

                if !siblings.isEmpty {
                    Section {
                        groupLabel("Merge into another tag")
                        mergePanel(counts: counts).pageBodyRow(top: 8, gutter: gutter)
                        footnote(mergeNote(workCount: workCount))
                    }
                }

                Section {
                    groupLabel("Remove")
                    SubjectFormRow(
                        label: workCount == 0
                            ? "Remove from this queue"
                            : "Remove tag from \(workCount) work\(workCount == 1 ? "" : "s")",
                        isDestructive: true,
                        action: { confirmStrip = true }
                    ) { EmptyView() }
                        .subjectPanel()
                        .pageBodyRow(top: 8, gutter: gutter)
                }
            }
            .cardList()
            // Rows at their own padding, not the List minimum (L3-FORM-1).
            .environment(\.defaultMinListRowHeight, 0)
            .navigationTitle("Edit tag")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
                .subjectScreenWash(palette: palette)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save", action: rename)
                            .disabled(trimmed.isEmpty || trimmed == tag.name || renameConflict != nil)
                    }
                }
                .confirmationDialog(
                    workCount == 0
                        ? "Remove “\(tag.name)” from this queue?"
                        : "Remove “\(tag.name)” from \(workCount) work\(workCount == 1 ? "" : "s")?",
                    isPresented: $confirmStrip,
                    titleVisibility: .visible
                ) {
                    Button("Remove", role: .destructive, action: strip)
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text(stripNote(workCount: workCount))
                }
                // Merge used to run on the first tap with nothing to catch a
                // slip, though the board's own note says it "cannot be undone
                // from the app" — the Remove row beside it already asked first.
                .confirmationDialog(
                    "Merge “\(tag.name)” into “\(mergeTarget?.name ?? "")”?",
                    isPresented: Binding(
                        get: { mergeTarget != nil },
                        set: { if !$0 { mergeTarget = nil } }
                    ),
                    titleVisibility: .visible,
                    presenting: mergeTarget
                ) { target in
                    Button("Merge", role: .destructive) { merge(into: target) }
                    Button("Cancel", role: .cancel) {}
                } message: { _ in
                    Text(mergeNote(workCount: workCount))
                }
        }
        .screenTint(palette)
        #if os(iOS)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        #endif
    }

    private func groupLabel(_ text: String) -> some View {
        SubjectFieldLabel(text: text, style: .formGroup)
            .pageBodyRow(top: 18, gutter: gutter)
    }

    private func footnote(_ text: String) -> some View {
        Text(text)
            .font(.system(size: footnoteSize))
            .foregroundStyle(.secondary.opacity(0.7))
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .pageBodyRow(top: 8, gutter: gutter)
    }

    /// 1bh: each sibling with its count in this queue. The rows only ask — the
    /// merge happens behind a confirmation.
    private func mergePanel(counts: [PersistentIdentifier: Int]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(siblings.enumerated()), id: \.element.persistentModelID) { index, sibling in
                if index > 0 { SubjectRowSeparator() }
                let count = counts[sibling.persistentModelID, default: 0]
                SubjectFormRow(
                    label: sibling.name,
                    value: "\(count)",
                    isMonospaced: true,
                    action: { mergeTarget = sibling }
                )
                .accessibilityLabel("Merge into \(sibling.name)")
                .accessibilityValue("\(count) work\(count == 1 ? "" : "s") in this queue")
            }
        }
        .subjectPanel()
    }

    /// True of `merge(into:)` as written: works in THIS queue move over, and the
    /// tag leaves this queue — it is not deleted, because works elsewhere may
    /// still carry it.
    ///
    /// Zero is its own sentence: "moves all 0 works" was what the simulator
    /// showed for an unused tag.
    private func mergeNote(workCount: Int) -> String {
        let undo = " You can't undo this in Kudos."
        switch workCount {
        case 0:
            // No "cannot be undone" here: with nothing to retag, merging only
            // takes the tag off the queue, and `QueueTagSheet` puts it back in
            // one tap — the same change Remove makes, and Remove says so.
            return "No work in this queue uses “\(tag.name)”. Merging removes the tag from this queue."
        case 1:
            return "The 1 work in this queue gets the tag you pick, and “\(tag.name)” leaves the queue." + undo
        default:
            return "All \(workCount) works in this queue get the tag you pick, and “\(tag.name)” leaves the queue."
                + undo
        }
    }

    /// Points at Merge only when the colliding tag is actually in the merge
    /// list, i.e. on this queue — the library-wide `allTags` lookup can find a
    /// tag that lives only on works, which the list below never shows. And it
    /// says what Merge does (this queue's works), not "make them one tag",
    /// which a queue-scoped merge does not do.
    private func conflictNote(_ existing: Tag) -> String {
        let taken = "You already have a tag called “\(existing.name)”."
        let isSibling = siblings.contains { $0.persistentModelID == existing.persistentModelID }
        return isSibling
            ? taken + " To use it for this queue's works, choose it below."
            : taken
    }

    private func stripNote(workCount: Int) -> String {
        switch workCount {
        case 0: "This tag stays on your other works and queues."
        case 1: "That work keeps its other tags. Works outside this queue keep this tag."
        default: "Those works keep their other tags. Works outside this queue keep this tag."
        }
    }

    private func rename() {
        let next = trimmed
        guard !next.isEmpty, next != tag.name, renameConflict == nil else { return }
        tag.name = next
        context.saveBestEffort(reason: "Renaming tag failed")
        dismiss()
    }

    /// Moves every work in this queue off `tag` and onto `other`, then takes
    /// `tag` off the queue. The tag itself is left alone: it may still be on
    /// works outside this queue, and deleting it would strip those too.
    ///
    /// Walks `orderedWorks`, the works the reader sees and the counts are
    /// built from. It used to walk raw memberships, which `softDelete` leaves
    /// in place, so a work in Recently Deleted was retagged too — and came back
    /// from Recently Deleted changed by a merge whose dialog said "no work in
    /// this queue carries" the tag.
    private func merge(into other: Tag) {
        for work in ReadingQueueService.orderedWorks(in: queue) {
            guard work.tags.contains(where: { $0.persistentModelID == tag.persistentModelID })
            else { continue }
            work.tags.removeAll { $0.persistentModelID == tag.persistentModelID }
            if !work.tags.contains(where: { $0.persistentModelID == other.persistentModelID }) {
                work.tags.append(other)
            }
            work.markModified()
        }
        queue.tags.removeAll { $0.persistentModelID == tag.persistentModelID }
        if !queue.tags.contains(where: { $0.persistentModelID == other.persistentModelID }) {
            queue.tags.append(other)
        }
        queue.markModified()
        context.saveBestEffort(reason: "Merging tags failed")
        dismiss()
    }

    /// The same population as `merge(into:)` and every figure on this sheet —
    /// see its comment.
    private func strip() {
        queue.removeTagFromWorks(tag)
        context.saveBestEffort(reason: "Removing tag failed")
        dismiss()
    }
}

extension Tag {
    /// The existing tag a rename of `tag` to `proposedName` would collide with,
    /// or nil. Case-insensitive, matching how every in-app "add a tag" path
    /// dedupes (backup restore is the exception: it matches exact case), so
    /// "Fluff" and "fluff" are never both created by a rename either; `tag` itself is excluded so a case-only rename ("slow burn" →
    /// "Slow Burn") still goes through.
    static func renameConflict(for tag: Tag, proposedName: String, among tags: [Tag]) -> Tag? {
        let name = proposedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        return tags.first {
            $0.persistentModelID != tag.persistentModelID
                && $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame
        }
    }
}
