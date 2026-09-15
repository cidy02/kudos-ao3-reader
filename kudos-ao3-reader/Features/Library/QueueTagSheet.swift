import SwiftData
import SwiftUI

/// The reader's tags on one reading queue — artboard **1h**'s "the queue's tags
/// with a dashed + Tag", and what **1i**'s tag rail filters on.
///
/// The same `Tag` a work carries. 1h calls the way out of this list "Manage all
/// tags as the way out to the shared vocabulary", so a queue tagged "Comfort" and
/// a work tagged "Comfort" are one word, not two that happen to match.
///
/// Shaped like `WorkBulkTagSheet` because it is the same job over a different
/// subject, including the rule that matters most here: a tag is looked up by name
/// before it is created, because `Tag.name` is `@Attribute(.unique)` and
/// inserting a second one by the same name throws.
struct QueueTagSheet: View {
    let queue: ReadingQueue

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Tag.name) private var allTags: [Tag]
    @State private var newTagName = ""

    private var queueTagIDs: Set<PersistentIdentifier> {
        Set(queue.tags.map(\.persistentModelID))
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        TextField("New tag", text: $newTagName)
                            .onSubmit(addTypedTag)
                        Button("Add", action: addTypedTag)
                            .buttonStyle(.borderless)
                            .disabled(trimmedNewTag.isEmpty)
                    }
                } footer: {
                    Text("Tags are shared with your works, so one word means the same "
                        + "thing wherever you use it.")
                }

                if allTags.isEmpty {
                    Section {
                        Text("No tags yet — add one above.")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section("Your tags") {
                        ForEach(allTags) { tag in
                            row(for: tag)
                        }
                    }
                }
            }
            .appThemedRows()
            .appThemedScroll()
            .navigationTitle("Tags")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
    }

    private func row(for tag: Tag) -> some View {
        let isOn = queueTagIDs.contains(tag.persistentModelID)
        return Button {
            toggle(tag, isOn: isOn)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isOn ? Color.accentColor : Color.secondary)
                Text(tag.name)
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tag.name)
        .accessibilityValue(isOn ? "on this queue" : "not on this queue")
    }

    private func toggle(_ tag: Tag, isOn: Bool) {
        if isOn {
            queue.tags.removeAll { $0.persistentModelID == tag.persistentModelID }
        } else {
            queue.tags.append(tag)
        }
        queue.markModified()
        context.saveBestEffort(reason: "Saving queue tags failed")
    }

    private var trimmedNewTag: String {
        newTagName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func addTypedTag() {
        let name = trimmedNewTag
        guard !name.isEmpty else { return }
        // Reuse an existing tag rather than inserting a second one by the same
        // name — `Tag.name` is unique, and a duplicate throws.
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
        context.saveBestEffort(reason: "Saving new queue tag failed")
        newTagName = ""
    }
}
