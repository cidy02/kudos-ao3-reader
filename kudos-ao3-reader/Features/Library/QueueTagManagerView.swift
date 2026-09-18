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

    @Environment(\.modelContext) private var context
    @Environment(ThemeManager.self) private var themeManager
    @Query(sort: \Tag.name) private var allTags: [Tag]
    @State private var newTagName = ""
    @State private var editing: Tag?

    /// The queue's own colour, as Queue Details draws it — this screen is
    /// pushed from there, and 1bh's wash is the queue's.
    private var palette: SubjectPalette {
        themeManager.appTheme.subjectPalette(hue: queue.displayHue)
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
                    footnote("Kept until you remove them — an empty tag is usually one "
                        + "you have not finished applying.")
                }
            }

            // Last, where 1bh draws it — below the tags it adds to.
            Section {
                groupLabel("Add")
                addPanel.pageBodyRow(top: 8, gutter: gutter)
                footnote("Tags are shared with your works, so one word means the "
                    + "same thing wherever you use it.")
            }
        }
        .cardList()
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

    /// 1bh's rows: name, and how many works IN THIS QUEUE carry the tag — "18",
    /// not the library's figure, because the header's "across 42 works" is the
    /// queue's. Its colour dots are not drawn: `Tag` has no colour, and one
    /// derived from the name would repaint on rename — the defect
    /// `ReadingQueue.hue` exists to fix.
    private func tagPanel(_ tags: [Tag], counts: [PersistentIdentifier: Int]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(tags.enumerated()), id: \.element.persistentModelID) { index, tag in
                if index > 0 { SubjectRowSeparator() }
                let count = counts[tag.persistentModelID, default: 0]
                SubjectFormRow(
                    label: tag.name,
                    value: "\(count)",
                    showsDisclosure: true,
                    isMonospaced: true,
                    action: { editing = tag }
                )
                .accessibilityLabel(tag.name)
                .accessibilityValue("\(count) work\(count == 1 ? "" : "s") in this queue")
            }
        }
        .subjectPanel()
    }

    private var addPanel: some View {
        HStack(spacing: 10) {
            Image(systemName: "plus")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(palette.accent)
                .frame(width: 20)
                .accessibilityHidden(true)
            TextField("New tag", text: $newTagName)
                .font(.system(size: 15))
                .onSubmit(addTypedTag)
            // Always present, dimmed while empty, as the old screen had it —
            // appearing only once typing starts put a submit control into a
            // panel VoiceOver had already read past.
            Button("Add", action: addTypedTag)
                .font(.system(size: 15, weight: .semibold))
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
            .font(.system(size: 11.5))
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
        let name = trimmedNewTag
        guard !name.isEmpty else { return }
        let tag = allTags.first { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }
            ?? {
                let created = Tag(name: name)
                context.insert(created)
                return created
            }()
        if !queue.tags.contains(where: { $0.persistentModelID == tag.persistentModelID }) {
            queue.tags.append(tag)
            queue.markModified()
        }
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

    private var palette: SubjectPalette {
        themeManager.appTheme.subjectPalette(hue: queue.displayHue)
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
                        footnote("This tag is shared with your works, so renaming it "
                            + "here renames it everywhere.")
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
    }

    private func groupLabel(_ text: String) -> some View {
        SubjectFieldLabel(text: text, style: .formGroup)
            .pageBodyRow(top: 18, gutter: gutter)
    }

    private func footnote(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11.5))
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
        let undo = " It cannot be undone from the app."
        switch workCount {
        case 0:
            // No "cannot be undone" here: with nothing to retag, merging only
            // takes the tag off the queue, and `QueueTagSheet` puts it back in
            // one tap — the same change Remove makes, and Remove says so.
            return "No work in this queue carries “\(tag.name)”, so merging only "
                + "takes it off the queue, the same as Remove below."
        case 1:
            return "Merging moves the 1 work in this queue onto the tag you pick and "
                + "takes “\(tag.name)” off the queue." + undo
        default:
            return "Merging moves all \(workCount) works in this queue onto the tag you "
                + "pick and takes “\(tag.name)” off the queue." + undo
        }
    }

    /// Points at Merge only when the colliding tag is actually in the merge
    /// list, i.e. on this queue — the library-wide `allTags` lookup can find a
    /// tag that lives only on works, which the list below never shows. And it
    /// says what Merge does (this queue's works), not "make them one tag",
    /// which a queue-scoped merge does not do.
    private func conflictNote(_ existing: Tag) -> String {
        let taken = "A tag called “\(existing.name)” already exists, so that name is taken."
        let isSibling = siblings.contains { $0.persistentModelID == existing.persistentModelID }
        return isSibling
            ? taken + " To move this queue's works onto it, merge below."
            : taken
    }

    private func stripNote(workCount: Int) -> String {
        switch workCount {
        case 0: "The tag stays on your other works and queues."
        case 1: "That work keeps its other tags, and works outside this queue keep this one."
        default: "Those works keep their other tags, and works outside this queue keep this one."
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
        for work in ReadingQueueService.orderedWorks(in: queue) {
            work.tags.removeAll { $0.persistentModelID == tag.persistentModelID }
            work.markModified()
        }
        queue.tags.removeAll { $0.persistentModelID == tag.persistentModelID }
        queue.markModified()
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
