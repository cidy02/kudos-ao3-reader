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
    @Environment(ThemeManager.self) private var theme
    @Query(sort: \Tag.name) private var allTags: [Tag]
    @State private var newTagName = ""
    @State private var editing: Tag?

    /// Works actually in this queue — the population every count on this screen
    /// is measured against.
    private var queueWorks: [SavedWork] {
        queue.memberships
            .filter { !$0.isPendingDeletion }
            .compactMap(\.work)
            .filter { !$0.isPendingDeletion }
    }

    /// 1bh's per-tag figure: how many works IN THIS QUEUE carry the tag. Not how
    /// many the library has — the board's header says "9 tags across 42 works",
    /// and those 42 are the queue's.
    private func workCount(for tag: Tag) -> Int {
        queueWorks.filter { work in
            work.tags.contains { $0.persistentModelID == tag.persistentModelID }
        }.count
    }

    private var used: [Tag] {
        queue.tags.filter { workCount(for: $0) > 0 }
            .sorted { workCount(for: $0) > workCount(for: $1) }
    }

    private var unused: [Tag] {
        queue.tags.filter { workCount(for: $0) == 0 }
            .sorted { $0.name < $1.name }
    }

    private var tally: String {
        let tags = queue.tags.count
        let works = queueWorks.count
        return "\(tags) tag\(tags == 1 ? "" : "s") across "
            + "\(works) work\(works == 1 ? "" : "s")"
    }

    var body: some View {
        List {
            Section {
                Text(tally)
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
            }

            Section {
                HStack {
                    TextField("New tag", text: $newTagName)
                        .onSubmit(addTypedTag)
                    Button("Add", action: addTypedTag)
                        .buttonStyle(.borderless)
                        .disabled(trimmedNewTag.isEmpty)
                }
            } header: {
                Text("Add")
            }

            if !used.isEmpty {
                Section("In this queue") {
                    ForEach(used) { tag in
                        row(tag)
                    }
                }
            }

            // 1bh keeps these in their own group rather than sweeping them up,
            // and says why: on a shared queue "a collaborator may still be
            // filling an empty tag". The grouping is still right for one person —
            // a tag you have made but not applied yet is not rubbish.
            if !unused.isEmpty {
                Section {
                    ForEach(unused) { tag in
                        row(tag)
                    }
                } header: {
                    Text("Unused")
                } footer: {
                    Text("Kept until you remove them — an empty tag is usually one "
                        + "you have not finished applying.")
                }
            }

            if queue.tags.isEmpty {
                Section {
                    Text("This queue has no tags yet.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .appThemedRows()
        .appThemedScroll()
        .navigationTitle("Manage tags")
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
            .sheet(item: $editing) { tag in
                QueueTagEditSheet(
                    tag: tag,
                    queue: queue,
                    workCount: workCount(for: tag),
                    siblings: queue.tags.filter { $0.persistentModelID != tag.persistentModelID }
                )
            }
    }

    private func row(_ tag: Tag) -> some View {
        Button {
            editing = tag
        } label: {
            HStack {
                Text(tag.name)
                    .foregroundStyle(.primary)
                Spacer(minLength: 8)
                Text("\(workCount(for: tag))")
                    .font(.system(size: 12))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tag.name)
        .accessibilityValue("\(workCount(for: tag)) works in this queue")
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

/// 1bh's second sheet: "one tag: rename, merge into a sibling with its count, or
/// strip it from all 18 works".
struct QueueTagEditSheet: View {
    let tag: Tag
    let queue: ReadingQueue
    let workCount: Int
    let siblings: [Tag]

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var confirmStrip = false

    init(tag: Tag, queue: ReadingQueue, workCount: Int, siblings: [Tag]) {
        self.tag = tag
        self.queue = queue
        self.workCount = workCount
        self.siblings = siblings
        self._name = State(initialValue: tag.name)
    }

    private var trimmed: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Name", text: $name)
                        .onSubmit(rename)
                } header: {
                    Text("Rename")
                } footer: {
                    // The rename is global because the Tag is: this is the same
                    // word the reader's works carry, which is the point of one
                    // shared vocabulary rather than a queue-local copy.
                    Text("This tag is shared with your works, so renaming it here "
                        + "renames it everywhere.")
                }

                if !siblings.isEmpty {
                    Section {
                        ForEach(siblings) { sibling in
                            Button {
                                merge(into: sibling)
                            } label: {
                                HStack {
                                    Text(sibling.name).foregroundStyle(.primary)
                                    Spacer(minLength: 8)
                                    Image(systemName: "arrow.triangle.merge")
                                        .foregroundStyle(.secondary)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    } header: {
                        Text("Merge into")
                    } footer: {
                        Text("Every work tagged “\(tag.name)” takes the other tag "
                            + "instead, and this one is removed from the queue.")
                    }
                }

                Section {
                    Button(role: .destructive) {
                        confirmStrip = true
                    } label: {
                        Text(workCount == 0
                            ? "Remove from queue"
                            : "Strip from all \(workCount) works")
                    }
                }
            }
            .appThemedRows()
            .appThemedScroll()
            .navigationTitle(tag.name)
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save", action: rename)
                            .disabled(trimmed.isEmpty || trimmed == tag.name)
                    }
                }
                .confirmationDialog(
                    workCount == 0
                        ? "Remove “\(tag.name)” from this queue?"
                        : "Strip “\(tag.name)” from \(workCount) works?",
                    isPresented: $confirmStrip,
                    titleVisibility: .visible
                ) {
                    Button("Remove", role: .destructive, action: strip)
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text(workCount == 0
                        ? "The tag stays on your other works and queues."
                        : "The works keep their other tags.")
                }
        }
    }

    private func rename() {
        let next = trimmed
        guard !next.isEmpty, next != tag.name else { return }
        tag.name = next
        context.saveBestEffort(reason: "Renaming tag failed")
        dismiss()
    }

    /// Moves every work in this queue off `tag` and onto `other`, then takes
    /// `tag` off the queue. The tag itself is left alone: it may still be on
    /// works outside this queue, and deleting it would strip those too.
    private func merge(into other: Tag) {
        for membership in queue.memberships where !membership.isPendingDeletion {
            guard let work = membership.work,
                  work.tags.contains(where: { $0.persistentModelID == tag.persistentModelID })
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

    private func strip() {
        for membership in queue.memberships where !membership.isPendingDeletion {
            guard let work = membership.work else { continue }
            work.tags.removeAll { $0.persistentModelID == tag.persistentModelID }
            work.markModified()
        }
        queue.tags.removeAll { $0.persistentModelID == tag.persistentModelID }
        queue.markModified()
        context.saveBestEffort(reason: "Removing tag failed")
        dismiss()
    }
}
